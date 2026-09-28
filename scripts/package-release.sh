#!/bin/bash
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_root"

tag="${1:-}"
build_number="${2:-1}"
if [ "$#" -gt 2 ] || [[ ! "$tag" =~ ^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]] ||
  [[ ! "$build_number" =~ ^[1-9][0-9]*$ ]]; then
  printf 'Usage: %s vMAJOR.MINOR.PATCH [positive-build-number]\n' "$0" >&2
  exit 2
fi
version="${tag#v}"
output_dir="$project_root/build/releases/$tag"
mkdir -p "$output_dir"
stage="$(mktemp -d "$output_dir/.package.XXXXXX")"
trap 'rm -rf "$stage"' EXIT

# Keep distribution builds separate from the local installation's build products.
xcodebuild -project MySalah.xcodeproj -scheme MySalah \
  -configuration Release -derivedDataPath build/ReleaseDerivedData \
  -destination 'generic/platform=macOS' -onlyUsePackageVersionsFromResolvedFile build \
  'ARCHS=arm64 x86_64' ONLY_ACTIVE_ARCH=NO \
  CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual \
  "MARKETING_VERSION=$version" "CURRENT_PROJECT_VERSION=$build_number"

app_source="$project_root/build/ReleaseDerivedData/Build/Products/Release/MySalah.app"
app="$stage/MySalah.app"
ditto "$app_source" "$app"
# Resource-only rebuilds can leave Xcode's outer app seal stale.
codesign --force --sign - --preserve-metadata=identifier,entitlements,flags "$app"
codesign --verify --deep --strict "$app"
for architecture in arm64 x86_64; do
  xcrun lipo "$app/Contents/MacOS/MySalah" -verify_arch "$architecture"
done
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")" = "$version"
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$app/Contents/Info.plist")" = "$build_number"
test -s "$app/Contents/Resources/ThirdPartyNotices.txt"

archive="MySalah-$tag-macOS.zip"
ditto -c -k --sequesterRsrc --keepParent "$app" "$stage/$archive"
# Verify the distributed ZIP, including its signature, after extraction.
ditto -x -k "$stage/$archive" "$stage/extracted"
codesign --verify --deep --strict "$stage/extracted/MySalah.app"
mv "$stage/$archive" "$output_dir/$archive"
cd "$output_dir"
shasum -a 256 "$archive" > "$archive.sha256"
printf '\nPackaged: %s/%s\n' "$output_dir" "$archive"
