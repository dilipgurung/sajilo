#!/usr/bin/env python3
"""
Download Nepali Wikipedia dump and produce a frequency-ranked list of
Devanagari words by streaming <text> elements directly from the bz2
XML dump.

Output: work/corpus/frequencies.tsv  (word<TAB>count, sorted desc)

Used only for ranking — romanizations come from Aksharantar
(see fetch_aksharantar.py). This step picks which Devanagari
headwords actually ship in the IME bundle.

Implementation note: we don't run wikiextractor — it's unmaintained
and breaks on Python 3.12+. We don't actually need clean text either,
since the DEVA_TOKEN regex only matches Devanagari sequences and wiki
markup is overwhelmingly ASCII. Streaming the bz2 directly with stdlib
xml.etree.ElementTree.iterparse is faster and has no deps.
"""
import argparse
import bz2
import re
import sys
import unicodedata
import urllib.request
import xml.etree.ElementTree as ET
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


def iter_wiki_text(dump_path: Path):
    """Stream the text content of every <page><revision><text> in the dump.

    MediaWiki dumps use a namespace like
    {http://www.mediawiki.org/xml/export-0.11/}text — we strip it.
    """
    with bz2.open(dump_path, "rb") as fh:
        for _event, elem in ET.iterparse(fh, events=("end",)):
            tag = elem.tag.rsplit("}", 1)[-1]
            if tag == "text" and elem.text:
                yield elem.text
            elem.clear()


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
    out_path = args.work_dir / "frequencies.tsv"

    fetch(WIKI_URL, dump_path)

    print("[count] streaming bz2 + tokenizing Devanagari runs...")
    counter: Counter = Counter()
    pages = 0
    for text in iter_wiki_text(dump_path):
        pages += 1
        if pages % 5000 == 0:
            print(f"[count] {pages:,} pages, {len(counter):,} unique types so far")
        for tok in DEVA_TOKEN.findall(text):
            tok = unicodedata.normalize("NFC", tok)
            if is_clean_word(tok):
                counter[tok] += 1
    print(f"[count] processed {pages:,} pages")

    kept = counter.most_common(args.top)
    print(f"[count] {len(counter):,} unique words; keeping top {len(kept):,}")

    with out_path.open("w", encoding="utf-8") as fh:
        for word, count in kept:
            fh.write(f"{word}\t{count}\n")
    print(f"[count] wrote {out_path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
