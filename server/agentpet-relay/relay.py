"""AgentPet two-person relay. No access tokens or message bodies are logged."""
from __future__ import annotations
import asyncio
import hashlib
import json
import os
import secrets
import sqlite3
import string
import time
import uuid
from collections import defaultdict, deque
from pathlib import Path

import regex
from aiohttp import web

ICONS = {"heart": "❤️", "water": "💧", "meal": "🍚", "rest": "☕", "hug": "🤗", "look": "👀"}
INVITE_TTL = 600


def characters(value: str) -> int:
    return len(regex.findall(r"\X", value))


def clean_text(value, maximum=20):
    if not isinstance(value, str):
        raise Problem("invalid_text", 400)
    value = value.strip()
    if not value or len(value.encode()) > 1024 or characters(value) > maximum:
        raise Problem("invalid_text", 400)
    # ZWJ/variation selectors are allowed for emoji, but not control characters.
    if regex.search(r"[\p{Cc}\p{Zl}\p{Zp}]", value):
        raise Problem("invalid_text", 400)
    return value


def random_code():
    alphabet = string.ascii_uppercase + string.digits
    while True:
        value = "".join(secrets.choice(alphabet) for _ in range(6))
        if any(c.isalpha() for c in value) and any(c.isdigit() for c in value):
            return value


class Problem(Exception):
    def __init__(self, code, status=409):
        self.code, self.status = code, status


class Relay:
    def __init__(self, database):
        self.db = sqlite3.connect(database)
        self.db.row_factory = sqlite3.Row
        self.db.execute("PRAGMA journal_mode=WAL")
        self.db.execute("PRAGMA foreign_keys=ON")
        self.db.executescript("""
        CREATE TABLE IF NOT EXISTS devices(id TEXT PRIMARY KEY, token_hash TEXT UNIQUE NOT NULL,
            name TEXT NOT NULL, created REAL NOT NULL);
        CREATE TABLE IF NOT EXISTS pairs(id TEXT PRIMARY KEY, a TEXT NOT NULL REFERENCES devices(id),
            b TEXT NOT NULL REFERENCES devices(id), active INTEGER NOT NULL DEFAULT 1, created REAL NOT NULL);
        CREATE INDEX IF NOT EXISTS pair_a ON pairs(a,active);
        CREATE INDEX IF NOT EXISTS pair_b ON pairs(b,active);
        CREATE TABLE IF NOT EXISTS invites(code TEXT PRIMARY KEY, creator TEXT NOT NULL REFERENCES devices(id),
            candidate TEXT REFERENCES devices(id), expires REAL NOT NULL);
        CREATE TABLE IF NOT EXISTS messages(id TEXT PRIMARY KEY, client_id TEXT NOT NULL,
            pair_id TEXT NOT NULL REFERENCES pairs(id), sender TEXT NOT NULL REFERENCES devices(id),
            recipient TEXT NOT NULL REFERENCES devices(id), sender_name TEXT NOT NULL,
            text TEXT, icon TEXT, reply_to TEXT, created REAL NOT NULL, delivered REAL, handled REAL,
            UNIQUE(sender,client_id));
        CREATE INDEX IF NOT EXISTS message_inbox ON messages(recipient,handled,created);
        """)
        self.sockets = defaultdict(set)
        self.limits = {}

    def limit(self, bucket, maximum, period):
        now = time.monotonic()
        # Bound the limiter table; expired buckets contain no live accounting.
        for key, (_, expiry) in list(self.limits.items()):
            if expiry <= now:
                del self.limits[key]
        count, expiry = self.limits.get(bucket, (0, now + period))
        if count >= maximum:
            raise Problem("rate_limited", 429)
        self.limits[bucket] = (count + 1, expiry)

    def active_pair(self, device):
        return self.db.execute("SELECT * FROM pairs WHERE active=1 AND (a=? OR b=?)", (device, device)).fetchone()

    def name(self, device):
        return self.db.execute("SELECT name FROM devices WHERE id=?", (device,)).fetchone()[0]

    def invite(self, device):
        return self.db.execute("SELECT * FROM invites WHERE expires>? AND (creator=? OR candidate=?)",
                               (time.time(), device, device)).fetchone()

    def snapshot(self, device):
        pair = self.active_pair(device)
        pairing = None
        if pair:
            peer = pair["b"] if pair["a"] == device else pair["a"]
            pairing = {"id": pair["id"], "peerName": self.name(peer)}
        invite = self.invite(device)
        invitation = None
        if invite:
            is_creator = invite["creator"] == device
            peer = invite["candidate"] if is_creator else invite["creator"]
            invitation = {"code": invite["code"], "expiresAt": invite["expires"],
                          "isCreator": is_creator, "peerName": self.name(peer) if peer else None,
                          "awaitingConfirmation": invite["candidate"] is not None}
        inbox = self.db.execute("SELECT * FROM messages WHERE recipient=? AND handled IS NULL ORDER BY created,id", (device,))
        sent = self.db.execute("SELECT * FROM messages WHERE sender=? ORDER BY created DESC,id LIMIT 50", (device,))
        return {"deviceID": device, "name": self.name(device), "pair": pairing,
                "invitation": invitation, "incoming": [self.message(row) for row in inbox],
                "sent": [self.message(row) for row in sent]}

    @staticmethod
    def message(row):
        return {"id": row["id"], "clientID": row["client_id"], "pairID": row["pair_id"],
                "senderName": row["sender_name"], "text": row["text"], "icon": row["icon"],
                "replyTo": row["reply_to"], "createdAt": row["created"],
                "deliveredAt": row["delivered"], "handledAt": row["handled"]}

    async def notify(self, *devices):
        for device in set(devices):
            for socket in tuple(self.sockets.get(device, ())):
                try:
                    await socket.send_json({"type": "changed"})
                except (ConnectionError, RuntimeError):
                    pass

    def related(self, device):
        result = {device}
        pair = self.active_pair(device)
        if pair:
            result.update((pair["a"], pair["b"]))
        invite = self.invite(device)
        if invite:
            result.update(x for x in (invite["creator"], invite["candidate"]) if x)
        return result


