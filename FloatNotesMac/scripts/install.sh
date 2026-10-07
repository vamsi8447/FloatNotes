#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "Run this installer on macOS." >&2
  exit 1
fi
if pgrep -x FloatNotes >/dev/null 2>&1; then
  echo "Quit FloatNotes with Command-Q before installing." >&2
  exit 1
fi
if [[ "${1:-}" != "--skip-build" ]]; then
  bash scripts/build.sh
fi
APP_SOURCE="$PWD/dist/FloatNotes.app"
APP_DESTINATION="$HOME/Applications/FloatNotes.app"
if [[ ! -f "$APP_SOURCE/Contents/MacOS/FloatNotes" ]]; then
  echo "No built application found. Run bash scripts/install.sh without --skip-build." >&2
  exit 1
fi
codesign --verify --strict "$APP_SOURCE"
mkdir -p "$HOME/Applications"
ditto "$APP_SOURCE" "$APP_DESTINATION"
codesign --verify --strict "$APP_DESTINATION"
echo "Installed $APP_DESTINATION"
echo "Always launch this copy. You do not need to rebuild to reopen it."
open "$APP_DESTINATION"
