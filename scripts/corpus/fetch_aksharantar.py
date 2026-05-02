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

    # Lazy import so --help works without `datasets` / `huggingface_hub`.
    from datasets import load_dataset  # type: ignore
    from huggingface_hub import list_repo_files  # type: ignore

    # Discover Nepali data files. The repo currently has only the 'default'
    # config; the per-language splits are encoded in filenames.
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

    ds = load_dataset(HF_DATASET, data_files=nep_files, split="train")

    # Inspect schema once so the user can confirm field names.
    sample = ds[0]
    print(f"[hf] sample row: {sample}")
    keys = list(sample.keys())

    # Aksharantar uses 'native word' / 'english word' per the dataset card,
    # but field names have varied across versions. Detect at runtime.
    def pick(prefer):
        for k in keys:
            kl = k.lower().replace("_", " ")
            for p in prefer:
                if p in kl:
                    return k
        return None

    deva_key = pick(["native", "indic", "target"])
    roman_key = pick(["english", "roman", "source"])
    if not deva_key or not roman_key:
        raise SystemExit(
            f"could not identify devanagari/roman fields in row keys {keys!r}; "
            "edit fetch_aksharantar.py to map them explicitly"
        )
    print(f"[hf] mapping deva='{deva_key}' roman='{roman_key}'")

    try:
        from tqdm import tqdm  # type: ignore
        rows_iter = tqdm(ds, desc="aksharantar", unit="row")
    except ImportError:
        rows_iter = ds

    seen: set[tuple[str, str]] = set()
    bad = 0
    with out_path.open("w", encoding="utf-8") as fh:
        for row in rows_iter:
            deva_raw = row.get(deva_key)
            roman_raw = row.get(roman_key)
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

    print(f"[hf] wrote {len(seen):,} unique pairs to {out_path}")
    if bad:
        print(f"[hf] skipped {bad:,} rows (empty / non-ASCII roman / etc.)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
