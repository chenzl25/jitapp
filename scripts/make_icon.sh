#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ASSETS_DIR="$ROOT_DIR/Assets"
ICONSET_DIR="$ASSETS_DIR/AppIcon.iconset"
PNG_1024="$ASSETS_DIR/AppIcon-1024.png"
ICNS_PATH="$ASSETS_DIR/AppIcon.icns"

mkdir -p "$ASSETS_DIR"
rm -rf "$ICONSET_DIR"
mkdir -p "$ICONSET_DIR"

swift "$ROOT_DIR/scripts/generate_icon.swift" "$PNG_1024"

sips -z 16 16 "$PNG_1024" --out "$ICONSET_DIR/icon_16x16.png" >/dev/null
sips -z 32 32 "$PNG_1024" --out "$ICONSET_DIR/icon_16x16@2x.png" >/dev/null
sips -z 32 32 "$PNG_1024" --out "$ICONSET_DIR/icon_32x32.png" >/dev/null
sips -z 64 64 "$PNG_1024" --out "$ICONSET_DIR/icon_32x32@2x.png" >/dev/null
sips -z 128 128 "$PNG_1024" --out "$ICONSET_DIR/icon_128x128.png" >/dev/null
sips -z 256 256 "$PNG_1024" --out "$ICONSET_DIR/icon_128x128@2x.png" >/dev/null
sips -z 256 256 "$PNG_1024" --out "$ICONSET_DIR/icon_256x256.png" >/dev/null
sips -z 512 512 "$PNG_1024" --out "$ICONSET_DIR/icon_256x256@2x.png" >/dev/null
sips -z 512 512 "$PNG_1024" --out "$ICONSET_DIR/icon_512x512.png" >/dev/null
cp "$PNG_1024" "$ICONSET_DIR/icon_512x512@2x.png"

iconutil -c icns "$ICONSET_DIR" -o "$ICNS_PATH"
echo "Generated $ICNS_PATH"
