---
date: 2026-09-07
type: fix
status: verified-with-limits
---

# Preserve dialogue geometry and keep translated cards readable

## Request

Continue Android/iOS quality improvements using the user's menu and comic images in Desktop/Record. Prioritize image algorithms and weigh additional API cost.

## Root cause

The native region deduplicator never compared text. It connected overlapping reads transitively and paired the longest text with the smallest rectangle, even when they came from different native reads. A full French paragraph consequently inherited a 230x50 fragment rectangle. Latin OCR crops could also contain several native paragraphs, which were flattened into one source block.

Vision could return one block per word or vertical fragment. The old balloon snap assigned each shape once, so the first word occupied a whole balloon while later words remained separate. Estimated model coordinates could place a name over artwork. Overlay duplicate suppression used rendered card overlap, which is not evidence of repeated source content. Cards could grow beyond nearby rows and the photo.

## Changes

- `lib/core/camera/ocr_region_matching.dart`: deduplicate only overlapping reads with matching substantial content. Preserve different digit sequences and short dialogue. Direct comparisons avoid transitive chains.
- `lib/core/camera/camera_service.dart:1759`: retain independent Latin native paragraphs, map crop coordinates through scale and crop origin, clip to the source image, and keep text/geometry/metadata from the same selected read. Apple Vision winners remain intact.
- `lib/core/camera/vision_dialogue_geometry.dart`: group fragments sharing a bounded detected balloon; optionally join nearby vertical CJK fragments without joining separate detected balloons. Keep the union of text boxes rather than expanding into artwork. Match substantial, unique native text anchors conservatively; repeated, short, or differing content cannot relocate a model box.
- `lib/features/translate/screens/camera_screen.dart:2692`: apply grouping to the gallery manga Vision path. Translate only newly grouped dialogue in existing 15-item text batches; preserve earlier fragment translations on repair failure. Cache lookups use captured language/scene parameters. Normal menu/sign Vision blocks remain separate.
- `lib/features/translate/widgets/overlay_card_bounds.dart` and `camera_result_overlay.dart:1066`: reserve source-centered cells for automatic card placement, constrain text to available height, show ellipses when needed, and retain the complete source/translation in the existing tap action sheet. Duplicate suppression compares source reads rather than displayed card size. Manual dragging remains available.
- Six new dialogue geometry cases plus paragraph, overlap, dense-row, large-font, and full-text tap regressions. Existing tests that required mixing text and boxes from different reads were corrected.

## Verification

- Full Flutter analysis: pass. Final unit/widget suite: 128 passed, one pre-existing smoke test skipped. The suite includes concurrent language-metadata work, which is not attributed to this task.
- Android release build: pass, 95.9MB APK. Installed in place with existing account and draft preserved. Final regular app process: 32212.
- iOS simulator build: pass. Native ML Kit dependencies exclude arm64 simulator support, so this verifies x86_64 compilation. No connected iPhone, no claim of physical iOS camera/OCR acceptance.
- Controlled native probe on the same French file: baseline 6 blocks; matching-content dedup 8; independent paragraph mapping 13. Japanese native output remained 4 blocks. These are counts, not labeled recall or accuracy scores. The probe invoked real Android OCR directly without a paid Vision request.
- Deterministic captured Japanese geometry: 13 model fragments become 6 dialogue groups. Neighboring balloons, long vertical regions, large white panels, and ambiguous anchors have regression controls.
- Final Android gallery: Japanese then French selected from the real system picker. Japanese native preflight yielded 30 characters and escalated. This API response contained 12 fragments, grouped into 6 cards with 3 repair candidates; the Vision-plus-grouping/repair stage logged 7585ms. The request's varying output differs from the earlier 13-fragment fixture, so the two counts are deliberately reported separately.
- Japanese visual result: one card for the multi-fragment right-hand dialogue, a complete "Tra loi di" dialogue, a lower name card inside its source balloon, and no overlapping automatic cards on this sample. Tapping the ellipsized acknowledgment opened the full translation and source.
- French final gallery route: 16 blocks / 742 characters, no full-page Vision call. Paragraphs use separate source regions, long cards stay inside available cells, and the full-text action sheet works. OCR errors, duplicate noisy reads, wrong script selections, and omitted dialogue remain visible. The controlled probe and gallery are different entry paths; do not equate their block counts.
- Dense Japanese menu control: real picker and translation completed. Automatic cards stayed within the photo; long heading showed an ellipsis and opened its complete translation/source on tap. Source prices remained visible in the photo. Numerous labels still have semantic errors and many require full-text taps; this does not establish ordering-grade menu accuracy.
- Final process log: zero matches for Exception, ERROR, RenderFlex, overflowed, failed, or DioError during the three-image checks. This is scoped log evidence, not a full native plugin-suite pass.

## Evidence

All source photos under Desktop/Record remain unchanged and outside Git. Local temporary evidence:

- `/tmp/transkey-region-native.log`: controlled native probes and production route logs, separated by process ID.
- `/tmp/transkey-region-final-paragraphs.json`: native paragraph probe output.
- `/tmp/transkey-region-final-process.log`: final production process only.
- `/tmp/transkey-region-final-japanese.png`, `/tmp/transkey-region-final-japanese-fulltext.png`: grouped dialogue and full-text tap.
- `/tmp/transkey-region-final-french.png`, `/tmp/transkey-region-french-fulltext.png`: final paragraph layout and pre-final full-text action sheet (same bounded renderer).
- `/tmp/transkey-region-final-menu.png`, `/tmp/transkey-region-final-menu-fulltext.png`: dense-menu control and full heading.
- `/tmp/transkey-region-analyze-final.log`, `/tmp/transkey-region-suite-final.log`, `/tmp/transkey-region-android-final.log`, `/tmp/transkey-region-ios-final.log`: final gates.

## Cost and limits

No provider/model configuration or backend source changed in this task. Local geometry and card layout require no extra provider calls. Fragmented manga dialogue can add text translation requests and consume additional quota; each request contains at most the existing 15 items and no image. The final Japanese page had only 3 grouped repair candidates, fitting one text batch. No production billing measurement or cost-neutrality claim is made. Failed repairs retain already translated fragments.

Grouping preserves API order within a balloon; it does not prove reading order for arbitrary multi-column Japanese pages. Exact native anchors help only when both engines agree on a unique substantial text. Fuzzy matching anchors would risk moving repeated dialogue to a different character and is intentionally excluded. A full glyph/coverage benchmark, selective Latin crop recovery, dense-menu reading-mode improvements, direct-shutter Vision grouping parity, physical iOS checks, and retention cohorts remain follow-ups.

## Cleanup and commits

Removed the three task-owned Android media rows/files, their empty directory, and the scratch UI dump. Restored the original charging sleep setting to 0 and stopped only the task-owned log capture. The normal release app remains installed at home with the existing draft preserved. Concurrent code was not reverted. No commit, push, release publication, or store deployment was requested or performed.
