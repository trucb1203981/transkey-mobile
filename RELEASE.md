# TransKey Mobile - Release Runbook (Android + iOS)

How to ship a new version of the mobile app to Google Play and the Apple App Store.
iOS and Android release **independently** - they share `pubspec.yaml` but each store
has its own build number / versionCode and its own review.

---

## 0. Versioning (shared `pubspec.yaml`)

```yaml
version: 2.0.4+24
#        ^^^^^ ^^
#        |     build number (N) - internal, must always increase
#        marketing version (x.y.z) - what users see
```

- **Marketing version** (`x.y.z`): bump for features/fixes that users should notice.
- **Build number** (`+N`): **must be higher than every previous upload, on each store.**
  A build number / versionCode can **never be reused**, even for a build you discarded
  or a submission you cancelled. When in doubt, just increase it.
- `flutter build` bakes the **entire working tree, including uncommitted changes**, into
  the binary. Run `git status` before building so untested WIP does not ship.

---

## 1. Android (Google Play)

### Build
```bash
cd transkey-mobile
# bump pubspec version + build number first (see section 0)
flutter build appbundle --release
# output: build/app/outputs/bundle/release/app-release.aab
```
- Build an **AAB** (`appbundle`), not an APK - Play requires AAB.
- Signing is already configured; the 16 KB page-size fix
  (`packaging.jniLibs.useLegacyPackaging = false`) is already in
  `android/app/build.gradle.kts`.

### Upload + release
1. Google Play Console -> the app -> **Production** (or Internal/Closed testing first).
2. **Create new release** -> upload `app-release.aab`.
3. Write **release notes** for ALL store languages, each <= 500 chars, native-written,
   benefit-only, no jargon. Languages: en-US, ar, de-DE, fr-FR, id, ja-JP, ko-KR,
   pt-BR, vi.
4. Review -> Roll out.

### Android gotchas
- Bump `+N` before EVERY AAB upload. A **discarded draft still reserves** that
  versionCode forever.
- `INSTALL_FAILED` while testing locally: `adb uninstall app.transkey.mobile`.
- Verify a release APK/AAB signature with `apksigner` if needed.

---

## 2. iOS (Apple App Store)

### Build
```bash
cd transkey-mobile
# bump pubspec version + build number first (see section 0)
rm -rf build/ios && flutter build ipa --release
# output: build/ios/ipa/TransKey.ipa
```
- `rm -rf build/ios` first: incremental iOS builds can corrupt the code signature.
- The app icon **1024x1024 must be opaque (no alpha)** or upload fails with
  `Invalid large app icon ... alpha channel (409)`. To verify the icon inside the IPA:
  ```bash
  unzip -q build/ios/ipa/TransKey.ipa -d /tmp/ipacheck
  assetutil --info /tmp/ipacheck/Payload/Runner.app/Assets.car | grep -A2 marketing
  # want: "Opaque": true
  ```

### Upload
- Open **Transporter** (Mac App Store, free), sign in, drag `TransKey.ipa`, **Deliver**.
- The verbose Transporter debug log is normal. Success looks like
  `"errors":[]`, `"warnings":[]`, `state COMPLETE` - not an error.
- Alternative: Xcode -> Organizer -> Distribute App (handles signing for all 3 targets:
  Runner, TransKeyKeyboard, TransKeyShare).

### Create the version + submit (App Store Connect)
1. Wait ~5-15 min for the build to finish **Processing** in the **TestFlight** tab.
2. **Distribution** tab -> **+ (Version or Platform)** -> enter the marketing version
   (e.g. 2.0.4). The version number on this page **must match** the build's
   `CFBundleShortVersionString`, or the build will not appear in the selector.
3. Fill **What's New in This Version** (required for updates).
4. **Build** section -> select the new build.
5. **Add for Review** -> **Submit**.

### Carries over automatically on an UPDATE (do NOT redo)
App Privacy, Primary/Secondary Category, Age Rating, Pricing & Availability,
screenshots, description, keywords, and **already-approved in-app purchases**.

### In-app purchases / subscriptions
- The **first-ever** subscription/IAP must be attached to a version in its
  **In-App Purchases and Subscriptions** section and submitted **together with** that
  app version. It will not get reviewed on its own.
- After the first one is approved, new IAPs can be submitted standalone from the
  Subscriptions section.
- Each IAP needs a **Review Screenshot** or it shows "Missing Metadata" and blocks
  submission.
- Encryption: `Info.plist` has `ITSAppUsesNonExemptEncryption = false`, so App Store
  Connect auto-answers the export-compliance question - no document upload needed.

### iOS gotchas
- "CFBundleVersion already exists": bump `+N` and rebuild.
- Cancelling a review submission does **not** delete the uploaded build or any
  metadata; you can just re-submit using the same build.
- Demo/review account must stay logged-in-able for Apple's reviewer.

---

## 3. Quick checklist per release

- [ ] `git status` clean of unintended WIP
- [ ] `pubspec.yaml` version + build number bumped (higher than last upload)
- [ ] Build the right artifact (AAB for Play, IPA for App Store)
- [ ] Write release notes / "What's New"
- [ ] Upload, wait for processing
- [ ] Submit / roll out
- [ ] (iOS first-time only) attach IAPs to the version before submitting
