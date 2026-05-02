#!/usr/bin/env bash
# Build BundleResources/system_dict.tsv from the Aksharantar HF dataset
# (romanizations) ranked by Nepali Wikipedia frequency.
#
# Sets up a venv at .venv-corpus/ on first run. Each step caches its
# intermediate output under work/corpus/, so re-running is fast unless
# you delete the cache.
#
# Usage:
#     ./scripts/corpus/run_all.sh                # full run (~10 min)
#     ./scripts/corpus/run_all.sh --top 500      # smoke test (small)
#
# Args after the script name pass through to fetch_wiki_freq.py.
set -euo pipefail

ROOT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/../.." && pwd )"
cd "$ROOT_DIR"

VENV="$ROOT_DIR/.venv-corpus"
if [[ ! -d "$VENV" ]]; then
    echo "==> Creating venv at $VENV"
    python3 -m venv "$VENV"
    "$VENV/bin/pip" install --upgrade pip
    "$VENV/bin/pip" install -r scripts/corpus/requirements.txt
fi
PY="$VENV/bin/python"

echo "==> Step 1: Wikipedia frequency list"
"$PY" scripts/corpus/fetch_wiki_freq.py "$@"

echo "==> Step 2: Aksharantar pairs (HuggingFace download)"
"$PY" scripts/corpus/fetch_aksharantar.py

echo "==> Step 3: Build system_dict.tsv"
"$PY" scripts/corpus/build_dict.py

echo "==> Step 4: Eval regression check"
if ! "$PY" scripts/corpus/eval.py; then
    echo "==> Eval found misses. Inspect output above; pipeline still produced a dict."
fi

echo
echo "==> Done. New dictionary at BundleResources/system_dict.tsv"
echo "    Run ./scripts/install.sh to rebuild and install the IME."
