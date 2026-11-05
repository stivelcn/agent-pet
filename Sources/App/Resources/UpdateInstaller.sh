#!/bin/sh
# Transactional app-bundle replacement only. NEVER touch user data, defaults or Keychain.
set -eu
mode="$1"
shift
if [ "$mode" = relaunch ]; then
    target="$1"; pid="$2"; backup="$3"; work="$4"
    # A blocked/cancelled quit must not launch a second instance.
    attempts=0
    while kill -0 "$pid" 2>/dev/null; do
        attempts=$((attempts + 1))
        [ "$attempts" -lt 120 ] || exit 1
        sleep 1
    done
    if ! /usr/bin/open -n "$target" >"$work/relaunch.log" 2>&1; then
        # Keep both bundles for recovery; never delete the only working application.
        /usr/bin/open -n "$backup" >>"$work/relaunch.log" 2>&1 || true
        /usr/bin/osascript -e 'display alert "LuMate" message "更新后的应用未能启动。旧版备份已保留，请重新打开旧版或手动恢复。用户数据未删除。"' || true
        exit 1
    fi
    exit 0
fi
[ "$#" -eq 4 ] || exit 2
source="$1"; target="$2"; backup="$3"; candidate="$4"
# Generated sibling paths only, no globbing, and no overwriting existing backups.
case "$target" in /*.app) ;; *) exit 2 ;; esac
parent="$(dirname "$target")"
[ "$(dirname "$backup")" = "$parent" ] && [ "$(dirname "$candidate")" = "$parent" ] || exit 2
case "$(basename "$backup")" in .LuMate-backup-*.app) ;; *) exit 2 ;; esac
case "$(basename "$candidate")" in .LuMate-install-*.app) ;; *) exit 2 ;; esac
[ "$source" != "$target" ] && [ "$target" != "$backup" ] && [ "$target" != "$candidate" ] || exit 2
[ ! -L "$source" ] && [ ! -L "$target" ] && [ ! -L "$backup" ] && [ ! -L "$candidate" ] || exit 2
# Serialize separate app instances updating the same destination.
lock="$target.lumate-update-lock"
/bin/mkdir "$lock" || exit 1
trap '/bin/rmdir "$lock" 2>/dev/null || true' EXIT
if [ "$mode" = rollback ]; then
    [ -d "$backup" ] && [ ! -e "$candidate" ] || exit 2
    /bin/mv "$target" "$candidate"
    if ! /bin/mv "$backup" "$target"; then /bin/mv "$candidate" "$target"; exit 1; fi
    exit 0
fi
[ "$mode" = swap ] || exit 2
[ -d "$source" ] && [ -d "$target" ] && [ ! -e "$backup" ] && [ ! -e "$candidate" ] || exit 2
# Copy to the destination filesystem BEFORE moving the current app.
if ! /usr/bin/ditto "$source" "$candidate"; then
    /bin/rm -rf "$candidate"
    exit 1
fi
# A signal or failed second rename restores the previous app.
moved=0
committed=0
restore() {
    if [ "$moved" = 1 ] && [ "$committed" = 0 ] && [ ! -e "$target" ]; then
        /bin/mv "$backup" "$target" || true
    fi
    /bin/rmdir "$lock" 2>/dev/null || true
}
trap restore EXIT
trap 'exit 1' HUP INT TERM
/bin/mv "$target" "$backup"
moved=1
/bin/mv "$candidate" "$target"
committed=1
printf 'Installed: %s\nPrevious app: %s\n' "$target" "$backup"
