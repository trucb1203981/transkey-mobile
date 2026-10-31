#!/usr/bin/env python3
"""Build the keyboard word-suggestion lists for DE/FR/ES/IT/PT.

Output: one word per line, most frequent first, written to both
android/app/src/main/assets/words_<lang>.txt and
ios/TransKeyKeyboard/Resources/words_<lang>.txt (read by WordSuggester).

Ranking comes from wordfreq (lowercased). Web text carries common misspellings
("trés", "perchè", "tambien"), English and slang, so every word must pass a
LibreOffice hunspell dictionary (build time only, never shipped); a word only
accepted capitalised is kept capitalised (names, German nouns). German casing
is first restored from a Leipzig news corpus sentences file: a word takes its
capitalised form when, away from the start of a sentence, that form is more
frequent than the lowercase one (sentence-initial "Denn" must not win).
See README.md in this folder for sources and licences.

Usage:
  pip install wordfreq spylls
  python3 build_word_lists.py --leipzig-de <path to deu_news_*-sentences.txt> \
      --hunspell-dir <folder with fr.dic/.aff, de_DE_frami, es_ES, it_IT, pt_BR, pt_PT>
"""
import argparse
import re
from pathlib import Path

from spylls.hunspell import Dictionary
from wordfreq import top_n_list

LANGS = ["de", "fr", "es", "it", "pt"]
# LibreOffice dictionaries (github.com/LibreOffice/dictionaries); a word passes
# if any dictionary of its language accepts it.
HUNSPELL = {
    "de": ["de_DE_frami"],
    "fr": ["fr"],
    "es": ["es_ES"],
    "it": ["it_IT"],
    "pt": ["pt_BR", "pt_PT"],
}
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


def spelled(w, dicts):
    """The form of w a dictionary accepts (w itself first, then capitalised), or None."""
    for form in (w, w[:1].upper() + w[1:]):
        if any(d.lookup(form) for d in dicts):
            return form
    return None


def eszett_forms(w):
    """w with every subset of its "ss" restored to "ß", w itself first.

    wordfreq casefolds, which turns "ß" into "ss" ("große" arrives as
    "grosse"), so German words must get their ß back before the spell check.
    """
    parts = w.split("ss")
    forms = [parts[0]]
    for part in parts[1:]:
        forms = [f + sep + part for f in forms for sep in ("ss", "ß")]
    return forms


def with_casing(w, casing):
    """w capitalised when Leipzig sees that form more often away from sentence starts."""
    cap = w[:1].upper() + w[1:]
    if casing.get(cap, 0) >= 3 and casing.get(cap, 0) > casing.get(w, 0):
        return cap
    return w


def build(lang, casing, dicts):
    out, seen, kept = [], set(), set()
    for raw in top_n_list(lang, POOL):
        if len(raw) < 2 or not raw.isalpha() or raw in seen:
            continue
        seen.add(raw)
        # German: restore ß first (Leipzig and the dictionary both spell it),
        # then take Leipzig's casing, then the spell check.
        word = None
        for c in (eszett_forms(raw) if lang == "de" else [raw]):
            if casing:
                c = with_casing(c, casing)
            word = spelled(c, dicts) or spelled(c.lower(), dicts)
            if word:
                break
        if word is None or word in kept:
            continue
        kept.add(word)
        out.append(word)
        if len(out) >= SIZE:
            break
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--leipzig-de", required=True, help="Leipzig deu_*-sentences.txt for German casing")
    ap.add_argument("--hunspell-dir", required=True, help="folder with the LibreOffice .dic/.aff files")
    args = ap.parse_args()
    casing_de = load_leipzig_counts(args.leipzig_de)
    for lang in LANGS:
        dicts = [Dictionary.from_files(str(Path(args.hunspell_dir) / n)) for n in HUNSPELL[lang]]
        words = build(lang, casing_de if lang == "de" else None, dicts)
        for d in OUTPUTS:
            (d / f"words_{lang}.txt").write_text("\n".join(words) + "\n", encoding="utf-8")
        print(f"{lang}: {len(words)} words, top: {' '.join(words[:8])}")


if __name__ == "__main__":
    main()
