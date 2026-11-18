#!/usr/bin/env bash
set -euo pipefail

APP_PATH="${1:-}"
IDENTITY="${2:-}"

if [[ -z "$APP_PATH" ]]; then
  echo "Usage: $0 <app_path> [codesign_identity|-]"
  exit 1
fi

if [[ ! -d "$APP_PATH" ]]; then
  echo "App not found: $APP_PATH"
  exit 1
fi

# macOS ties Accessibility and Input Monitoring grants to the signature. An
# ad hoc signature changes with every build, so sign with the local identity
# from scripts/setup_signing.sh when there is one; grants then survive rebuilds.
SIGNING_DIR="${JIT_SIGNING_DIR:-$HOME/Library/Application Support/JitSigning}"
KEYCHAIN="$SIGNING_DIR/jit-signing.keychain-db"
PASSWORD_FILE="$SIGNING_DIR/keychain-password"
KEYCHAIN_ARGS=()

if [[ -z "$IDENTITY" ]]; then
  if [[ -f "$KEYCHAIN" && -f "$PASSWORD_FILE" ]]; then
    security unlock-keychain -p "$(cat "$PASSWORD_FILE")" "$KEYCHAIN"
    IDENTITY="Jit Local Code Signing"
    KEYCHAIN_ARGS=(--keychain "$KEYCHAIN")
  else
    echo "warning: no local signing identity, signing ad hoc; permissions will reset on every build." >&2
    echo "         Run scripts/setup_signing.sh once to fix that." >&2
    IDENTITY="-"
  fi
fi

codesign --force --deep "${KEYCHAIN_ARGS[@]}" --sign "$IDENTITY" "$APP_PATH"
codesign --verify --deep --strict "$APP_PATH"

echo "Signed: $APP_PATH ($IDENTITY)"
