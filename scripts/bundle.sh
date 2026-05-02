#!/usr/bin/env bash
# Build the NepaliIME executable in release mode and assemble it into a .app bundle
# under dist/NepaliIME.app, then ad-hoc sign it.
set -euo pipefail

ROOT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"
cd "$ROOT_DIR"

APP_NAME="NepaliIME"
DIST_DIR="$ROOT_DIR/dist"
APP_DIR="$DIST_DIR/$APP_NAME.app"
CONTENTS="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS/MacOS"
RESOURCES_DIR="$CONTENTS/Resources"

echo "==> Building $APP_NAME (release)..."
swift build -c release --product "$APP_NAME"

BUILT_BIN="$(swift build -c release --product "$APP_NAME" --show-bin-path)/$APP_NAME"
if [[ ! -x "$BUILT_BIN" ]]; then
    echo "ERROR: built binary not found at $BUILT_BIN" >&2
    exit 1
fi

echo "==> Assembling bundle at $APP_DIR..."
rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

cp "$BUILT_BIN" "$MACOS_DIR/$APP_NAME"
chmod +x "$MACOS_DIR/$APP_NAME"

cp "$ROOT_DIR/BundleResources/Info.plist" "$CONTENTS/Info.plist"
cp "$ROOT_DIR/BundleResources/system_dict.tsv" "$RESOURCES_DIR/system_dict.tsv"

if [[ -f "$ROOT_DIR/BundleResources/MenuIcon.pdf" ]]; then
    cp "$ROOT_DIR/BundleResources/MenuIcon.pdf" "$RESOURCES_DIR/MenuIcon.pdf"
fi

# Copy localized strings (each *.lproj/ supplies localized display names
# for CFBundleName, CFBundleDisplayName, and the input mode IDs declared in
# ComponentInputModeDict).
for lproj in "$ROOT_DIR"/BundleResources/*.lproj; do
    [[ -d "$lproj" ]] || continue
    name="$(basename "$lproj")"
    mkdir -p "$RESOURCES_DIR/$name"
    cp -R "$lproj"/. "$RESOURCES_DIR/$name/"
done

echo "==> Ad-hoc signing..."
codesign --force --sign - --timestamp=none --options=runtime "$APP_DIR"
codesign --verify --deep --strict --verbose=2 "$APP_DIR" || true

echo "==> Bundle ready: $APP_DIR"
