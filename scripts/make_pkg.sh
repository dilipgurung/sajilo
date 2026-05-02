#!/usr/bin/env bash
# Build a per-user .pkg installer for the Nepali IME.
#
# Output: dist/NepaliIME.pkg
# Install location: ~/Library/Input Methods/NepaliIME.app  (no admin password)
#
# This is a Tier-1 (ad-hoc / unsigned) build — recipients on macOS 10.15+
# will need to right-click the .pkg → Open the first time, since
# Gatekeeper won't trust an unsigned installer. To produce a notarized
# .pkg that just-works for strangers, we need an Apple Developer Program
# membership ($99/yr) and Developer ID certs — see scripts/pkg_resources/
# for the structure that supports it.
set -euo pipefail

ROOT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"
cd "$ROOT_DIR"

APP_NAME="NepaliIME"
DIST_DIR="$ROOT_DIR/dist"
APP_DIR="$DIST_DIR/$APP_NAME.app"
STAGING="$DIST_DIR/pkg-staging"
COMPONENT_PKG="$DIST_DIR/component.pkg"
FINAL_PKG="$DIST_DIR/$APP_NAME.pkg"

# Read version from Info.plist so the pkg version tracks the bundle.
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" \
    "$ROOT_DIR/BundleResources/Info.plist" 2>/dev/null || echo "0.1.0")

echo "==> Building app bundle (delegates to bundle.sh)"
"$ROOT_DIR/scripts/bundle.sh"

if [[ ! -d "$APP_DIR" ]]; then
    echo "ERROR: bundle.sh did not produce $APP_DIR" >&2
    exit 1
fi

echo "==> Staging payload at $STAGING"
rm -rf "$STAGING" "$COMPONENT_PKG" "$FINAL_PKG"
# Mirror the destination tree relative to / so pkgbuild's
# --install-location=/ + the distribution.xml's
# enable_currentUserHome=true gives us ~/Library/Input Methods/NepaliIME.app.
mkdir -p "$STAGING/Library/Input Methods"
cp -R "$APP_DIR" "$STAGING/Library/Input Methods/"

echo "==> Building component pkg"
pkgbuild \
    --root "$STAGING" \
    --install-location "/" \
    --identifier "com.gurungdilip.inputmethod.NepaliIME.pkg" \
    --version "$VERSION" \
    --scripts "$ROOT_DIR/scripts/pkg_resources/scripts" \
    "$COMPONENT_PKG"

echo "==> Building distribution pkg with installer UI"
productbuild \
    --distribution "$ROOT_DIR/scripts/pkg_resources/distribution.xml" \
    --package-path "$DIST_DIR" \
    --resources "$ROOT_DIR/scripts/pkg_resources/resources" \
    "$FINAL_PKG"

# Component pkg is an intermediate; productbuild has copied it inside.
rm -f "$COMPONENT_PKG"
rm -rf "$STAGING"

PKG_SIZE=$(stat -f%z "$FINAL_PKG" 2>/dev/null || echo "?")
echo
echo "==> Done: $FINAL_PKG ($PKG_SIZE bytes)"
echo
echo "    To test locally:    open \"$FINAL_PKG\""
echo "    To distribute:      share the .pkg + tell recipients to"
echo "                        right-click → Open the first time"
echo "                        (it's unsigned; Gatekeeper would block a"
echo "                        plain double-click on macOS 10.15+)."
