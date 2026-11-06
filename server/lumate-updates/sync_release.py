#!/usr/bin/env python3
"""Mirror verified public LuMate releases. No GitHub token or third-party dependency."""
import argparse
import fcntl
import hashlib
import json
import os
from pathlib import Path
import re
import tempfile
import urllib.request
from urllib.parse import urlsplit

API = 'https://api.github.com/repos/stivelcn/lumate/releases/'
DOWNLOAD = 'https://github.com/stivelcn/lumate/releases/download/'
ROOT = Path('/srv/lumate-updates')
MAX_ASSET_SIZE = 512 * 1024 * 1024


def version(tag):
    if not isinstance(tag, str) or not re.fullmatch(r'v[0-9]+\.[0-9]+\.[0-9]+', tag):
        raise ValueError('Only stable vX.Y.Z release tags are accepted')
    parts = tuple(map(int, tag[1:].split('.')))
    if any(p > 2**63 - 1 for p in parts):
        raise ValueError('Release version is too large')
    return parts


def validate_release(release):
    tag = release['tag_name']
    version(tag)
    if release.get('draft') is not False or release.get('prerelease') is not False:
        raise ValueError('Drafts and prereleases cannot be mirrored')
    assets = []
    for asset in release['assets']:
        name = asset.get('name', '')
        if name not in {f'LuMate-{tag[1:]}-{arch}.dmg' for arch in ('universal', 'arm64', 'x86_64')}:
            continue
        digest = asset.get('digest', '')
        size = asset.get('size')
        if not isinstance(digest, str) or not re.fullmatch(r'sha256:[0-9a-fA-F]{64}', digest):
            raise ValueError('GitHub has not provided a valid SHA-256 for ' + name)
        if type(size) is not int or not 0 < size <= MAX_ASSET_SIZE:
            raise ValueError('Invalid asset size')
        if asset.get('browser_download_url') != DOWNLOAD + tag + '/' + name:
            raise ValueError('Untrusted asset URL')
        assets.append({key: asset[key] for key in ('name', 'size', 'digest', 'browser_download_url')})
    if not assets or len({a['name'] for a in assets}) != len(assets):
        raise ValueError('Release has no unique verified architecture-specific DMG')
    return {'tag_name': tag, 'body': release.get('body'), 'draft': False, 'prerelease': False, 'assets': assets}


def open_url(url):
    req = urllib.request.Request(url, headers={'User-Agent': 'LuMate-release-mirror/1.0', 'Accept': 'application/vnd.github+json'})
    response = urllib.request.urlopen(req, timeout=30)
    final = urlsplit(response.url)
    # GitHub redirects public assets to its authenticated release CDN, never to arbitrary HTTP hosts.
    if final.scheme != 'https' or final.hostname not in {'github.com', 'api.github.com', 'release-assets.githubusercontent.com', 'objects.githubusercontent.com'}:
        response.close()
        raise ValueError('Untrusted download redirect')
    return response


def valid_file(path, asset):
    if path.is_symlink() or not path.is_file() or path.stat().st_size != asset['size']:
        return False
    digest = hashlib.sha256()
    with path.open('rb') as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b''):
            digest.update(chunk)
    return digest.hexdigest() == asset['digest'][7:].lower()


def sync(root, tag='latest', opener=open_url):
    if tag != 'latest':
        version(tag)
    state, public = root / 'state', root / 'public'
    state.mkdir(parents=True, exist_ok=True)
    public.mkdir(parents=True, exist_ok=True)
    with (state / 'sync.lock').open('a') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        endpoint = API + ('latest' if tag == 'latest' else 'tags/' + tag)
        with opener(endpoint) as response:
            metadata = validate_release(json.load(response))
        latest = public / 'latest.json'
        previous = json.loads(latest.read_text()) if latest.exists() else None
        # A delayed workflow for an older release must never roll latest.json back.
        if previous and version(previous['tag_name']) > version(metadata['tag_name']):
            return {'status': 'ignored-older-release', 'tag': metadata['tag_name']}
        destination = public / metadata['tag_name']
        destination.mkdir(mode=0o755, exist_ok=True)
        with tempfile.TemporaryDirectory(dir=public, prefix='.sync-') as temporary:
            pending = []
            for asset in metadata['assets']:
                target = destination / asset['name']
                if valid_file(target, asset):
                    continue
                staged = Path(temporary) / asset['name']
                count = 0
                with opener(asset['browser_download_url']) as source, staged.open('xb') as output:
                    for chunk in iter(lambda: source.read(1024 * 1024), b''):
                        count += len(chunk)
                        if count > asset['size']:
                            raise ValueError('Asset is larger than declared by GitHub')
                        output.write(chunk)
                    output.flush()
                    os.fsync(output.fileno())
                if not valid_file(staged, asset):
                    raise ValueError('Downloaded bytes do not match GitHub size/SHA-256')
                staged.chmod(0o644)
                pending.append((staged, target))
            # Publish metadata last, only after every DMG has passed the same checks as the client.
            for staged, target in pending:
                os.replace(staged, target)
            manifest = Path(temporary) / 'latest.json'
            manifest.write_text(json.dumps(metadata, ensure_ascii=False, indent=2) + '\n')
            manifest.chmod(0o644)
            os.replace(manifest, latest)
        return {'status': 'synced', 'tag': metadata['tag_name'], 'assets': [a['name'] for a in metadata['assets']]}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, default=ROOT)
    parser.add_argument('--tag', default='latest')
    parser.add_argument('--ssh', action='store_true')
    args = parser.parse_args()
    if args.ssh:
        command = os.environ.get('SSH_ORIGINAL_COMMAND', '')
        match = re.fullmatch(r'sync (latest|v[0-9]+\.[0-9]+\.[0-9]+)', command)
        if not match:
            raise SystemExit('Only sync latest or sync vX.Y.Z is permitted')
        args.tag = match[1]
        args.root = ROOT
    print(json.dumps(sync(args.root, args.tag)))


if __name__ == '__main__':
    main()
