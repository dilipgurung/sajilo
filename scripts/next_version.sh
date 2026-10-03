#!/usr/bin/env bash
# Print the version the next release should use.
#
# Info.plist's CFBundleShortVersionString (X.Y.Z) is the base. If tag vX.Y.Z
# doesn't exist yet, release it as-is; otherwise take the highest vX.Y.* tag
# and bump its patch. Bump X or Y in Info.plist to start a new series.
set -euo pipefail

ROOT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"
cd "$ROOT_DIR"

BASE=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" BundleResources/Info.plist)
if [[ ! "$BASE" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)$ ]]; then
    echo "ERROR: CFBundleShortVersionString '$BASE' is not X.Y.Z" >&2
    exit 1
fi
SERIES="${BASH_REMATCH[1]}.${BASH_REMATCH[2]}"

if ! git rev-parse -q --verify "refs/tags/v$BASE" >/dev/null; then
    echo "$BASE"
    exit 0
fi

LATEST_PATCH=$(git tag -l "v$SERIES.*" \
    | sed -nE "s/^v${SERIES//./\\.}\.([0-9]+)$/\1/p" \
    | sort -n | tail -1)
echo "$SERIES.$((LATEST_PATCH + 1))"
