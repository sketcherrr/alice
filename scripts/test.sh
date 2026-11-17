#!/usr/bin/env bash
set -euo pipefail
alice_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$alice_root"
cargo test --locked
cargo build --locked
python3 scripts/prepare-assets.py
export ALICE_CORE_LIBRARY="$alice_root/target/debug/libalice_core.so"
cd apps/companion
flutter pub get
flutter analyze --no-pub
flutter test --no-pub
