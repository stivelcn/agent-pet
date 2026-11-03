#!/usr/bin/env bash
# Compatibility entry point. Local CI uses the same manual DMG workflow.
# Optional: SIGNING_IDENTITY and NOTARY_PROFILE, owned by this fork's distributor.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
exec "$ROOT/scripts/release.sh" "$@"
