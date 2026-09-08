---
date: 2026-09-08
type: fix
status: targeted-device-verification-passed
---

# French comic fragments and redundant glyphs

## Plan
1. [x] Capture native crop and full-page evidence on img171 and img169.
2. [x] Reconcile overlapping reads and assemble supported adjacent fragments without deleting valid short dialogue.
3. [x] Run full analysis/tests/builds and normal iPhone gallery acceptance with Japanese control.

Preserve previous quantity and cross-panel fixes, dirty work, and user data. No API/model upgrade or commit. The cafe page has split UN / CAFE and isolated duplicated letters near otherwise recognized dialogue. Capture evidence before changing thresholds.


## Evidence and changes
- Physical iPhone crop/page capture on img171 returned 37 final blocks. Small duplicate fragments M/VOL/DEL/HE and ON/E occupied already recognized sentences; UN/CAFE and the four-line bottom sentence were separate cards.
- Added Latin dialogue reconciliation using existing full-page native evidence. Grouping requires text agreement and neighboring rows; overlapping paragraph anchors cannot join panels. Existing text is retained, with no model calls or text rewriting.
- Added measured native fixtures for img171 and img169 and six regression tests including independent panels, short text/numbers, unrelated text, and overlapping paragraphs.
- Full Flutter analysis: no issues. Full suite: 182 passed, 1 skipped. Normal iOS build and device acceptance pending.
- This structural fix does not guarantee perfect spelling in stylized lettering or remove every isolated drawing read. Those require evidence beyond paragraph membership; never delete all short/numeric reads.


## Second revision and release coordination
- First normal iPhone build: img171 has joined coffee, exact-response, and bottom four-line utterances; img169 retains separate left dialogue/caption/refusal. One unsupported mirrored-sign card MAZ remains, confirmed by original-text detail. A different Japanese control completes through the existing Vision fallback with nine visible cards; no native CJK accuracy claim.
- Second revision compares existing ML Kit/Vision short reads at matching positions. A conflicting orphan is dropped only with both engines present, no full-page support, no strong confidence, and no near-text agreement. Numeric-only reads remain. Added physical mirror-sign fixture regression and conservative short-read controls.
- Second gates: analysis clean, 184 tests passed with one existing skip; normal iOS build/sign/install and Android release build passed. Android APK SHA256: 939dec55f2ae5277009eed36b7601dd3750e155b19d2b0f0c0f8f75308fc6685.
- Keyboard/release task 01a07e76-362e-78a0-a93b-43f1842bc212 owns Xiaomi verification and release/version work. Camera task owns iPhone. Do not bump or claim camera ready until the final mirror-sign acceptance is recorded.
- Final iPhone UI acceptance is in progress. WDA sometimes turns taps into long presses; native photo context-menu Select successfully chooses images. A subsequent WDA request timed out, and only task-owned WDA/proxy/log processes were restarted. Normal production app remains installed, with user data intact.


## Android r2 acceptance failure
- Release task reports 21 native blocks / 860 characters on img171, including M/VOL, DEL/HE and ON/E fragments. Coffee detail contains only CAFE, losing UN. Do not classify iPhone fixture success as Android acceptance.
- Delegated temporary diagnostic-only ownership of camera_service.dart to the release task for page/pre-reconciliation/ML Kit/Vision JSON capture on img171 and img169. No concurrent edits or builds by the camera task until restoration is confirmed.
- iPhone WDA restart restored fast ordinary taps; final-r2 batch now contains img171, img169, and the original seven-card Japanese control.


## Third revision
- Exact iPhone gallery capture showed MAZ from ML Kit, VA2 from Vision, and dAA from page OCR. The second revision incorrectly accepted page geometry alone as corroboration; now page text must agree as well.
- Android groups individual crop-edge glyphs into multi-row fragments. Extend contained-fragment rejection to narrow groups of short alphabetic tokens, still requiring a substantial matching page/crop paragraph and preserving numbers.
- Recover short missing page rows only when an adjacent longer row in the same small utterance is independently supported by a crop. This restores Android UN above CAFE without replacing CAFE text or inserting isolated page specks.
- For trailing mixed letter/number artifacts such as G2 after EXACT, require the page row and the opposite native engine to agree on the clean prefix, with measured right-side geometric overflow. A code recognized by both engines or lacking independent evidence remains intact.
- Added original Android, recompressed iPhone gallery, and original-Android-panel fixtures/tests. Full suite: 188 passed / one existing skip. Full analysis clean after correcting three brace-style findings.
- Android r3 build passed, SHA256 30b8f7d4775b20ac751c01c7c93aeb5167f2bd331e8f5d2f422539ec14a5b237, handed to the release task for physical acceptance. iOS r3 build/sign passed, install in progress.
- Diagnostic source restored before normal builds. Five task-created app Documents files removed successfully. No user photo or setting was deleted.


