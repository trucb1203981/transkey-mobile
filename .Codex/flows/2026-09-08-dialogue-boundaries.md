---
date: 2026-09-08
type: fix
status: verified-targeted
---

# Preserve independent comic dialogue

## Plan
1. [x] Capture physical region OCR and compare its line positions with the French and Japanese source pages.
2. [x] Preserve independent horizontal paragraphs when the Vision region candidate wins, without modifying recognized text or CJK ordering.
3. [x] Run focused and full checks, install the normal app, and verify multiple visible results.

## Scope
Continue the user-requested OCR repair. Preserve previous quantity improvements, dirty work, user data, and original Record images. No API/model upgrade or commit.

## Investigation
The ML Kit winner preserves Latin paragraphs, but the Apple Vision winner currently joins all lines in a detector crop. A crop may span neighboring panels. Capture actual line geometry before choosing replacement rules. Temporary diagnostic source will be restored immediately after its build.


## Confirmed root cause and implementation

The physical iPhone baseline returned one French block at [80,795,992,155] containing left-panel dialogue, the right-panel caption, and a separate balloon. Region 7 native output contains distinct lines for all three; the Vision winner discarded their independent geometry. The new horizontal row/paragraph grouping preserves these three groups using line-sized spacing and overlap checks, not accumulated paragraph height. Same-row fragments may slightly overlap due to OCR boxes. Tests retain every source index exactly once and preserve short final lines.

Only pages already classified as Latin use the new Vision paragraph output. Winner scoring and raw recognized strings are unchanged; the existing CJK reading-order branch remains unchanged. There are no additional OCR or model requests. The diagnostic install completed after several minutes; it was not interrupted. Its temporary source logging was restored before production edits.


## Focused verification

`test/fixtures/french_dialogue_region.json` records physical region 7, including slightly overlapping same-row fragments. `french_dialogue_native.json` records the earlier full-page native control. Six new tests cover both actual transcripts, growing paragraphs, interleaved columns, word gaps, and empty/degenerate boxes. Full analysis is clean; 176 tests pass with one pre-existing skip. The baseline diagnostic also completed the Japanese page (four native blocks before the app's existing model catch-up), with the same CJK path retained.

This change adds no direct OCR/model request. It changes the granularity of text submitted through the existing translation batch path; downstream chunk overhead is not assumed to be identical for every page. Physical normal-app acceptance remains pending.


## Final build and current verification boundary

Normal `lib/main.dart` release built (129.3MB, Xcode 82.3s), passed strict signing verification, and installed successfully. Android release build also passed (95.9MB). Five task-owned diagnostic app-container files were removed; no Photos copies or Safari tabs were created this turn. The existing home draft and Auto/English preferences remain intact.

Physical normal-app acceptance is currently blocked at the automation input boundary: repeated Camera taps show a tooltip rather than navigation; a native element click instead selected the draft. No app code or device settings were changed to work around this. The user was asked to tap Camera manually to discriminate device input from application navigation. See the task scratchpad `unstick-device-tap.md`. The installed normal app contains the final source changes and no diagnostic target. No commit or API deployment was made.

Task-owned WDA, USB forwarding, and logging processes were stopped while awaiting manual device confirmation.


## Resumed physical acceptance

The user requested continuation. The same normal app process resumed with light appearance and an empty draft already present before testing. After dismissing the keyboard, ordinary Camera taps and gallery selection worked. No device preference or application code change was required to restore input; the exact cause of the earlier automation behavior remains unconfirmed.

A three-image Comic gallery batch completed with Auto source and English target: the original French img169 page, the Japanese control, and another French cafe page from the existing library. On img169, the left dialogue, right-panel Spirou caption, and right-panel refusal now render and open as three independent source/translation cards. The left source ends in `D'UNE IMPASSE`; the caption contains only its own narration; the refusal contains `IMPOSSIBLE DE / VOUS AIDER`. Evidence: `/tmp/transkey-dialogue-batch-progress.png`, `/tmp/transkey-dialogue-left-detail.png`, `/tmp/transkey-dialogue-caption-detail.png`, `/tmp/transkey-dialogue-balloon-detail.png`.

The Japanese control retains seven visible cards, including two sound-effect cards. Its selected right-hand dialogue opens with complete Japanese source and English translation. Evidence: `/tmp/transkey-dialogue-japanese-result.png`, `/tmp/transkey-dialogue-japanese-detail.png`. The second French page completes and page navigation works, but several phrases remain fragmented and noise cards remain visible. Evidence: `/tmp/transkey-dialogue-second-french.png`. This is targeted acceptance of the cross-panel collapse correction, not general comic recognition or translation accuracy acceptance. There is no previous paired baseline for the second French page to attribute every observed fragment to this change.

No source code changed during this resumed UI verification, so the 176-test, analysis, and build gates above still apply. Fresh runtime logs contain no Flutter OCR diagnostics, so no new latency/provider-route claim is made from this run. No manual retry or explanation request was added. Source Auto, target English, scene Auto, and the current empty draft/light appearance were preserved on return to home. Task device tools were stopped; no new Photos copies or diagnostic app files were created.

## Remaining quality work

Prioritize distinguishing small valid utterances from OCR noise and reassembling adjacent fragments using balloon/panel evidence. The French cafe page's short coffee utterance is visibly split; isolated letters and numbers also create clutter. Capture paired native inputs before changing thresholds, and preserve valid one-letter or short utterances in controls. API note/semantic issues remain separate from this verified geometry correction.
