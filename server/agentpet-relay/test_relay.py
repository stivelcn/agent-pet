import json
import tempfile
import unittest
import uuid
from pathlib import Path
from aiohttp.test_utils import AioHTTPTestCase
from relay import make_app, random_code, characters


class RelayTests(AioHTTPTestCase):
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


if __name__ == '__main__':
    unittest.main()
