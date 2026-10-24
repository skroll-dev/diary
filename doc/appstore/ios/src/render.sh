#!/usr/bin/env bash
# Renders header.html to the App Store product page header (3840x1646 PNG, no alpha).
# Usage: render-header.sh [en|de]   → doc/appstore/ios/header[-de].png
set -euo pipefail
lang="${1:-en}"
dir="$(cd "$(dirname "$0")" && pwd)"
out="$dir/../header$([ "$lang" = en ] || echo "-$lang").png"
tmp="$(mktemp -d)"
chrome="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"

"$chrome" --headless=new --disable-gpu --hide-scrollbars --allow-file-access-from-files \
  --force-device-scale-factor=1 --window-size=3840,1646 --virtual-time-budget=3000 \
  --screenshot="$tmp/raw.png" "file://$dir/header.html?lang=$lang" >/dev/null 2>&1

# Strip the alpha channel (Apple rejects transparency): PNG → BMP (24-bit) → PNG.
sips -s format bmp "$tmp/raw.png" --out "$tmp/flat.bmp" >/dev/null
sips -s format png "$tmp/flat.bmp" --out "$out" >/dev/null
rm -rf "$tmp"
sips -g pixelWidth -g pixelHeight -g hasAlpha "$out"
