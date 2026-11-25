#!/usr/bin/env bash
set -euo pipefail
alice_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$alice_root"
cargo build --release --locked -p alice_core --bin alice-card-server
printf 'Built: %s/target/release/alice-card-server\n' "$alice_root"
