---
date: 2026-09-08
type: fix-and-verification
status: completed-with-quality-follow-ups
---

# Verify image quality improvements on physical iPhone

## Plan

1. [x] Build, verify signing, and replace the installed app without uninstalling or clearing its data.
2. [x] Drive real gallery flows for the French comic, Japanese manga, and dense menu; check retry and camera recovery behavior.
3. [x] Fix the clipped camera toolbar, run regression gates, and verify the installed final iPhone build.
4. [x] Record device evidence and limits, preserve user state, and stop task-owned tools.

## Baseline

The user requested continuation on iPhone after Android verification. The connected device is REMVN TEST, iOS 16.7.16, UDID 5a80bfa7ca9fd7d12272e80be40ffbdd339c3ad0. Pairing is valid, a Developer Disk Image is mounted, and TransKey 2.4.0 plus WebDriverAgent are installed. No WDA, iproxy, syslog, or competing mobile build process was running at preflight. Existing mobile changes are preserved; no API/model configuration changes or release publication are planned.

The previous simulator build was moved into a task-owned temporary directory before the clean physical release build. The bundled mobile-e2e workflow is adapted to avoid deleting an existing build or using broad process termination; signing identities are verified from the current keychain rather than a stale helper default.

## Evidence

Physical arm64 release build passes (129.2MB app, Xcode stage 74.5s). The build-selected development signer is present in the current keychain and included in the embedded profile. The profile includes this UDID and expires on July 13, 2027. The objective_c framework was re-signed with the same identity; the outer app was re-sealed with its existing entitlements. Deep strict verification passes. Installation completed at 100%, exit zero, without uninstalling or clearing data.

The first local packaging attempt used an ambiguous codesign optional-argument form and failed before creating an IPA; a subsequent install command therefore found no package and did not install anything. Using the explicit option=value form fixed certificate extraction. The actual packaging and successful installation were run as separately checked stages.

Initial build log: /tmp/transkey-iphone-build.log. Initial install log: /tmp/transkey-iphone-install.log. Task directory pointer: /tmp/transkey-iphone-workdir.txt. Source fixtures remain under /Users/trucnguyen/Desktop/Record. The initial iOS build required no source/configuration changes; the later toolbar fix is described below.

## Resolved setup blockers

WDA and the USB tunnel are operational. A session without an app can inspect and drive system Settings. TransKey launch is denied before its UI starts. Device SpringBoard diagnostics explicitly report `Profile Needs Network Validation` and `Requires Network Validation`; the native alert states that an Internet connection is required to verify the developer. Settings confirms Wi-Fi is not connected and the device has no SIM. The local signature/profile checks do not bypass this Apple verification requirement.

The user connected iPhone to Wi-Fi and launch succeeded. Camera was then gated by an expired/free account showing "Unlock Camera"; the user restored access themselves. No plan purchase, entitlement override, network credentials, or trust settings were changed by this task. Initial evidence: /tmp/transkey-iphone-settings-network.png, /tmp/transkey-iphone-settings-network-clear.png, /tmp/transkey-iphone-wifi.png, and launch-diagnostics.log in the task directory.

## Root cause and change

At 375 logical pixels, the original camera toolbar's unconstrained nested rows combined the intrinsic width of "Auto Detect", the target language, and four icons. The settings control extended past the right edge, leaving only 27 pixels visible. The new CameraToolbar gives the language pair flexible space, constrains long labels with full-label tooltips, keeps primary settings in the first row, and places optional flash/help controls in a second row on narrow or large-text layouts. Language controls have a 48-pixel minimum height. The sharpness hint follows the extra row.

Changed files: lib/features/translate/widgets/camera_toolbar.dart, lib/features/translate/screens/camera_screen.dart, and test/camera_toolbar_test.dart. Seven widget regressions check widths 320/375/430 at text scales 1/2, control bounds and taps, and the result toolbar without preview actions. The first test run exposed floating-point contact at a shared edge; the assertion now ignores 0.001-pixel rounding while still checking actual overlap. A stale comment belonging to the removed private language widget was removed after installation; this final comment-only cleanup changes no runtime behavior.

## Physical results

Device: iPhone X, iOS 16.7.16, 375x812 logical / 1125x2436 native pixels. The normal signed app was used, not an integration-test entrypoint.

