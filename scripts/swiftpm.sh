#!/usr/bin/env bash
# Project-local SwiftPM compatibility; never changes the installed toolchain.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
COMMAND="${1:-build}"
shift || true
FLAGS=()
SWIFTC="$(xcrun --find swiftc)"
TOOLCHAIN="$(cd "$(dirname "$SWIFTC")/.." && pwd)"
MANIFEST="$TOOLCHAIN/lib/swift/pm/ManifestAPI"
MODULE="$MANIFEST/PackageDescription.swiftmodule/$(uname -m)-apple-macos"

# Some upgraded CLT installations retain a 5.10 private interface beside a
# newer public interface/library. Use the matching public interface via VFS,
# with a separate module cache. All generated files remain inside build/.
if [ -f "$MODULE.private.swiftinterface" ] && [ -f "$MODULE.swiftinterface" ] &&
   [ "$(sed -n '2p' "$MODULE.private.swiftinterface")" != "$(sed -n '2p' "$MODULE.swiftinterface")" ]; then
    COMPAT="$ROOT/build/toolchain-compat"
    mkdir -p "$COMPAT"
    /usr/bin/python3 - "$MANIFEST" "$COMPAT/manifest-overlay.json" <<'PY'
import json, pathlib, sys
root, output = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
entries = []
for private in root.glob('*.swiftmodule/*.private.swiftinterface'):
    public = pathlib.Path(str(private).replace('.private.swiftinterface', '.swiftinterface'))
    if public.exists() and private.read_text().splitlines()[1] != public.read_text().splitlines()[1]:
        entries.append({'type': 'file', 'name': str(private), 'external-contents': str(public)})
content = json.dumps({'version': 0, 'roots': entries})
if not output.exists() or output.read_text() != content:
    output.write_text(content)
PY
    export SWIFTPM_MODULECACHE_OVERRIDE="$COMPAT/ModuleCache"
    # -Xmanifest is also understood by the minimum supported Swift 6.0.
    FLAGS+=(--manifest-cache local -Xmanifest -vfsoverlay -Xmanifest "$COMPAT/manifest-overlay.json")
    echo "SwiftPM: using project-local compatibility for mismatched CLT manifest interfaces." >&2
fi

SDK="${AGENTPET_SDK_PATH:-}"
DEFAULT_SDK="$(cd "$(xcrun --show-sdk-path)" && pwd -P)"
# This machine's CLT 27 SDK requires SwiftUIMacros but CLT omits that plugin.
# Prefer the already-installed 26.5 SDK only for this known combination. A full
# Xcode installation, other SDK versions, or an explicit override stay untouched.
if [ -z "$SDK" ] && [[ "$DEFAULT_SDK" == /Library/Developer/CommandLineTools/SDKs/MacOSX27* ]] &&
   [ ! -e "$TOOLCHAIN/lib/swift/host/plugins/libSwiftUIMacros.dylib" ] &&
   [ -d /Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk ]; then
    SDK="/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk"
    echo "SwiftPM: using installed macOS 26.5 SDK (CLT 27 lacks SwiftUIMacros)." >&2
fi
if [ -n "$SDK" ]; then
    [ -d "$SDK" ] || { echo "SDK does not exist: $SDK" >&2; exit 2; }
    FLAGS+=(--sdk "$SDK")
fi
# macOS ships Bash 3.2, where expanding an empty array under `set -u` fails.
if [ "${#FLAGS[@]}" -eq 0 ]; then
    exec swift "$COMMAND" "$@"
fi
exec swift "$COMMAND" "${FLAGS[@]}" "$@"
