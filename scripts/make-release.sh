#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="0.1.0"
APP_PATH="$ROOT_DIR/dist/边记.app"
RELEASE_DIR="$ROOT_DIR/releases"
ZIP_PATH="$RELEASE_DIR/Bianji-v$VERSION.zip"

"$ROOT_DIR/scripts/package-app.sh" >/dev/null

mkdir -p "$RELEASE_DIR"
ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"

echo "$ZIP_PATH"
