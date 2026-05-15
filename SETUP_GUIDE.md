# TransKey Mobile — Hướng dẫn cài đặt môi trường dev

## Tổng quan yêu cầu

| Component | Phiên bản | Cài qua |
|---|---|---|
| Flutter SDK | 3.41.9 (stable) | Homebrew |
| Android Studio | 2025.3.4 | Homebrew |
| Android SDK | 36 | sdkmanager |
| Java (JBR 21) | Bundled với Android Studio | — |
| CocoaPods | 1.16.2 | Homebrew |
| Xcode | 26.4.1 | App Store |

---

## Bước 1: Flutter SDK

```bash
brew install --cask flutter
flutter --version
# Flutter 3.41.9 • channel stable
```

## Bước 2: Android Studio

```bash
brew install --cask android-studio
```

Mở Android Studio lần đầu để hoàn tất setup wizard.

## Bước 3: Java (dùng JBR từ Android Studio)

Android Studio ships JBR 21 — không cần cài riêng JDK.

```bash
# Verify
/Applications/Android\ Studio.app/Contents/jbr/Contents/Home/bin/java -version
# openjdk version "21.0.10"
```

## Bước 4: Android SDK + Command-line Tools

```bash
# Cài command-line tools (có sdkmanager)
brew install --cask android-commandlinetools

# Tạo thư mục SDK
mkdir -p ~/Library/Android/sdk

# Move cmdline-tools vào SDK (Flutter cần cấu trúc này)
mkdir -p ~/Library/Android/sdk/cmdline-tools
mv /opt/homebrew/share/android-commandlinetools/cmdline-tools/latest \
   ~/Library/Android/sdk/cmdline-tools/

# Cài SDK 36 + build-tools + platform-tools
export JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home"
export ANDROID_SDK_ROOT="$HOME/Library/Android/sdk"
export PATH="$ANDROID_SDK_ROOT/cmdline-tools/latest/bin:$PATH"

sdkmanager --sdk_root="$ANDROID_SDK_ROOT" \
  "platforms;android-36" \
  "build-tools;36.0.0" \
  "platform-tools"

# Accept licenses
yes | sdkmanager --sdk_root="$ANDROID_SDK_ROOT" --licenses
yes | flutter doctor --android-licenses
```

## Bước 5: Config Flutter nhận Android

```bash
flutter config --android-sdk "$HOME/Library/Android/sdk"
flutter config --android-studio-dir "/Applications/Android Studio.app"
```

## Bước 6: CocoaPods (cho iOS)

```bash
brew install cocoapods
pod --version
# 1.16.2
```

## Bước 7: Xcode (cần thao tác thủ công)

> Không thể cài tự động vì cần sudo password + download ~8GB.

**Cách 1 — App Store:**
1. Mở App Store → tìm "Xcode" → Install
2. Sau khi cài xong, chạy trong terminal:
   ```bash
   sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer
   sudo xcodebuild -runFirstLaunch
   ```

**Cách 2 — xcodes (có Apple ID):**
```bash
brew install xcodes
xcodes install --latest
# Nhập Apple ID khi được hỏi
```

## Bước 8: Environment variables

Thêm vào `~/.zshrc`:

```bash
# Android / Flutter
export JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home"
export ANDROID_SDK_ROOT="$HOME/Library/Android/sdk"
export PATH="$ANDROID_SDK_ROOT/cmdline-tools/latest/bin:$ANDROID_SDK_ROOT/platform-tools:$PATH"
```

Reload:
```bash
source ~/.zshrc
```

## Bước 9: Verify

```bash
flutter doctor
```

Kết quả mong đợi:

```
[✓] Flutter (Channel stable, 3.41.9)
[✓] Android toolchain (Android SDK version 36.0.0)
[✓] Xcode (version 26.4.1)
[✓] Chrome
[✓] Connected device
[✓] Network resources
```

## Bước 10: Chạy project

```bash
cd transkey_mobile
flutter pub get
flutter run
```

---

## Troubleshooting

| Vấn đề | Fix |
|---|---|
| `sdkmanager: integer expression expected` | Warning vô hại, bỏ qua |
| `Unable to locate Java Runtime` | Đảm bảo `JAVA_HOME` trỏ đúng JBR path |
| `cmdline-tools component is missing` | Move cmdline-tools vào `$ANDROID_SDK_ROOT/cmdline-tools/latest/` |
| `Android license status unknown` | `yes \| flutter doctor --android-licenses` |
| CocoaPods warning UTF-8 | Thêm `export LANG=en_US.UTF-8` vào `~/.zshrc` |
| `Xcode installation incomplete` | Chưa cài Xcode full — xem Bước 7 |
