#!/usr/bin/env bash
# Build the NepaliIME .app bundle (via bundle.sh), copy it into ~/Library/Input Methods/,
# and poke the system input source registry so the new bundle is discovered.
set -euo pipefail

ROOT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"
APP_NAME="NepaliIME"
SRC_APP="$ROOT_DIR/dist/$APP_NAME.app"
DEST_DIR="$HOME/Library/Input Methods"
DEST_APP="$DEST_DIR/$APP_NAME.app"

"$ROOT_DIR/scripts/bundle.sh"

if [[ ! -d "$SRC_APP" ]]; then
    echo "ERROR: bundle did not produce $SRC_APP" >&2
    exit 1
fi

mkdir -p "$DEST_DIR"

if [[ -d "$DEST_APP" ]]; then
    echo "==> Replacing existing $DEST_APP"
    rm -rf "$DEST_APP"
fi

echo "==> Copying $APP_NAME to $DEST_DIR/"
cp -R "$SRC_APP" "$DEST_DIR/"

echo "==> Re-registering input sources..."
killall "TextInputMenuAgent" 2>/dev/null || true
killall "ControlCenter" 2>/dev/null || true
killall "TextInputSwitcher" 2>/dev/null || true

cat <<'EOF'

==> Install complete.
    Next steps:
      1. Open System Settings → Keyboard → Text Input → Edit (Input Sources)
      2. Click "+" and search "Nepali" — pick "Nepali IME"
      3. Add it; switch via the input-source menu (Control+Space or the menu-bar globe)
      4. Logs: open Console.app and filter by subsystem "com.gurungdilip.inputmethod.NepaliIME"

    User dictionary lives at:
      ~/Library/Application Support/NepaliIME/user_dict.tsv
    (one "input<TAB>output" per line; live-reloads on save)
EOF
