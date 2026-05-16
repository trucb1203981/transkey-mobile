# TransKey Mobile — System Documentation

> Generated: 2026-05-16
> Scope: `transkey-mobile` (Flutter app for Android + iOS)
> Backend reference: see [`../SYSTEM_DOC.md`](../SYSTEM_DOC.md) for the NestJS API

---

## 1. Project Overview

**TransKey Mobile** is the phone-side companion to TransKey. It calls the same NestJS backend as the desktop app and adds three platform-specific entry points that let users translate without opening the main app:

- **Android floating bubble** — system-wide overlay (chathead-style) that reads clipboard and shows the result above any app.
- **Android share / PROCESS_TEXT** — appears in the system text-selection menu (Translate / Reply / Summarize / Explain / Refine).
- **iOS Share Extension + custom Keyboard** — `TransKeyShare` opens from the system share sheet; `TransKeyKeyboard` is a system keyboard with an inline Translate panel.

### High-level architecture

```
┌──────────────────────────────────────────────────────────────────┐
│                       transkey-mobile (Flutter)                  │
│                                                                  │
│  Main UI ─── Riverpod ── Dio (ApiClient) ──────────┐             │
│                                                    │             │
│  Android native:                                   │             │
│    BubbleService (overlay)   ─── MethodChannel ───▶│             │
│    ShareActivity (intent in) ─── MethodChannel ───▶│  /translate │
│    AccessibilityService ─── paste reply to focus   │  /summarize │
│                                                    ├─▶ /explain  │
│  iOS native (App Group: group.app.transkey):       │  /refine    │
│    TransKeyShare → APIClient.swift ──── direct ───▶│  /glossary  │
│    TransKeyKeyboard → APIClient.swift ── direct ──▶│  /features  │
│    AppGroupStore (token + deviceID + baseURL)      │  /usage     │
│                                                    │  /auth/*    │
└────────────────────────────────────────────────────┼─────────────┘
                                                     │
                                                     ▼
                                          transkey-web/api (NestJS)
```

### Key design decisions

- **Stack**: Flutter 3.2+ / Dart 3.x · Riverpod 2 (Notifier + AsyncNotifier) · GoRouter · Dio · flutter_secure_storage · shared_preferences.
- **Single Dio client** with 3 interceptors: headers (Authorization + `X-Device-ID` + `X-Platform: mobile`), JWT auto-refresh on 401, exponential-backoff retry on 408/429/5xx.
- **Token storage**: `flutter_secure_storage` (Android `EncryptedSharedPreferences`, iOS Keychain) with a SharedPreferences mirror as fallback — secure storage hangs on some MIUI/ColorOS/FuntouchOS skins; the 4-second timeout falls through to the mirror so login never freezes.
- **Device fingerprint**: SHA-256 of `identifierForVendor` (iOS) or `androidId + manufacturer + model` (Android), sent as `X-Device-ID`. Mirrored to SharedPreferences so a single secure-storage failure can't mint a new device ID and trip the Pro device limit.
- **iOS App Group `group.app.transkey`**: the main Flutter app writes `token + deviceId + plan + baseURL` to a shared `UserDefaults` suite; `TransKeyShare` and `TransKeyKeyboard` read it. Extensions never touch secure storage directly.
- **Android extensions**: there are no separate processes — everything (`BubbleService`, `ShareActivity`, `TransKeyAccessibilityService`) runs in the main app process and uses MethodChannels back into the Flutter engine for API calls.
- **Free tier**: same server-enforced limits as desktop (20 req/day, 2 000 chars/day). The mobile app additionally shows a `QuotaBar` driven by `/usage`.

---

## 2. Directory Structure

