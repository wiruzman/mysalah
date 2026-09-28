#!/bin/bash
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_root"
xcodebuild -project MySalah.xcodeproj -scheme MySalah \
  -configuration Debug -derivedDataPath build/DerivedData \
  -destination 'platform=macOS' build-for-testing
export MYSALAH_PREVIEW_DIR="$project_root/build/previews"
# Running the hostless bundle directly reliably forwards the opt-in environment.
xcrun xctest build/DerivedData/Build/Products/Debug/MySalahTests.xctest
