# Corpus Build Pipeline

Generates `BundleResources/system_dict.tsv` (the IME's bundled dictionary)
from real-world data sources. Replaces the 150-word hand-curated starter
with a ~30k-headword / ~30k-row dictionary that passes 68/68 of the
hand-curated eval set.

## Sources

| Data | Used for | License |
|---|---|---|
| [AI4Bharat Aksharantar](https://huggingface.co/datasets/ai4bharat/Aksharantar) Nepali split (`nep.zip` → `nep_train.json` + `nep_valid.json` + `nep_test.json`) | Romanization variants per Devanagari word (~2.4M Nepali pairs of inflected/conjugated forms) | CC0 (mined) + CC-BY (manual) |
| [Nepali Wikipedia dump](https://dumps.wikimedia.org/newiki/) (`newiki-latest-pages-articles.xml.bz2`) | Frequency ranking — picks which 30k Devanagari headwords actually ship | CC-BY-SA |
| `lemma_seed.tsv` (in this directory) | Hand-curated bare-lemma backfill (~250 entries: pronouns, copula, numbers, common verbs, days/months, places, food, greetings) | This repo (MIT) |

### Why these three sources together

Aksharantar is the dataset IndicXlit was *trained* on. Using it directly
gives gold human-aligned pairs without paying for ~5GB of torch+fairseq
to run inference, and quality is better — these are real human-typed
romanizations, not model guesses.

But Aksharantar's Nepali split was mined from running text without
lemmatization, so it captures inflected forms (नेपालको, गरेको, थियो)
extremely well but **0 rows for bare lemmas like नेपाल, छ, हो, नमस्ते**.
Without `lemma_seed.tsv`, a user typing the most common short Nepali
words gets no candidates — eval drops to 16/68. The seed file fixes that.

Why not Hindi-trained transliteration? Schwa deletion differs (`मन` =
"man" in Hindi, "mana" in Nepali speech), postpositions/verbs are
different (छ vs है, गर्छु vs करता हूँ), loanwords differ. Aksharantar's
Nepali split contains both schwa-preserving and Hindi-influenced typing
styles — both end up in the output.

## One-liner

```bash
./scripts/corpus/run_all.sh                # full run (~10 min, ~700MB cache)
./scripts/corpus/run_all.sh --top 500      # smoke test (~2 min, ~16/68 eval)
```

The first run creates a venv at `.venv-corpus/` and pip-installs
`datasets`, `huggingface_hub`, `tqdm` (~200MB total — vs several GB if
we used IndicXlit). Subsequent runs reuse it.

**Back up the existing dictionary first** if you care about the 150-word
starter — `build_dict.py` overwrites `BundleResources/system_dict.tsv`:

```bash
cp BundleResources/system_dict.tsv BundleResources/system_dict.tsv.starter
```

After the pipeline finishes, rebuild and install the IME:

```bash
./scripts/install.sh
```

## Verified end-state

After a full run on the latest dump:

```
[build] wrote 30,168 rows (29,229 unique headwords) to BundleResources/system_dict.tsv
[build] seed: +304 new pairs, 82 frequency boosts on existing pairs
[build] 20,953 ranked words had no Aksharantar coverage (skipped — could be filled with IndicXlit later)
[eval] 68/68 pairs found (100.0%)
```

The 20,953-word coverage gap is the long-tail of low-frequency
Wikipedia words that lack Aksharantar pairs. The lemma seed handles
the high-frequency hole at the head of the distribution; the long tail
is acceptable for v1 — those words appear rarely enough that Aksharantar's
inflected variants of nearby roots usually cover the user's typing.

## Expected timings

| Step | What happens | Time |
|---|---|---|
| 1 | Download `newiki-latest-pages-articles.xml.bz2` + stream-tokenize | ~3 min |
| 2 | HuggingFace download `nep.zip` + parse JSONL → TSV | ~3 min |
| 3 | Build `system_dict.tsv` (Wikipedia rank ∩ Aksharantar pairs ∪ seed) | ~30 sec |
| 4 | Eval regression check | <1 sec |

First run also pip-installs deps (~1 min) and pulls Aksharantar to
`~/.cache/huggingface/` (~500MB).

Set `HF_TOKEN=hf_...` to silence the unauthenticated-download warning
and get higher rate limits — get a free read token at
<https://huggingface.co/settings/tokens>.

## Files

```
scripts/corpus/
├── README.md              you're here
├── requirements.txt       datasets, huggingface_hub, tqdm
├── fetch_wiki_freq.py     newiki dump → work/corpus/frequencies.tsv
├── fetch_aksharantar.py   HF nep.zip → work/corpus/aksharantar_nep.tsv
├── build_dict.py          combine + lemma_seed → BundleResources/system_dict.tsv
├── lemma_seed.tsv         hand-curated bare-lemma backfill (~250 entries)
├── eval_pairs.tsv         hand-curated regression set (~70 pairs)
├── eval.py                check eval_pairs against generated dict
└── run_all.sh             venv setup + orchestrates all 4 steps
```

Intermediate files live in `work/corpus/` (gitignored). Each step is
idempotent — if its output exists it's skipped. To force re-run a step,
delete its output and re-invoke `run_all.sh`.

## Extending the lemma seed

When `eval.py` reports a miss for a word you genuinely use (or you
discover one by typing in real apps), add it to `lemma_seed.tsv`:

```
# Format: roman<TAB>devanagari<TAB>optional_frequency
# Lines starting with # are comments.
# Multiple romanizations per Devanagari word are encouraged.
your_word	तपाईंको_देवनागरी
your_word_alt	तपाईंको_देवनागरी
```

Frequency column is optional — defaults to 100,000, which is above
Wikipedia's top-frequency words (~38,000) so seeded lemmas always
outrank corpus-mined inflected variants. Set explicit frequency
only if you want a specific row to rank lower than another seed row.

After editing the seed, re-run only the build step (no need to
re-fetch sources) and re-install:

```bash
.venv-corpus/bin/python scripts/corpus/build_dict.py
./scripts/install.sh
```

## Eval set

`eval_pairs.tsv` is a small hand-authored regression set covering
Nepali-specific cases that a Hindi-trained model would get wrong:
postpositions (छ, छैन), verb forms (गर्छु, गर्नुस्), schwa-preserving
variants (मन ← mana), conjuncts (क्षेत्र, ज्ञान), numbers, family,
greetings. Run after any pipeline change:

```bash
.venv-corpus/bin/python scripts/corpus/eval.py
```

Misses don't fail the pipeline (the dict is still produced) but they
print so you can see what's missing.

For Roman inputs that have multiple valid Devanagari spellings, use
`|`-separated alternatives — eval passes if *any* expected spelling
is in the dict:

```
buba	बुवा|बुबा
kathmandu	काठमाडौं|काठमाडौँ
```

Add cases to `eval_pairs.tsv` whenever you find a regression-worthy
word the IME should always handle. Then add the corresponding pair
to `lemma_seed.tsv` to make the eval pass.

## Troubleshooting

**`re.PatternError: global flags not at the start of the expression`** —
You're seeing a stale traceback from `wikiextractor`. The current
pipeline doesn't use it; if you have an older checkout, pull and
retry. `fetch_wiki_freq.py` now streams the bz2 directly with stdlib.

**`BuilderConfig 'nep-en' not found. Available: ['default']`** — Stale
`fetch_aksharantar.py`. The current version uses
`huggingface_hub.list_repo_files` and downloads `nep.zip` directly.

**`UnicodeDecodeError: 'utf-8' codec can't decode byte 0xcb`** —
Aksharantar's Nepali asset is a ZIP. The current `iter_records`
detects `.zip` and unpacks; if you see this you're on an older script.

**Eval drops to 16/68 after pipeline change** — `lemma_seed.tsv` isn't
being loaded. Check `--seed` arg on `build_dict.py` (defaults to
`scripts/corpus/lemma_seed.tsv`); make sure the path is correct from
your cwd.

## Coverage gap recovery (future, optional)

`build_dict.py` reports how many ranked Devanagari words have no
Aksharantar coverage and were skipped (typically ~20k). For most of
those, the IME's prefix matching against nearby Aksharantar entries
covers the user's typing. If you find specific high-value words
genuinely missing, the cleanest fix is to add them to `lemma_seed.tsv`.
A bulk gap-filler using IndicXlit on the missed Wikipedia frequencies
is possible but adds a 5GB torch+fairseq dependency — out of scope
for v1.

## Distribution note

Personal/dev install: no attribution required.

If you redistribute the bundled dict outside personal use, add a
`LICENSE-third-party` file crediting:

- AI4Bharat Aksharantar (CC0 / CC-BY)
- Wikimedia Foundation (CC-BY-SA on derived frequency data)
