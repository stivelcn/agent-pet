#!/usr/bin/env bash
# One command to rebuild/restart ONLY this checkout's development app.
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"
APP="$ROOT/build/AgentPet Local Dev.app"
EXECUTABLE="$APP/Contents/MacOS/agentpet"
COMMAND="${1:-run}"
case "$COMMAND" in run|build|stop) ;; *) echo "Usage: $0 [run|build|stop]" >&2; exit 2 ;; esac

stop_development_app() {
    # Match the complete executable path, never a shared process name such as agentpet.
    while read -r pid executable; do
        if [ "$executable" = "$EXECUTABLE" ]; then
            kill -TERM "$pid" 2>/dev/null || true
            for ((i=0; i<50; i++)); do
                kill -0 "$pid" 2>/dev/null || break
                sleep 0.1
            done
            if kill -0 "$pid" 2>/dev/null; then
                echo "Development app did not exit. Close it and retry; no other app was stopped." >&2
                return 1
            fi
        fi
    done < <(ps -ww -axo pid=,comm=)
}

if [ "$COMMAND" = stop ]; then stop_development_app; exit 0; fi
"$ROOT/scripts/build-app.sh" debug native
if [ "$COMMAND" = build ]; then exit 0; fi
# Build first; leave the running instance alone if compilation fails.
stop_development_app
OPEN_ARGS=(-n --env "AGENTPET_ENABLE_DEV_HOOKS=${AGENTPET_ENABLE_DEV_HOOKS:-1}")
# LaunchServices does not reliably inherit the invoking shell's environment.
for name in AGENTPET_DATA_DIR AGENTPET_PREFERENCES_SUITE AGENTPET_AUTOCONNECT CODEX_HOME; do
    value="${!name:-}"
    [ -z "$value" ] || OPEN_ARGS+=(--env "$name=$value")
done
open "${OPEN_ARGS[@]}" "$APP"
echo "智能桌宠（开发版）已启动。修改代码后再次运行此命令即可，无需安装 DMG。"
echo "默认自动检测并连接已安装的编程助手；客户端要求的信任确认需在客户端完成。"
