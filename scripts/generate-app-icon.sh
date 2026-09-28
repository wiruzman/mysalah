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
printf 'Updated macOS app icon sizes in %s\n' "$icon_set"
