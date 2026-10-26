#!/usr/bin/env bash
# Packs a built Payroof.app into a drag-to-Applications disk image.
# Usage: apple/make-dmg.sh <path/to/Payroof.app> <output.dmg>
# Needs dmgbuild (pip install dmgbuild); no Finder or GUI session is used.
set -euo pipefail
app="$1" output="$2"
[[ -d "$app" ]] || { echo "no app at $app" >&2; exit 1; }
root="$(cd "$(dirname "$0")/.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
# One HiDPI TIFF from the 1x and 2x backgrounds, so the window is sharp on Retina displays.
tiffutil -cathidpicheck "$root/assets/dmg/background.png" "$root/assets/dmg/background@2x.png" \
  -out "$work/background.tiff" >/dev/null
rm -f "$output"
dmgbuild -s "$root/apple/dmg-settings.py" -D app="$app" -D background="$work/background.tiff" \
  Payroof "$output"
hdiutil verify -quiet "$output"
echo "wrote $output"