```
transkey-mobile/
├── lib/                          Flutter / Dart source
│   ├── main.dart                 Entry — initializes dotenv, root ProviderContainer, MethodChannel('transkey/bubble') handler for native → Dart translate calls, MaterialApp.router with i18n
│   ├── core/                     Cross-cutting infrastructure (not feature-specific)
│   │   ├── api/
│   │   │   ├── dio_client.dart       ApiClient + 3 interceptors (_HeadersInterceptor, _AuthRefreshInterceptor, _RetryInterceptor); apiClientProvider; baseURL from .env (TRANSKEY_API_URL)
│   │   │   ├── api_errors.dart       ApiException.fromDio() — maps Dio errors to friendly user messages
│   │   │   └── error_handler.dart    Top-level error formatter used by widgets
│   │   ├── auth/
│   │   │   ├── auth_provider.dart    AuthNotifier (AsyncNotifier) — login / register / logout / refreshUser / refreshIfNeeded / forceLogout / updateSession / handleDeepLink (transkey://auth?token=...)
│   │   │   ├── session_store.dart    AuthSession (token + userId + email + name + plan + expiresAt); SessionStore wraps secure storage with 4s timeout + SharedPreferences fallback
│   │   │   └── app_group_bridge.dart MethodChannel('transkey/appgroup') — iOS only — saveAuth / clearAuth into App Group UserDefaults
│   │   ├── bubble/
│   │   │   └── bubble_manager.dart   MethodChannel('transkey/bubble') — checkPermission / requestPermission (SYSTEM_ALERT_WINDOW), startBubble / stopBubble / setBubbleState, checkAccessibility / requestAccessibility, replaceFocusedText, tryAutoStart on cold launch
│   │   ├── device/
│   │   │   └── device_id.dart        SHA-256 hardware fingerprint — secure storage primary, SharedPreferences mirror + fallback; 3s timeout on device_info_plus; persistent fallback ID so cold-start failures don't keep minting new devices
│   │   ├── locale/
│   │   │   └── locale_provider.dart  AsyncNotifier<Locale> persisted to SharedPreferences (tk_ui_locale)
│   │   └── router/
│   │       └── app_router.dart       GoRouter with auth redirect + deep-link listener (app_links) that calls authProvider.handleDeepLink for transkey://auth callbacks
│   ├── features/                 Feature-vertical organization (each owns providers + models + screens + widgets)
│   │   ├── auth/
│   │   │   └── screens/auth_screen.dart           Login/Register tabs; Google OAuth via launchUrl(externalApplication) to /auth/google?state=mobile (server returns intent:// page that fires deep link)
│   │   ├── onboarding/
│   │   │   └── screens/keyboard_setup_screen.dart Post-login wizard for iOS (open Keyboard settings) / Android (request overlay permission); persists `keyboard_setup_done` in prefs
│   │   ├── translate/
│   │   │   ├── providers/
│   │   │   │   ├── translate_provider.dart        TranslateNotifier (AsyncNotifier) — translate / reply / summarize / explain / refine; in-memory LRU cache (50 entries); _requestSeq token so stale responses can't overwrite newer ones
│   │   │   │   ├── features_provider.dart         FeaturesNotifier — GET /features; 5-min staleness; isFeatureEnabled checks used to gate Pro-only modes
│   │   │   │   └── language_settings_provider.dart  source/target lang + recent targets (max 4); reload() called when bubble service may have mutated prefs from outside
│   │   │   ├── models/
│   │   │   │   ├── translate_models.dart          TranslateResult + SuggestionEntry + TranslateMode enum (translate/reply/summarize/explain/refine — `requiresPro` getter)
│   │   │   │   └── language.dart                  Language code → display name map
│   │   │   ├── services/
│   │   │   │   └── tts_service.dart               TtsNotifier — wraps flutter_tts (system TTS); per-language voice picker; rate control; abort on text change
│   │   │   ├── screens/
│   │   │   │   └── home_screen.dart               Main 4-tab shell (Translate / History / Glossary / Settings); IndexedStack with lazy-build; clipboard suggestion chip; iOS skips clipboard peek on resume to avoid the "TransKey pasted from…" privacy banner; restores last source text from prefs
│   │   │   └── widgets/
│   │   │       ├── language_picker_sheet.dart     Bottom sheet with Recent / All sections
│   │   │       ├── result_bottom_sheet.dart       Result display — translation, romanization, TTS, copy, favorite toggle, suggestions chips
│   │   │       └── tts_button.dart                Speak/stop button bound to TtsNotifier
│   │   ├── history/
│   │   │   ├── models/history_entry.dart          id (uuid v4) + createdAt + sourceText + translation + langs + mode + isFavorite + isLocked
│   │   │   ├── providers/history_provider.dart    HistoryNotifier — list, add, delete, toggleFavorite, toggleLock, clear, clearNonFavorites
│   │   │   ├── storage/history_store.dart         SharedPreferences `tk_history` (JSON), max 500 entries, _trimKeepLocked keeps locked items even past limit; single-process write lock so bubble + in-app writes can't drop entries
│   │   │   ├── screens/history_screen.dart        List + filter by mode + bulk actions
│   │   │   └── widgets/history_card.dart, history_detail_sheet.dart
│   │   ├── glossary/
│   │   │   ├── models/glossary_entry.dart         id + source + target; legacy entries get synthesized id "legacy_{source}_{target}"
│   │   │   ├── providers/glossary_provider.dart   GlossaryNotifier — load local, pull (GET /glossary), push (PUT /glossary) with 1.5s debounce; flushPendingPush() on navigation
│   │   │   ├── screens/glossary_screen.dart       List + add/edit/delete; max 50 entries enforced client-side
│   │   │   └── widgets/add_glossary_sheet.dart
│   │   ├── settings/
│   │   │   ├── providers/
│   │   │   │   ├── app_settings_provider.dart     AsyncNotifier<AppSettings> — historySave, romanization, replySuggestions, toneOverride, replyToneOverride, replyLang, autoCloseSeconds; toneOptions list aligned with desktop
│   │   │   │   ├── devices_provider.dart          AsyncNotifier — GET /auth/user/devices, DELETE /auth/user/devices/:id
│   │   │   │   └── subscription_provider.dart     AsyncNotifier — GET /auth/subscription, POST /auth/subscription/cancel
│   │   │   ├── screens/
│   │   │   │   ├── settings_screen.dart           Plan card, language pickers, tone, history toggle, romanization, locale picker, logout, link out to devices / subscription / change-password
│   │   │   │   ├── devices_screen.dart            List + remove devices (Pro device limit management)
│   │   │   │   ├── subscription_screen.dart       Plan status + cancel + renewal/end dates
│   │   │   │   └── change_password_screen.dart    Current + new password form → POST /auth/change-password
│   │   │   └── widgets/plan_badge.dart            Color-coded plan pill (free / pro / mobile / trial / banned)
│   │   └── upgrade/
│   │       ├── providers/usage_provider.dart      AsyncNotifier — GET /usage, 1-min staleness, refreshIfStale() called from HomeScreen.onResume
│   │       └── screens/upgrade_screen.dart        Pro upgrade pitch with checkout button → opens hosted checkout URL via url_launcher
│   ├── shared/
│   │   ├── theme/app_theme.dart                   AppColors, AppSpacing, light/dark ThemeData
│   │   └── widgets/                               error_state, feature_gate, quota_bar, skeleton, empty_states, copy_button, upgrade_nudge_sheet, selectable_with_actions
│   └── l10n/
│       ├── app_en.arb, app_vi.arb                 ARB source (English + Vietnamese)
│       └── generated/                             Generated by `flutter gen-l10n` (driven by ../l10n.yaml)
│
├── android/
│   └── app/src/main/
│       ├── AndroidManifest.xml                    Permissions, MainActivity (deep-link transkey://auth), ShareActivity + 4 activity-aliases (Reply/Summarize/Explain/Refine — each is a separate PROCESS_TEXT menu entry), BubbleService (foregroundServiceType=specialUse), TransKeyAccessibilityService
│       ├── kotlin/com/example/transkey_mobile/
│       │   ├── MainActivity.kt                    FlutterActivity; configures MethodChannel('transkey/share') + MethodChannel('transkey/bubble'); handleIncomingIntent for ACTION_SEND / ACTION_PROCESS_TEXT
│       │   ├── BubbleService.kt                   Foreground service — overlay bubble (WindowManager); mode picker; target/source lang cycle; tone picker; result panel with romanization + TTS (android.speech.tts); reads & writes Flutter SharedPreferences via "FlutterSharedPreferences" / "flutter.tk_*" keys; calls Flutter via MethodChannel('transkey/bubble').invokeMethod('translateText') and waits for `deliverResult`
│       │   ├── ShareActivity.kt                   Transparent receiver for ACTION_SEND + ACTION_PROCESS_TEXT + ACTION_READ_CLIPBOARD; resolves mode from activity-alias meta-data `transkey.mode`; forwards to BubbleService; onWindowFocusChanged gates clipboard read (Android 10+ blocks unfocused activities)
│       │   ├── TransKeyAccessibilityService.kt    Optional service — lets bubble paste a reply directly into the focused EditText of any app via ACTION_SET_TEXT; also exposes getSelectedText() that walks the active window's node tree (works in apps that block clipboard copy: LinkedIn, banking)
│       │   └── TransKeyApp.kt                     Application class (registers plugins)
│       └── res/
│           ├── xml/accessibility_service_config.xml  Capabilities + flags for AccessibilityService
│           ├── values/strings.xml, styles.xml        LaunchTheme, NormalTheme, ShareActivityTheme (transparent but focusable)
│           ├── values-night/styles.xml
│           ├── mipmap-*/ic_launcher.png              App icon (all densities)
│           └── drawable/launch_background.xml
│
├── ios/
│   ├── Runner/
│   │   ├── AppDelegate.swift                       FlutterAppDelegate; bootstraps AppGroupPlugin
│   │   ├── SceneDelegate.swift
│   │   ├── AppGroupPlugin.swift                    MethodChannel('transkey/appgroup') — saveAuth / clearAuth / openKeyboardSettings; bridges to AppGroupStore
│   │   ├── AppGroupStore.swift                     `UserDefaults(suiteName: "group.app.transkey")` wrapper — keys: tk_access_token, tk_device_id, tk_user_plan, tk_api_base_url
│   │   └── Info.plist                              CFBundleURLSchemes: ["transkey"]; NSAppTransportSecurity allows arbitrary loads (debug); UI orientations
│   ├── TransKeyShare/                              Share Extension target — appears in the iOS share sheet
│   │   ├── ShareViewController.swift               Receives shared text via NSExtensionContext; 4 mode buttons; reads token + plan from AppGroupStore; calls APIClient
│   │   ├── APIClient.swift                         Lightweight URLSession client; reads token + deviceID + baseURL from AppGroupStore; no Dio, no Riverpod
│   │   └── Info.plist                              NSExtension activation rule (text/plain)
│   ├── TransKeyKeyboard/                           Custom Keyboard Extension target
│   │   ├── KeyboardViewController.swift            UIInputViewController; checks `hasFullAccess`; toolbar with mode picker + result panel; auto-insert + undo banner; reads from AppGroupStore
│   │   └── Info.plist                              IsASCIICapable, RequestsOpenAccess (required to make network requests from the keyboard)
│   └── Flutter/AppFrameworkInfo.plist
│
├── pubspec.yaml                                    Deps: flutter_riverpod, dio, go_router, flutter_secure_storage, shared_preferences, app_links, flutter_tts, url_launcher, flutter_dotenv, device_info_plus, intl, uuid
├── l10n.yaml                                       template-arb-file: app_en.arb, output-localization-file: app_localizations.dart, output-dir: lib/l10n/generated
├── .env                                            TRANSKEY_API_URL (committed; switches localhost ↔ api.transkey.app)
└── SETUP_GUIDE.md                                  Developer setup
```

