#!/usr/bin/env bash
# Build a universal, ad-hoc-signed test app on a Mac/macOS CI runner.
set -euo pipefail
alice_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
[[ "$(uname -s)" == Darwin ]] || { echo '此脚本需要 macOS + Xcode；Linux 无法生成 Flutter macOS 应用。' >&2; exit 1; }
export PATH="${HOME}/.cargo/bin:$PATH"
for alice_tool in flutter cargo rustup python3 xcodebuild xcrun ditto codesign; do
  command -v "$alice_tool" >/dev/null || { echo "构建机缺少工具：$alice_tool" >&2; exit 1; }
done
xcodebuild -version
xcrun --sdk macosx --show-sdk-path >/dev/null
cd "$alice_root"
rustup target add aarch64-apple-darwin x86_64-apple-darwin
python3 scripts/prepare-assets.py
# Avoid relying on global Flutter configuration or an Apple signing account.
export FLUTTER_MACOS_ARM64_ONLY=false
export FLUTTER_XCODE_ARCHS='arm64 x86_64'
export FLUTTER_XCODE_ONLY_ACTIVE_ARCH=NO
export FLUTTER_XCODE_CODE_SIGN_IDENTITY=-
export FLUTTER_XCODE_CODE_SIGN_STYLE=Manual
export FLUTTER_XCODE_DEVELOPMENT_TEAM=''
# Keep the sandbox enabled in CI too; Flutter's default CI override otherwise hides permission bugs.
export FLUTTER_XCODE_CODE_SIGN_ENTITLEMENTS="$alice_root/apps/companion/macos/Runner/Release.entitlements"
(
  cd apps/companion
  flutter pub get
  flutter build macos --release --no-pub
)
alice_built="$alice_root/apps/companion/build/macos/Build/Products/Release/alice_companion.app"
[[ -d "$alice_built" ]] || { echo '未找到预期的 .app 构建产物。' >&2; exit 1; }
mkdir -p "$alice_root/dist"
alice_stage="$(mktemp -d "$alice_root/dist/.macos-package.XXXXXX")"
trap 'rm -rf "$alice_stage"' EXIT
/usr/bin/ditto "$alice_built" "$alice_stage/Alice.app"
"$alice_root/scripts/verify-macos.sh" "$alice_stage/Alice.app"
# Validate this runner's native slice and the actual bundled Rust/SQLite boundary.
export ALICE_CORE_LIBRARY="$alice_stage/Alice.app/Contents/Frameworks/libalice_core.dylib"
dart scripts/check-offline.dart
dart scripts/check-agent.dart
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$alice_stage/Alice.app" "$alice_stage/Alice-macOS-universal-test.zip"
cp "$alice_stage/Alice-macOS-universal-test.zip" "$alice_root/dist/Alice-macOS-universal-test.zip"
(
  cd "$alice_root/dist"
  /usr/bin/shasum -a 256 Alice-macOS-universal-test.zip > Alice-macOS-universal-test.zip.sha256
)
echo "已生成测试应用：$alice_root/dist/Alice-macOS-universal-test.zip"
echo '包含 Apple Silicon 和 Intel 架构；测试版使用临时签名，尚未经 Apple 公证。'
