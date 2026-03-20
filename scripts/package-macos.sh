#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_PATH="$ROOT_DIR/Multi-Agent-Flow.xcodeproj"
SCHEME="Multi-Agent-Flow"
CONFIGURATION="${CONFIGURATION:-Release}"
APP_NAME="Multi-Agent-Flow"
DERIVED_DATA_PATH="$ROOT_DIR/.build/DerivedData"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE_PATH="$DERIVED_DATA_PATH/Build/Products/$CONFIGURATION/$APP_NAME.app"
DIST_APP_PATH="$DIST_DIR/$APP_NAME.app"
ZIP_PATH="$DIST_DIR/$APP_NAME-macOS.zip"
DMG_STAGING_DIR="$DIST_DIR/.dmg"
DMG_PATH="$DIST_DIR/$APP_NAME-macOS.dmg"

rm -rf "$DIST_DIR"
mkdir -p "$DIST_DIR"

echo "Building $APP_NAME ($CONFIGURATION)..."
xcodebuild \
  -project "$PROJECT_PATH" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -destination "platform=macOS" \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  build

if [[ ! -d "$APP_BUNDLE_PATH" ]]; then
  echo "Build succeeded but app bundle was not found at:"
  echo "  $APP_BUNDLE_PATH"
  exit 1
fi

echo "Copying app bundle to dist..."
cp -R "$APP_BUNDLE_PATH" "$DIST_APP_PATH"

echo "Creating zip archive..."
ditto -c -k --sequesterRsrc --keepParent "$DIST_APP_PATH" "$ZIP_PATH"

echo "Creating dmg image..."
rm -rf "$DMG_STAGING_DIR"
mkdir -p "$DMG_STAGING_DIR"
cp -R "$DIST_APP_PATH" "$DMG_STAGING_DIR/"
ln -s /Applications "$DMG_STAGING_DIR/Applications"
hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$DMG_STAGING_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH" \
  >/dev/null
rm -rf "$DMG_STAGING_DIR"
find "$DIST_DIR" -name ".DS_Store" -delete 2>/dev/null || true

echo
echo "Artifacts:"
echo "  App: $DIST_APP_PATH"
echo "  Zip: $ZIP_PATH"
echo "  Dmg: $DMG_PATH"
echo
echo "Note: Gatekeeper may reject this build on other Macs unless you re-sign"
echo "with a Developer ID certificate and notarize the final app or dmg."