---

## 3. Data Flows

### 3.1 In-App Translate (primary)

```
HomeScreen tab 0 → user types text + selects target lang → presses Translate
        │
        ▼
TranslateNotifier.translate(text, targetLang, sourceLang?, isReply)
  1. _settings() → load AppSettings (tone, romanization, replySuggestions)
  2. Build body Map: { text, targetLang, sourceLang?, withRomanization?, toneOverride?, isReply?, withSuggestions? }
  3. reqId = ++_requestSeq          (token so stale responses can't win the race)
  4. state = Loading(sourceText: trimmed)
  5. cacheKey = `{text}|{src}|{target}|{mode}|{tone}|{roman}|{isReply}|{suggestions}`
     If _cache contains key → emit cached result + _maybeSaveHistory; return
  6. apiClient.dio.post(endpoint, body)
        │
        ▼  Headers (Authorization + X-Device-ID + X-Platform: mobile)
        ▼  RetryInterceptor: exponential backoff on 408/429/5xx (up to 2 retries)
        ▼  AuthRefreshInterceptor: on 401 → POST /auth/refresh → retry once
        ▼
  7. TranslateResult.fromMap(response.data)
  8. _cache[key] = result (evict oldest if >50)
  9. _maybeSaveHistory() — only if settings.historySave (default true)
  10. state = AsyncData(result)
  11. unawaited(usageProvider.refresh())     (quota bar updates in background)

If reqId != _requestSeq at any await point → drop the response (user moved on).
```

