#!/bin/bash
# Build a distributable DMG of Verso.
# Usage: ./Tools/build_dmg.sh [version]
#   default version: read from project.yml

set -euo pipefail

cd "$(dirname "$0")/.."

VERSION="${1:-$(grep -A1 'CFBundleShortVersionString' project.yml | head -1 | awk -F'"' '{print $2}')}"
if [ -z "$VERSION" ]; then VERSION="0.0.0"; fi

DIST_DIR="./dist"
BUILD_DIR="./build/Build/Products/Release"
DMG_NAME="Verso-v${VERSION}.dmg"
DMG_PATH="$DIST_DIR/$DMG_NAME"

echo "▸ Generating Xcode project..."
xcodegen >/dev/null

echo "▸ Building Verso (Release, $VERSION)..."
xcodebuild -scheme Verso -configuration Release \
    -destination 'platform=macOS' -derivedDataPath ./build build \
    | grep -E "(error:|warning:|BUILD SUCCEEDED|BUILD FAILED)" | tail -5

if [ ! -d "$BUILD_DIR/Verso.app" ]; then
    echo "✗ Verso.app not found at $BUILD_DIR"
    exit 1
fi

echo "▸ Staging DMG contents..."
mkdir -p "$DIST_DIR"
STAGING="$(mktemp -d)"
cp -R "$BUILD_DIR/Verso.app" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

echo "▸ Creating $DMG_NAME..."
rm -f "$DMG_PATH"
hdiutil create \
    -volname "Verso $VERSION" \
    -srcfolder "$STAGING" \
    -ov -format UDZO \
    "$DMG_PATH" >/dev/null

rm -rf "$STAGING"

SIZE=$(du -sh "$DMG_PATH" | awk '{print $1}')
echo ""
echo "✓ Built $DMG_PATH ($SIZE)"
echo ""
echo "Next steps to share:"
echo "  • Upload $DMG_PATH somewhere (iCloud Drive, GitHub release, etc.)"
echo "  • On the recipient's Mac: open the DMG, drag Verso.app → Applications"
echo "  • First launch: right-click → Open (unsigned app warning)"
echo "  • Grant Accessibility when prompted"
