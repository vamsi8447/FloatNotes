#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "Build this project on macOS 15 or later." >&2
  exit 1
fi
if pgrep -x FloatNotes >/dev/null 2>&1; then
  echo "Quit FloatNotes with Command-Q before rebuilding; do not replace a running app." >&2
  exit 1
fi
if ! xcrun --find swift >/dev/null 2>&1; then
  echo "Install Xcode Command Line Tools first: xcode-select --install" >&2
  exit 1
fi
swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"
APP_PATH="$PWD/dist/FloatNotes.app"
mkdir -p "$APP_PATH/Contents/MacOS"
cp "$BIN_DIR/FloatNotes" "$APP_PATH/Contents/MacOS/FloatNotes"
cp Info.plist "$APP_PATH/Contents/Info.plist"
# Use a real, stable signing identity when exactly one suitable identity exists.
# With multiple identities, let the user choose via SIGNING_IDENTITY rather than
# silently selecting an account. No permissions database is modified.
FLOATNOTES_SIGNING_IDENTITY="${SIGNING_IDENTITY:-}"
if [[ -z "$FLOATNOTES_SIGNING_IDENTITY" ]]; then
  IDENTITIES="$(security find-identity -v -p codesigning 2>/dev/null | awk '/"(Apple Development:|Developer ID Application:)/ {print $2}' || true)"
  IDENTITY_COUNT="$(printf '%s\n' "$IDENTITIES" | awk 'NF {n++} END {print n+0}')"
  if [[ "$IDENTITY_COUNT" == "1" ]]; then
    FLOATNOTES_SIGNING_IDENTITY="$IDENTITIES"
  else
    FLOATNOTES_SIGNING_IDENTITY="-"
    echo "No single signing certificate selected: using a local ad-hoc signature."
    echo "macOS may ask for capture/Keychain permission again after a rebuild."
    echo "For stable updates, set SIGNING_IDENTITY to an Apple Development or Developer ID identity."
  fi
fi
codesign --force --sign "$FLOATNOTES_SIGNING_IDENTITY" --timestamp=none "$APP_PATH"
codesign --verify --strict "$APP_PATH"
echo "Built $APP_PATH"
echo "Install to the stable location: bash scripts/install.sh --skip-build"