Endpoints:
- `translate` / `reply` → `POST /translate` (reply sends `isReply: true` + `replyToOriginal?` + `withSuggestions?`)
- `summarize` → `POST /summarize`
- `explain` → `POST /explain` (MaxLength 500 on server)
- `refine` → `POST /refine` (MaxLength 2000 on server; no targetLang)

### 3.2 Android Floating Bubble Translate

```
User has bubble running (foreground service) on top of another app
        │
        ▼  taps bubble → mode picker (Translate/Reply/Summarize/Explain/Refine)
        │
        ▼
BubbleService → starts ShareActivity with ACTION_READ_CLIPBOARD + EXTRA_MODE
        │
        ▼
ShareActivity.onWindowFocusChanged(true)
  (Android 10+ blocks ClipboardManager.primaryClip for unfocused activities,
   so we need a real focusable window briefly — ShareActivityTheme is transparent
   but NOT translucent. Fallback timer fires after FOCUS_FALLBACK_MS.)
        │
        ▼
  Reads clipboard text → finish() (instant) → forwardClipboardToService(mode):
    BubbleService onStartCommand(ACTION_TRANSLATE, EXTRA_TEXT, EXTRA_MODE)
        │
        ▼
BubbleService:
  1. setState(LOADING) on overlay
  2. read prefs ("flutter.tk_target_lang", "flutter.tk_source_lang", …)
  3. requestId = ++nextRequestId
  4. MethodChannel('transkey/bubble').invokeMethod('translateText', { text, mode, targetLang, requestId, replyToOriginal? })
        │
        ▼   (handled in main.dart _wireBubbleChannel)
_translateForBubble(text, mode, targetLang, requestId):
  1. SessionStore().load() → 401-style guard if logged out
  2. Read prefs (romanization, sourceLang, toneOverride, replyTone, replyLang, replySuggestions)
  3. Build endpoint + body per mode (mirrors TranslateNotifier logic)
  4. apiClient.dio.post(endpoint, body)
  5. Optionally addFromTranslate to history (settings.historySave gated)
  6. _bubbleChannel.invokeMethod('deliverResult', { translation, romanization, detectedLang, error, requestId })
        │
        ▼
BubbleService.onStartCommand(ACTION_SHOW_RESULT):
  If incoming requestId == latest → render result panel (translation + romanization + TTS + copy + insert-via-accessibility button)
  Otherwise → drop (user already moved on)
```

