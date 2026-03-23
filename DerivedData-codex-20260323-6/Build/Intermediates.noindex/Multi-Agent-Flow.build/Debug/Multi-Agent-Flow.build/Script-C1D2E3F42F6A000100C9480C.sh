#!/bin/sh
set -euo pipefail
RUNTIME_SOURCE="$SRCROOT/managed-runtime/openclaw"
RUNTIME_TARGET="$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH/openclaw"
mkdir -p "$RUNTIME_TARGET/bin"
cp "$RUNTIME_SOURCE/managed-runtime.json" "$RUNTIME_TARGET/managed-runtime.json"
cp "$RUNTIME_SOURCE/bin/openclaw" "$RUNTIME_TARGET/bin/openclaw"
chmod +x "$RUNTIME_TARGET/bin/openclaw"

