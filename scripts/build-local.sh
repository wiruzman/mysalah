#!/bin/bash
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_root"
xcodebuild -project MySalah.xcodeproj -scheme MySalah \
  -configuration Release -derivedDataPath build/DerivedData \
  -destination 'generic/platform=macOS' build \
  CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual
app_source="$project_root/build/DerivedData/Build/Products/Release/MySalah.app"
test -d "$app_source"
# SwiftPM resource-only updates can leave Xcode's outer app seal stale.
codesign --force --sign - --preserve-metadata=identifier,entitlements,flags "$app_source"
codesign --verify --deep --strict "$app_source"
printf '\nBuilt: %s\n' "$app_source"