@web.middleware
async def errors(request, handler):
    try:
        response = await handler(request)
    except Problem as error:
        response = web.json_response({"error": error.code}, status=error.status)
    except (json.JSONDecodeError, UnicodeDecodeError, TypeError, ValueError):
        response = web.json_response({"error": "invalid_request"}, status=400)
    response.headers["Cache-Control"] = "no-store"
    response.headers["X-Content-Type-Options"] = "nosniff"
    return response


@web.middleware
async def authenticate(request, handler):
    relay = request.app["relay"]
    ip = request.remote or "unknown"
    if ip in ("127.0.0.1", "::1"):
        ip = request.headers.get("X-Real-IP", ip)
    request["ip"] = ip
    if request.path not in ("/healthz", "/v1/devices"):
        auth = request.headers.get("Authorization", "")
        if not auth.startswith("Bearer ") or len(auth) > 256:
            raise Problem("unauthorized", 401)
        digest = hashlib.sha256(auth[7:].encode()).hexdigest()
        row = relay.db.execute("SELECT id FROM devices WHERE token_hash=?", (digest,)).fetchone()
        if not row:
            raise Problem("unauthorized", 401)
        request["device"] = row[0]
        relay.limit(("request", row[0]), 600, 60)
    return await handler(request)


async def body(request):
    value = await request.json()
    if not isinstance(value, dict):
        raise Problem("invalid_request", 400)
    return value


async def health(request):
    return web.json_response({"ok": True, "service": "agentpet-relay", "protocol": 1})


async def register(request):
    r = request.app["relay"]
    r.limit(("register", request["ip"]), 30, 3600)
    data = await body(request)
    name = clean_text(data.get("name", "Pet friend"))
    device, token = str(uuid.uuid4()), secrets.token_urlsafe(32)
    with r.db:
        r.db.execute("INSERT INTO devices VALUES(?,?,?,?)", (device, hashlib.sha256(token.encode()).hexdigest(), name, time.time()))
    return web.json_response({"deviceID": device, "token": token}, status=201)


async def sync(request):
    return web.json_response(request.app["relay"].snapshot(request["device"]))


async def change_name(request):
    r, device = request.app["relay"], request["device"]
    name = clean_text((await body(request)).get("name"))
    with r.db:
        r.db.execute("UPDATE devices SET name=? WHERE id=?", (name, device))
    await r.notify(*r.related(device))
    return web.json_response(r.snapshot(device))


