#!/usr/bin/env bash
# Decide whether HEAD needs a release. Prints "yes" or "no: <reason>".
#
# Skips when everything changed since the last release tag is docs only:
# README.md (at any level), AGENTS.md or CLAUDE.md. None of these ship in
# the app. With no release tag yet, always releases.
set -euo pipefail

ROOT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"
cd "$ROOT_DIR"

TAG_RE='^v[0-9]+\.[0-9]+\.[0-9]+$'

current=$(git tag --points-at HEAD | grep -E "$TAG_RE" || true)
if [[ -n "$current" ]]; then
    echo "no: already released as $current"
    exit 0
fi

last=$(git tag -l --sort=-v:refname | grep -E "$TAG_RE" | head -1 || true)
if [[ -z "$last" ]]; then
    echo "yes"
    exit 0
fi

shipping=$(git diff --name-only "$last" HEAD \
    | grep -vE '(^|/)README\.md$|^AGENTS\.md$|^CLAUDE\.md$' || true)
if [[ -z "$shipping" ]]; then
    echo "no: only docs changed since $last"
else
    echo "yes"
fi
