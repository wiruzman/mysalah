#!/bin/bash
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
launch=false
install_root="$HOME/Applications"
for argument in "$@"; do
  case "$argument" in
    --launch) launch=true ;;
    --system) install_root=/Applications ;;
    --help) printf 'Usage: %s [--system] [--launch]\n' "$0"; exit 0 ;;
    *) printf 'Usage: %s [--system] [--launch]\n' "$0" >&2; exit 2 ;;
  esac
done
app_source="$project_root/build/DerivedData/Build/Products/Release/MySalah.app"
if [ ! -d "$app_source" ]; then "$project_root/scripts/build-local.sh"; fi
destination="$install_root/MySalah.app"
if pgrep -x MySalah >/dev/null; then
  printf 'Quit MySalah from its menu before installing an update.\n' >&2
  exit 1
fi
mkdir -p "$install_root"
if [ ! -w "$install_root" ]; then
  printf 'Cannot write to %s. Install the built app there using Finder.\n' "$install_root" >&2
  exit 1
fi
stage="$(mktemp -d "$install_root/.mysalah-install.XXXXXX")"
trap 'rm -rf "$stage"' EXIT
ditto "$app_source" "$stage/MySalah.app"
codesign --verify --deep --strict "$stage/MySalah.app"
if [ -e "$destination" ]; then mv "$destination" "$stage/PreviousMySalah.app"; fi
if ! mv "$stage/MySalah.app" "$destination"; then
  if [ -d "$stage/PreviousMySalah.app" ]; then mv "$stage/PreviousMySalah.app" "$destination"; fi
  exit 1
fi
printf 'Installed: %s\n' "$destination"
if $launch; then open "$destination"; fi
