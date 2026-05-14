#!/bin/bash
# Build a distributable DMG of Verso, then print Sparkle signing info.
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
SPARKLE_BIN="./build/SourcePackages/artifacts/sparkle/Sparkle/bin"

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

DMG_SIZE_BYTES=$(stat -f%z "$DMG_PATH")
DMG_SIZE_HUMAN=$(du -sh "$DMG_PATH" | awk '{print $1}')

echo ""
echo "✓ Built $DMG_PATH ($DMG_SIZE_HUMAN, $DMG_SIZE_BYTES bytes)"

# Sparkle signing — emit the appcast snippet
if [ -x "$SPARKLE_BIN/sign_update" ]; then
    echo ""
    echo "▸ Signing with Sparkle EdDSA key..."
    SIGNATURE_OUTPUT=$("$SPARKLE_BIN/sign_update" "$DMG_PATH")
    echo "$SIGNATURE_OUTPUT"

    PUB_DATE=$(date -R)
    cat <<EOF

▸ APPCAST SNIPPET — paste this <item> into docs/appcast.xml inside <channel>:

    <item>
      <title>v${VERSION}</title>
      <pubDate>${PUB_DATE}</pubDate>
      <sparkle:version>$(grep -A1 'CFBundleVersion' project.yml | head -1 | awk -F'"' '{print $2}')</sparkle:version>
      <sparkle:shortVersionString>${VERSION}</sparkle:shortVersionString>
      <description><![CDATA[
        <ul>
          <li>TODO: changelog for v${VERSION}</li>
        </ul>
      ]]></description>
      <enclosure
        url="https://github.com/$(gh api user --jq .login 2>/dev/null || echo USERNAME)/verso/releases/download/v${VERSION}/${DMG_NAME}"
        ${SIGNATURE_OUTPUT}
        length="${DMG_SIZE_BYTES}"
        type="application/octet-stream" />
    </item>

▸ NEXT STEPS:
  1. Edit docs/appcast.xml — paste the <item> snippet above into <channel>
  2. git add docs/appcast.xml && git commit -m "release v${VERSION}" && git push
  3. gh release create v${VERSION} ${DMG_PATH} --title "Verso v${VERSION}" --generate-notes
  4. Wait ~1 minute for GitHub Pages to update, then test:
     curl https://\$(gh api user --jq .login).github.io/verso/appcast.xml
EOF
else
    echo ""
    echo "⚠ Sparkle CLI not found at $SPARKLE_BIN — Run a Release build first to fetch SPM artifacts."
fi
