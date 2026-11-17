#!/usr/bin/env bash
set -euo pipefail
alice_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$alice_root"
command -v flutter >/dev/null || { echo '请先安装 Flutter，并将 flutter 加入 PATH。'; exit 1; }
python3 scripts/prepare-assets.py
cargo build --release --locked
mkdir -p apps/companion/native/linux
cp target/release/libalice_core.so apps/companion/native/linux/
cd apps/companion
flutter pub get
flutter build linux --release --no-pub
