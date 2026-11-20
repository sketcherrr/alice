#!/usr/bin/env bash
set -euo pipefail
alice_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
export ALICE_DEVICE_MODE=1
if [[ "${1:-}" == --preview ]]; then
  export ALICE_DEVICE_MODE=preview
  shift
fi
exec "$alice_root/scripts/run-linux.sh" "$@"