Bubble auto-start: `main.dart` fires `bubbleManagerProvider.tryAutoStart()` after `runApp` — reads `tk_bubble_active`, checks `Settings.canDrawOverlays`, starts the service if previously active. The service writes `flutter.tk_bubble_active` itself on start/stop.

### 3.3 Android Share / PROCESS_TEXT (Cold path — no app open)

```
User selects text in another app → text-selection menu shows
  Translate / Reply / Summarize / Explain / Refine
  (5 entries because each activity-alias in AndroidManifest.xml exposes
   its own PROCESS_TEXT intent-filter; each carries meta-data transkey.mode=...)
        │
        ▼
ShareActivity (transparent) launches:
  - resolveMode() reads the alias's meta-data
  - extractText() reads EXTRA_PROCESS_TEXT or EXTRA_TEXT
        │
        ▼
If overlay permission granted (Settings.canDrawOverlays):
  startService(BubbleService, ACTION_TRANSLATE, EXTRA_TEXT, EXTRA_MODE)
  ShareActivity finishes immediately → result shown as overlay,
  user never leaves their original app.

If overlay permission denied:
  startActivity(MainActivity) with EXTRA_TEXT → main app opens to HomeScreen
  which picks up the text via MethodChannel('transkey/share') 'onSharedText'.
```

### 3.4 iOS Share Extension

```
User in any app → Share sheet → TransKey
        │
        ▼
ShareViewController.viewDidLoad:
  1. AppGroupStore.shared.plan      → isPro?
  2. extractSharedText() — NSItemProvider with "public.plain-text"
  3. Render 4 mode buttons (Translate / Summarize / Explain / Refine)
        │
        ▼  user taps a button
APIClient (TransKeyShare/APIClient.swift):
  URLSession POST  {AppGroupStore.shared.apiBaseURL}/translate (or /summarize…)
  Headers: Authorization: Bearer {AppGroupStore.shared.token}, X-Device-ID, X-Platform: mobile
  Result rendered inline in the share modal (no Flutter engine involved).
```

The share extension is a **separate iOS process**. It cannot read `flutter_secure_storage`, so the main Flutter app writes the token (+ deviceID, plan, baseURL) into the App Group's `UserDefaults(suiteName: "group.app.transkey")` on every login / refresh / logout. `AppGroupBridge.dart` ↔ `AppGroupPlugin.swift` ↔ `AppGroupStore.swift` form that bridge.

### 3.5 iOS Keyboard Extension

