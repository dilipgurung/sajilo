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

# Sanity-check the dictionary size — refuse to ship the 150-word
# starter unless the caller explicitly opts in. Counts non-blank,
# non-comment lines as data rows.
DICT_ROWS=$(grep -cv '^[[:space:]]*#\|^[[:space:]]*$' \
    "$RESOURCES_DIR/system_dict.tsv" || true)
if (( DICT_ROWS < 5000 )); then
    echo "ERROR: system_dict.tsv has only $DICT_ROWS data rows — looks like" >&2
    echo "       the 150-word starter, not the corpus-built dictionary." >&2
    echo "       Run ./scripts/corpus/run_all.sh first, then re-run bundle.sh." >&2
    echo "       (To bypass deliberately, e.g. for a starter-only build," >&2
    echo "        re-run with NEPALI_IME_ALLOW_STARTER=1.)" >&2
    if [[ "${NEPALI_IME_ALLOW_STARTER:-0}" != "1" ]]; then
        exit 1
    fi
    echo "==> NEPALI_IME_ALLOW_STARTER=1 set — proceeding with starter dict" >&2
fi
echo "==> Bundled system_dict.tsv ($DICT_ROWS data rows)"

# Bundle the hand-curated lemma seed alongside the merged dictionary —
# transparency artifact / audit trail. The IME doesn't load it at
# runtime (its rows are already merged into system_dict.tsv with
# boosted frequencies); shipping it lets users see what was hand-
# curated and supports future "ship as separate higher-priority
# source" features.
if [[ -f "$ROOT_DIR/scripts/corpus/lemma_seed.tsv" ]]; then
    cp "$ROOT_DIR/scripts/corpus/lemma_seed.tsv" "$RESOURCES_DIR/lemma_seed.tsv"
    SEED_ROWS=$(grep -cv '^[[:space:]]*#\|^[[:space:]]*$' \
        "$RESOURCES_DIR/lemma_seed.tsv" || true)
    echo "==> Bundled lemma_seed.tsv ($SEED_ROWS data rows)"
fi

if [[ -f "$ROOT_DIR/BundleResources/MenuIcon.icns" ]]; then
    cp "$ROOT_DIR/BundleResources/MenuIcon.icns" "$RESOURCES_DIR/MenuIcon.icns"
fi

if [[ -f "$ROOT_DIR/BundleResources/PaletteIconTemplate.icns" ]]; then
    cp "$ROOT_DIR/BundleResources/PaletteIconTemplate.icns" "$RESOURCES_DIR/PaletteIconTemplate.icns"
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
