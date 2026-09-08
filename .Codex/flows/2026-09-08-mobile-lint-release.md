---
date: 2026-09-08
type: fix
status: complete
---

# Mobile lint repair and combined release preparation

## Request and scope
Fix the five Android lint errors, extract reusable patterns, then bump the mobile version. The user subsequently expanded the release to include unfinished camera improvements before the version bump.

The camera task owned its source changes and physical iPhone verification. Its final source freeze preceded the version bump and release build; no concurrent camera edits entered the artifact.

## Root causes and changes
- ShareActivity: the API-33 overload was protected indirectly through a nullable flags value. Put argument construction and the call inside the explicit SDK branch so lint can prove compatibility; keep the legacy overload for older Android versions.
- TransKeyIME and transkey_ime_view.xml: XML tint triggered the AppCompat lint rule even though the IME explicitly uses a framework ImageButton. Set its native imageTintList during initialization and retain the existing view class and color.
- Localized Android string resources: the keyboard service and default-subtype labels were missing in 13 supported locales. Add both translations in each locale, preserving the existing labels' meaning.
- AndroidManifest: the camera permission implied mandatory camera hardware. Declare camera and autofocus optional because text translation is usable without them.

## Verification
- Full :app:lintDebug and :app:testDebugUnitTest completed successfully. Lint reports zero errors and 139 existing warnings; the native suite has 100 tests with zero failures/errors.
- No lint baseline, severity reduction, NewApi suppression, or missing-translation suppression was introduced. The changes preserve the API fallback, native paste-button widget, and supported locales.
- Final Flutter analysis is clean; 190 tests pass with one existing skip. Debug, Release, and Profile lint each report zero errors and 139 warnings. The combined r4 installed APK passes 42 keyboard cases, and the final AAB-derived APK additionally passes six keyboard checks and a camera gallery smoke check. Keep these artifact-specific results distinct.

## Pattern extraction
Eight requested upserts were written to /Users/trucnguyen/.codex/memories/extensions/ad_hoc/notes/20260908T091301-transkey-keyboard-pattern-sync.md. The current session permits memory edits only through update notes, so no canonical development-memory shard was modified directly.

The existing index and relevant store contents were checked before writing. The note specifies six Android keyboard patterns and two general build/compatibility patterns, their intended new shards, and corresponding index updates; task measurements remain in the keyboard flow log.

## Release status
After Android and iPhone camera acceptance, pubspec was bumped from 2.5.0+29 to 2.5.1+30. The normal lib/main.dart release AAB built successfully in 134 seconds and contains versionName 2.5.1 / versionCode 30.

The AAB is 88,308,691 bytes, SHA-256 1cac699f730283f4abe773b762d4601e756c49b4322032c922aeb8057670a27f, at build/app/outputs/bundle/release/app-release.aab. Bundle validation, manifest checks, and signature verification pass. The derived universal APK has the same signer as accepted r4, installs without data clearing, and reports 2.5.1 / 30 on the device. Bundletool required the installed SDK aapt2 path because its Gradle-cache JAR does not embed that executable; no app source workaround was made. Evidence: docs/verification/mobile-2.5.1+30/. English benefit-only notes: docs/releases/2.5.1+30.md.

## Android camera acceptance history
The camera owner supplied normal release r2, SHA-256 939dec55f2ae5277009eed36b7601dd3750e155b19d2b0f0c0f8f75308fc6685, copied to /tmp/transkey-camera-keyboard-combined-r2.apk. Installed it on Xiaomi without clearing data. Initial app state has Auto source and Vietnamese target; the existing draft and clipboard are preserved.

Physical img171 gallery input used Comic mode. Native routing returned 21 blocks / 860 characters without a vision-provider call. The rendered result still contains duplicate M/VOL, DEL/HE, ON/E and other fragments; the coffee card source is only CAFÉ.., missing UN. This does not meet Android acceptance. Evidence: /tmp/transkey-release-cafe-rendered.png, /tmp/transkey-release-cafe-now.xml, /tmp/transkey-release-cafe-detail.xml, and /tmp/transkey-camera-android-r2.log.

The camera owner granted temporary exclusive diagnostic access to camera_service.dart and paused edits/builds. A native-only probe embeds img171/img169, calls recognizePerRegion, and captures page paragraphs, pre-reconciliation reads, both engine outputs, dimensions, and boxes. No translation API or credentials are involved. Source backup: /tmp/transkey-camera-service-before-native-capture.dart, SHA-256 80976b7da15015f293fd0092fcb4a11ba9dd9b0a25e7bba7982be92df134abd0. Build log: /tmp/transkey-native-android-probe-build.log. The build wrapper restores the exact original source in finally and refuses to overwrite concurrent edits.

After capture, the normal r2 APK was restored and the two JSON files were delivered to the camera owner. The diagnostic target was never released. Two task-owned comic copies were kept temporarily under /sdcard/Pictures/transkey-release-20260908 for subsequent UI checks, then removed with their verified media rows after final AAB acceptance. Earlier task screenshot copies at the device root were also removed from the media store; local evidence remains preserved.

