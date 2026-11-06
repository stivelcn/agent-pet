"""Six-hour retention for handled mail and finished shared activities; logs counts only."""
import argparse
import json
import sqlite3
import time
from pathlib import Path

DATABASE = Path("/var/lib/agentpet-relay/messages.sqlite3")
RETENTION_SECONDS = 6 * 60 * 60
ELIGIBLE = "handled IS NOT NULL AND handled < ?"


def purge_messages(database=DATABASE, *, now=None, dry_run=False):
    now = time.time() if now is None else now
    cutoff = now - RETENTION_SECONDS
    uri = Path(database).resolve().as_uri() + "?mode=rw"
    connection = sqlite3.connect(uri, uri=True, timeout=30, isolation_level=None)
    try:
        connection.execute("PRAGMA busy_timeout=30000")
        connection.execute("PRAGMA foreign_keys=ON")
        has_together = connection.execute(
            "SELECT 1 FROM sqlite_master WHERE type='table' AND name='together_sessions'"
        ).fetchone() is not None
        if dry_run:
            eligible = connection.execute("SELECT COUNT(*) FROM messages WHERE " + ELIGIBLE, (cutoff,)).fetchone()[0]
            sessions = connection.execute(
                "SELECT COUNT(*) FROM together_sessions WHERE (status='ended' AND ended<?) OR (status!='ended' AND expires<?)",
                (cutoff, cutoff)).fetchone()[0] if has_together else 0
            return {"dry_run": True, "eligible_messages": eligible,
                    "eligible_together": sessions, "retention_hours": 6}
        connection.execute("PRAGMA secure_delete=ON")
        connection.execute("BEGIN IMMEDIATE")
        try:
            deleted = connection.execute("DELETE FROM messages WHERE " + ELIGIBLE, (cutoff,)).rowcount
            sessions = 0
            if has_together:
                # Expire offline sessions too, retaining the actual deadline as their end time.
                connection.execute("UPDATE together_sessions SET status='ended',ended=expires,reason=CASE WHEN status='pending' THEN 'expired' ELSE 'completed' END WHERE status!='ended' AND expires<=?", (now,))
                sessions = connection.execute("DELETE FROM together_sessions WHERE status='ended' AND ended<?", (cutoff,)).rowcount
            connection.commit()
        except BaseException:
            connection.rollback()
            raise
        checkpoint_busy = None
        if deleted or sessions:
            checkpoint_busy = connection.execute("PRAGMA wal_checkpoint(TRUNCATE)").fetchone()[0]
        return {"dry_run": False, "deleted_messages": deleted, "deleted_together": sessions,
                "retention_hours": 6, "checkpoint_busy": checkpoint_busy}
    finally:
        connection.close()


def main():
    parser = argparse.ArgumentParser(description="Delete mail handled and activities ended more than six hours ago.")
    parser.add_argument("--dry-run", action="store_true")
    arguments = parser.parse_args()
    print(json.dumps(purge_messages(dry_run=arguments.dry_run)), flush=True)


if __name__ == "__main__":
    main()
