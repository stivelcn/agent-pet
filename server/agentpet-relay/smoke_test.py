"""Explicit production smoke check. Creates only isolated QA identities.
No credentials, pairing codes or message contents are printed or saved.
"""
import asyncio
import argparse
import base64
import json
from pathlib import Path
import random
import struct
import time
import uuid
import zlib
import aiohttp

BASE = 'https://imagepro.ycgod.online/agentpet-relay/'

def test_portrait():
    """A bounded PNG over 8 KiB verifies the proxy's new request limit as well."""
    def chunk(kind, value):
        return struct.pack('>I', len(value)) + kind + value + struct.pack('>I', zlib.crc32(kind + value) & 0xffffffff)
    rng = random.Random(20261106)
    pixels = b''.join(b'\0' + b''.join(bytes([rng.randrange(256), rng.randrange(256), rng.randrange(256), 255])
                                     for _ in range(80)) for _ in range(80))
    png = b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', 80, 80, 8, 6, 0, 0, 0))
    png += chunk(b'IDAT', zlib.compress(pixels)) + chunk(b'IEND', b'')
    assert 8192 < len(png) <= 32768
    return base64.b64encode(png).decode()


async def main(report=None):
    result = {'ok': False, 'qaDeviceIDs': [], 'checks': []}
    async with aiohttp.ClientSession(timeout=aiohttp.ClientTimeout(total=20)) as session:
        async def call(path, token=None, data=None, status=200):
            headers = {'Authorization': 'Bearer ' + token} if token else {}
            async with session.request('POST' if data is not None else 'GET', BASE + path, headers=headers, json=data) as response:
                result = await response.json()
                assert response.status == status, (path, response.status, result.get('error'))
                return result
        health = await call('healthz')
        assert health['ok'] and health['protocol'] == 2 and 'pet-interactions-v1' in health['capabilities']
        result['checks'].append('新版协议')
        a = await call('v1/devices', data={'name': '联调甲'}, status=201)
        result['qaDeviceIDs'].append(a['deviceID'])
        if report:
            Path(report).write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n')
        b = await call('v1/devices', data={'name': '联调乙'}, status=201)
        result['qaDeviceIDs'].append(b['deviceID'])
        # Only disposable identity IDs are saved for exact cleanup; credentials stay in memory.
        if report:
            Path(report).write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n')
        for device, pet in [(a, 'lulu'), (b, 'lumei')]:
            await call('v1/device/pet', device['token'], {'name': '噜噜' if pet == 'lulu' else '噜妹',
                       'builtinID': pet, 'interactionVersion': 1})
        invitation = await call('v1/pairing/create', a['token'], {})
        code = invitation['invitation']['code']
        assert len(code) == 6 and any(c.isdigit() for c in code) and any(c.isalpha() for c in code)
        await call('v1/pairing/join', b['token'], {'code': code.lower()})
        pair = (await call('v1/pairing/confirm', a['token'], {'code': code}))['pair']['id']
        assert (await call('v1/sync', a['token']))['pair']['peerPet']['builtinID'] == 'lumei'
        assert (await call('v1/sync', b['token']))['pair']['peerPet']['builtinID'] == 'lulu'
        result['checks'].append('双方形象同步与配对')
        headers = {'Authorization': 'Bearer ' + b['token']}
        async with session.ws_connect(BASE.replace('https:', 'wss:') + 'v1/events', headers=headers, heartbeat=20) as ws:
            assert (await ws.receive_json(timeout=10))['type'] == 'changed'
            payload = {'pairID': pair, 'clientID': str(uuid.uuid4()), 'gesture': 'poke', 'expiresAt': time.time() + 30}
            began = time.monotonic()
            sent = await call('v1/messages', a['token'], payload, status=201)
            assert (await ws.receive_json(timeout=10))['type'] == 'changed'
        # Offline recipient: no socket needed. Sync does not auto-dismiss it.
        incoming = (await call('v1/sync', b['token']))['incoming']
        assert len(incoming) == 1 and incoming[0]['gesture'] == 'poke'
        assert incoming[0]['senderPet']['builtinID'] == 'lulu'
        result['checks'].append('戳戳与实时通知')
        await call('v1/messages', a['token'], payload)  # retry cannot duplicate
        assert len((await call('v1/sync', b['token']))['incoming']) == 1
        mid = incoming[0]['id']
        await call('v1/messages/ack', b['token'], {'ids': [mid], 'kind': 'delivered'})
        assert len((await call('v1/sync', b['token']))['incoming']) == 1
        expired = await call('v1/messages', a['token'], {'pairID': pair, 'clientID': str(uuid.uuid4()),
            'gesture': 'peek', 'expiresAt': time.time() - 1}, status=409)
        assert expired['error'] == 'gesture_expired'
        replied = await call('v1/messages', b['token'], {'pairID': pair, 'clientID': str(uuid.uuid4()),
            'gesture': 'hug', 'expiresAt': time.time() + 30, 'replyTo': mid}, status=201)
        assert not replied['incoming']
        assert (await call('v1/sync', a['token']))['sent'][0]['handledAt'] is not None
        hug = (await call('v1/sync', a['token']))['incoming'][0]
        assert hug['gesture'] == 'hug' and hug['senderPet']['builtinID'] == 'lumei'
        await call('v1/messages/ack', a['token'], {'ids': [hug['id']], 'kind': 'handled'})
        result['checks'].append('抱回去与原消息处理')
        await asyncio.sleep(max(0, 3.1 - (time.monotonic() - began)))
        await call('v1/messages', a['token'], {'pairID': pair, 'clientID': str(uuid.uuid4()),
            'gesture': 'peek', 'expiresAt': time.time() + 30}, status=201)
        peek = (await call('v1/sync', b['token']))['incoming'][0]
        assert peek['gesture'] == 'peek'
        await call('v1/messages/ack', b['token'], {'ids': [peek['id']], 'kind': 'handled'})
        result['checks'].append('探头、过期与重复请求去重')
        # Existing short text and icons still work after the schema migration.
        text = await call('v1/messages', a['token'], {'pairID': pair, 'clientID': str(uuid.uuid4()), 'text': '联调消息'}, status=201)
        reply = await call('v1/messages', b['token'], {'pairID': pair, 'clientID': str(uuid.uuid4()),
            'icon': 'water', 'replyTo': text['sent'][0]['id']}, status=201)
        assert not reply['incoming']
        await call('v1/messages/ack', a['token'], {'ids': [reply['sent'][0]['id']], 'kind': 'handled'})
        portrait = test_portrait()
        await call('v1/device/pet', b['token'], {'name': '测试头像', 'thumbnailPNG': portrait, 'interactionVersion': 1})
        assert (await call('v1/sync', a['token']))['pair']['peerPet']['thumbnailPNG'] == portrait
        result['checks'].append('原有传话、小头像与入口请求上限')
        await call('v1/pairing/disconnect', a['token'], {})
        assert (await call('v1/sync', b['token']))['pair'] is None
        result['ok'] = True
        if report:
            Path(report).write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n')
        print('线上验证通过：' + '、'.join(result['checks']))

if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--report', help='记录验证结论和临时身份 ID，不含凭据或消息正文')
    asyncio.run(main(parser.parse_args().report))
