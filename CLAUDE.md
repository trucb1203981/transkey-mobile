# transkey-mobile (Flutter + native Kotlin)

## Build & verify
- Verify: `flutter analyze`
- Build+install: `flutter build apk --release` → `adb -s e552d9b install -r build/app/outputs/flutter-apk/app-release.apk` (different device → `adb devices`)
- After a UI change + install: self-review BEFORE handing to user — `/Users/trucnguyen/Documents/projects/translate/.claude/hooks/adb-screenshot.sh` (prints PNG path) → Read the image to catch crashes / broken layout / blank screen
- On-device keyboard testing: reuse the saved coord map `.claude/keyboard-ondevice-test-map.md` (Keep clean-note flow + key centers + lang-switch + candidate-feature checks) so no re-dumping the UI each time
- i18n: add a new key to ALL 14 `lib/l10n/app_*.arb` files, then `flutter pub get` to regen (a missing locale = broken fallback)

Patterns: `~/.claude-dev-memory/transkey/patterns-mobile.md` (Dart) + `patterns-android.md` (native Kotlin).