## Fourth revision
- Physical Android r3 acceptance restored UN/CAFE and removed embedded glyph groups, but retained two LA SEULE SOLUTION crops and omitted MAIS OUI. The generic uncovered-page recovery requires eight characters, so it skipped this seven-letter utterance.
- Recover short multiword page phrases only inside a small detected speech shape with strong geometric coverage. Reconcile near-identical overlapping crops against page agreement, preserving different ordered numbers and using only retained candidates for subsequent containment checks.
- Full Flutter analysis clean; full suite 190 passed and one existing skip. Android and iOS normal release builds passed. APK SHA256 f84c1a8c03baa795c4043c165d5282ce50e6b2e8599d157eebce1773e46d712d. iOS normal r4 signature verification and installation passed. Final physical acceptance in progress.
- No extra recognition request, provider call, or model upgrade is introduced by reconciliation. Existing OCR spelling errors on img169 remain outside this structural fix.

## Physical Android r4 acceptance
- Xiaomi img171: 15 cards, native 15 blocks / 827 characters without Vision fallback. Source details confirm MAIS OUI, one LA SEULE SOLUTION, UN/CAFE, and EST BIEN/EXACT. Embedded M/VOL/DEL/HE/ON/E cards are absent. The pre-existing missing C apostrophe in EST BIEN is a character-recognition limitation, not a grouping claim.
- Evidence: /tmp/transkey-r4-cafe-final.png and /tmp/transkey-r4-cafe-{mais,solution,coffee,exact}.xml. Translation semantics remain variable; no perfect translation claim.
- iOS r4 is installed normally. Device screenshot proves XCTest is waiting for local passcode to enable UI Automation. User input requested; no passcode is collected.


## Final normal iPhone r4 acceptance
- User completed the local XCTest authentication. Restarting task-owned WDA restored ordinary input. The normal installed app processed a gallery batch of img171, img169, and the original Japanese control.
- img171 source sheets confirm UN/CAFE, CEST BIEN/EXACT, LA SEULE/SOLUTION, and the bottom four-row utterance each stay together. MAZ, G2, and embedded glyph-only cards are absent. There is one solution card. Evidence: /tmp/transkey-r4-ios-{coffee,exact,solution,bottom}.png and /tmp/transkey-r4-progress.png.
- The short MAIS utterance is present, but iOS still reads MAIS OU instead of MAIS OUI, causing BUT WHERE. This is a remaining character/semantic error; Android reads MAIS OUI. Other stylized spelling errors and clipped suffixes remain. Evidence: /tmp/transkey-r4-ios-mais.png.
- img169 left dialogue, Spirou caption, and refusal open independently with their own source text: /tmp/transkey-r4-ios-original-{left,caption,right}.png. Other isolated noise on this page remains outside the targeted cafe fix.
- Japanese control renders and opens the full right-hand dialogue: /tmp/transkey-r4-ios-japanese.png and /tmp/transkey-r4-ios-japanese-detail.png. This run shows eight overlays including sound effects, versus seven noted previously. Do not claim exact-count parity or perfect Japanese OCR; this change leaves the CJK path unchanged.
- Source Auto, target English, scene Auto, empty draft, light theme, and AssistiveTouch were preserved/restored. Retake and return home pass: /tmp/transkey-r4-ios-restored.png. Normal production r4 remains installed. No user image was added or deleted during final acceptance.
- Final gates remain /tmp/transkey-fragments-analyze4b.log (clean) and /tmp/transkey-fragments-suite4b.log (190 passed, one existing skip). No source changes after gates. Camera source frozen and handed to release task; no commit/version change by this task.
