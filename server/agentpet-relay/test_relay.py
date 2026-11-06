import json
import base64
import hashlib
import sqlite3
import struct
import tempfile
import unittest
import uuid
import time
import zlib
from pathlib import Path
from aiohttp.test_utils import AioHTTPTestCase
from relay import make_app, random_code, characters


class RelayTests(AioHTTPTestCase):
    async def profiles(self, a, b):
        for headers, pet in [(a, 'lulu'), (b, 'lumei')]:
            await self.post('device/pet', headers, {'name': pet, 'builtinID': pet, 'interactionVersion': 1})

    async def test_pet_profiles_visits_reply_and_sender_appearance_snapshot(self):
        a, b, pair = await self.pair()
        await self.profiles(a, b)
        state = await (await self.client.get('/v1/sync', headers=b)).json()
        self.assertEqual(state['pair']['peerPet']['builtinID'], 'lulu')
        data = {'pairID': pair, 'clientID': str(uuid.uuid4()), 'gesture': 'poke', 'expiresAt': time.time() + 30}
        sent = await self.post('messages', a, data, status=201)
        parent = sent['sent'][0]['id']
        self.assertEqual(sent['sent'][0]['senderPet']['builtinID'], 'lulu')
        await self.post('device/pet', a, {'name': 'changed', 'builtinID': 'lumei', 'interactionVersion': 1})
        inbox = (await (await self.client.get('/v1/sync', headers=b)).json())['incoming']
        self.assertEqual(inbox[0]['senderPet']['builtinID'], 'lulu')
        self.assertEqual(inbox[0]['gesture'], 'poke')
        self.assertTrue(inbox[0]['text'])  # readable fallback on old clients
        replied = await self.post('messages', b, {'pairID': pair, 'clientID': str(uuid.uuid4()),
            'gesture': 'hug', 'expiresAt': time.time() + 30, 'replyTo': parent}, status=201)
        self.assertEqual(replied['incoming'], [])
        self.assertEqual(replied['sent'][0]['gesture'], 'hug')

    async def test_gesture_expiry_cooldown_legacy_peer_and_idempotency(self):
        a, b, pair = await self.pair()
        def payload(**kw):
            return dict(pairID=pair, clientID=str(uuid.uuid4()), gesture='peek', expiresAt=time.time() + 30, **kw)
        state = await self.post('messages', a, payload(), status=409)
        self.assertEqual(state['error'], 'interactions_unavailable')
        await self.profiles(a, b)
        bad = payload(); bad['expiresAt'] = time.time() - 1
        self.assertEqual((await self.post('messages', a, bad, status=409))['error'], 'gesture_expired')
        bad['expiresAt'] = float('nan')
        await self.post('messages', a, bad, status=409)
        original = payload()
        await self.post('messages', a, original, status=201)
        self.assertEqual((await self.post('messages', a, payload(), status=429))['error'], 'gesture_cooldown')
        # Duplicate recognition precedes cooldown and expiry, including after service restart.
        await self.post('messages', a, original)
        from unittest.mock import patch
        with patch('relay.time.time', return_value=time.time() + 40):
            await self.post('messages', a, original)
            await self.post('messages', a, dict(original, clientID=str(uuid.uuid4())), status=409)
        await self.post('messages', a, dict(original, gesture='poke'), status=409)
        for bad in [{'gesture': []}, {'gesture': 'unknown'}, {'gesture': 'poke', 'text': 'hi'},
                    {'gesture': 'hug', 'expiresAt': True}, {'gesture': 'peek', 'expiresAt': None}]:
            value = payload(); value.update(bad)
            await self.post('messages', a, value, status=400)

    async def test_custom_portrait_is_bounded_validated_and_private_to_pair(self):
        def chunk(kind, value):
            return struct.pack('>I', len(value)) + kind + value + struct.pack('>I', zlib.crc32(kind + value) & 0xffffffff)
        png = b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', 1, 1, 8, 6, 0, 0, 0))
        png += chunk(b'IDAT', zlib.compress(b'\x00\xff\x00\x00\xff')) + chunk(b'IEND', b'')
        encoded = base64.b64encode(png).decode()
        a, b, pair = await self.pair()
        profile = {'name': 'Custom', 'thumbnailPNG': encoded, 'interactionVersion': 1}
        await self.post('device/pet', a, profile)
        peer = (await (await self.client.get('/v1/sync', headers=b)).json())['pair']['peerPet']
        self.assertEqual(peer['thumbnailPNG'], encoded)
        stranger = await self.device('stranger')
        state = await (await self.client.get('/v1/sync', headers=stranger)).json()
        self.assertIsNone(state['pair']); self.assertIsNone(state['pet'])
        for bad in ['not base64', base64.b64encode(b'not png').decode(), encoded[:-8], 'a' * 43693]:
            await self.post('device/pet', a, dict(profile, thumbnailPNG=bad), status=400)
        await self.post('device/pet', a, dict(profile, builtinID='../lulu'), status=400)
        await self.post('device/pet', a, dict(profile, interactionVersion=True), status=400)

    async def test_additive_schema_migration_preserves_legacy_credentials_and_messages(self):
        from relay import Relay
        path = str(Path(self.folder.name) / 'legacy.sqlite3')
        old = sqlite3.connect(path)
        old.executescript('''
            CREATE TABLE devices(id TEXT PRIMARY KEY, token_hash TEXT UNIQUE NOT NULL, name TEXT NOT NULL, created REAL NOT NULL);
            CREATE TABLE messages(id TEXT PRIMARY KEY, client_id TEXT NOT NULL, pair_id TEXT NOT NULL,
                sender TEXT NOT NULL, recipient TEXT NOT NULL, sender_name TEXT NOT NULL,
                text TEXT, icon TEXT, reply_to TEXT, created REAL NOT NULL, delivered REAL, handled REAL,
                UNIQUE(sender,client_id));
        ''')
        digest = hashlib.sha256(b'old-token').hexdigest()
        old.execute('INSERT INTO devices VALUES(?,?,?,?)', ('old', digest, 'old friend', 1))
        old.execute('INSERT INTO messages(id,client_id,pair_id,sender,recipient,sender_name,text,created) VALUES(?,?,?,?,?,?,?,?)',
                    ('message', 'client', 'old-pair', 'sender', 'old', 'sender name', 'unread', 1))
        old.commit(); old.close()
        for _ in range(2):
            migrated = Relay(path)
            state = migrated.snapshot('old')
            self.assertEqual(state['incoming'][0]['text'], 'unread')
            self.assertIsNone(state['incoming'][0]['senderPet'])
            self.assertEqual(migrated.db.execute('SELECT token_hash FROM devices').fetchone()[0], digest)
            migrated.db.close()

    async def get_application(self):
        self.folder = tempfile.TemporaryDirectory()
        return make_app(str(Path(self.folder.name) / "test.sqlite3"))

    async def asyncTearDown(self):
        await super().asyncTearDown()
        self.folder.cleanup()

    async def device(self, name):
        response = await self.client.post('/v1/devices', json={"name": name})
        self.assertEqual(response.status, 201)
        data = await response.json()
        return {"Authorization": "Bearer " + data["token"]}

    async def post(self, path, headers, data=None, status=200):
        response = await self.client.post('/v1/' + path, headers=headers, json=data or {})
        value = await response.json()
        self.assertEqual(response.status, status, value)
        return value

    async def pair(self):
        a, b = await self.device("Lulu"), await self.device("Lumei")
        state = await self.post('pairing/create', a)
        code = state['invitation']['code']
        await self.post('pairing/join', b, {"code": code.lower()})
        state = await self.post('pairing/confirm', a, {"code": code})
        return a, b, state['pair']['id']

    async def send(self, a, pair, **kw):
        data = {"pairID": pair, "clientID": str(uuid.uuid4()), "text": "你好👨‍👩‍👧‍👦"}
        data.update(kw)
        return await self.post('messages', a, data, status=201)

    async def test_random_codes_and_case_insensitive_two_party_confirmation(self):
        for _ in range(1000):
            code = random_code()
            self.assertRegex(code, r'^[A-Z0-9]{6}$')
            self.assertTrue(any(c.isdigit() for c in code))
            self.assertTrue(any(c.isalpha() for c in code))
        a, b = await self.device("A"), await self.device("B")
        state = await self.post('pairing/create', a)
        code = state['invitation']['code']
        state = await self.post('pairing/join', b, {"code": code.lower()})
        self.assertIsNone(state['pair'])
        await self.post('pairing/confirm', b, {"code": code}, status=409)
        await self.post('pairing/confirm', a, {"code": code})
        third = await self.device("C")
        await self.post('pairing/join', third, {"code": code}, status=409)

    async def test_third_member_cannot_join_or_confirm(self):
        a, b, c = await self.device("A"), await self.device("B"), await self.device("C")
        code = (await self.post('pairing/create', a))['invitation']['code']
        await self.post('pairing/join', b, {"code": code})
        await self.post('pairing/join', c, {"code": code}, status=409)
        await self.post('pairing/confirm', c, {"code": code}, status=409)
        state = await self.post('pairing/confirm', a, {"code": code})
        self.assertEqual(state['pair']['peerName'], 'B')

    async def test_expired_cancelled_and_guessed_codes(self):
        a, b = await self.device('A'), await self.device('B')
        code = (await self.post('pairing/create', a))['invitation']['code']
        self.app['relay'].db.execute('UPDATE invites SET expires=0')
        self.app['relay'].db.commit()
        await self.post('pairing/join', b, {'code': code}, status=409)
        code = (await self.post('pairing/create', a))['invitation']['code']
        await self.post('pairing/disconnect', a)
        await self.post('pairing/join', b, {'code': code}, status=409)
        for _ in range(8):
            await self.post('pairing/join', b, {'code': 'A12345'}, status=409)
        await self.post('pairing/join', b, {'code': 'A12345'}, status=429)

    async def test_offline_queue_receipts_and_manual_handling(self):
        a, b, pair = await self.pair()
        state = await self.send(a, pair)
        message = state['sent'][0]
        self.assertIsNone(message['deliveredAt'])
        for _ in range(2):
            response = await self.client.get('/v1/sync', headers=b)
            self.assertEqual(len((await response.json())['incoming']), 1)
        await self.post('messages/ack', a, {'ids': [message['id']], 'kind': 'handled'})
        state = await self.post('messages/ack', b, {'ids': [message['id']], 'kind': 'delivered'})
        self.assertEqual(len(state['incoming']), 1)
        self.assertIsNotNone(state['incoming'][0]['deliveredAt'])
        state = await self.post('messages/ack', b, {'ids': [message['id']], 'kind': 'handled'})
        self.assertEqual(state['incoming'], [])
        state = await (await self.client.get('/v1/sync', headers=a)).json()
        self.assertIsNotNone(state['sent'][0]['handledAt'])

    async def test_idempotency_rejects_changed_payload(self):
        a, b, pair = await self.pair()
        client = str(uuid.uuid4())
        await self.send(a, pair, clientID=client)
        await self.post('messages', a, {'pairID': pair, 'clientID': client, 'text': '你好👨‍👩‍👧‍👦'})
        await self.post('messages', a, {'pairID': pair, 'clientID': client, 'text': 'changed'}, status=409)
        state = await (await self.client.get('/v1/sync', headers=b)).json()
        self.assertEqual(len(state['incoming']), 1)

    async def test_successful_reply_is_atomic_but_failed_reply_does_not_clear(self):
        a, b, pair = await self.pair()
        parent = (await self.send(a, pair))['sent'][0]['id']
        await self.post('messages', b, {'pairID': pair, 'clientID': str(uuid.uuid4()), 'text': 'a'*21, 'replyTo': parent}, status=400)
        state = await (await self.client.get('/v1/sync', headers=b)).json()
        self.assertEqual(len(state['incoming']), 1)
        state = await self.send(b, pair, text='收到', replyTo=parent)
        self.assertEqual(state['incoming'], [])
        await self.post('messages', a, {'pairID': pair, 'clientID': str(uuid.uuid4()), 'text': 'bad', 'replyTo': parent}, status=400)

    async def test_grapheme_limit_icons_and_input_validation(self):
        a, b, pair = await self.pair()
        family = '👨‍👩‍👧‍👦'
        self.assertEqual(characters(family), 1)
        await self.send(a, pair, text=family*20)
        for bad in ['x'*21, ' ', 'a\nb', 'a\x00b', family*21]:
            await self.post('messages', a, {'pairID': pair, 'clientID': str(uuid.uuid4()), 'text': bad}, status=400)
        await self.post('messages', a, {'pairID': pair, 'clientID': str(uuid.uuid4()), 'icon': 'water'}, status=201)
        await self.post('messages', a, {'pairID': pair, 'clientID': str(uuid.uuid4()), 'icon': 'url'}, status=400)
        await self.post('messages', a, {'pairID': pair, 'clientID': str(uuid.uuid4()), 'text': 'hi', 'icon': 'water'}, status=400)

    async def test_unpair_preserves_unread_and_disallows_cross_pair_send(self):
        a, b, pair = await self.pair()
        parent = (await self.send(a, pair))['sent'][0]['id']
        await self.post('pairing/disconnect', b)
        state = await (await self.client.get('/v1/sync', headers=b)).json()
        self.assertIsNone(state['pair'])
        self.assertEqual(len(state['incoming']), 1)
        await self.post('messages', b, {'pairID': pair, 'clientID': str(uuid.uuid4()), 'text': 'old'}, status=409)
        state = await self.post('messages/ack', b, {'ids': [parent], 'kind': 'handled'})
        self.assertEqual(state['incoming'], [])

    async def test_database_restart_preserves_unread_and_auth(self):
        a, b, pair = await self.pair()
        await self.send(a, pair)
        from relay import Relay
        original = self.app['relay']
        original.db.close()
        original.db = Relay(str(Path(self.folder.name) / 'test.sqlite3')).db
        state = await (await self.client.get('/v1/sync', headers=b)).json()
        self.assertEqual(len(state['incoming']), 1)
        self.assertEqual(state['pair']['id'], pair)
        stored = original.db.execute('SELECT token_hash FROM devices').fetchall()
        self.assertNotIn(a['Authorization'][7:], [row[0] for row in stored])

    async def test_message_rate_and_unread_backlog_are_bounded(self):
        a, b, pair = await self.pair()
        for _ in range(30):
            await self.send(a, pair, text='hi')
        await self.post('messages', a, {'pairID': pair, 'clientID': str(uuid.uuid4()), 'text': 'later'}, status=429)
        r = self.app['relay']
        row = r.db.execute('SELECT * FROM messages LIMIT 1').fetchone()
        r.limits.clear()
        with r.db:
            for _ in range(170):
                r.db.execute('INSERT INTO messages(id,client_id,pair_id,sender,recipient,sender_name,text,created) VALUES(?,?,?,?,?,?,?,?)',
                    (str(uuid.uuid4()), str(uuid.uuid4()), pair, row['sender'], row['recipient'], 'test', 'hi', 1))
        await self.post('messages', a, {'pairID': pair, 'clientID': str(uuid.uuid4()), 'text': 'later'}, status=409)

    async def test_foreign_pair_and_unknown_icon_cannot_inject_messages(self):
        a, b, pair = await self.pair()
        stranger = await self.device('stranger')
        await self.post('messages', stranger, {'pairID': pair, 'clientID': str(uuid.uuid4()), 'text': 'intruder'}, status=409)
        response = await self.client.post('/v1/messages', headers=a, json={'pairID': pair, 'clientID': str(uuid.uuid4()), 'icon': ['water']})
        self.assertEqual(response.status, 400)
        state = await (await self.client.get('/v1/sync', headers=b)).json()
        self.assertEqual(state['incoming'], [])

    async def test_auth_and_websocket_notification(self):
        response = await self.client.get('/v1/sync')
        self.assertEqual(response.status, 401)
        a, b, pair = await self.pair()
        ws = await self.client.ws_connect('/v1/events', headers=b)
        self.assertEqual((await ws.receive_json())['type'], 'changed')
        await self.send(a, pair)
        self.assertEqual((await ws.receive_json())['type'], 'changed')
        await ws.close()

    async def test_large_snapshots_compress_without_changing_contents_or_legacy_clients(self):
        a, b, pair = await self.pair()
        await self.profiles(a, b)
        # A real bounded PNG repeated in message-time profiles reproduces the
        # growing response that slowed sending while leaving the protocol intact.
        from smoke_test import test_portrait
        await self.post('device/pet', a, {'name': '测试宠物', 'thumbnailPNG': test_portrait(), 'interactionVersion': 1})
        for _ in range(6):
            await self.send(a, pair)
        plain = await self.client.get('/v1/sync', headers=dict(a, **{'Accept-Encoding': 'identity'}), auto_decompress=False)
        original = await plain.read()
        self.assertIsNone(plain.headers.get('Content-Encoding'))
        self.assertGreater(len(original), 100000)
        for coding in ['gzip', 'deflate']:
            compressed = await self.client.get('/v1/sync', headers=dict(a, **{'Accept-Encoding': coding}), auto_decompress=False)
            wire = await compressed.read()
            self.assertEqual(compressed.headers.get('Content-Encoding'), coding)
            self.assertEqual(compressed.headers.get('Vary'), 'Accept-Encoding')
            self.assertEqual(compressed.headers.get('Cache-Control'), 'no-store')
            self.assertEqual(int(compressed.headers['Content-Length']), len(wire))
            decoded = zlib.decompress(wire, 31 if coding == 'gzip' else 15)
            self.assertEqual(json.loads(decoded), json.loads(original))
            self.assertLess(len(wire), len(original) / 3)
        # Native URLSession transparently decompresses, like this normal client.
        automatic = await self.client.get('/v1/sync', headers=a)
        self.assertEqual(await automatic.json(), json.loads(original))
        sent = await self.client.post('/v1/messages', headers=dict(a, **{'Accept-Encoding': 'gzip'}),
            json={'pairID': pair, 'clientID': str(uuid.uuid4()), 'text': '压缩发送'}, auto_decompress=False)
        self.assertEqual(sent.status, 201)
        self.assertEqual(sent.headers.get('Content-Encoding'), 'gzip')
        self.assertEqual(json.loads(zlib.decompress(await sent.read(), 31))['sent'][0]['text'], '压缩发送')
        small = await self.client.get('/healthz', headers={'Accept-Encoding': 'gzip'}, auto_decompress=False)
        self.assertIsNone(small.headers.get('Content-Encoding'))


if __name__ == '__main__':
    unittest.main()
