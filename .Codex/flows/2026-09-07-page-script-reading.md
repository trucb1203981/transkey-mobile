---
date: 2026-09-07
type: fix
status: completed-with-limits
---

# Page script, missing dialogue, and menu reading access

## Root cause

Crop scoring could prefer isolated hallucinated CJK glyphs on a French page. Region detection omitted a substantial bottom-right paragraph that native whole-page Latin OCR could read. The menu list was icon-only and discarded source rows whose API translation was blank. All five camera text-batch requests omitted sourceLang although the UI and cache already tracked it.

## Changes

- Select Latin from whole-page evidence before crop OCR; retain the existing CJK path when evidence is insufficient.
- Recover substantial native Latin paragraphs outside the union of accepted source regions, preserving native geometry and avoiding duplicate coverage.
- Expose a labeled menu List action, complete readable/selectable text, original-only notes, source explanations, and copy-all preservation.
- Forward selected sourceLang in gallery, per-region, dialogue-repair, progressive, and ordinary batch requests. Keep current provider configuration and retry count.
- Add seven page-evidence/coverage regressions and two reading-list regressions.

## Gates

Full Flutter analysis passes. Full unit/widget suite: 137 passed and one pre-existing skipped smoke test. The suite includes concurrent language-metadata changes not attributed to this task. Android release build passes (95.9MB); normal production target is installed in place. iOS simulator build passes, verifying x86_64 compilation because native ML Kit dependencies exclude arm64 simulator support. No physical iPhone is connected.

## Native evidence

The controlled pre-change raw recognizer comparison used the same French, Japanese manga, and Japanese menu files from Desktop/Record. French Latin: 13 blocks, 809 characters; Japanese-script: 15 blocks, 793 characters, seven CJK glyphs. Japanese manga and Japanese menu favored Japanese OCR. The fixed auto-script native probe returned 15 French blocks, recovered the bottom-right dialogue, and had no CJK leakage; the Japanese native control retained four blocks. One cold probe measured 4445ms French and 4170ms Japanese. These are diagnostic counts/timings, not a labeled accuracy benchmark or speed improvement.

The pre-final production Auto gallery route returned 17 French blocks / 805 characters with one recovered paragraph and no full-page Vision call. The recovered paragraph was visible but remained source French. One manual Auto retry still echoed the source. The final sourceLang-field change was then checked with French explicitly selected: the gallery again produced 17 blocks / 805 characters and the recovered bottom-right paragraph still echoed French. Correcting the request contract did not resolve this semantic failure. A manual retry of the recovered dialogue with French pinned still returned source text, with no caught request failure in the scoped Flutter log.

## Cost and limits

Auto-script adds two native whole-page reads on the region path; explicit Latin adds one. This consumes local time/energy. Recovered paragraphs can add text quota; no new Vision upload or automatic semantic retry was added. Existing dialogue-group repair from the prior pass can add one or more bounded text requests. No model upgrade, backend change, measured billing claim, or retention-rate claim is made.

Minority scripts, noisy French glyphs, dense menu semantics, context across translation chunks, and physical iOS remain evaluation targets.

## Evidence paths

- /tmp/transkey-page-native.log: raw OCR probes and device logs, separated by PID.
- /tmp/transkey-page-baseline.json and /tmp/transkey-page-fixed.json: diagnostic native output.
- /tmp/transkey-page-french-result.png: pre-final Auto gallery source-only recovered dialogue.
- /tmp/transkey-source-{analyze,suite,android,ios}.log: final checks and builds.
- /tmp/transkey-source-final-process.log: final production Flutter log only.
- /tmp/transkey-source-french-result.png and /tmp/transkey-source-french-retry.png: French selection and unchanged source echo.
- /tmp/transkey-source-japanese-result.png: final Japanese dialogue grouping.
- /tmp/transkey-source-menu-result.png, /tmp/transkey-source-menu-list.png, and /tmp/transkey-source-menu-list-footer.png: list entry, original-only rows, and complete footer.
- /tmp/transkey-source-final-home.png: restored Auto language and existing draft.

## Final device verification and cleanup

Final French gallery and manual retry were visually inspected. Final Japanese gallery with source restored to Auto produced 12 Vision fragments grouped into six cards, with three text-repair candidates and 7372ms for Vision/grouping/repair. The right dialogue remains grouped and the lower name card remains inside its source balloon. The native page selector did not force Latin on the Japanese control. Final dense menu: the labeled List action opened 63 entries. Two swipes reached the complete tax/allergy footer. Original-only headings and omitted rows were visible with the Original label; the full translated note and Japanese source were readable. Copy content and narrow/large-font layout were verified by deterministic tests, without changing the device clipboard. Menu OCR noise and semantic errors remain. Final process 18419 had 41 scoped Flutter log lines and 0 error-pattern matches. This is not a full native plugin log audit.

Removed the three task-owned Android media rows/files and verified no matching rows remain, then removed their empty directory and scratch UI dump. Restored charging sleep to the saved value 0. Restored source language Auto, returned to app home, and visually confirmed the existing innovation draft. Stopped only the task-owned log capture after confirming its output file. The normal production release remains installed. All original Record images remain unchanged and outside Git. Source files and existing app account/draft are preserved. No commit, push, release, or store publication was requested.
