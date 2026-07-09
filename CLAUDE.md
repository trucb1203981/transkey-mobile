# transkey-mobile (Flutter + native Kotlin)

## Build & verify
- Verify: `flutter analyze`
- Build+install: `flutter build apk --release` → `adb -s e552d9b install -r build/app/outputs/flutter-apk/app-release.apk` (different device → `adb devices`)
- Build success ≠ exit code when piped: `flutter build … | tail` (esp. run in background) reports the TAIL's exit (0) even when the build FAILED — confirm by `✓ Built` in the log OR the APK file actually existing, never the task/pipe exit code (bit me repeatedly 2026-07-08).
- After a UI change + install: self-review BEFORE handing to user — foreground the app with `adb -s e552d9b shell am start -n app.transkey.mobile/.MainActivity` (NOT `monkey -c LAUNCHER` — it can silently no-op and leave whatever app the user had open, so you screenshot the wrong app — happened 2026-07-08), then `~/Management/projects/translate/.claude/hooks/adb-screenshot.sh` (prints PNG path) → Read the image to catch crashes / broken layout / blank screen
- On-device keyboard testing: reuse the saved coord map `.claude/keyboard-ondevice-test-map.md` (Keep clean-note flow + key centers + lang-switch + candidate-feature checks) so no re-dumping the UI each time
- i18n: add a new key to ALL 14 `lib/l10n/app_*.arb` files, then `flutter pub get` to regen (a missing locale = broken fallback)

Patterns: `~/.claude-dev-memory/transkey/patterns-mobile.md` (Dart) + `patterns-android.md` (native Kotlin).
