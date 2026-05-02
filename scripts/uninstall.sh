#!/usr/bin/env bash
# Uninstall NepaliIME from the current user's account.
#
# Removes the .app from ~/Library/Input Methods/, kills any running
# instance, restarts the input agents so System Settings re-scans, and
# (with confirmation) wipes the user dictionary + learner database
# from ~/Library/Application Support/NepaliIME/.
#
# Usage:
#     ./scripts/uninstall.sh              # interactive — asks before deleting user data
#     ./scripts/uninstall.sh --keep-data  # remove .app only, preserve user data
#     ./scripts/uninstall.sh --all        # remove .app AND user data without prompting
set -euo pipefail

APP_PATH="$HOME/Library/Input Methods/NepaliIME.app"
DATA_DIR="$HOME/Library/Application Support/NepaliIME"

KEEP_DATA=0
PURGE_DATA=0
case "${1:-}" in
    --keep-data) KEEP_DATA=1 ;;
    --all)       PURGE_DATA=1 ;;
    "")          ;;
    *)
        echo "usage: $0 [--keep-data | --all]" >&2
        exit 2
        ;;
esac

echo "==> Stopping any running NepaliIME instance"
# pkill returns non-zero when nothing matched; that's fine.
pkill -9 -f "Input Methods/NepaliIME.app" 2>/dev/null || true

if [[ -d "$APP_PATH" ]]; then
    echo "==> Removing $APP_PATH"
    rm -rf "$APP_PATH"
else
    echo "==> $APP_PATH not present (already removed?)"
fi

if [[ $KEEP_DATA -eq 0 ]]; then
    if [[ -d "$DATA_DIR" ]]; then
        if [[ $PURGE_DATA -eq 1 ]]; then
            echo "==> Removing user data at $DATA_DIR"
            rm -rf "$DATA_DIR"
        else
            echo
            echo "User data lives at:"
            echo "    $DATA_DIR"
            echo "Contents:"
            ls -la "$DATA_DIR" | sed 's/^/    /'
            echo
            read -r -p "Delete user data (user_dict.tsv, learner.sqlite, cache)? [y/N] " confirm
            if [[ "$confirm" =~ ^[Yy]$ ]]; then
                rm -rf "$DATA_DIR"
                echo "==> Removed $DATA_DIR"
            else
                echo "==> Kept user data — re-installing later will resume your learned entries"
            fi
        fi
    else
        echo "==> No user data at $DATA_DIR (nothing to clean up)"
    fi
fi

echo "==> Re-registering input sources..."
killall "TextInputMenuAgent" >/dev/null 2>&1 || true
killall "TextInputSwitcher" >/dev/null 2>&1 || true
killall "ControlCenter"     >/dev/null 2>&1 || true

echo
echo "==> Done."
echo "    macOS may still list 'Nepali IME' as a stale entry under"
echo "    System Settings → Keyboard → Text Input → Edit (Input Sources)."
echo "    Select it and click '−' to fully forget it."
