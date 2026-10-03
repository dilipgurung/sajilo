#!/usr/bin/env python3
"""Build the GitHub Pages landing page into _site/.

The page's text comes from README.md: the paragraphs between the title and
the first `##` become the hero, and every `##` section except those in
SKIPPED_SECTIONS becomes a section of the page. Everything else (download
button, demo, layout) lives in site/.

    pip install -r scripts/site_requirements.txt
    python3 scripts/build_site.py && open _site/index.html
"""
from __future__ import annotations

import html
import os
import re
import shutil
import sys
from pathlib import Path

import markdown

ROOT = Path(__file__).resolve().parent.parent
SITE_SRC = ROOT / "site"
OUT = ROOT / "_site"
TEMPLATE = "index.template.html"

REPO = os.environ.get("GITHUB_REPOSITORY", "dilipgurung/sajilo")
REPO_URL = f"https://github.com/{REPO}"

SKIPPED_SECTIONS = {"Building from source / contributing", "License"}
REQUIRED_SECTIONS = {"Install"}


def fail(msg: str) -> None:
    print(f"build_site: {msg}", file=sys.stderr)
    sys.exit(1)


def github_slug(heading: str) -> str:
    """Anchor id GitHub generates for a heading, so README links keep working."""
    slug = heading.strip().lower()
    slug = re.sub(r"[^\w\- ]", "", slug)
    return slug.replace(" ", "-")


def split_readme(text: str) -> tuple[str, list[tuple[str, str]]]:
    """Return (lead, [(heading, body), ...]); `##` inside code fences is ignored."""
    lead: list[str] = []
    sections: list[tuple[str, list[str]]] = []
    in_fence = False
    for line in text.splitlines():
        if line.startswith("```"):
            in_fence = not in_fence
        if not in_fence and line.startswith("## "):
            sections.append((line[3:].strip(), []))
        elif not in_fence and line.startswith("# ") and not sections:
            continue  # the page title; the template has its own
        elif sections:
            sections[-1][1].append(line)
        else:
            lead.append(line)
    return "\n".join(lead).strip(), [(h, "\n".join(b).strip()) for h, b in sections]


def render(md: str) -> str:
    out = markdown.markdown(md, extensions=["tables", "fenced_code"])
    # Relative links point into the repo, which only resolves on GitHub.
    out = re.sub(
        r'href="(?!https?:|mailto:|#)([^"]+)"',
        lambda m: f'href="{REPO_URL}/blob/main/{m.group(1)}"',
        out,
    )
    # Wide tables scroll inside their own box instead of the page.
    out = out.replace("<table>", '<div class="table-scroll"><table>')
    return out.replace("</table>", "</table></div>")


def main() -> None:
    lead, sections = split_readme((ROOT / "README.md").read_text(encoding="utf-8"))

    paragraphs = [p.strip() for p in lead.split("\n\n") if p.strip()]
    if len(paragraphs) < 2:
        fail("README.md needs a one-line tagline and an intro paragraph before the first `##`")
    headline, intro = paragraphs[0], "\n\n".join(paragraphs[1:])

    kept = [(h, b) for h, b in sections if h not in SKIPPED_SECTIONS]
    missing = REQUIRED_SECTIONS - {h for h, _ in kept}
    if missing:
        fail(f"README.md is missing required section(s): {', '.join(sorted(missing))}")

    toc = "\n".join(
        f'<li><a href="#{github_slug(h)}">{html.escape(h)}</a></li>' for h, _ in kept
    )
    body = "\n".join(
        f'<section class="doc-section" id="{github_slug(h)}" aria-labelledby="{github_slug(h)}-h">\n'
        f'<h2 id="{github_slug(h)}-h">{html.escape(h)}</h2>\n{render(b)}\n</section>'
        for h, b in kept
    )

    page = (SITE_SRC / TEMPLATE).read_text(encoding="utf-8")
    for key, value in {
        "headline": render(headline).removeprefix("<p>").removesuffix("</p>"),
        "intro": render(intro),
        "toc": toc,
        "sections": body,
        "repo_url": REPO_URL,
    }.items():
        token = "{{" + key + "}}"
        if token not in page:
            fail(f"{TEMPLATE} has no {token} placeholder")
        page = page.replace(token, value)

    if OUT.exists():
        shutil.rmtree(OUT)
    shutil.copytree(SITE_SRC, OUT, ignore=shutil.ignore_patterns(TEMPLATE, ".DS_Store"))
    (OUT / "index.html").write_text(page, encoding="utf-8")
    print(f"build_site: wrote {OUT.relative_to(ROOT)}/ ({len(kept)} sections)")


if __name__ == "__main__":
    main()
