#!/bin/bash
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
icon_set="$project_root/App/Assets.xcassets/AppIcon.appiconset"
icon_master="$icon_set/icon-1024.png"
test -f "$icon_master"
# Keep the alpha channel and derive every size directly from the master.
for pixels in 16 32 64 128 256 512; do
  sips --resampleHeightWidth "$pixels" "$pixels" "$icon_master" \
    --out "$icon_set/icon-$pixels.png" >/dev/null
done
# Ship a complete standalone macOS icon, including all ten size/scale slots.
stage="$(mktemp -d "${TMPDIR:-/tmp}/mysalah-icon.XXXXXX")"
trap 'rm -rf "$stage"' EXIT
mkdir "$stage/MySalah.iconset"
for pixels in 16 32 128 256 512; do
  cp "$icon_set/icon-$pixels.png" "$stage/MySalah.iconset/icon_${pixels}x${pixels}.png"
  double_pixels=$((pixels * 2))
  cp "$icon_set/icon-$double_pixels.png" "$stage/MySalah.iconset/icon_${pixels}x${pixels}@2x.png"
done
iconutil -c icns "$stage/MySalah.iconset" -o "$project_root/App/MySalah.icns"
printf 'Updated macOS app icon PNGs and App/MySalah.icns\n'
