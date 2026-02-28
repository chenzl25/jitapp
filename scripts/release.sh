#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

"$ROOT_DIR/scripts/build_app.sh"
"$ROOT_DIR/scripts/package_dmg.sh"

echo "Release artifacts are in $ROOT_DIR/dist"