```
User installs "TransKey" keyboard in Settings → General → Keyboard → Keyboards
       and enables "Allow Full Access" (required for network)
        │
        ▼
User opens any app, switches to TransKey keyboard → KeyboardViewController loads
  - hasFullAccess gate → if false, render overlay with setup instructions
  - Toolbar: source-lang chip, target-lang chip, Translate / Reply / Refine buttons
  - Inline result panel with [Insert] button → replaces selected text via
    textDocumentProxy.deleteBackward + insertText, with undoSnapshot for one-shot Undo
        │
        ▼
APIClient (TransKeyKeyboard/APIClient.swift, same code as TransKeyShare):
  reads token from AppGroupStore, POSTs to /translate, renders inline
```

### 3.6 Auth — Email/Password

```
AuthScreen → _submit() → AuthNotifier.login / register
  POST /auth/login | /auth/register
  Body: { email, password, name? }
  Headers: X-Device-ID, X-Platform: mobile
  20s hard timeout on the whole flow
        │
        ▼
SessionStore.save(AuthSession{token, userId, email, name, plan, expiresAt})
  → flutter_secure_storage.write (4s timeout)
  → on timeout/failure: fall through to SharedPreferences
ApiClient.invalidateSessionCache()      (so next request reads fresh token)
AppGroupBridge.saveAuth(...)            (iOS only — sync to App Group)
        │
        ▼
state = AuthState(isLoggedIn: true) → GoRouter refresh redirect → "/"
```

### 3.7 Auth — Google OAuth (Mobile-specific)

```
AuthScreen → Continue with Google →
  launchUrl(`{baseUrl}/auth/google?state=mobile`, mode: externalApplication)
        ↑ NOT a Chrome Custom Tab — Custom Tab silently blocks intent:// redirects
          without a user gesture, leaving users stuck on the post-OAuth page.
        │
        ▼
Server (auth.controller.ts googleCallback): state="mobile" branch →
  serves an HTML page with <meta http-equiv="refresh" url="intent://auth?token=...">
  (or transkey://auth?token=... on iOS) — fires the system deep-link handler.
        │
        ▼
OS routes transkey://auth?token=... to TransKey:
  - Android: AndroidManifest intent-filter on MainActivity (scheme=transkey, host=auth)
  - iOS:     CFBundleURLSchemes = ["transkey"]
        │
        ▼
app_links package emits URI on uriLinkStream → app_router._initDeepLinkListener →
AuthNotifier.handleDeepLink(uri):
  uri.queryParameters['error'] → set AuthState.error (surfaced in AuthScreen banner)
  uri.queryParameters['token'] → SessionStore.save + invalidateApiSessionCache +
    AppGroupBridge.saveAuth → state = AsyncData(AuthState(isLoggedIn: true))
```

### 3.8 JWT Auto-Refresh (transparent to callers)

```
Any request → 401 from server
        │
        ▼
_AuthRefreshInterceptor.onError:
  If path == '/auth/refresh' → forceLogout, propagate
  Otherwise:
    POST /auth/refresh with current token
    On success → save new token + expiresAt, retry the failed request once
    On failure → AuthNotifier.forceLogout() → state cleared → router redirects to /auth/login

In addition, AuthNotifier.refreshIfNeeded() can be called proactively if
session.isExpiringSoon (token expires within 7 days).
```

---

## 4. Cross-platform Native Bridges

### 4.1 Method Channels (Flutter ↔ Native)

| Channel | Direction | Methods |
|---|---|---|
| `transkey/share` | Native → Flutter | `getSharedText`, `onSharedText` (push from MainActivity to home screen) |
| `transkey/bubble` | Both | Flutter→Native: `checkPermission`, `requestPermission`, `startBubble`, `stopBubble`, `setBubbleState`, `isRunning`, `checkAccessibility`, `requestAccessibility`, `replaceFocusedText`. Native→Flutter: `translateText` → Flutter→Native reply: `deliverResult` |
| `transkey/appgroup` | iOS only — Flutter → Native | `saveAuth`, `clearAuth`, `openKeyboardSettings` |
| `transkey/deeplink` | iOS only — Flutter → Native | `open` (fallback URL opener for Keyboard settings) |

### 4.2 SharedPreferences Keys (Android cross-process)

The bubble service runs in the same process but native code accesses Flutter's prefs via `getSharedPreferences("FlutterSharedPreferences", MODE_PRIVATE)`. Flutter keys are stored with the `flutter.` prefix on the native side:

