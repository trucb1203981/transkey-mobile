# TransKey Mobile - Quy trinh phat hanh (Android + iOS)

Cach phat hanh phien ban moi cua app len Google Play va Apple App Store.
iOS va Android phat hanh **doc lap** - chung dung chung `pubspec.yaml` nhung moi cho
co build number / versionCode rieng va duyet rieng.

> Ban tieng Anh goc: [RELEASE.md](RELEASE.md)

---

## 0. Danh so version (chung trong `pubspec.yaml`)

```yaml
version: 2.0.4+24
#        ^^^^^ ^^
#        |     build number (N) - so noi bo, luon phai tang
#        marketing version (x.y.z) - so nguoi dung thay
```

- **Marketing version** (`x.y.z`): tang khi co tinh nang/sua loi dang ke voi nguoi dung.
- **Build number** (`+N`): **bat buoc cao hon moi lan upload truoc do, tren tung cho.**
  Build number / versionCode **khong bao gio duoc dung lai**, ke ca khi ban da huy build
  hay huy submission. Phan van thi cu tang len.
- `flutter build` goi **toan bo thu muc lam viec, gom ca thay doi chua commit**, vao file
  binary. Chay `git status` truoc khi build de code dang dang do khong bi phat hanh nham.

---

## 1. Android (Google Play)

### Build
```bash
cd transkey-mobile
# bump version + build number trong pubspec truoc (xem muc 0)
flutter build appbundle --release
# output: build/app/outputs/bundle/release/app-release.aab
```
- Build ra **AAB** (`appbundle`), khong phai APK - Play yeu cau AAB.
- Chu ky so da cau hinh san; fix 16 KB page-size
  (`packaging.jniLibs.useLegacyPackaging = false`) da co trong
  `android/app/build.gradle.kts`.

### Upload + phat hanh
1. Google Play Console -> chon app -> **Production** (hoac test Internal/Closed truoc).
2. **Create new release** -> upload `app-release.aab`.
3. Viet **release notes** cho TAT CA ngon ngu cua store, moi ban <= 500 ky tu, viet boi
   nguoi ban dia, chi noi loi ich, khong thuat ngu ky thuat. Ngon ngu: en-US, ar, de-DE,
   fr-FR, id, ja-JP, ko-KR, pt-BR, vi.
4. Review -> Roll out.

### Luu y Android
- Tang `+N` truoc MOI lan upload AAB. Mot **ban nhap da bo van giu cho** versionCode do
  vinh vien.
- `INSTALL_FAILED` khi test may that: `adb uninstall app.transkey.mobile`.
- Kiem tra chu ky cua APK/AAB release bang `apksigner` neu can.

---

## 2. iOS (Apple App Store)

### Build
```bash
cd transkey-mobile
# bump version + build number trong pubspec truoc (xem muc 0)
rm -rf build/ios && flutter build ipa --release
# output: build/ios/ipa/TransKey.ipa
```
- `rm -rf build/ios` truoc: build iOS theo kieu tang dan co the lam hong chu ky so.
- Icon **1024x1024 phai dac (khong co kenh alpha)** neu khong upload se loi
  `Invalid large app icon ... alpha channel (409)`. Kiem tra icon ben trong IPA:
  ```bash
  unzip -q build/ios/ipa/TransKey.ipa -d /tmp/ipacheck
  assetutil --info /tmp/ipacheck/Payload/Runner.app/Assets.car | grep -A2 marketing
  # can thay: "Opaque": true
  ```

### Upload
- Mo **Transporter** (Mac App Store, mien phi), dang nhap, keo `TransKey.ipa` vao, bam
  **Deliver**.
- Cai log debug dai cua Transporter la binh thuong. Thanh cong trong giong nhu
  `"errors":[]`, `"warnings":[]`, `state COMPLETE` - khong phai loi.
- Cach khac: Xcode -> Organizer -> Distribute App (tu lo chu ky cho ca 3 target:
  Runner, TransKeyKeyboard, TransKeyShare).

### Tao version + submit (App Store Connect)
1. Cho ~5-15 phut cho build xong **Processing** o tab **TestFlight**.
2. Tab **Distribution** -> **+ (Version or Platform)** -> nhap marketing version
   (vi du 2.0.4). So version o trang nay **phai khop** voi `CFBundleShortVersionString`
   cua build, neu khong build se khong hien ra de chon.
3. Dien **What's New in This Version** (bat buoc voi ban update).
4. Muc **Build** -> chon build moi.
5. **Add for Review** -> **Submit**.

### Tu ke thua khi UPDATE (KHONG phai lam lai)
App Privacy, Category (chinh/phu), Age Rating, Pricing & Availability, anh chup man hinh,
mo ta, keywords, va **cac goi IAP da duoc duyet**.

### In-app purchase / subscription
- Goi IAP/subscription **dau tien** phai duoc gan vao mot version o muc
  **In-App Purchases and Subscriptions** va submit **chung voi** version do. No khong tu
  duoc duyet rieng.
- Sau khi goi dau tien duoc duyet, cac goi moi co the submit rieng tu muc Subscriptions.
- Moi goi can mot **Review Screenshot**, thieu se bao "Missing Metadata" va chan submit.
- Ma hoa: `Info.plist` da co `ITSAppUsesNonExemptEncryption = false`, nen App Store
  Connect tu tra loi cau hoi export-compliance - khong can upload tai lieu.

### Luu y iOS
- "CFBundleVersion already exists": tang `+N` roi build lai.
- Huy mot submission **khong** xoa build da upload hay metadata; cu submit lai bang chinh
  build do.
- Tai khoan demo/review phai luon dang nhap duoc de nguoi duyet cua Apple test.

---

## 3. Checklist nhanh moi lan phat hanh

- [ ] `git status` sach, khong dinh WIP ngoai y muon
- [ ] `pubspec.yaml` da bump version + build number (cao hon lan upload truoc)
- [ ] Build dung loai (AAB cho Play, IPA cho App Store)
- [ ] Viet release notes / "What's New"
- [ ] Upload, cho xu ly (processing)
- [ ] Submit / roll out
- [ ] (iOS lan dau) gan IAP vao version truoc khi submit