Native capture completed with no failures. JSON evidence is at /tmp/transkey-android-native-capture/native-fragments_cafe.jpg.json (1030x1600; 17 page paragraphs, 21 current/crop reads) and native-fragments_original.jpg.json (1078x1600; 13 page paragraphs, 15 current/crop reads). Android supplies no second-engine reads in this path. Delivered both files to the camera owner for the Android correction. The exact source was restored by hash before handoff, and normal r2 APK reinstallation succeeded; the diagnostic entrypoint is no longer installed.

### Third Android revision

Installed normal r3, SHA-256 30b8f7d4775b20ac751c01c7c93aeb5167f2bd331e8f5d2f422539ec14a5b237, from the preserved /tmp/transkey-camera-keyboard-combined-r3.apk. Gallery img171 now has 15 cards: isolated M/VOL, DEL/HE and ON/E fragments are gone, UN / CAFE is restored, and EST BIEN / EXACT appears in one card. Two overlapping LA SEULE SOLUTION reads still produce duplicate cards, and the page-supported MAIS OUI utterance has no overlay. Reported both to the camera owner before release acceptance.

Gallery img169 retains separate left dialogue, caption, and right dialogue. Opened each card to verify its source independently: 31 JOSA|S ... D'UNE IMPASSE, PIROU RACONTE PAR LE, and /HELASILMEST ... VOUS AIDER. The intended cross-panel separation passes, while character recognition errors and a duplicate right-side crop remain. Evidence: /tmp/transkey-r3-original-result.png and /tmp/transkey-r3-original-{left,caption,right}.xml. Do not claim complete text or translation accuracy.

### Fourth Android revision and final lint

Normal r4, SHA-256 f84c1a8c03baa795c4043c165d5282ce50e6b2e8599d157eebce1773e46d712d, passes the targeted img171 gallery acceptance: 15 cards / 827 native characters without a Vision request; MAIS OUI is restored, only one LA SEULE SOLUTION remains, UN / CAFE and EST BIEN / EXACT remain grouped, and isolated glyph fragments are absent. Opened all four source details to confirm recognition rather than inferring it from translations. Img169 again preserves the left dialogue, caption, and right dialogue separately. Ambiguous right-side crop duplication and recognition/translation errors remain conservative limitations. Retained evidence: docs/verification/mobile-camera-2026-09-08/.

Explicit :app:lintRelease and :app:lintProfile pass, each with zero errors and 139 warnings, matching the debug report. Log: /tmp/transkey-release-profile-lint.log. All 100 native tests pass. Camera owner reports full Flutter analysis clean and 190 tests passing with one existing skip. No build jobs remain from the release task.

Added four camera patterns through /Users/trucnguyen/.codex/memories/extensions/ad_hoc/notes/20260908T101500-transkey-camera-pattern-sync.md, bringing the requested extraction to 12 patterns. The user entered the device automation passcode directly on the iPhone, allowing final physical r4 acceptance before the version bump.

The combined r4 installed keyboard matrix passes 42/42 assertions across all 18 modes and auxiliary checks. The first instrumentation attempt stalled before opening its host and wrote no assertions; stopped only the task-owned test host, brought it to the foreground, and reran successfully. Do not count the empty first attempt as a passing run. Evidence: tools/keyboard-perf/results/combined-r4/. Ordinary typing rendered 1,076 frames with 13 janky frames; the burst retained all 160 characters, with 240 frames / two janky frames and p95 14ms. First emoji opening still has a slow frame (p95 117ms in this three-frame sample); the release does not eliminate every cold-opening delay.

## Final iPhone acceptance and cleanup

Normal iOS r4 gallery source details confirm grouped UN/CAFE and CEST BIEN/EXACT, one LA SEULE SOLUTION card, and grouped bottom dialogue. Mirror-sign MAZ, G2, and embedded glyph cards are absent. The short phrase remains recognized as MAIS OU rather than MAIS OUI on iOS, a documented character/translation limitation. Img169 left dialogue, caption, and refusal were opened separately. The same Japanese control completed with a full right-balloon source; eight overlays were visible versus seven in an earlier note, including an extra sound effect. This is a completed control flow, not exact-count parity or perfect Japanese recognition. Retained evidence: docs/verification/mobile-camera-2026-09-08/.

Android finishes on the normal 2.5.1+30 home screen with the prior draft, Auto source, Vietnamese target, and Auto camera scene. Verified task media IDs 1000013800 and 1000013801, their copies, and the task UI dump were removed. The camera owner restored iPhone home settings and stopped its owned automation/log processes. User photos, account data, and drafts were preserved.

## Commits

Source fixes, regression coverage, and r4 evidence: 1cd71c86e1d67cfdf6291bb94adc79cc332a1d71 (fix(mobile): improve keyboard performance and camera text recovery). Committed frame dumps trim trailing whitespace only; their measurement tokens are unchanged. The following version commit records pubspec, release notes, artifact checks, and this completed flow. No push or store upload was performed.
