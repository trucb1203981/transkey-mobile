# Android keyboard performance audit

## Scope
- Audit all 18 input modes, symbols, numeric fields, emoji, suggestions, mode changes, and input lifecycle.
- Preserve unrelated in-progress Flutter camera, history, localization, and test changes.
- Device: Xiaomi 13 Lite, adb serial e552d9b. Installed app initially reports 2.5.0 (29).

## Plan
1. [complete] Trace key handling and measure the current implementation on the device.
2. [complete] Optimize Telex prefix replay, Vietnamese correction, stale Chinese suggestion queries, and emoji creation; repair Chunjiin symbols.
3. [complete] Run native tests, build and install the release, verify the complete physical-device matrix, and compare measurements. Remaining limitations are listed below.

## Evidence
- The device is authorized and the selected IME is app.transkey.mobile/.TransKeyIME.
- Input modes: EN, VI, VI_VNI, DE, ES, FR, ID, IT, PT, RU, RU_PHON, AR, TH, KO, KO_CHUN, JA, JA_FLICK, ZH.
- No nested AGENTS.md exists in the mobile tree. The optional transkey development-memory shards are absent.
- Physical-device ART benchmark: Telex 600-key run 1896.19 ms -> 12.25 ms median; Vietnamese correction for nguoivietnam 97.17 ms -> 13.67 ms. These are component CPU measurements, not end-to-end touch latency.
- Full native unit suite: 100 tests, no failures/errors.
- Baseline differential verification: 34536 matching Telex prefix/deletion/literal states and Vietnamese correction/suggestion results.
- Full Flutter analyze: no issues. Final release APK: build/app/outputs/flutter-apk/app-release.apk. Build and analyze were run sequentially to avoid generated plugin-registration changes during compilation.
- Full Android lint reports five pre-existing errors: ShareActivity NewApi, transkey_ime_view UseAppTint, two MissingTranslation labels, and missing optional camera hardware declaration. None of those files is changed by this task.
- Baseline installed-IME UI run passes EN, VI, VI_VNI, ZH, ES, FR, AR, PT, RU, RU_PHON, ID, DE, JA. Initial flick test exposed a test-driver issue: clipped picker rows were tapped behind the bottom bar. The driver now uses accessibility click for picker selection and real pointer events for all typing. Flick returns to the language picker through symbols because its own layout has no globe key.
- Test host app app.transkey.keyboardperf contains local-only synthetic text fields. UI screenshots and per-mode framestats are saved in its external files directory and pulled to /tmp.
- The corrected baseline tail passes JA_FLICK, KO, KO_CHUN, IT, and TH text input. Both symbol pages fail specifically in KO_CHUN: the character handler unconditionally routed digits/punctuation to the consonant-group composer. It now restricts that route to the letters layer.
- Baseline first emoji opening: 150 ms histogram bucket, one slow frame among three frames. The old panel eagerly allocated all emoji TextViews. The replacement uses GridView recycling, preserves padded category boundaries, and scrolls to adapter positions.
- Original installed release APK backed up at /tmp/transkey-keyboard-original-release.apk. The final build is deliberately rerun after the emoji edit so its class files match the source.
- Final release APK includes the emoji category-navigation repair and was installed successfully at 2026-09-08 08:49:42. SHA-256: 2a394b6bb4f9a8564342ed2f9308416b11ec72850025dbca23d7c6b07432a47f.
- Final installed run verified-release: 42/42 cases pass. All 18 modes and their 18 symbol checks pass, plus emoji insertion/deletion/category navigation, numeric fields, 160-key burst typing, and held-delete cancellation. Screenshots inspected for every mode and auxiliary flow.
- Emoji category verification exposed the inherited GridView position scroller stopping before the target row after disabled padding. A four-second wait and captured accessibility tree confirmed this was not just a test timing issue. Category tabs now switch directly with setSelection. Animals and food both display and insert the expected emoji; only 32 grid cells are attached.
- Ordinary typing: 14 janky frames among 1077 rendered frames (1.30%), with per-mode p95 9-16 ms. The 160-key burst preserves every character: 253 rendered frames, one janky frame, p95 13 ms, maximum 18.85 ms. Held delete removes eight characters and remains stable after release.
- First emoji opening: maximum frame 158.86 ms before, 110.20 ms after in the final installed run, about 31% lower. It still has one slow frame among three opening frames. This is a single paired observation, not a statistical cold-start guarantee or evidence that all jank is eliminated.
- Crash buffer is empty and retained runtime logs contain no fatal exception or app-specific ANR marker during the final installed test window.

## Retained results
- tools/keyboard-perf/results/installed-release.jsonl: all 42 assertions.
- tools/keyboard-perf/results/installed-frame-summary.json and installed-framestats/: per-mode rendering measurements and raw input-method frame data.
- tools/keyboard-perf/results/screenshots/: inspected contact sheets of text, layouts, symbols, and auxiliary cases. Full original screenshots: /tmp/transkey-keyboard-verified-release/.
- tools/keyboard-perf/results/baseline.jsonl and optimized-banded.jsonl: physical-device component CPU comparisons. baseline-emoji-gfx.txt retains the original cold-opening frame data.
- Reproduction instructions: tools/keyboard-perf/README.md. Root causes and verification history: .Codex/flows/2026-09-08-android-keyboard-performance.md.

## Verification limits
- Verified on this Xiaomi 13 Lite only. Other Android vendors, OS releases, landscape layouts, and prolonged thermal/battery behavior were not measured. This audit covers TransKey's 18 input modes, not third-party installed keyboards.
- First emoji opening still has a 110 ms frame; normal typing also retains occasional missed deadlines. No claim of zero jank or measured touch-to-display latency is made.
- Full Android lint still has the five existing errors noted above; no severity or baseline was weakened.
- The local-only test host app.transkey.keyboardperf remains installed. The language picker adds tested modes to the enabled cycle; the final preferred mode is Telex.
- No commit or push requested.