| Flow | Observed result | Limit |
| --- | --- | --- |
| Gallery cancel | Native Photos picker opens and cancellation returns to active preview. | No physical shutter capture against a controlled subject was performed. |
| French comic, comic/img169.jpg | First page of a two-photo batch completes; page navigation works and the X1 negation is retained in this run. | Paragraphs still merge across panels, and the bottom-right sentence is split into multiple cards. This does not establish general semantic or geometry correctness. |
| Japanese manga, Manga/Screenshot_2026-06-02-19-19-18-444_com.android.chrome.jpg | Second page has seven visible cards, including a second sound-effect card compared with the six-card Android run. Tapping opens full source/translation; one explicit per-block retry replaces the chosen translation. | Successful replacement was tested physically; unchanged/failure/stale guards were covered by existing logic tests and prior Android checks. Different output does not establish better translation. |
| Dense Japanese menu, japan menu/2025_menu_kohoku_all_page-0001-1-scaled.jpg | Final toolbar build opens the native picker and completes the image. Apple Vision logs 113 lines in 3857ms and 85 retained menu items. List (85) opens, preserves source-only entries, and scrolls through the full tax/allergy footer. Full block details open. | Footer notes are original Japanese in this run, not translated. Quantity 4 is misread as 14 in the source OCR and remains 14 in Vietnamese. Several names and small overlay cards remain unreliable. More entries than Android's 63 is not an accuracy score. |
| Final toolbar and camera recovery | Settings and Camera tips open on the final 375-pixel build. Settings exposes its full 48-pixel width. Retake reinitializes the camera, and closing it logs AVCaptureSession release. Auto scene and English target are restored. | The user's existing AssistiveTouch bubble partially covers Help; the exposed edge remains tappable. Its position was preserved. No physical large-text setting was changed; large-text coverage is widget-level. |

The comic batch, successful retry, and picker-cancel checks used the first physical build. The menu, toolbar, retake, and final restoration used the final toolbar-fixed build; their OCR/retry implementation is identical. No full comic rerun was needed for the toolbar-only change.

Evidence screenshots under /tmp:

- transkey-iphone-access-ready.png: original clipped settings control.
- transkey-iphone-picker-cancel.png: camera preview restored after cancel.
- transkey-iphone-comics-ready.png and transkey-iphone-japanese-baseline.png: two-page results.
- transkey-iphone-block-detail.png and transkey-iphone-retry-result.png: full text and successful retry.
- transkey-iphone-final-camera-settings.png and transkey-iphone-final-camera-help.png: final controls open their sheets.
- transkey-iphone-menu-final-result.png, transkey-iphone-menu-list-top.png, and transkey-iphone-menu-list-end.png: 85-item list and original-only footer.
- transkey-iphone-menu-quantity.png: source OCR already contains 14.
- transkey-iphone-preview-restored.png and transkey-iphone-final-home.png: original language/scene restored and draft retained.

## Final gates and cleanup

- Flutter analysis: clean, including after the comment-only cleanup. Logs: /tmp/transkey-iphone-analyze.log and /tmp/transkey-iphone-final-analyze.log.
- Full unit/widget suite: 157 passed, one pre-existing skip. Log: /tmp/transkey-iphone-suite.log.
- Physical iOS release: 129.2MB, Xcode stage 78.8s; deep strict signing verification and in-place installation passed. Logs: /tmp/transkey-iphone-final-build.log and /tmp/transkey-iphone-final-install.log.
- Shared Android release: 95.9MB APK, build passed. Log: /tmp/transkey-iphone-shared-android-build.log. This toolbar revision was not reinstalled on Android in the iPhone pass.
- User draft "dược", account data, source Auto, target English, and scene Auto retained/restored. User-controlled Wi-Fi, entitlement, and AssistiveTouch settings were preserved.
- One task-owned menu copy was transferred through a tokenized local-LAN URL, saved once to Photos, and removed after checking the exact image and Today 02:44 timestamp. Recently Deleted was not emptied. Only the task's Safari tab was closed; other tabs and existing photos were preserved. Record originals were unchanged.
- Task-owned image server, WDA, USB tunnel, and syslog processes were stopped by exact verified PID. Build backups and diagnostic files remain in the task directory.
- No commit, push, deployment, API/model configuration change, or automatic extra OCR/translation requests were introduced by the toolbar fix.

## Open quality work

Keep OCR errors separate from translation errors. The menu quantity failure is already present in OCR, while the footer is recognized but remains untranslated. Prioritize measured local region re-reads for ambiguous numbers, panel-aware grouping for French comics, and API note-preservation/unresolved-status contracts before a broader model upgrade. Evaluate the same checked crops and transcripts on both platforms; do not infer accuracy from block count or one result.

This pass does not verify controlled shutter image quality, battery/thermal behavior over long sessions, offline recovery, or retention cohorts. The initial overly restrictive runtime log contains no useful OCR evidence; only the final syslog provides the menu timing and camera lifecycle facts above. Camera robustness and semantic quality still require broader evaluation.
