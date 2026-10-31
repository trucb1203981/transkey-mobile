#!/usr/bin/env python3
"""Build the keyboard word-suggestion lists for DE/FR/ES/IT/PT.

Output: one word per line, most frequent first, written to both
android/app/src/main/assets/words_<lang>.txt and
ios/TransKeyKeyboard/Resources/words_<lang>.txt (read by WordSuggester).

Ranking comes from wordfreq (lowercased). German capitalises nouns, so its
casing is restored from a Leipzig news corpus sentences file: a word takes its
capitalised form when, away from the start of a sentence, that form is more
frequent than the lowercase one (sentence-initial "Denn" must not win).
See README.md in this folder for sources and licences.

Usage:
  pip install wordfreq
  python3 build_word_lists.py --leipzig-de <path to deu_news_*-sentences.txt>
"""
import argparse
import re
from pathlib import Path

from wordfreq import top_n_list

LANGS = ["de", "fr", "es", "it", "pt"]
SIZE = 12000          # words kept per language
POOL = 40000          # wordfreq candidates scanned to fill SIZE after filtering
ROOT = Path(__file__).resolve().parents[2]
OUTPUTS = [
    ROOT / "android/app/src/main/assets",
    ROOT / "ios/TransKeyKeyboard/Resources",
]


WORD = re.compile(r"[^\W\d_]+")
SENTENCE_BREAK = re.compile(r"[.!?:]\s*$")


def load_leipzig_counts(path):
    """Token counts from a Leipzig sentences file, skipping sentence-initial tokens."""
    counts = {}
    with open(path, encoding="utf-8") as f:
        for line in f:
            text = line.rstrip("\n").split("\t", 1)[-1]
            for i, m in enumerate(WORD.finditer(text)):
                if i == 0 or SENTENCE_BREAK.search(text[:m.start()]):
                    continue
                counts[m.group()] = counts.get(m.group(), 0) + 1
    return counts


def build(lang, casing):
    out, seen = [], set()
    for w in top_n_list(lang, POOL):
        if len(w) < 2 or not w.isalpha() or w in seen:
            continue
        seen.add(w)
        if casing:
            cap = w[:1].upper() + w[1:]
            if casing.get(cap, 0) >= 3 and casing.get(cap, 0) > casing.get(w, 0):
                w = cap
        out.append(w)
        if len(out) >= SIZE:
            break
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--leipzig-de", required=True, help="Leipzig deu_*-sentences.txt for German casing")
    args = ap.parse_args()
    casing_de = load_leipzig_counts(args.leipzig_de)
    for lang in LANGS:
        words = build(lang, casing_de if lang == "de" else None)
        for d in OUTPUTS:
            (d / f"words_{lang}.txt").write_text("\n".join(words) + "\n", encoding="utf-8")
        print(f"{lang}: {len(words)} words, top: {' '.join(words[:8])}")


if __name__ == "__main__":
    main()
