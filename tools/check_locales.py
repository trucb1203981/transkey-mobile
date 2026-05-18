#!/usr/bin/env python3
"""
Locale spot-check: compares each app_<lang>.arb against app_en.arb to
surface suspect translations that a human reviewer should look at first.

Two checks:
  1. Length anomaly  — a translated string > LENGTH_RATIO_MAX times the
     English source. Hints at AI over-explanation or untranslated leftover
     boilerplate.
  2. English leak  — a content word from EN (>= MIN_LEAK_WORD_LEN chars,
     not a brand / placeholder / acronym) appearing verbatim in the
     translation. Usually means the translator left the word alone instead
     of finding the local equivalent.

Run from the repo root or anywhere:
    python3 tools/check_locales.py
    python3 tools/check_locales.py --langs pt ru ar      # subset
    python3 tools/check_locales.py --verbose             # full per-key report
"""

import argparse
import json
import re
import sys
from pathlib import Path

# ---- tuning knobs ------------------------------------------------------
LENGTH_RATIO_MAX = 2.5            # >2.5x English length triggers a flag
MIN_LEAK_WORD_LEN = 4             # words shorter than this are skipped
LEAK_REPORT_LIMIT = 5             # show up to N leaked words per file

# Words that legitimately stay English in any locale: brand names, codes,
# acronyms, well-known global products. Don't flag these as leaks.
ALLOWLIST = {
    'transkey', 'google', 'apple', 'ios', 'android', 'youtube', 'netflix',
    'whatsapp', 'iphone', 'wifi', 'pro', 'mobile', 'free', 'trial',
    'tts', 'ocr', 'pdf', 'api', 'http', 'https', 'url', 'gif', 'png', 'jpg',
    'ai', 'ux', 'ui', 'app', 'apps',
    'romaji', 'pinyin',
    'email', 'http', 'idtoken', 'serverclientid',
    'lens',  # accepted brand-style term in some langs
    # ICU MessageFormat plural keywords — they live inside {var, plural, ...}
    # and are not user-visible text, but our regex picks them up.
    'plural', 'select', 'zero', 'one', 'two', 'few', 'many', 'other',
    # "$N/month" price tokens are intentionally English across all locales.
    'month',
    # Common UI loanwords legitimately retained in many target languages
    # (PT/IT/ID especially).
    'menu', 'chat', 'extra', 'mobile', 'desktop',
    'feedback', 'privacy', 'password', 'username',
    'casual', 'formal', 'keyboard', 'internet', 'online', 'offline',
    'area', 'video', 'photo',
}

# Locales the team has already reviewed — skip them in the report unless
# user passes them explicitly.
BASELINE_LOCALES = {'en', 'vi'}

# Regexes -----------------------------------------------------------------
# Matches {placeholder}, {plural, ...}, ${var}.
PLACEHOLDER_RE = re.compile(r'\{[^{}]*\}|\$\{[^}]+\}|%\d*\$?[sdf]|%[sdf]')
# Strips ICU plural / select wrapping so we compare just the body strings.
PLURAL_BODY_RE = re.compile(r'\{[^,{}]+,\s*(?:plural|select),[^{}]*\}')
# Extracts ASCII words (basic Latin).
WORD_RE = re.compile(r"[A-Za-z][A-Za-z'-]+")


def load_arb(path: Path) -> dict[str, str]:
    """Return {key: value} for non-metadata keys only (skip @key / @@locale)."""
    raw = json.loads(path.read_text(encoding='utf-8'))
    return {
        k: v
        for k, v in raw.items()
        if not k.startswith('@') and isinstance(v, str)
    }


def strip_dynamic(s: str) -> str:
    """Remove placeholders so they don't pollute length / word checks."""
    out = PLURAL_BODY_RE.sub('', s)
    out = PLACEHOLDER_RE.sub('', out)
    return out


def english_content_words(s: str) -> set[str]:
    """Significant lowercase English words in s, excluding allowlist."""
    return {
        w.lower()
        for w in WORD_RE.findall(strip_dynamic(s))
        if len(w) >= MIN_LEAK_WORD_LEN
        and w.lower() not in ALLOWLIST
    }


