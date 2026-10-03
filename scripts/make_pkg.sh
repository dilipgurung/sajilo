#!/usr/bin/env bash
# Build a per-user .pkg installer for Sajilo.
#
# Output: dist/Sajilo.pkg
# Install location: ~/Library/Input Methods/Sajilo.app  (no admin password)
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

APP_NAME="Sajilo"
DIST_DIR="$ROOT_DIR/dist"
APP_DIR="$DIST_DIR/$APP_NAME.app"
STAGING="$DIST_DIR/pkg-staging"
COMPONENT_PKG="$DIST_DIR/component.pkg"
FINAL_PKG="$DIST_DIR/$APP_NAME.pkg"

# Read version from Info.plist so the pkg version tracks the bundle.
# SAJILO_VERSION (set by the release workflow) overrides it; bundle.sh
# stamps the same value into the app.
VERSION="${SAJILO_VERSION:-$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" \
    "$ROOT_DIR/BundleResources/Info.plist" 2>/dev/null || echo "0.1.0")}"

echo "==> Building app bundle (delegates to bundle.sh)"
"$ROOT_DIR/scripts/bundle.sh"

if [[ ! -d "$APP_DIR" ]]; then
    echo "ERROR: bundle.sh did not produce $APP_DIR" >&2
    exit 1
fi

echo "==> Staging payload at $STAGING"
COMPONENT_PLIST="$DIST_DIR/component.plist"
rm -rf "$STAGING" "$COMPONENT_PKG" "$FINAL_PKG" "$COMPONENT_PLIST" "$DIST_DIR/distribution.xml"
# Mirror the destination tree relative to / so pkgbuild's
# --install-location=/ + the distribution.xml's
# enable_currentUserHome=true gives us ~/Library/Input Methods/Sajilo.app.
mkdir -p "$STAGING/Library/Input Methods"
cp -R "$APP_DIR" "$STAGING/Library/Input Methods/"

# Generate a component plist and force BundleIsRelocatable=NO. Without
# this, pkgbuild auto-marks the .app as relocatable (the default for
# any CFBundle in the payload). Combined with enable_currentUserHome,
# Installer ends up either prompting for a relocation target or
# silently skipping the copy into ~/Library/Input Methods/. We want
# the path locked: it MUST land at ~/Library/Input Methods/Sajilo.app.
echo "==> Generating component plist (BundleIsRelocatable=NO)"
pkgbuild --analyze --root "$STAGING" "$COMPONENT_PLIST" >/dev/null
/usr/libexec/PlistBuddy -c "Set :0:BundleIsRelocatable false" "$COMPONENT_PLIST"

echo "==> Building component pkg"
pkgbuild \
    --root "$STAGING" \
    --component-plist "$COMPONENT_PLIST" \
    --install-location "/" \
    --identifier "com.gurungdilip.inputmethod.Sajilo.pkg" \
    --version "$VERSION" \
    --scripts "$ROOT_DIR/scripts/pkg_resources/scripts" \
    "$COMPONENT_PKG"

echo "==> Building distribution pkg with installer UI"
# distribution.xml carries a __VERSION__ placeholder; Info.plist is the
# single source of truth for the version.
DISTRIBUTION_XML="$DIST_DIR/distribution.xml"
sed "s/__VERSION__/$VERSION/g" "$ROOT_DIR/scripts/pkg_resources/distribution.xml" > "$DISTRIBUTION_XML"
productbuild \
    --distribution "$DISTRIBUTION_XML" \
    --package-path "$DIST_DIR" \
    --resources "$ROOT_DIR/scripts/pkg_resources/resources" \
    "$FINAL_PKG"

# Component pkg is an intermediate; productbuild has copied it inside.
rm -f "$COMPONENT_PKG" "$COMPONENT_PLIST" "$DISTRIBUTION_XML"
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
