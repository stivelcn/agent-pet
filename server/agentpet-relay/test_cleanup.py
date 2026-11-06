import sqlite3
import tempfile
import unittest
from pathlib import Path
from cleanup_messages import purge_messages


class CleanupTests(unittest.TestCase):
    def setUp(self):
        self.folder = tempfile.TemporaryDirectory()
        self.path = Path(self.folder.name) / "cleanup.sqlite3"
        self.db = sqlite3.connect(self.path)
        self.db.executescript("""
            CREATE TABLE messages(id TEXT PRIMARY KEY, text TEXT, gesture TEXT, delivered REAL, handled REAL);
            CREATE TABLE together_sessions(id TEXT PRIMARY KEY, status TEXT, expires REAL, ended REAL, reason TEXT);
        """)
        self.now = 100000
        self.cutoff = self.now - 21600

    def tearDown(self):
        self.db.close()
        self.folder.cleanup()

    def test_mail_retains_unhandled_and_six_hour_boundary_for_every_kind(self):
        keep = set()
        for gesture in (None, "poke", "hug", "peek", "future-action"):
            for label, handled in (("unread", None), ("old", self.cutoff - 1),
                                   ("boundary", self.cutoff), ("recent", self.cutoff + 1)):
                key = str(gesture) + label
                self.db.execute("INSERT INTO messages VALUES(?,?,?,?,?)", (key, "private", gesture, 1, handled))
                if label != "old":
                    keep.add(key)
        self.db.commit()
        preview = purge_messages(self.path, now=self.now, dry_run=True)
        self.assertEqual(preview["eligible_messages"], 5)
        self.assertEqual(self.db.execute("SELECT COUNT(*) FROM messages").fetchone()[0], 20)
        result = purge_messages(self.path, now=self.now)
        self.assertEqual(result["deleted_messages"], 5)
        self.assertEqual({r[0] for r in self.db.execute("SELECT id FROM messages")}, keep)

    def test_offline_expiry_and_end_time_control_session_retention(self):
        rows = [("old", "ended", self.now + 100, self.cutoff - 1, "end"),
                ("boundary", "ended", 0, self.cutoff, "end"),
                ("recent", "ended", 0, self.now - 1, "end"),
                ("live", "active", self.now + 100, None, None),
                ("waiting", "pending", self.now + 50, None, None),
                ("offline-old", "active", self.cutoff - 1, None, None),
                ("offline-boundary", "pending", self.cutoff, None, None)]
        self.db.executemany("INSERT INTO together_sessions VALUES(?,?,?,?,?)", rows)
        self.db.commit()
        self.assertEqual(purge_messages(self.path, now=self.now, dry_run=True)["eligible_together"], 2)
        self.assertEqual(self.db.execute("SELECT COUNT(*) FROM together_sessions").fetchone()[0], 7)
        self.assertEqual(purge_messages(self.path, now=self.now)["deleted_together"], 2)
        states = {r[0]: r[1:] for r in self.db.execute("SELECT id,status,ended,reason FROM together_sessions")}
        self.assertEqual(set(states), {"boundary", "recent", "live", "waiting", "offline-boundary"})
        self.assertEqual(states["live"][0], "active")
        self.assertEqual(states["offline-boundary"], ("ended", self.cutoff, "expired"))

    def test_legacy_schema_and_idempotent_repeated_cleanup(self):
        self.db.execute("DROP TABLE together_sessions")
        self.db.execute("INSERT INTO messages VALUES('old','private',NULL,1,?)", (self.cutoff - 1,))
        self.db.commit()
        self.assertEqual(purge_messages(self.path, now=self.now)["deleted_messages"], 1)
        self.assertEqual(purge_messages(self.path, now=self.now)["deleted_messages"], 0)

    def test_missing_database_is_not_created(self):
        missing = self.path.with_name("missing.sqlite3")
        with self.assertRaises(sqlite3.OperationalError):
            purge_messages(missing, now=self.now)
        self.assertFalse(missing.exists())
