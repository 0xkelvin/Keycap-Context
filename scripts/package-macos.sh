#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
set -eu

project_root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
dist_root=${KEYCAP_DIST_ROOT:-"$project_root/dist"}
app_root="$dist_root/Keycap Context.app"
identity=${KEYCAP_SIGNING_IDENTITY:--}

cd "$project_root/host/macos"
swift build -c release

mkdir -p "$app_root/Contents/MacOS" "$app_root/Contents/Resources/adapters"
cp .build/release/keycap-host "$app_root/Contents/MacOS/keycap-host"
cp "$project_root/packaging/macos/Info.plist" "$app_root/Contents/Info.plist"
for adapter in claude codex shared gemini generic opencode antigravity; do
  target="$app_root/Contents/Resources/adapters/$adapter"
  rm -rf "$target"
  cp -R "$project_root/adapters/$adapter" "$target"
done
find "$app_root/Contents/Resources/adapters" \
  -type d \( -name __pycache__ -o -name tests \) -prune -exec rm -rf {} +

codesign --force --deep --options runtime --sign "$identity" "$app_root"
codesign --verify --deep --strict "$app_root"

if [ -n "${KEYCAP_NOTARY_PROFILE:-}" ]; then
  ditto -c -k --keepParent "$app_root" "$dist_root/Keycap-Context.zip"
  xcrun notarytool submit "$dist_root/Keycap-Context.zip" \
    --keychain-profile "$KEYCAP_NOTARY_PROFILE" --wait
  xcrun stapler staple "$app_root"
fi

echo "Packaged: $app_root"
