#!/usr/bin/env python3
"""
Download the Nepali split of AI4Bharat's Aksharantar dataset and
flatten it to a deduped Devanagari↔Roman TSV.

Output: work/corpus/aksharantar_nep.tsv  (devanagari<TAB>roman)

Aksharantar is the gold human-aligned word-pair corpus IndicXlit was
trained on. ~2.4M Nepali pairs, license CC0 + CC-BY. Using the
dataset directly avoids the ~5GB torch+fairseq install required to
run IndicXlit, and gives more accurate romanizations (real-world
typed forms, not model guesses).

Lang code is "nep" (3-letter ISO 639-3) — NOT "ne". The PyPI README
for ai4bharat-transliteration is wrong on this point.
"""
import argparse
import sys
import unicodedata
from pathlib import Path

HF_DATASET = "ai4bharat/Aksharantar"
# The repo no longer publishes per-language BuilderConfigs (only 'default').
# We discover Nepali file(s) by name match instead.
NEPALI_NAME_TOKENS = ("nep", "ne_", "/ne/", "_ne.", "_ne_", "-ne-", "nepali")


def is_clean_roman(s: str) -> bool:
    if not s:
        return False
    if not s.isascii():
        return False
    for c in s:
        if c.isdigit():
            return False
        if not (c.isalpha() or c in " '-"):
            return False
    return True


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--work-dir", type=Path, default=Path("work/corpus"))
    args, _unknown = ap.parse_known_args()

    args.work_dir.mkdir(parents=True, exist_ok=True)
    out_path = args.work_dir / "aksharantar_nep.tsv"

    print(f"[hf] loading {HF_DATASET} (Nepali files)")
    print("     (first run downloads ~500MB to ~/.cache/huggingface/)")

    # Lazy import so --help works without huggingface_hub installed.
    from huggingface_hub import hf_hub_download, list_repo_files  # type: ignore

    # Discover Nepali data files. The repo no longer publishes per-language
    # BuilderConfigs (only 'default'); per-language splits are filename-based.
    all_files = list_repo_files(HF_DATASET, repo_type="dataset")
    nep_files = sorted(
        f for f in all_files
        if any(tok in f.lower() for tok in NEPALI_NAME_TOKENS)
    )
    if not nep_files:
        print("[hf] could not find any Nepali files. Repo contents:")
        for f in sorted(all_files):
            print(f"        {f}")
        raise SystemExit(
            "no Nepali files matched — inspect the listing above and "
            "edit NEPALI_NAME_TOKENS in fetch_aksharantar.py"
        )
    print(f"[hf] matched {len(nep_files)} Nepali file(s):")
    for f in nep_files:
        print(f"        {f}")

    # Download each file. We parse JSON ourselves rather than going through
    # `datasets.load_dataset(data_files=...)` because Aksharantar's per-split
    # files have inconsistent schemas (train has 'score', test/val do not),
    # which trips load_dataset's schema-merging step.
    local_paths = []
    for f in nep_files:
        local = hf_hub_download(HF_DATASET, filename=f, repo_type="dataset")
        local_paths.append(Path(local))
        print(f"[hf]   downloaded {f} -> {local}")

    deva_keys = ("native word", "native_word", "indic", "target")
    roman_keys = ("english word", "english_word", "roman", "source_word")

    seen: set[tuple[str, str]] = set()
    bad = 0
    examined = 0
    with out_path.open("w", encoding="utf-8") as fh:
        for path in local_paths:
            for row in iter_records(path):
                examined += 1
                deva_raw = first_present(row, deva_keys)
                roman_raw = first_present(row, roman_keys)
                if not deva_raw or not roman_raw:
                    bad += 1
                    continue
                deva = unicodedata.normalize("NFC", str(deva_raw).strip())
                roman = str(roman_raw).strip().lower()
                if not deva or not is_clean_roman(roman):
                    bad += 1
                    continue
                key = (deva, roman)
                if key in seen:
                    continue
                seen.add(key)
                fh.write(f"{deva}\t{roman}\n")

    print(f"[hf] examined {examined:,} rows, kept {len(seen):,} unique pairs")
    print(f"[hf] wrote {out_path}")
    if bad:
        print(f"[hf] skipped {bad:,} rows (empty / non-ASCII roman / missing fields)")
    return 0


def first_present(row: dict, keys: tuple) -> object:
    for k in keys:
        if k in row and row[k]:
            return row[k]
    return None


def iter_records(path: Path):
    """Yield dict records from a JSON / JSONL file or a ZIP of either."""
    import io
    import zipfile

    if path.suffix.lower() == ".zip":
        with zipfile.ZipFile(path) as zf:
            for inner in zf.namelist():
                if inner.endswith("/") or inner.startswith("__MACOSX"):
                    continue
                with zf.open(inner) as raw:
                    text_stream = io.TextIOWrapper(raw, encoding="utf-8")
                    print(f"[hf]   reading {path.name}!{inner}")
                    yield from _iter_text(text_stream, f"{path.name}!{inner}")
        return

    with path.open(encoding="utf-8") as fh:
        yield from _iter_text(fh, path.name)


def _iter_text(fh, label: str):
    import json
    first = fh.read(1)
    if not first:
        return
    if first == "[":
        rest = first + fh.read()
        for r in json.loads(rest):
            yield r
        return
    # JSON Lines
    line0 = first + fh.readline()
    for i, line in enumerate([line0, *fh], 1):
        line = line.strip()
        if not line:
            continue
        try:
            yield json.loads(line)
        except json.JSONDecodeError as e:
            print(f"[hf]   {label}:{i} bad JSON ({e}); skipping")
            continue


if __name__ == "__main__":
    sys.exit(main())
