# Mobile quality improvement plan

## Scope and constraints

Improve repeat-use reliability on Android and iOS, prioritizing image processing and local correctness. Preserve existing API/model configuration and concurrent web changes. No release, account changes, or paid provider upgrades are part of implementation.

## Plan

1. [x] Trace capture/gallery, OCR coordinates, translation reuse, and saved history.
2. [x] Move Android image preparation off the UI isolate, restore original image coordinates, and clean temporary images on all exits.
3. [x] Preserve more gallery detail for dense scenes without raising vision upload caps.
4. [x] Prevent cached translations from masking changed source content; retain saved favorites during automatic history trimming.
5. [x] Add deterministic regressions, run full Flutter checks, build Android/iOS, and verify actual Android OCR and UI.
6. [x] Record API/model recommendations with cost assumptions and verification limitations.
7. [x] Verify the gallery handoff fix discovered during real-image testing: detach the preview before disposing its controller. Final release: open/cancel returns to initialized camera; reopen/select returns a translated menu; zero exception/error matches for the new process. The three-minute background timer guard was source-checked, not timed on device.

## Initial evidence

- `CameraService._writeDownscaled` decodes/resizes synchronously, returns only a path, and leaves its temporary directory behind. `recognizeText` returns resized coordinates although both screen callers display original dimensions. DBNet also compares original-image boxes with resized ML Kit boxes.
- Gallery picks cap non-manga images at 1280 before scene-aware OCR and upload processing, losing small-text detail permanently.
- `TranslationCache` removes punctuation/symbols and accepts 85% text similarity, so different amounts, negation, and CJK characters can reuse an unrelated translation.
- `HistoryStore` preserves locked entries beyond its 500-entry window but evicts ordinary favorites.
- Mobile checkout started clean. Web checkout contains unrelated pending API changes and is read-only for this task.
- Android device `e552d9b` is connected. Neither `devicectl` nor `idevice_id` reports an iPhone.

## Verification

Full analysis and 112 Flutter tests pass, with one pre-existing skipped smoke test. The last three tests belong to concurrent language-metadata work; they are not credited to this task. Three Android native reference images pass on the final image algorithms. Production UI processed two synthetic menus and four real Record images. Real dense menus and comics still expose semantic and region-layout defects, documented separately. Final Android release and iOS simulator builds pass. Physical iOS verification remains unavailable. Retention improvement requires production return-rate measurements; code and device checks alone cannot establish that users return more often.

## Algorithm follow-up

- Replaced the width-dependent adaptive threshold window with a short-axis window, preserving decisions when a rectangular image rotates 90 degrees.
- Replaced the generic integral array with bounded-width integer storage and retained a wide fallback for large inputs.
- Replayed six threshold cases against the original algorithm in an isolated scratch directory: four passed and the two low-contrast rotation cases failed. The new algorithm passes all six. The scratch copy was removed after comparison.

## Continuation: region grouping and readable overlays

1. [x] Capture native region geometry on the French and Japanese Record pages; separate detector, grouping, and layout errors.
2. [x] Correct over-grouping using source text geometry, with regressions for distinct neighboring bubbles and vertical text.
3. [x] Bound translated cards to available photo space, retaining complete text in the existing tap-through view.
4. [x] Run focused regressions and full analysis/tests; build Android/iOS and repeat real gallery checks on the same sources plus a menu control.
5. [x] Record before/after evidence, remaining semantic limitations, and cost impact without changing provider configuration.

### Continuation verification

Full analysis passes; 128 unit/widget tests pass with one pre-existing skip. Final Android release (95.9MB) and iOS simulator builds pass. Controlled native geometry probe: French 6 baseline blocks to 13 independent paragraphs; final gallery route has 16 blocks and remains semantically imperfect. Final Japanese gallery response: 12 model fragments to 6 cards, 3 text-repair candidates, 7585ms for the Vision/grouping/repair stage. Dense-menu control and complete-text tap recovery pass. Zero final-process error matches during the three-image checks. Physical iOS, general OCR accuracy, and return-rate improvements remain unverified.

See `.Codex/flows/2026-09-07-dialogue-regions-overlay.md` for evidence, added text-request cost, remaining coverage/script problems, and completed device cleanup. Source images and user data were preserved; no commit or publication was performed.

## Continuation: page script and missing dialogue

1. [x] Compare whole-page Latin/Japanese/Chinese native reads against region output on the French comic, Japanese manga, and dense menu.
2. [x] Use page evidence to prevent wrong-script crop selection and recover missing native paragraphs without blanket paid escalation. Add deterministic controls.
3. [x] Make the menu reading list discoverable and retain untranslated source notes. Verify complete text and source recovery.
4. [x] Honor the selected source language in all five camera text-batch requests. Run full analysis/tests, build Android/iOS, and inspect the same three images in the production Android gallery.
5. [x] Record measured changes, extra local work or API cost, remaining semantic limits, and cleanup.

### Page-script continuation verification

137 tests pass with one pre-existing skip; full analysis and Android release / iOS simulator builds pass. Controlled native French probe: 15 blocks, recovered bottom-right paragraph, no CJK leakage. Final French gallery: 17 blocks / 805 characters, one recovered paragraph; two tail paragraphs still echo source even with French selected and one manual retry. Final Japanese gallery: 12 fragments to six cards, three repair candidates. Dense menu: labeled List, 63 entries, original-only rows retained, complete tax/allergy footer readable. Device cleanup and original settings restoration completed; regular release remains installed. Physical iOS, broader OCR/semantic accuracy, cost deltas, and user retention remain unverified. See `.Codex/flows/2026-09-07-page-script-reading.md`.
