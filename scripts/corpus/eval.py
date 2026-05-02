#!/usr/bin/env python3
"""
Regression check: confirm that hand-curated Roman→Devanagari pairs
are present in the generated system_dict.tsv. Catches Hindi/Nepali
divergence regressions (schwa preservation, छ/छैन, conjuncts).

Exit code is 0 if all REQUIRED pairs hit, 1 otherwise.
A "miss" prints the expected pair plus what the dict actually returned
for that Roman input, so it's easy to see whether the romanization
maps to a different Devanagari word or simply isn't in the dict.
"""
import argparse
import sys
import unicodedata
from collections import defaultdict
from pathlib import Path


def load_dict(path: Path) -> dict[str, set[str]]:
    """Returns {roman: set(devanagari_outputs)}."""
    out: dict[str, set[str]] = defaultdict(set)
    with path.open(encoding="utf-8") as fh:
        for line in fh:
            line = line.rstrip("\n")
            if not line or line.startswith("#"):
                continue
            parts = line.split("\t")
            if len(parts) < 2:
                continue
            roman = parts[0].strip().lower()
            deva = unicodedata.normalize("NFC", parts[1])
            if roman and deva:
                out[roman].add(deva)
    return out


def load_pairs(path: Path) -> list[tuple[str, list[str]]]:
    """Each pair is (roman, [accepted_devanagari, ...]).
    Multiple accepted spellings are written pipe-separated:
        buba<TAB>बुवा|बुबा
    """
    pairs = []
    with path.open(encoding="utf-8") as fh:
        for line in fh:
            line = line.rstrip("\n")
            if not line or line.startswith("#"):
                continue
            parts = line.split("\t")
            if len(parts) < 2:
                continue
            roman = parts[0].strip().lower()
            accepted = [
                unicodedata.normalize("NFC", v.strip())
                for v in parts[1].split("|")
                if v.strip()
            ]
            if roman and accepted:
                pairs.append((roman, accepted))
    return pairs


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--dict", type=Path,
                    default=Path("BundleResources/system_dict.tsv"))
    ap.add_argument("--pairs", type=Path,
                    default=Path("scripts/corpus/eval_pairs.tsv"))
    args = ap.parse_args()

    if not args.dict.exists():
        raise SystemExit(f"missing {args.dict} — run build_dict.py first")
    if not args.pairs.exists():
        raise SystemExit(f"missing {args.pairs}")

    dict_map = load_dict(args.dict)
    pairs = load_pairs(args.pairs)

    misses = []
    hits = 0
    for roman, accepted in pairs:
        outputs = dict_map.get(roman, set())
        if any(a in outputs for a in accepted):
            hits += 1
        else:
            misses.append((roman, accepted, outputs))

    total = len(pairs)
    print(f"[eval] {hits}/{total} pairs found "
          f"({(100 * hits / total) if total else 0:.1f}%)")
    if misses:
        print(f"[eval] {len(misses)} miss(es):")
        for roman, accepted, actual in misses:
            expected_str = " | ".join(accepted)
            actual_str = ", ".join(sorted(actual)) if actual else "(no entry)"
            print(f"        {roman!r:>16}  expected {expected_str}  "
                  f"got: {actual_str}")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
