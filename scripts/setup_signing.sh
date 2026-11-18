#!/usr/bin/env bash
# Creates a local code-signing identity for Jit, once per Mac.
#
# An ad-hoc signature changes with every build, and macOS ties privacy
# permissions (Accessibility, Input Monitoring) to the signature, so each new
# build lost them. A fixed certificate keeps them across builds.
#
# The certificate lives in its own keychain, unlocked with a random password
# stored next to it, so signing never prompts and never needs the login
# password. Nothing here is trusted system-wide; macOS only compares the
# certificate when it checks permissions.
set -euo pipefail

DIR="${JIT_SIGNING_DIR:-$HOME/Library/Application Support/JitSigning}"
KEYCHAIN="$DIR/jit-signing.keychain-db"
PASSWORD_FILE="$DIR/keychain-password"
NAME="Jit Local Code Signing"

if [[ -f "$KEYCHAIN" && -f "$PASSWORD_FILE" ]]; then
  security unlock-keychain -p "$(cat "$PASSWORD_FILE")" "$KEYCHAIN"
  if security find-identity -p codesigning "$KEYCHAIN" | grep -q "\"$NAME\""; then
    echo "Signing identity already set up: $NAME ($KEYCHAIN)"
    exit 0
  fi
fi

mkdir -p "$DIR"
chmod 700 "$DIR"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

PASSWORD="$(openssl rand -hex 24)"
umask 077
printf '%s' "$PASSWORD" > "$PASSWORD_FILE"

cat > "$WORK/cert.cnf" <<CNF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $NAME
[ext]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
CNF

openssl req -x509 -newkey rsa:2048 -nodes -days 7300 \
  -config "$WORK/cert.cnf" -keyout "$WORK/key.pem" -out "$WORK/cert.pem" 2>/dev/null
# macOS `security import` reads only the legacy PKCS#12 encryption.
openssl pkcs12 -export -legacy -inkey "$WORK/key.pem" -in "$WORK/cert.pem" \
  -name "$NAME" -out "$WORK/identity.p12" -passout "pass:$PASSWORD"

rm -f "$KEYCHAIN"
security create-keychain -p "$PASSWORD" "$KEYCHAIN"
security set-keychain-settings "$KEYCHAIN"
security unlock-keychain -p "$PASSWORD" "$KEYCHAIN"
security import "$WORK/identity.p12" -k "$KEYCHAIN" -P "$PASSWORD" -T /usr/bin/codesign >/dev/null
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$PASSWORD" "$KEYCHAIN" >/dev/null

echo "Created signing identity: $NAME ($KEYCHAIN)"
