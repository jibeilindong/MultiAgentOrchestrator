#!/bin/sh
set -euo pipefail
RUNTIME_SOURCE="$SRCROOT/managed-runtime/openclaw"
RUNTIME_TARGET="$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH/openclaw"
rm -rf "$RUNTIME_TARGET"
mkdir -p "$RUNTIME_TARGET"
cp -R "$RUNTIME_SOURCE/." "$RUNTIME_TARGET"
chmod +x "$RUNTIME_TARGET/bin/openclaw"