def check_locale(en: dict[str, str], target: dict[str, str], lang: str, verbose: bool):
    """Returns a dict with counts + sample issues."""
    length_flags: list[tuple[str, float, str, str]] = []   # (key, ratio, en, tr)
    leak_flags: list[tuple[str, set[str]]] = []            # (key, leaked_words)
    missing_keys: list[str] = []

    for key, en_val in en.items():
        tr_val = target.get(key)
        if tr_val is None:
            missing_keys.append(key)
            continue

        # Length check (only meaningful for strings with substantive text)
        en_body = strip_dynamic(en_val).strip()
        tr_body = strip_dynamic(tr_val).strip()
        if len(en_body) >= 8 and len(tr_body) > 0:
            ratio = len(tr_body) / len(en_body)
            # German/Russian/Japanese can be longer than English by ~30-50%.
            # 2.5x is well above natural variance and likely indicates
            # AI verbosity or accidental duplication.
            if ratio >= LENGTH_RATIO_MAX:
                length_flags.append((key, ratio, en_val, tr_val))

        # English-leak check: which en content words appear verbatim?
        en_words = english_content_words(en_val)
        if not en_words:
            continue
        tr_words = english_content_words(tr_val)
        leaked = en_words & tr_words
        if leaked:
            leak_flags.append((key, leaked))

    print(f'\n── {lang} ({len(target)} keys) ────────────────────────')
    if missing_keys:
        print(f'  ✗ missing {len(missing_keys)} keys: {missing_keys[:3]}…')
    print(f'  length anomalies (>{LENGTH_RATIO_MAX}x EN): {len(length_flags)}')
    print(f'  English leaks (content words verbatim): {len(leak_flags)}')

    if verbose or length_flags:
        for key, ratio, en_val, tr_val in length_flags[:5]:
            en_short = (en_val[:60] + '…') if len(en_val) > 60 else en_val
            tr_short = (tr_val[:90] + '…') if len(tr_val) > 90 else tr_val
            print(f'   • {key}  (ratio {ratio:.1f}x)')
            print(f'     EN: {en_short}')
            print(f'     {lang.upper()}: {tr_short}')

    if leak_flags:
        # Sort by leaked-word count descending; users review the most
        # suspect keys first.
        leak_flags.sort(key=lambda x: -len(x[1]))
        print(f'  Top {min(LEAK_REPORT_LIMIT, len(leak_flags))} leak keys:')
        for key, words in leak_flags[:LEAK_REPORT_LIMIT]:
            sample = ', '.join(sorted(words)[:5])
            print(f'   • {key}  →  {sample}')

    return len(length_flags) + len(leak_flags) + len(missing_keys)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--langs', nargs='*', help='Locale codes to check')
    parser.add_argument('--verbose', action='store_true')
    parser.add_argument(
        '--arb-dir',
        default=str(Path(__file__).resolve().parent.parent / 'lib' / 'l10n'),
        help='Directory containing app_*.arb',
    )
    args = parser.parse_args()

    arb_dir = Path(args.arb_dir)
    en_file = arb_dir / 'app_en.arb'
    if not en_file.exists():
        print(f'app_en.arb not found at {en_file}', file=sys.stderr)
        return 1
    en = load_arb(en_file)
    print(f'EN source: {len(en)} keys')

    if args.langs:
        targets = args.langs
    else:
        targets = sorted(
            f.stem.removeprefix('app_')
            for f in arb_dir.glob('app_*.arb')
            if f.stem.removeprefix('app_') not in BASELINE_LOCALES | {'en'}
        )

    issues_total = 0
    for lang in targets:
        path = arb_dir / f'app_{lang}.arb'
        if not path.exists():
            print(f'  ✗ no file for {lang}', file=sys.stderr)
            continue
        target = load_arb(path)
        issues_total += check_locale(en, target, lang, args.verbose)

    print(f'\nTotal flagged issues across {len(targets)} locales: {issues_total}')
    return 0


if __name__ == '__main__':
    sys.exit(main())
