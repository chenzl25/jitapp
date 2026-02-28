#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_PATH="${1:-$ROOT_DIR/dist/Jit APP.app}"
DMG_PATH="${2:-$ROOT_DIR/dist/Jit-APP.dmg}"
STAGE_DIR="$ROOT_DIR/dist/dmg-stage"

if [[ ! -d "$APP_PATH" ]]; then
  echo "App not found: $APP_PATH"
  echo "Run scripts/build_app.sh first."
  exit 1
fi

rm -f "$DMG_PATH"
rm -rf "$STAGE_DIR"
mkdir -p "$STAGE_DIR"
cp -R "$APP_PATH" "$STAGE_DIR/"
ln -s /Applications "$STAGE_DIR/Applications"

hdiutil create -volname "Jit APP" -srcfolder "$STAGE_DIR" -ov -format UDZO "$DMG_PATH" >/dev/null

rm -rf "$STAGE_DIR"

echo "Created dmg: $DMG_PATH"
