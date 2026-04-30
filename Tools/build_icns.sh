#!/bin/bash
# Generate AppIcon.icns from a 1024×1024 source PNG.
# Usage: ./build_icns.sh <source-1024.png> <output-icns-path>

set -euo pipefail

SRC="${1:-/tmp/icon_1024.png}"
DST="${2:-Sources/Translator/Resources/AppIcon.icns}"
ICONSET="$(mktemp -d)/AppIcon.iconset"

mkdir -p "$ICONSET"

# Generate all the sizes Apple expects in an iconset
sips -z 16 16     "$SRC" --out "$ICONSET/icon_16x16.png"      >/dev/null
sips -z 32 32     "$SRC" --out "$ICONSET/icon_16x16@2x.png"   >/dev/null
sips -z 32 32     "$SRC" --out "$ICONSET/icon_32x32.png"      >/dev/null
sips -z 64 64     "$SRC" --out "$ICONSET/icon_32x32@2x.png"   >/dev/null
sips -z 128 128   "$SRC" --out "$ICONSET/icon_128x128.png"    >/dev/null
sips -z 256 256   "$SRC" --out "$ICONSET/icon_128x128@2x.png" >/dev/null
sips -z 256 256   "$SRC" --out "$ICONSET/icon_256x256.png"    >/dev/null
sips -z 512 512   "$SRC" --out "$ICONSET/icon_256x256@2x.png" >/dev/null
sips -z 512 512   "$SRC" --out "$ICONSET/icon_512x512.png"    >/dev/null
cp "$SRC" "$ICONSET/icon_512x512@2x.png"

mkdir -p "$(dirname "$DST")"
iconutil -c icns "$ICONSET" -o "$DST"
echo "✓ generated $DST"
