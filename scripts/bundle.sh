#!/usr/bin/env bash
# Build the Sajilo executable in release mode and assemble it into a .app bundle
# under dist/Sajilo.app, then ad-hoc sign it.
set -euo pipefail

ROOT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"
cd "$ROOT_DIR"

APP_NAME="Sajilo"
DIST_DIR="$ROOT_DIR/dist"
APP_DIR="$DIST_DIR/$APP_NAME.app"
CONTENTS="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS/MacOS"
RESOURCES_DIR="$CONTENTS/Resources"

# Universal binary: the .pkg advertises arm64 + x86_64 hosts. Build each
# arch separately and lipo them together — `swift build --arch a --arch b`
# goes through the Xcode build system, which rejects Swift 6 language mode
# on some Xcode 16 toolchains.
MIN_MACOS="14.0"
ARCH_BINS=()
for arch in arm64 x86_64; do
    echo "==> Building $APP_NAME (release, $arch)..."
    BUILD_ARGS=(-c release --product "$APP_NAME" --triple "$arch-apple-macosx$MIN_MACOS"
                --scratch-path "$ROOT_DIR/.build/$arch")
    swift build "${BUILD_ARGS[@]}"
    bin="$(swift build "${BUILD_ARGS[@]}" --show-bin-path)/$APP_NAME"
    if [[ ! -x "$bin" ]]; then
        echo "ERROR: built binary not found at $bin" >&2
        exit 1
    fi
    ARCH_BINS+=("$bin")
done

BUILT_BIN="$ROOT_DIR/.build/$APP_NAME-universal"
lipo -create "${ARCH_BINS[@]}" -output "$BUILT_BIN"

echo "==> Assembling bundle at $APP_DIR..."
rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

cp "$BUILT_BIN" "$MACOS_DIR/$APP_NAME"
chmod +x "$MACOS_DIR/$APP_NAME"

cp "$ROOT_DIR/BundleResources/Info.plist" "$CONTENTS/Info.plist"
# Release builds (CI) stamp the version into the bundled copy; the
# committed Info.plist only carries the base version.
if [[ -n "${SAJILO_VERSION:-}" ]]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $SAJILO_VERSION" "$CONTENTS/Info.plist"
fi
if [[ -n "${SAJILO_BUILD:-}" ]]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $SAJILO_BUILD" "$CONTENTS/Info.plist"
fi
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
    echo "        re-run with SAJILO_ALLOW_STARTER=1.)" >&2
    if [[ "${SAJILO_ALLOW_STARTER:-0}" != "1" ]]; then
        exit 1
    fi
    echo "==> SAJILO_ALLOW_STARTER=1 set — proceeding with starter dict" >&2
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
codesign --verify --deep --strict --verbose=2 "$APP_DIR"

echo "==> Bundle ready: $APP_DIR"
