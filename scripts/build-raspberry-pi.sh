#!/usr/bin/env bash
set -euo pipefail
alice_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ "$(uname -s)" != Linux || "$(uname -m)" != aarch64 ]]; then
  echo '请在 64 位树莓派系统或 ARM64 Linux 构建机运行此脚本。x64 包不能用于树莓派。'
  exit 1
fi
"$alice_root/scripts/build-linux.sh"
mkdir -p "$alice_root/dist"
tar -C "$alice_root/apps/companion/build/linux/arm64/release/bundle" -czf "$alice_root/dist/Alice-linux-arm64-test.tar.gz" .
echo "已生成 $alice_root/dist/Alice-linux-arm64-test.tar.gz"
echo '解压整个目录，使用 ALICE_DEVICE_MODE=1 ./alice_companion 启动。'
