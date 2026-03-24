#!/bin/sh
set -euo pipefail
RUNTIME_SOURCE="$SRCROOT/managed-runtime/openclaw"
RUNTIME_TARGET="$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH/openclaw"
mkdir -p "$RUNTIME_TARGET"
rsync -a --delete --exclude='.DS_Store' --exclude='__MACOSX' "$RUNTIME_SOURCE/" "$RUNTIME_TARGET/"
find "$RUNTIME_TARGET" -name '.DS_Store' -delete
chmod +x "$RUNTIME_TARGET/bin/openclaw"
if [ -f "$RUNTIME_TARGET/libexec/openclaw" ]; then
  chmod +x "$RUNTIME_TARGET/libexec/openclaw"
fi
if [ -f "$RUNTIME_TARGET/runtime/node/bin/node" ]; then
  chmod +x "$RUNTIME_TARGET/runtime/node/bin/node"
fi
if [ -f "$RUNTIME_TARGET/node/bin/node" ]; then
  chmod +x "$RUNTIME_TARGET/node/bin/node"
fi

