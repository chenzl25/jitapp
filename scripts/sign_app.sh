#!/usr/bin/env bash
set -euo pipefail

APP_PATH="${1:-}"
IDENTITY="${2:--}"

if [[ -z "$APP_PATH" ]]; then
  echo "Usage: $0 <app_path> [codesign_identity|-]"
  exit 1
fi

if [[ ! -d "$APP_PATH" ]]; then
  echo "App not found: $APP_PATH"
  exit 1
fi

codesign --force --deep --sign "$IDENTITY" "$APP_PATH"
codesign --verify --deep --strict "$APP_PATH"

echo "Signed: $APP_PATH"
