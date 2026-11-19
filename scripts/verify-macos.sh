#!/usr/bin/env bash
# Verify a real .app, not a source archive or a directory renamed to .app.
set -euo pipefail
[[ "$(uname -s)" == Darwin ]] || { echo 'macOS bundle verification requires macOS.' >&2; exit 1; }
alice_app="${1:?Usage: verify-macos.sh /path/to/Alice.app}"
alice_info="$alice_app/Contents/Info.plist"
[[ -f "$alice_info" ]] || { echo 'Missing app Info.plist.' >&2; exit 1; }
alice_executable="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$alice_info")"
alice_core="$alice_app/Contents/Frameworks/libalice_core.dylib"
for alice_binary in "$alice_app/Contents/MacOS/$alice_executable" "$alice_core" \
  "$alice_app/Contents/Frameworks/FlutterMacOS.framework/FlutterMacOS" \
  "$alice_app/Contents/Frameworks/App.framework/App"; do
  [[ -f "$alice_binary" ]] || { echo "Missing binary: $alice_binary" >&2; exit 1; }
  xcrun lipo "$alice_binary" -verify_arch arm64 x86_64
done
for alice_symbol in alice_call alice_free alice_alloc alice_dealloc; do
  # nm's external, defined symbols must include the entire FFI boundary in both slices.
  for alice_arch in arm64 x86_64; do
    xcrun nm -arch "$alice_arch" -gU "$alice_core" | awk -v symbol="_$alice_symbol" '$NF == symbol { found=1 } END { exit !found }'
  done
done
alice_assets="$alice_app/Contents/Frameworks/App.framework/Resources/flutter_assets/assets"
for alice_asset in character.png NotoSansCJKsc-Regular.otf animations/calm.png animations/social.png animations/activities.png animations/idle-v2.png animations/social-v2.png animations/rest-v2.png audio/tide-window.mp3 audio/moon-postcard.mp3; do
  [[ -s "$alice_assets/$alice_asset" ]] || { echo "Missing asset: $alice_asset" >&2; exit 1; }
done
/usr/bin/codesign --verify --deep --strict --verbose=2 "$alice_app"
alice_entitlements="$(mktemp -t alice-entitlements)"
trap 'rm -f "$alice_entitlements"' EXIT
/usr/bin/codesign -d --entitlements :- "$alice_app" > "$alice_entitlements" 2>/dev/null
python3 - "$alice_entitlements" <<'PY'
import plistlib,sys
with open(sys.argv[1],'rb') as f: entitlements=plistlib.load(f)
for key in ('com.apple.security.app-sandbox','com.apple.security.network.client','com.apple.security.device.audio-input'):
    if entitlements.get(key) is not True: raise SystemExit('Missing entitlement: '+key)
print('PASS: universal app, native FFI symbols, assets, signatures, sandbox and network entitlement.')
PY
