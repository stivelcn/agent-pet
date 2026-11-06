#!/bin/sh
# Run as root on the already-authorized server after copying this directory.
set -eu
cd "$(dirname "$0")"
root=/srv/lumate-updates
if ! id -u lumate-updates >/dev/null 2>&1; then
    useradd --system --user-group --home-dir "$root" --no-create-home --shell /bin/sh lumate-updates
fi
install -d -m 755 "$root"
install -d -m 755 -o lumate-updates -g lumate-updates "$root/public"
install -d -m 750 -o lumate-updates -g lumate-updates "$root/state"
install -d -m 700 "$root/admin-backups"
install -m 644 sync_release.py "$root/sync_release.py"
install -m 644 lumate-updates.service /etc/systemd/system/lumate-updates.service
install -m 644 lumate-updates.timer /etc/systemd/system/lumate-updates.timer
install -m 644 nginx.location.conf /usr/local/nginx/conf/lumate-updates.location.conf
python3 - <<'PY'
from pathlib import Path
import datetime,os,subprocess
config=Path('/usr/local/nginx/conf/nginx.conf')
before=config.read_bytes()
include=b'    include /usr/local/nginx/conf/lumate-updates.location.conf; # LuMate release mirror\n'
if include not in before:
    anchor=b'server_name imagepro.ycgod.online;\n'
    if before.count(anchor)!=1:raise SystemExit('Expected exactly one existing imagepro HTTPS server')
    after=before.replace(anchor,anchor+include,1)
    stamp=datetime.datetime.now().strftime('%Y%m%d-%H%M%S')
    backup=Path('/srv/lumate-updates/admin-backups')/('nginx.pre-mirror-'+stamp+'.conf')
    backup.write_bytes(before);backup.chmod(0o600)
    staged=config.with_name('nginx.conf.lumate-stage')
    staged.write_bytes(after);staged.chmod(config.stat().st_mode&0o777)
    if config.read_bytes()!=before:raise SystemExit('Nginx config changed concurrently')
    os.replace(staged,config)
    test=subprocess.run(['/usr/local/nginx/sbin/nginx','-t'])
    if test.returncode:
        if config.read_bytes()==after:config.write_bytes(before)
        raise SystemExit('Validation failed; restored previous Nginx config')
else:
    subprocess.run(['/usr/local/nginx/sbin/nginx','-t'],check=True)
subprocess.run(['/usr/local/nginx/sbin/nginx','-s','reload'],check=True)
PY
systemctl daemon-reload
systemctl start lumate-updates.service
systemctl enable --now lumate-updates.timer
systemctl is-active lumate-updates.timer
