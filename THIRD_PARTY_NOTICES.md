# Third-party notices

Sajilo is MIT-licensed (see `LICENSE`). It ships with, or is built from, the
third-party software and data below.

## GRDB.swift

Linked into the Sajilo binary. <https://github.com/groue/GRDB.swift>

```
Copyright (C) 2015-2025 Gwendal Roué

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
```

## SQLite

Used through GRDB, from the copy that ships with macOS. Public domain.
<https://sqlite.org/copyright.html>

## AI4Bharat Aksharantar

The romanizations in `system_dict.tsv` are derived from the Nepali split of
Aksharantar by AI4Bharat. Mined pairs are CC0; manually collected pairs are
CC BY 4.0. <https://huggingface.co/datasets/ai4bharat/Aksharantar>

> Madhani et al., "Aksharantar: Open Indic-language Transliteration datasets
> and models for the Next Billion Users", Findings of EMNLP 2023.

## Nepali Wikipedia

The word frequencies used to choose and rank the headwords in
`system_dict.tsv` were counted from the Nepali Wikipedia dump, © Wikipedia
contributors, CC BY-SA 4.0. <https://dumps.wikimedia.org/newiki/>