async def create(request):
    r, device = request.app["relay"], request["device"]
    r.limit(("invite", device), 10, 600)
    if r.active_pair(device):
        raise Problem("already_paired")
    previous = r.related(device)
    with r.db:
        r.db.execute("DELETE FROM invites WHERE expires<=? OR creator=? OR candidate=?", (time.time(), device, device))
        code = random_code()
        while r.db.execute("SELECT 1 FROM invites WHERE code=?", (code,)).fetchone():
            code = random_code()
        r.db.execute("INSERT INTO invites VALUES(?,?,NULL,?)", (code, device, time.time() + INVITE_TTL))
    await r.notify(*previous)
    return web.json_response(r.snapshot(device))


async def join(request):
    r, device = request.app["relay"], request["device"]
    r.limit(("guess_device", device), 10, 600)
    r.limit(("guess_ip", request["ip"]), 30, 600)
    code = (await body(request)).get("code", "")
    if not isinstance(code, str):
        raise Problem("invalid_code", 400)
    code = code.strip().upper()
    if not regex.fullmatch(r"(?=.*[A-Z])(?=.*[0-9])[A-Z0-9]{6}", code):
        raise Problem("invalid_code", 400)
    if r.active_pair(device):
        raise Problem("already_paired")
    with r.db:
        invite = r.db.execute("SELECT * FROM invites WHERE code=? AND expires>?", (code, time.time())).fetchone()
        if not invite or invite["creator"] == device:
            raise Problem("invite_unavailable")
        if invite["candidate"] not in (None, device):
            raise Problem("invite_unavailable")
        current = r.invite(device)
        if current and current["code"] != code:
            raise Problem("cancel_invitation_first")
        if r.active_pair(invite["creator"]):
            raise Problem("invite_unavailable")
        r.db.execute("UPDATE invites SET candidate=? WHERE code=?", (device, code))
    await r.notify(device, invite["creator"])
    return web.json_response(r.snapshot(device))


async def confirm(request):
    r, device = request.app["relay"], request["device"]
    data = await body(request)
    with r.db:
        invite = r.invite(device)
        if not invite or invite["creator"] != device or not invite["candidate"] or data.get("code") != invite["code"]:
            raise Problem("invite_unavailable")
        peer = invite["candidate"]
        if r.active_pair(device) or r.active_pair(peer):
            raise Problem("already_paired")
        r.db.execute("INSERT INTO pairs VALUES(?,?,?,1,?)", (str(uuid.uuid4()), device, peer, time.time()))
        r.db.execute("DELETE FROM invites WHERE creator IN (?,?) OR candidate IN (?,?)", (device, peer, device, peer))
    await r.notify(device, peer)
    return web.json_response(r.snapshot(device))


async def disconnect(request):
    r, device = request.app["relay"], request["device"]
    related = r.related(device)
    with r.db:
        r.db.execute("UPDATE pairs SET active=0 WHERE a=? OR b=?", (device, device))
        r.db.execute("DELETE FROM invites WHERE creator=? OR candidate=?", (device, device))
    await r.notify(*related)
    return web.json_response(r.snapshot(device))


