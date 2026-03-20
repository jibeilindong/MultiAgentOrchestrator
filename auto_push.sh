#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"
git add -A
git commit -m "Auto commit: $(date '+%Y-%m-%d %H:%M:%S')"
git push origin main
