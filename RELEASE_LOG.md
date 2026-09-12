# TransKey Mobile - Release Log

What each version actually shipped, and where it went. This file is the HISTORY;
`RELEASE.md` is the RUNBOOK (how to ship).

**Read this before writing release notes for a new version.** It answers the two
questions that otherwise get guessed, and guessing them is what makes a new
version's notes repeat or contradict the previous one:

1. What did the previous version already tell users? New notes must not repeat it.
2. Did the previous version actually reach the store? If it never shipped, its
   content is still unannounced and the new notes must cover BOTH versions.

**Store status vocabulary - record what is known, never infer:**
`not submitted` | `uploaded` | `in review` | `live` | `rejected` | `unknown`

Android and iOS release independently, so each gets its own status line. Write
`unknown` rather than a guess, and update the entry when the status changes.
Building an artifact is NOT the same as uploading it, and uploading is NOT the
same as being live.

---

## 2.6.0+31 - 2026-09-12

- **Play:** not submitted. AAB `2.6.0(31)` built 2026-09-12 21:28 (93.1MB), verified `versionName 2.6.0` inside the bundle manifest.
- **App Store:** not submitted. Nothing uploaded to App Store Connect for this version; the local IPA build outcome is recorded by the follow-up docs commit.
- **Commits:** `d53dcd8..HEAD` (natural-voice read aloud + bump land in ONE commit; its sha is recorded by the follow-up docs commit)

Shipped in this version:
- Read aloud now uses natural online voices, with the device voice kept as the offline mode
- Voice and reading-speed picker per language, remembered per language
- The Android floating button reads aloud through the same voice engine as the app
- Clear localized messages when a language has no voice or playback fails

⚠ **Notes coverage differs per store this time.**
- **Play notes cover 2.6.0 ONLY.** They assume 2.5.1 reached users. 2.5.1's Play status is still
  `unknown` - if it never went live, the 2.5.0/2.5.1 items (guided setup, VNI, paste to translate)
  are still unannounced on Play and must be folded into the NEXT Play release.
- **App Store notes deliberately cover 2.5.0 + 2.5.1 + 2.6.0**, because neither 2.5.0 nor 2.5.1 was
  ever submitted to Apple. **Do NOT repeat guided setup, VNI or paste to translate in the next
  App Store release.**

en-US notes as published - Play (the other 8 locales mirror these bullets):
```
• Translations can now be read aloud in a natural-sounding voice
• Choose a natural online voice or an offline device voice, and set the speed
• The floating TransKey button reads text aloud in the same natural voice
• Point your camera at a menu to see dishes in your language
• Smoother performance and bug fixes
```

en-US notes as published - App Store (the other 13 locales mirror these bullets):
```
• Translations can now be read aloud in a natural-sounding voice
• A guided setup shows you exactly how to turn TransKey on
• A new way to type Vietnamese, with smarter word correction
• Paste text and translate it in one tap
• Faster keyboard, more accurate typing, and bug fixes
```

---

## 2.5.1+30 - 2026-09-08

- **Play:** unknown. AAB `2.5.1(30)` built 2026-09-08 10:27 (84MB), upload not confirmed in-session.
- **App Store:** not submitted. IPA build attempted twice on 2026-09-08, both runs killed before producing an artifact.
- **Commits:** `9595273..d53dcd8` (f5be46e, 1cd71c8, bump d53dcd8)

Shipped in this version:
- Keyboard performance improvements and camera text recovery
- Source language metadata accepted from all API features

⚠ **Notes coverage: the published notes for 2.5.1 deliberately cover BOTH 2.5.0 and 2.5.1**,
because 2.5.0's store status was never recorded and its features may never have been
announced to users. **Do NOT repeat the 2.5.0 items (guided setup, VNI, paste to translate)
in 2.5.2's notes.**

en-US notes as published (the other 8 Play / 13 App Store locales mirror these bullets):
```
• A guided setup now shows you exactly how to turn TransKey on
• A new way to type Vietnamese, with smarter word correction
• Paste text and translate it in one tap
• Point your camera at a menu to see dishes in your language
• Faster keyboard, more accurate typing, and bug fixes
```

---

## 2.5.0+29 - 2026-09-07

- **Play:** unknown (not recorded at the time)
- **App Store:** unknown (not recorded at the time)
- **Commits:** `03b15f8..9595273` (7e7219e, b760672, e8ae1d3, 6e34144, 9da02f4, e3d63cb, bump 9595273)

Shipped in this version:
- Guided setup hub walking a new user through enabling the TransKey button and the keyboard
- VNI Vietnamese input mode, shown as "Tiếng Việt (VNI)" in the language picker
- Vietnamese word correction and touch-bias key targeting
- Paste action in the keyboard, and paste-and-translate in the app
- Google Play Billing Library 8.3.0 via purchases_flutter 10.x
- Separate Dịch/Trả lời language pair on Android, matching iOS
- Device name sent to the server for admin device management

Release notes: none recorded. This is the gap that created the 2.5.1 overlap above.

---

## Before 2.5.0

Not logged. This file was created on 2026-09-08, so earlier versions have no
recorded store status or notes. Reconstruct from
`git log --grep="bump version"` and from the auto-memory entries
`project_ios_rejection_2026_06_18` (2.0.3+23 was rejected on 5 guidelines) and
`project_ios_audit_fixes_2026_07_10` (2.4.0+27 built, not pushed) if you need it.

Known bump history: 2.4.0+27 (2026-07-10), 2.3.0+26 (2026-07-09), 2.0.2+22 (2026-06-03).
