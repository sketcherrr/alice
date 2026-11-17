#!/usr/bin/env bash
set -euo pipefail
alice_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
case "$(uname -m)" in
  x86_64) alice_arch=x64 ;;
  aarch64) alice_arch=arm64 ;;
  *) echo '当前脚本支持 x86_64 和 aarch64 Linux。'; exit 1 ;;
esac
alice_binary="$alice_root/apps/companion/build/linux/$alice_arch/release/bundle/alice_companion"
if [[ ! -x "$alice_binary" ]]; then "$alice_root/scripts/build-linux.sh"; fi
exec "$alice_binary" "$@"
