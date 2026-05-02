# Corpus Build Pipeline

Generates `BundleResources/system_dict.tsv` (the IME's bundled dictionary)
from real-world data sources. Replaces the 150-word hand-curated starter
with a ~30k-headword / ~100k-row corpus.

## Sources

| Data | Used for | License |
|---|---|---|
| [AI4Bharat Aksharantar](https://huggingface.co/datasets/ai4bharat/Aksharantar) `nep-en` split | Romanization variants per Devanagari word (~2.4M Nepali pairs) | CC0 (mined) + CC-BY (manual) |
| [Nepali Wikipedia dump](https://dumps.wikimedia.org/newiki/) | Frequency ranking — picks which 30k of those words actually ship | CC-BY-SA |

Aksharantar is the dataset IndicXlit was *trained* on. Using it directly
gives gold human-aligned pairs without paying for ~5GB of torch+fairseq
to run inference. Quality is also higher — these are real human-typed
romanizations, not model guesses.

Why not Hindi-trained transliteration? Schwa deletion differs (`मन` =
"man" in Hindi, "mana" in Nepali speech), postpositions/verbs are
different (छ vs है, गर्छु vs करता हूँ), loanwords differ. Aksharantar's
Nepali split was mined from real Nepali corpora, so it already contains
both schwa-preserving and Hindi-influenced typing styles — both will be
in the output.

## One-liner

```bash
./scripts/corpus/run_all.sh                # ~10 min full run
./scripts/corpus/run_all.sh --top 500      # ~2 min smoke test
```

The first run creates a venv at `.venv-corpus/` and pip-installs
`datasets`, `wikiextractor`, `tqdm` (~200MB total — vs several GB if we
used IndicXlit). Subsequent runs reuse it.

**Back up the existing dictionary first** if you care about the 150-word
starter — `build_dict.py` overwrites `BundleResources/system_dict.tsv`:

```bash
cp BundleResources/system_dict.tsv BundleResources/system_dict.tsv.starter
```

After the pipeline finishes, rebuild and install the IME:

```bash
./scripts/install.sh
```

## Expected timings

| Step | What happens | Time |
|---|---|---|
| 1 | Download newiki dump + extract + tokenize + count | ~5 min |
| 2 | HuggingFace download Aksharantar nep-en | ~3 min |
| 3 | Build system_dict.tsv | ~30 sec |
| 4 | Eval regression check | <1 sec |

First run also pip-installs deps (~1 min) and pulls Aksharantar to
`~/.cache/huggingface/` (~500MB).

## Files

```
scripts/corpus/
├── README.md              you're here
├── requirements.txt       datasets, wikiextractor, tqdm
├── fetch_wiki_freq.py     wiki dump → work/corpus/frequencies.tsv
├── fetch_aksharantar.py   HF dataset → work/corpus/aksharantar_nep.tsv
├── build_dict.py          combine → BundleResources/system_dict.tsv
├── eval_pairs.tsv         hand-curated regression set (~70 pairs)
├── eval.py                check eval_pairs against generated dict
└── run_all.sh             venv setup + orchestrates all 4 steps
```

Intermediate files live in `work/corpus/` (gitignored). Each step is
idempotent — if its output exists it's skipped. To force re-run a step,
delete its output and re-invoke `run_all.sh`.

## Eval set

`eval_pairs.tsv` is a small hand-authored regression set covering
Nepali-specific cases that a Hindi-trained model would get wrong:
postpositions (छ, छैन), verb forms (गर्छु, गर्नुस्), schwa-preserving
variants (मन→mana), conjuncts (क्षेत्र, ज्ञान). Run after any pipeline
change:

```bash
.venv-corpus/bin/python scripts/corpus/eval.py
```

Misses don't fail the pipeline (the dict is still produced) but they
print to stderr so you can see what's missing. Add cases to
`eval_pairs.tsv` whenever you find a regression-worthy word the IME
should always handle.

## Coverage gap recovery (future, optional)

`build_dict.py` reports how many ranked Devanagari words have no
Aksharantar coverage and were skipped. If that number is large, the
gap can be filled by running IndicXlit on the missed words only — much
smaller workload than the full 30k. Out of scope for v1; would add
`fetch_indicxlit_gap.py` between steps 2 and 3.

## Distribution note

Personal/dev install: no attribution required.

If you redistribute the bundled dict outside personal use, add a
`LICENSE-third-party` file crediting:
- AI4Bharat Aksharantar (CC0/CC-BY)
- Wikimedia Foundation (CC-BY-SA on derived frequency data)