| Flutter key | Native key | Used by | Purpose |
|---|---|---|---|
| `tk_target_lang` | `flutter.tk_target_lang` | BubbleService | Cycle target lang in bubble |
| `tk_source_lang` | `flutter.tk_source_lang` | BubbleService, main | Source lang (default `auto`) |
| `tk_tone_override` | `flutter.tk_tone_override` | BubbleService, main | Tone for translate / refine |
| `tk_reply_tone_override` | — | main only | Tone for reply mode |
| `tk_reply_lang` | `flutter.tk_reply_lang` | BubbleService, main | Reply target lang |
| `tk_reply_suggestions` | — | main only | Include suggestions in reply API |
| `tk_romanization` | — | main only | `withRomanization` flag |
| `tk_history_save` | — | main only | Auto-save translations to history |
| `tk_auto_close_seconds` | — | main only | Result sheet auto-close |
| `tk_bubble_active` | `flutter.tk_bubble_active` | both | Bubble running state (auto-start signal) |
| `tk_history` | — | main only | History JSON (max 500) |
| `tk_glossary` | — | main only | Glossary JSON (max 50) |
| `tk_last_source_text` | — | main only | Restore last typed source text |
| `tk_recent_target_langs` | — | main only | Recently chosen target langs (max 4) |
| `tk_ui_locale` | — | main only | UI language (en/vi) |
| `tk_auth_session` | — | main only | (Mirror only) Session JSON if secure storage failed |
| `tk_device_fingerprint` | — | main only | (Mirror only) Device fingerprint if secure storage failed |
| `keyboard_setup_done` | — | main only | Skip keyboard setup screen after first run |

### 4.3 iOS App Group `group.app.transkey`

Keys in `UserDefaults(suiteName:)`:

| Key | Writer | Readers |
|---|---|---|
| `tk_access_token` | Flutter (AuthNotifier on every session change) | TransKeyShare, TransKeyKeyboard |
| `tk_device_id` | Flutter | TransKeyShare, TransKeyKeyboard |
| `tk_user_plan` | Flutter | TransKeyShare, TransKeyKeyboard (gate Pro modes) |
| `tk_api_base_url` | Flutter | TransKeyShare, TransKeyKeyboard |

Logout: `AppGroupStore.clearAll()` removes all four — extensions immediately see no token and refuse to call the API.

---

## 5. Riverpod Provider Graph

```
sessionStoreProvider           Provider<SessionStore>                — wraps secure storage
deviceIdProvider               Provider<DeviceIdService>             — fingerprint cache
apiClientProvider              Provider<ApiClient>                   — Dio + 3 interceptors

authStateProvider              AsyncNotifierProvider<AuthNotifier, AuthState>
                                 ↳ login / register / logout / refreshUser
                                 ↳ refreshIfNeeded / forceLogout / handleDeepLink

localeProvider                 AsyncNotifierProvider<LocaleNotifier, Locale>     — UI language
bubbleManagerProvider          StateNotifierProvider<BubbleManager, bool>        — Android only

routerProvider                 Provider<GoRouter>                                — refreshListenable watches authStateProvider
                                 ↳ also starts AppLinks().uriLinkStream listener

translateProvider              AsyncNotifierProvider<TranslateNotifier, TranslateState>
                                 ↳ translate / reply / summarize / explain / refine
                                 ↳ in-memory LRU cache (50)

featuresProvider               NotifierProvider<FeaturesNotifier, FeaturesState> — /features cache, 5-min TTL
languageSettingsProvider       AsyncNotifierProvider<LanguageSettingsNotifier, LanguageSettings>

historyProvider                AsyncNotifierProvider<HistoryNotifier, List<HistoryEntry>>
glossaryProvider               NotifierProvider<GlossaryNotifier, GlossaryState>  — debounced PUT (1.5s)

appSettingsProvider            AsyncNotifierProvider<AppSettingsNotifier, AppSettings>
devicesProvider                AsyncNotifierProvider<DevicesNotifier, List<UserDevice>>
subscriptionProvider           AsyncNotifierProvider<SubscriptionNotifier, SubscriptionInfo>
usageProvider                  AsyncNotifierProvider<UsageNotifier, UsageInfo?>   — /usage, 1-min TTL
ttsProvider                    NotifierProvider<TtsNotifier, TtsState>            — wraps flutter_tts
```

Root `ProviderContainer` is created in `main.dart` (`_rootContainer`) so the native bubble channel can read providers even before the widget tree builds.

---

## 6. Permissions

### Android