async def send(request):
    r, device = request.app["relay"], request["device"]
    data = await body(request)
    client = data.get("clientID", "")
    if not isinstance(client, str) or not regex.fullmatch(r"[a-zA-Z0-9-]{16,64}", client):
        raise Problem("invalid_request", 400)
    text = clean_text(data["text"]) if data.get("text") is not None else None
    icon = data.get("icon")
    if icon is not None and (not isinstance(icon, str) or icon not in ICONS):
        raise Problem("invalid_icon", 400)
    if (text is None) == (icon is None):
        raise Problem("invalid_text", 400)
    pair_id, reply = data.get("pairID"), data.get("replyTo")
    if not isinstance(pair_id, str) or (reply is not None and not isinstance(reply, str)):
        raise Problem("invalid_request", 400)
    existing = r.db.execute("SELECT * FROM messages WHERE sender=? AND client_id=?", (device, client)).fetchone()
    if existing:
        if (existing["pair_id"], existing["text"], existing["icon"], existing["reply_to"]) != (pair_id, text, icon, reply):
            raise Problem("idempotency_conflict")
        return web.json_response(r.snapshot(device))
    r.limit(("send", device), 30, 60)
    with r.db:
        pair = r.active_pair(device)
        if not pair or pair["id"] != pair_id:
            raise Problem("not_paired")
        peer = pair["b"] if pair["a"] == device else pair["a"]
        count = r.db.execute("SELECT COUNT(*) FROM messages WHERE recipient=? AND handled IS NULL", (peer,)).fetchone()[0]
        if count >= 200:
            raise Problem("inbox_full")
        if reply:
            parent = r.db.execute("SELECT * FROM messages WHERE id=? AND recipient=? AND pair_id=?", (reply, device, pair_id)).fetchone()
            if not parent:
                raise Problem("invalid_reply", 400)
        now = time.time()
        r.db.execute("INSERT INTO messages(id,client_id,pair_id,sender,recipient,sender_name,text,icon,reply_to,created) VALUES(?,?,?,?,?,?,?,?,?,?)",
                     (str(uuid.uuid4()), client, pair_id, device, peer, r.name(device), text, icon, reply, now))
        if reply:
            r.db.execute("UPDATE messages SET delivered=COALESCE(delivered,?),handled=COALESCE(handled,?) WHERE id=?", (now, now, reply))
    await r.notify(device, peer)
    return web.json_response(r.snapshot(device), status=201)


async def acknowledge(request):
    r, device = request.app["relay"], request["device"]
    data = await body(request)
    ids, kind = data.get("ids"), data.get("kind")
    if not isinstance(ids, list) or len(ids) > 200 or not all(isinstance(x, str) and len(x) <= 64 for x in ids) or kind not in ("delivered", "handled"):
        raise Problem("invalid_request", 400)
    peers = set()
    now = time.time()
    with r.db:
        for mid in set(ids):
            row = r.db.execute("SELECT sender FROM messages WHERE id=? AND recipient=?", (mid, device)).fetchone()
            if not row:
                continue
            peers.add(row[0])
            r.db.execute("UPDATE messages SET delivered=COALESCE(delivered,?) WHERE id=?", (now, mid))
            if kind == "handled":
                r.db.execute("UPDATE messages SET handled=COALESCE(handled,?) WHERE id=?", (now, mid))
    await r.notify(device, *peers)
    return web.json_response(r.snapshot(device))


async def events(request):
    r, device = request.app["relay"], request["device"]
    if len(r.sockets[device]) >= 3:
        raise Problem("too_many_connections", 429)
    socket = web.WebSocketResponse(heartbeat=25, max_msg_size=1024)
    await socket.prepare(request)
    r.sockets[device].add(socket)
    try:
        await socket.send_json({"type": "changed"})
        async for _ in socket:
            pass
    finally:
        r.sockets[device].discard(socket)
        if not r.sockets[device]:
            del r.sockets[device]
    return socket


def make_app(database):
    app = web.Application(middlewares=[errors, authenticate], client_max_size=8192)
    app["relay"] = Relay(database)
    app.add_routes([web.get("/healthz", health), web.post("/v1/devices", register),
                    web.get("/v1/sync", sync), web.get("/v1/events", events),
                    web.post("/v1/device/name", change_name), web.post("/v1/pairing/create", create),
                    web.post("/v1/pairing/join", join), web.post("/v1/pairing/confirm", confirm),
                    web.post("/v1/pairing/disconnect", disconnect), web.post("/v1/messages", send),
                    web.post("/v1/messages/ack", acknowledge)])
    async def shutdown(app):
        for sockets in list(app["relay"].sockets.values()):
            for socket in tuple(sockets):
                await socket.close(code=1001)
    async def cleanup(app):
        app["relay"].db.close()
    app.on_shutdown.append(shutdown)
    app.on_cleanup.append(cleanup)
    return app


if __name__ == "__main__":
    path = Path(os.environ.get("RELAY_DB", "/var/lib/agentpet-relay/messages.sqlite3"))
    path.parent.mkdir(parents=True, exist_ok=True)
    web.run_app(make_app(str(path)), host="127.0.0.1", port=int(os.environ.get("PORT", "7831")), access_log=None)
