#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_PATH="$ROOT_DIR/Build/TermWrap.app"

if [[ ! -d "$APP_PATH" ]]; then
    "$ROOT_DIR/build.sh" >/dev/null
fi

open "$APP_PATH"
