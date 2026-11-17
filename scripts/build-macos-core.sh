#!/usr/bin/env bash
# Called by Xcode before the app's signing phase. Requires macOS and Xcode.
set -euo pipefail
alice_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
[[ "$(uname -s)" == Darwin ]] || { echo 'error: macOS native core must be built on a Mac.' >&2; exit 1; }
export PATH="${HOME}/.cargo/bin:$PATH"
command -v cargo >/dev/null || { echo 'error: Rust/Cargo is required on the build machine.' >&2; exit 1; }
: "${TARGET_BUILD_DIR:?Run via the Xcode target or scripts/build-macos.sh}"
: "${FRAMEWORKS_FOLDER_PATH:?Missing Xcode bundle location}"
alice_archs="${ARCHS:-arm64 x86_64}"
alice_target_dir="$alice_root/target/macos"
alice_slices=()
export MACOSX_DEPLOYMENT_TARGET="${MACOSX_DEPLOYMENT_TARGET:-12.0}"
# Use the selected macOS SDK, even if the caller's environment points at iOS.
export SDKROOT="$(xcrun --sdk macosx --show-sdk-path)"
for alice_arch in $alice_archs; do
  case "$alice_arch" in
    arm64) alice_target=aarch64-apple-darwin ;;
    x86_64) alice_target=x86_64-apple-darwin ;;
    *) echo "error: Unsupported macOS architecture: $alice_arch" >&2; exit 1 ;;
  esac
  cargo build --manifest-path "$alice_root/Cargo.toml" --package alice_core \
    --release --locked --target "$alice_target" --target-dir "$alice_target_dir"
  alice_slices+=("$alice_target_dir/$alice_target/release/libalice_core.dylib")
done
[[ ${#alice_slices[@]} -gt 0 ]] || { echo 'error: Empty architecture list.' >&2; exit 1; }
alice_frameworks="$TARGET_BUILD_DIR/$FRAMEWORKS_FOLDER_PATH"
mkdir -p "$alice_frameworks"
alice_library="$alice_frameworks/libalice_core.dylib"
if [[ ${#alice_slices[@]} -eq 1 ]]; then
  cp "${alice_slices[0]}" "$alice_library"
else
  xcrun lipo -create "${alice_slices[@]}" -output "$alice_library"
fi
xcrun install_name_tool -id '@rpath/libalice_core.dylib' "$alice_library"
# Sign nested code before Xcode seals the outer application. No Developer ID needed for local testing.
if [[ "${CODE_SIGNING_ALLOWED:-YES}" != NO ]]; then
  /usr/bin/codesign --force --sign "${EXPANDED_CODE_SIGN_IDENTITY:--}" --timestamp=none "$alice_library"
fi
xcrun lipo -info "$alice_library"
