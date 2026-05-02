#!/usr/bin/env python3
"""
Download Nepali Wikipedia dump, extract plain text, and produce a
frequency-ranked list of Devanagari words.

Output: work/corpus/frequencies.tsv  (word<TAB>count, sorted desc)

Used only for ranking — romanizations come from Aksharantar
(see fetch_aksharantar.py). This step picks which Devanagari
headwords actually ship in the IME bundle.
"""
import argparse
import re
import subprocess
import sys
import unicodedata
import urllib.request
from collections import Counter
from pathlib import Path

WIKI_URL = (
    "https://dumps.wikimedia.org/newiki/latest/"
    "newiki-latest-pages-articles.xml.bz2"
)

DEVA_TOKEN = re.compile(r"[ऀ-ॿ]+")


def fetch(url: str, dest: Path) -> None:
    if dest.exists():
        print(f"[fetch] already have {dest} ({dest.stat().st_size:,} bytes)")
        return
    print(f"[fetch] downloading {url}")
    print(f"        -> {dest}")
    urllib.request.urlretrieve(url, dest)
    print(f"[fetch] done ({dest.stat().st_size:,} bytes)")


def extract(dump_path: Path, text_dir: Path) -> None:
    if text_dir.exists() and any(text_dir.rglob("wiki_*")):
        print(f"[extract] already extracted to {text_dir}")
        return
    text_dir.mkdir(parents=True, exist_ok=True)
    cmd = [
        sys.executable, "-m", "wikiextractor.WikiExtractor",
        "-o", str(text_dir),
        "-b", "20M",
        "--no-templates",
        "--quiet",
        str(dump_path),
    ]
    print(f"[extract] {' '.join(cmd)}")
    subprocess.check_call(cmd)


def iter_text(text_dir: Path):
    for path in sorted(text_dir.rglob("wiki_*")):
        with open(path, encoding="utf-8") as fh:
            for line in fh:
                line = line.strip()
                if not line or line.startswith("<"):
                    continue
                yield line


def is_clean_word(w: str) -> bool:
    if not (2 <= len(w) <= 25):
        return False
    for c in w:
        if not ("ऀ" <= c <= "ॿ"):
            return False
    if len(set(w)) == 1:
        return False
    return True


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--work-dir", type=Path, default=Path("work/corpus"))
    ap.add_argument("--top", type=int, default=50000,
                    help="Keep top-N most frequent words (default: 50000).")
    args, _unknown = ap.parse_known_args()  # tolerate orchestrator passthroughs

    args.work_dir.mkdir(parents=True, exist_ok=True)
    dump_path = args.work_dir / "newiki-latest-pages-articles.xml.bz2"
    text_dir = args.work_dir / "extracted"
    out_path = args.work_dir / "frequencies.tsv"

    fetch(WIKI_URL, dump_path)
    extract(dump_path, text_dir)

    print("[count] tokenizing extracted text...")
    counter: Counter = Counter()
    for line in iter_text(text_dir):
        for tok in DEVA_TOKEN.findall(line):
            tok = unicodedata.normalize("NFC", tok)
            if is_clean_word(tok):
                counter[tok] += 1

    kept = counter.most_common(args.top)
    print(f"[count] {len(counter):,} unique words; keeping top {len(kept):,}")

    with out_path.open("w", encoding="utf-8") as fh:
        for word, count in kept:
            fh.write(f"{word}\t{count}\n")
    print(f"[count] wrote {out_path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
