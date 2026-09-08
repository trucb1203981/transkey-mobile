---
date: 2026-09-08
type: fix
status: completed-with-known-limitations
---

# Android keyboard performance and complete layout audit

## Request
Audit all Android keyboard modes and fix discovered problems.

## Root causes and changes
- `android/app/src/main/kotlin/app/transkey/mobile/TelexProcessor.kt`: replaying every previous keystroke, including repeated prefix scans, caused sharply increasing work for long unbroken input. Reuse derived prefix state and retain at most 64 checkpoints at 32-key intervals. Backspace and typing-option changes derive from literal input, preserving prior output semantics.
- `android/app/src/main/kotlin/app/transkey/mobile/VietWordCorrector.kt`: correction repeatedly allocated distance rows and calculated diacritic/proximity costs inside every DP cell. Reuse request-local scratch rows, precompute substitution costs, restrict DP to the admissible diagonal band, and memoize repeated segments within one correction request. Request-local state preserves concurrent suggestion/commit safety.
- `android/app/src/main/kotlin/app/transkey/mobile/TransKeyIME.kt`: Chinese suggestions discarded stale results only after querying SQLite; they now skip obsolete queued work before querying and invalidate work when pinyin becomes empty. Chunjiin routed symbol-page input into its consonant composer and silently dropped digits/punctuation; it now limits that route to the letters layer.
- `android/app/src/main/kotlin/app/transkey/mobile/EmojiPanelView.kt`: the initial emoji panel allocated every TextView, causing a measured 158.86 ms frame. Replace the eager GridLayout with a recycling GridView, retaining category boundaries. On-device verification caught its inherited smooth position scroller stopping before the next category after padded cells; category tabs now use direct setSelection and pass live selection tests.
- Add native regression tests, physical-device component benchmarks, baseline parity checks, and a real-touch installed-IME matrix under `tools/keyboard-perf/`.

## Verified
- Physical device: Xiaomi 13 Lite, serial e552d9b, Android package app.transkey.mobile, selected IME app.transkey.mobile/.TransKeyIME.
- Component CPU median: Telex complete 600-key sequence 1896.19 -> 12.25 ms; Vietnamese correction nguoivietnam 97.17 -> 13.67 ms; 15-letter invalid token 122.03 -> 17.15 ms. These numbers do not describe per-key or touch-to-display latency.
- Native suite: 100 tests, zero failures/errors.
- Differential validation: 34536 output/state comparisons against independently compiled baseline classes, zero mismatches.
- Flutter analyze: no issues.
- Release build after the final category-navigation edit: success. APK SHA-256 2a394b6bb4f9a8564342ed2f9308416b11ec72850025dbca23d7c6b07432a47f.
- Installed final APK successfully on 2026-09-08 at 08:49:42 local time; version remains 2.5.0 (29).
- Original installed APK preserved at /tmp/transkey-keyboard-original-release.apk, SHA-256 fa4d77e577215b28e3dadfeece8f460889f749044f109d7ec16077b6db0885f0.
- Baseline live input passes all 18 modes. Baseline Chunjiin symbols failure reproduced and screens captured. Baseline emoji insertion/deletion and numeric field pass.

## Final live verification
- After the user unlocked the device, final run verified-release passed all 42 cases: 18 language modes and both symbol pages per mode, emoji insertion/deletion/category jumps, numeric input, 160-key burst, and held-delete cancellation. Inspected screenshot contact sheets confirm the entered text and each layout. All 160 burst characters are present, and deletion stops after release.
- Ordinary typing renders 1077 frames with 14 janky frames (1.30%), p95 9-16 ms by mode. The burst has one janky frame among 253, p95 13 ms and maximum 18.85 ms. Emoji category navigation inserts dog and apple and retains 32 attached cells.
- The final cold emoji opening has a 110.20 ms maximum frame, compared with the baseline's 158.86 ms. It remains one slow frame among three; this single paired sample is an improvement, not proof of zero jank or total input latency.
- Final test-window crash buffer is empty; retained runtime logs contain no fatal exception or app-specific ANR marker. Scope is this physical Xiaomi and TransKey's modes; other hardware, landscape, and sustained thermal/battery behavior remain unverified.

## Known limits and execution notes
- Full Android lint remains failed on five pre-existing errors in unchanged source/resources: ShareActivity NewApi, UseAppTint in transkey_ime_view, two MissingTranslation strings, and PermissionImpliesUnsupportedChromeOsHardware in the manifest. No lint severity or baseline was changed.
- Test host app app.transkey.keyboardperf is local-only and contains synthetic text. Selecting all languages through the normal picker adds them to the enabled language cycle; preferred typing mode is restored to Telex by successful full runs.
- Initial instrumentation was blocked by the locked device and an interrupted foreground host. No IME fix was inferred from Keyboard view missing. A fixed-delay emoji test was replaced by a bounded visibility assertion with screenshot/accessibility evidence; this confirmed the actual scrolling regression before the category fix.
- A release build failed when concurrent Flutter analyze dependency preparation rewrote GeneratedPluginRegistrant to include an unavailable integration_test class. Serializing analysis and build resolved it without editing generated code.

## Commits
- No commit or push requested or performed. Base HEAD f5be46e0207a0fa8dee1eea9433b4700f33ae04f.
- Preserve unrelated dirty Flutter camera, history, localization, and test work.

## Evidence
- Read docs/android-keyboard-performance-2026-09-08.md and tools/keyboard-perf/README.md for scope and reproduction. Results, raw frame statistics, and inspected contact sheets are retained under tools/keyboard-perf/results/.
- Full original device screenshots remain at /tmp/transkey-keyboard-verified-release/. Final local build, analyze, native-test/lint, installation, and runtime logs use the /tmp/transkey-keyboard- prefix.