| Permission | When asked | Required for |
|---|---|---|
| `INTERNET`, `ACCESS_NETWORK_STATE` | At install (normal perms) | All API calls |
| `SYSTEM_ALERT_WINDOW` | `bubbleManager.requestPermission` opens `ACTION_MANAGE_OVERLAY_PERMISSION` | Floating bubble |
| `FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_SPECIAL_USE` | Manifest | BubbleService notification |
| `BIND_ACCESSIBILITY_SERVICE` | User enables in Settings → Accessibility → TransKey | Paste reply into focused EditText |

### iOS

- Push share-sheet entry: declared via `NSExtensionActivationRule` in `TransKeyShare/Info.plist`.
- Keyboard with network: requires user to toggle "Allow Full Access" — `OpenAccessChecker.hasFullAccess(self)` gates the keyboard UI; otherwise an instruction overlay is shown.
- Deep link: `CFBundleURLSchemes = ["transkey"]` in main `Info.plist`.
- App Group: `group.app.transkey` entitlement on Runner + TransKeyShare + TransKeyKeyboard targets (entitlements files, not in Info.plist).

---

## 7. Environment & Configuration

`.env` (committed):
```
TRANSKEY_API_URL=https://api.transkey.app   # or http://localhost:3000 for dev
```

Resolved by `dotenv.load(fileName: '.env')` in `main.dart`. `kBaseUrl` in `dio_client.dart` defaults to `https://api.transkey.app` if missing.

`l10n.yaml`:
```
arb-dir: lib/l10n
template-arb-file: app_en.arb
output-dir: lib/l10n/generated
output-localization-file: app_localizations.dart
```
Re-run `flutter gen-l10n` after editing the ARB files (or it runs automatically on `flutter pub get` due to `flutter.generate: true`).

---

## 8. Build & Release

```
# Generate localizations + code gen (freezed / json_serializable)
flutter pub get
dart run build_runner build --delete-conflicting-outputs

# Run
flutter run                                              # current device
flutter run -d <android-id>                              # specific Android device
flutter run -d <ios-id>                                  # specific iOS device

# Release builds
flutter build apk --release
flutter build appbundle --release
flutter build ipa --release

# Open native IDEs when extension targets need signing:
open ios/Runner.xcworkspace            # TransKeyShare / TransKeyKeyboard provisioning
open -a "Android Studio" android       # bubble service / accessibility service tweaks
```

For first-time iOS setup (extensions, App Group, signing), see `SETUP_GUIDE.md`.

---

## 9. Known Gotchas

- **iOS clipboard banner**: `Clipboard.getData(...)` on iOS 14+ shows a privacy banner ("TransKey pasted from …") every call. `home_screen.dart` only peeks the clipboard on cold start, not on `didChangeAppLifecycleState resume` — Android has no such banner so it peeks freely.
- **Android 10+ clipboard from background**: `ClipboardManager.primaryClip` returns null for activities/services without input focus. `ShareActivity` is rendered transparent-but-focusable specifically so it can satisfy this check before forwarding clipboard text to `BubbleService`.
- **Custom Tabs block intent:// without user gesture** — Google OAuth uses `launchUrl(externalApplication)` (regular Chrome) instead of `inAppBrowserView` so the post-OAuth `intent://` redirect can fire.
- **Secure storage can hang on MIUI/ColorOS/FuntouchOS**: every `flutter_secure_storage` call wraps a 4-second timeout and falls back to `SharedPreferences` so login never freezes. Critical values (token, device fingerprint) are always mirrored to prefs.
- **Bubble can outlive the Flutter engine** — `main.dart` registers the `transkey/bubble` MethodChannel at top level, before `runApp`, so native invocations during a cold start (e.g. user taps bubble after the process was killed) are handled even before the widget tree exists.
- **Stale translate responses** — `TranslateNotifier._requestSeq` is bumped on every call, on `clearResult`, and on `setMode`. Each await point in the flow re-checks `reqId == _requestSeq`; mismatches drop the response so a slow first request can't overwrite a faster second one.
- **Cache key drift** — `_cacheKey` includes tone, romanization, isReply, withSuggestions, sourceLang. If you add a new server-affecting body field, add it to the cache key too, otherwise toggling that field reuses the old result.
- **History double-writes** — both the in-app flow (`translate_provider`) and the bubble flow (`main.dart _translateForBubble`) can call `historyProvider.addFromTranslate`. `HistoryStore` uses a single-process `_lock` future to serialize so concurrent load-modify-save cycles don't drop entries.
