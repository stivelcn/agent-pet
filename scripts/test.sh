#!/usr/bin/env bash
# Swift Testing uses disposable data/preferences, never the user's app or agent state.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build
TEST_ROOT="$(mktemp -d "$PWD/build/.test-state.XXXXXX")"
export AGENTPET_DATA_DIR="$TEST_ROOT/data"
export AGENTPET_PREFERENCES_SUITE="local.agentpet.tests.$(uuidgen)"
cleanup() {
    defaults delete "$AGENTPET_PREFERENCES_SUITE" >/dev/null 2>&1 || true
    rm -rf "$TEST_ROOT"
}
trap cleanup EXIT
export AGENTPET_ENABLE_DEV_HOOKS=0
export AGENTPET_AUTOCONNECT=0
export AGENTPET_EMBERCAT_ENABLED=0
export AGENTPET_RELAY_ENABLED=0
python3 "$PWD/scripts/check-test-inventory.py"
# CLT's Swift build system omits TestingMacros during module emission on this
# installation. Explicitly load the installed plugin; no download or Xcode needed.
PLUGIN="$(dirname "$(xcrun --find swiftc)")/../lib/swift/host/plugins/testing/libTestingMacros.dylib"
if [ -f "$PLUGIN" ]; then
    "$PWD/scripts/swiftpm.sh" test --disable-xctest --enable-swift-testing --no-parallel \
        -Xswiftc -load-plugin-library -Xswiftc "$PLUGIN" "$@"
else
    "$PWD/scripts/swiftpm.sh" test --disable-xctest --enable-swift-testing --no-parallel "$@"
fi
