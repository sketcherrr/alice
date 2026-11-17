#!/usr/bin/env bash
set -euo pipefail
alice_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
alice_flutter="$(dirname -- "$(dirname -- "$(readlink -f "$(command -v flutter)")")")"
cd "$alice_root"
python3 scripts/prepare-assets.py
cargo build --release --locked
export ALICE_CORE_LIBRARY="$alice_root/target/release/libalice_core.so"
export ALICE_ARTIFACT_DIR="$alice_root/artifacts/ui"
cd apps/companion
flutter build bundle --no-pub --target lib/smoke.dart
"$alice_flutter/bin/cache/artifacts/engine/linux-x64/flutter_tester" \
  --disable-vm-service --non-interactive --run-forever \
  --icu-data-file-path="$alice_flutter/bin/cache/artifacts/engine/linux-x64/icudtl.dat" \
  --flutter-assets-dir=build/flutter_assets build/flutter_assets/kernel_blob.bin
