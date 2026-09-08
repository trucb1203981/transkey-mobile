---
date: 2026-09-07
type: fix
status: verified-with-follow-ups
---

# Improve mobile image correctness and saved-content reliability

## Request

Improve Android/iOS usability and long-term usefulness, especially image algorithms. Investigate API/model limitations and propose cost-conscious improvements.

## Root cause

Android downscaling returned only a filename, so ML Kit boxes stayed in resized coordinates while the overlay and DBNet used original dimensions. JPEG decode, resize, and encode also ran on the UI isolate, and the scratch directory survived each scan.

Gallery import discarded dense text detail at 1280px before the scene-aware stages. The adaptive threshold's window depended on image width, changing low-contrast decisions after a 90-degree rotation. Translation reuse accepted 85% similarity after stripping punctuation/symbols, allowing changed numbers and words to replay old translations. Automatic history trimming retained locks but dropped older favorites.

Real Android testing also exposed a camera lifecycle race: gallery teardown disposed the controller before the still-mounted CameraPreview listener stopped rebuilding. The screen now renders a placeholder for one frame before teardown, and background disposal yields to an active picker transition.

## Changes

- `lib/core/camera/ocr_image_preparation.dart:8`: isolated image preparation, EXIF normalization, exact per-axis source transforms, scratch ownership, scene-specific limits.
- `lib/core/camera/camera_service.dart:836`: one working coordinate system across OCR passes and DBNet, one source transform on output, and cleanup in `finally`.
- `lib/core/camera/adaptive_threshold.dart:8`: rotation-invariant local window and bounded-width integral storage with a wide fallback.
- `lib/features/translate/screens/camera_screen.dart:1923`: retain detail at import without changing vision upload caps.
- `lib/features/translate/services/translation_cache.dart:9`: exact content reuse after whitespace normalization, constant-time lookups, unchanged bounded LRU.
- `lib/features/history/storage/history_store.dart:112`: preserve favorites and locks during automatic trimming.
- New deterministic tests and `integration_test/image_quality_test.dart` cover native OCR without a paid provider call.
- Gallery handoff detaches CameraPreview before controller disposal and restores the preview after cancellation.

## Verification

- Baseline and final full Flutter analysis: pass.
- Image-change Flutter suite: 109 passed, one pre-existing smoke test skipped. Final combined checkout suite: 112 passed, one skipped; the additional three metadata tests belong to concurrent work.
- Six threshold cases replayed against the previous implementation: two low-contrast rotation cases failed and four controls passed. All six pass with the new algorithm. The baseline copy lived in a task-owned scratch directory and was removed afterward.
- Android native OCR on the connected Xiaomi device: three reference cases pass on the final algorithm, with text and source-coordinate assertions. Menu 3000x2200: 2661ms; rotated document 1800x3000 with multiple passes: 11456ms; small sign 1000x700: 252ms. Single runs are not a latency distribution or evidence of a significant speedup.
- Native test APK was built in release mode, installed with replacement, and run directly. `QUALITY_SUITE passed=true tests=3` captures the Dart binding result. Native integration-test reporting is excluded from release builds and emits a warning; instrumentation/Flutter-driver success is not claimed.
- Final Android production release build: pass, 95.8MB APK; installed in place with data preserved. Final iOS simulator build: pass (x86_64 due native plugin support); no physical iPhone available.
- Production Android gallery: two synthetic menus differing by price complete with separate pages and source prices 15/19 retained. Four user Record images also complete through the real picker and network translation; completion does not mean their semantic/layout quality passes.
- Record Japanese manga route: 30 native characters triggers Vision, 12 blocks returned in 6638ms. French comic: native route accepts 6 blocks / 713 characters. Visual inspection finds fragmented Japanese dialogue, merged French panels, uncovered text, and overlapping dense-menu cards. These remain open follow-ups, not claimed fixed by the coordinate or threshold changes.
- Gallery controller race was captured before the handoff change (PID 9835). Final release (PID 17985): open picker, cancel, observe initialized preview, reopen, select synthetic menu, and observe translated result. Two initializations and two releases, zero exception/error log matches. The three-minute background timer guard was source-checked, not timed on device.

## Real-image evidence

The source paths and observations are listed in `docs/mobile-quality-recommendations-2026-09-07.md`. Originals under `/Users/trucnguyen/Desktop/Record` remain untouched. Only task-created copies were placed on Android. Screenshots and diagnostic logs are local temporary evidence, not committed user image assets:

- `/tmp/transkey-quality-realmenu-result.png`: Japanese-language menu from the Korean-menu folder, first batch page.
- `/tmp/transkey-quality-realmenu-page2.png`: dense Japanese restaurant menu, second batch page.
- `/tmp/transkey-quality-manga-result.png`: vertical Japanese manga after Vision escalation.
- `/tmp/transkey-quality-french-comic-result.png`: French comic accepted by the native route.
- `/tmp/transkey-quality-fixed-picker.png`: system picker after preview-detachment fix.
- `/tmp/transkey-quality-cancel-recovered.png`, `/tmp/transkey-quality-fixed-selection-result.png`: restored preview after cancel and successful translation after reopening the picker.
- `/tmp/transkey-quality-native.log`: native test assertions, route decisions, and before/after camera errors by process ID.
- `/tmp/transkey-quality-analyze-final.log`, `/tmp/transkey-quality-suite-final.log`, `/tmp/transkey-quality-android-final.log`, `/tmp/transkey-quality-ios-final.log`: successful final gates.

## API and cost

This task changed no backend source or provider configuration. Concurrent web changes and mobile language metadata edits were preserved and are not credited to this task. The accompanying recommendation document identifies geometry-sensitive OCR cache keys, non-atomic budget checks, stale cache reads, incomplete accounting of aborted provider attempts, and dish-only prompts dropping allergen notes. Static source line numbers may shift as concurrent work continues.

No higher-priced model was enabled. More exact client cache misses can increase translation requests; unchanged upload caps do not guarantee an unchanged total bill. Cost examples in the recommendation document are explicitly illustrative and cite current official pricing.

## Limits and follow-up

No iPhone is connected, so physical iOS camera, photo import, battery, and Apple Vision behavior remain unverified. Large multi-pass Android OCR remains slow; evaluate selective preprocessing on a labeled corpus before changing the fallback policy. Retention requires post-release D1/D7/D30 cohort measurements.

Cleanup completed: removed the six task-only Android media entries/files and scratch UI dump, restored the original charging sleep setting (0), and stopped the task-owned log capture. The normal release app remains installed with account data preserved. Desktop Record originals and unrelated mobile/backend edits were not changed by this task.

## Commits

Pending. No commit, push, release publication, or store deployment was requested or performed.

## Subsequent continuation

The region grouping and card-overflow follow-ups received a separate implementation and device verification in `.Codex/flows/2026-09-07-dialogue-regions-overlay.md`. Read that log for the latest 128-test result, six-card Japanese page, native paragraph fixes, three-image checks, and remaining semantic/coverage limitations. The observations above describe the first pass and are retained as baseline evidence.
