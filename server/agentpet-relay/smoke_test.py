"""Explicit production smoke check. Creates only isolated QA identities.
No credentials, pairing codes or message contents are printed or saved.
"""
import asyncio
import json
import uuid
import aiohttp

BASE = 'https://imagepro.ycgod.online/agentpet-relay/'

async def main():
    async with aiohttp.ClientSession(timeout=aiohttp.ClientTimeout(total=20)) as session:
        async def call(path, token=None, data=None, status=200):
            headers = {'Authorization': 'Bearer ' + token} if token else {}
            async with session.request('POST' if data is not None else 'GET', BASE + path, headers=headers, json=data) as response:
                result = await response.json()
                assert response.status == status, (path, response.status, result.get('error'))
                return result
        assert (await call('healthz'))['ok']
        a = await call('v1/devices', data={'name': 'QA WSS A'}, status=201)
        b = await call('v1/devices', data={'name': 'QA WSS B'}, status=201)
        invitation = await call('v1/pairing/create', a['token'], {})
        code = invitation['invitation']['code']
        assert len(code) == 6 and any(c.isdigit() for c in code) and any(c.isalpha() for c in code)
        await call('v1/pairing/join', b['token'], {'code': code.lower()})
        pair = (await call('v1/pairing/confirm', a['token'], {'code': code}))['pair']['id']
        headers = {'Authorization': 'Bearer ' + b['token']}
        async with session.ws_connect(BASE.replace('https:', 'wss:') + 'v1/events', headers=headers, heartbeat=20) as ws:
            assert (await ws.receive_json(timeout=10))['type'] == 'changed'
            payload = {'pairID': pair, 'clientID': str(uuid.uuid4()), 'icon': 'water'}
            sent = await call('v1/messages', a['token'], payload, status=201)
            assert (await ws.receive_json(timeout=10))['type'] == 'changed'
        # Offline recipient: no socket needed. Sync does not auto-dismiss it.
        incoming = (await call('v1/sync', b['token']))['incoming']
        assert len(incoming) == 1 and incoming[0]['icon'] == 'water'
        await call('v1/messages', a['token'], payload)  # retry cannot duplicate
        assert len((await call('v1/sync', b['token']))['incoming']) == 1
        mid = incoming[0]['id']
        await call('v1/messages/ack', b['token'], {'ids': [mid], 'kind': 'delivered'})
        assert len((await call('v1/sync', b['token']))['incoming']) == 1
        await call('v1/messages/ack', b['token'], {'ids': [mid], 'kind': 'handled'})
        assert not (await call('v1/sync', b['token']))['incoming']
        assert (await call('v1/sync', a['token']))['sent'][0]['handledAt'] is not None
        await call('v1/pairing/disconnect', a['token'], {})
        print('PASS: HTTPS, mixed 6-character code, lowercase join, two-party confirmation, WSS notification, offline catch-up, idempotency, delivery/handled receipts, unpair')

if __name__ == '__main__':
    asyncio.run(main())
