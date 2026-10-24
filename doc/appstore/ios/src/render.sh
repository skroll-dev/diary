#!/usr/bin/env bash
# Renders banner.html to the App Store creative assets (PNG, no alpha).
# Usage: render.sh [format] [lang...]   (defaults: all formats, en de)
#   header → doc/appstore/ios/header-<lang>.png   (3840x1646, product page header)
#   search → doc/appstore/ios/search-<lang>.png   (3840x2560, search results)
set -euo pipefail
dir="$(cd "$(dirname "$0")" && pwd)"
chrome="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
formats=(header search); [ $# -gt 0 ] && { formats=("$1"); shift; }
langs=("$@"); [ ${#langs[@]} -gt 0 ] || langs=(en de)

for format in "${formats[@]}"; do
  case "$format" in
    header) size=3840,1646 ;;
    search) size=3840,2560 ;;
    *) echo "unknown format: $format" >&2; exit 1 ;;
  esac
  for lang in "${langs[@]}"; do
    out="$dir/../$format-$lang.png"
    tmp="$(mktemp -d)"
    "$chrome" --headless=new --disable-gpu --hide-scrollbars --allow-file-access-from-files \
      --force-device-scale-factor=1 --window-size="$size" --virtual-time-budget=3000 \
      --screenshot="$tmp/raw.png" "file://$dir/banner.html?format=$format&lang=$lang" >/dev/null 2>&1

    # Strip the alpha channel (Apple rejects transparency): PNG → BMP (24-bit) → PNG.
    sips -s format bmp "$tmp/raw.png" --out "$tmp/flat.bmp" >/dev/null
    sips -s format png "$tmp/flat.bmp" --out "$out" >/dev/null
    rm -rf "$tmp"
    sips -g pixelWidth -g pixelHeight -g hasAlpha "$out" | tr '\n' ' '; echo
  done
done
