package app.transkey.mobile

import android.annotation.SuppressLint
import android.app.Service
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.graphics.Bitmap
import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.SystemClock
import android.speech.tts.TextToSpeech
import android.util.TypedValue
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import android.widget.EditText
import android.widget.FrameLayout
import android.widget.HorizontalScrollView
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.ProgressBar
import android.widget.ScrollView
import android.widget.TextView
import android.widget.Toast
import java.util.Locale

class BubbleService : Service() {

    companion object {
        /**
         * True while a BubbleService instance is alive in THIS process.
         * Resets to false on process death (static default), so after a hard
         * kill that bypasses START_STICKY — `am force-stop`, or an OEM
         * background killer (Xiaomi/OnePlus) — `isRunning` reports the bubble
         * as down instead of trusting the persisted `tk_bubble_active` flag
         * alone. That lets tryAutoStart actually restart it and keeps the
         * in-app toggle honest. BubbleService runs in the app's default
         * process (no android:process), so MainActivity / TransKeyApp read
         * the same value.
         */
        @Volatile
        var isAlive: Boolean = false
            private set

        const val CHANNEL_ID = "transkey_bubble"
        const val NOTIFICATION_ID = 1001
        const val ACTION_START = "transkey.bubble.START"
        const val ACTION_STOP = "transkey.bubble.STOP"
        const val ACTION_SET_STATE = "transkey.bubble.SET_STATE"
        const val ACTION_TRANSLATE = "transkey.bubble.TRANSLATE"
        const val ACTION_SHOW_RESULT = "transkey.bubble.SHOW_RESULT"
        const val ACTION_HIDE_PANEL = "transkey.bubble.HIDE_PANEL"
        // Sent by MicPermissionActivity after the user grants RECORD_AUDIO,
        // so the bubble can open its voice picker overlay.
        const val ACTION_START_VOICE = "transkey.bubble.START_VOICE"
        // Sent by ScreenCaptureService after a single frame has been OCR'd —
        // EXTRA_TEXT carries the recognised text (null on failure).
        const val ACTION_DELIVER_OCR = "transkey.bubble.DELIVER_OCR"
        // Sent by ScreenCaptureService for the Lens flow — bitmap + OCR
        // blocks sit in ScreenCaptureManager; we just need the signal to
        // start batch-translation and render the overlay.
        const val ACTION_DELIVER_LENS = "transkey.bubble.DELIVER_LENS"
        // Sent by ScreenCapturePermissionActivity when the user cancels
        // the system "Start recording?" dialog. We hid the bubble in
        // launchScanFlow before showing the dialog; without this signal
        // the bubble would stay GONE (looking to the user like it had
        // crashed) until they killed the service.
        const val ACTION_SCAN_CANCELLED = "transkey.bubble.SCAN_CANCELLED"
        // ScreenCaptureService hit a single-app grant that can't capture the
        // now-foreground app. We can't auto re-open consent (MIUI blocks
        // background activity starts off a timer), so restore the bubble and
        // show a tappable pill — the user's tap launches the fresh consent.
        const val ACTION_RECONSENT = "transkey.bubble.RECONSENT"
        // Region mode: capture finished but OCR deferred — show the
        // rubber-band selector on top of the bitmap so the user can crop
        // before we OCR + translate.
        const val ACTION_DELIVER_REGION_READY = "transkey.bubble.DELIVER_REGION_READY"
        // Progressive Lens translate: emitted by Flutter via
        // [TransKeyApp]'s deliverLensChunk handler each time one chunk
        // of /translate-batch returns. Lets the overlay patch its
        // already-shown chips in place so the user sees chips fill in
        // within ~1-2s instead of waiting for the slowest chunk.
        const val ACTION_DELIVER_LENS_CHUNK = "transkey.bubble.DELIVER_LENS_CHUNK"
        const val EXTRA_LENS_CHUNK_START = "lens_chunk_start"
        const val EXTRA_LENS_CHUNK_TRANSLATIONS = "lens_chunk_translations"
        // Source-language mismatch: server saw a script different from the
        // user's pinned source. Carries the detected language code so the
        // overlay can offer a one-tap "switch & re-translate".
        const val ACTION_DELIVER_LENS_MISMATCH = "transkey.bubble.DELIVER_LENS_MISMATCH"
        const val EXTRA_LENS_MISMATCH_DETECTED = "lens_mismatch_detected"
        const val EXTRA_STATE = "bubble_state"
        const val EXTRA_TEXT = "text"
        const val EXTRA_MODE = "mode"
        const val EXTRA_TRANSLATION = "translation"
        const val EXTRA_ROMANIZATION = "romanization"
        const val EXTRA_DETECTED_LANG = "detectedLang"
        const val EXTRA_SUGGESTION_SOURCES = "suggestion_sources"
        const val EXTRA_SUGGESTION_TARGETS = "suggestion_targets"
        // Scam warning for a received message (null level = safe).
        const val EXTRA_SCAM_LEVEL = "scam_level"
        const val EXTRA_SCAM_TYPE = "scam_type"
        const val EXTRA_SCAM_REASON = "scam_reason"
        const val EXTRA_ERROR = "error"
        const val EXTRA_REQUEST_ID = "request_id"

        const val METHOD_CHANNEL = "transkey/bubble"

        // Sent from mode picker → ShareActivity reads clipboard and forwards back
        const val ACTION_READ_CLIPBOARD = "transkey.bubble.READ_CLIPBOARD"

        const val STATE_IDLE = "idle"
        const val STATE_LOADING = "loading"
        const val STATE_RESULT = "result"
        const val STATE_ERROR = "error"

        const val MODE_TRANSLATE = "translate"
        const val MODE_SUMMARIZE = "summarize"
        const val MODE_EXPLAIN = "explain"
        const val MODE_REFINE = "refine"
        // Reply lives on the TransKey keyboard (types straight into the
        // focused field) + the in-app feature row. It was removed from the
        // bubble overlay because the bubble's auto-paste relied on the
        // Accessibility service, which we no longer ship.
        internal val ALL_MODES = listOf(MODE_TRANSLATE, MODE_SUMMARIZE, MODE_EXPLAIN, MODE_REFINE)
        // Mode → (string-resource id, drawable-resource id) for the picker and
        // result panel. Keeping resources here (instead of inline `when`) makes
        // it cheap to add a new mode in one place.
        private val MODE_STRING_IDS = mapOf(
            MODE_TRANSLATE to R.string.bubble_mode_translate,
            MODE_SUMMARIZE to R.string.bubble_mode_summarize,
            MODE_EXPLAIN to R.string.bubble_mode_explain,
            MODE_REFINE to R.string.bubble_mode_refine,
        )
        private val MODE_ICON_IDS = mapOf(
            MODE_TRANSLATE to R.drawable.ic_bubble_translate,
            MODE_SUMMARIZE to R.drawable.ic_bubble_summarize,
            MODE_EXPLAIN to R.drawable.ic_bubble_explain,
            MODE_REFINE to R.drawable.ic_bubble_refine,
        )

        // Target languages user can cycle through in the overlay.
        // Persisted to Flutter SharedPreferences via the "flutter.tk_target_lang" key.
        //
        // The two lists below are the FALLBACK catalog used only when the
        // mirrored server catalog (flutter.tk_lang_catalog, written by
        // FeaturesNotifier.fetch) is missing — first-run before /features
        // responded, OR a logged-out user. The runtime helpers
        // [getEffectiveTargetLangs] / [getEffectiveSourceLangs] /
        // [getEffectiveLangLabels] do the read-from-prefs-with-fallback,
        // so the bubble picker shows the SAME list as the home language
        // bar (admin can enable/disable languages per plan via
        // /admin/features without shipping a new app).
        internal val TARGET_LANGS = listOf(
            // Latin / European
            "en", "vi", "fr", "de", "es", "pt", "it", "nl", "sv", "da",
            "no", "fi", "pl", "cs", "ro", "hu", "tr",
            // CJK / SEA
            "ja", "zh", "ko", "th", "id", "ms", "fil",
            // Cyrillic / Hebrew / Greek / Arabic / Indic (vision path)
            "ru", "uk", "el", "he", "ar", "hi",
        )
        // Source picker mirrors the target list + an "auto" entry up front.
        // Built lazily off TARGET_LANGS so we only maintain ONE source of
        // truth — adding a language above automatically shows up in both.
        internal val SOURCE_LANGS: List<String> = listOf("auto") + TARGET_LANGS
        // English name only — keeps the single-line keyboard/bubble pickers
        // identifiable AND uncluttered (native + English side by side read as
        // noise, esp. with nested parens like "Chinese (Traditional)"). Pre-login
        // fallback only; once /features syncs, the server catalog labels (also
        // English-only, see FeaturesNotifier.fetch) override these.
        internal val LANG_LABELS = mapOf(
            "auto" to "Auto",
            // Latin
            "en" to "English", "vi" to "Vietnamese", "fr" to "French",
            "de" to "German", "es" to "Spanish", "pt" to "Portuguese",
            "it" to "Italian", "nl" to "Dutch", "sv" to "Swedish",
            "da" to "Danish", "no" to "Norwegian", "fi" to "Finnish",
            "pl" to "Polish", "cs" to "Czech", "ro" to "Romanian",
            "hu" to "Hungarian", "tr" to "Turkish",
            // CJK / SEA
            "ja" to "Japanese", "zh" to "Chinese", "ko" to "Korean",
            "th" to "Thai", "id" to "Indonesian", "ms" to "Malay",
            "fil" to "Filipino",
            // Cyrillic / Hebrew / Greek / Arabic / Indic
            "ru" to "Russian", "uk" to "Ukrainian", "el" to "Greek",
            "he" to "Hebrew", "ar" to "Arabic", "hi" to "Hindi",
        )
        private const val PREFS_NAME = "FlutterSharedPreferences"
        private const val KEY_TARGET_LANG = "flutter.tk_target_lang"
        private const val KEY_SOURCE_LANG = "flutter.tk_source_lang"
        private const val KEY_TONE_OVERRIDE = "flutter.tk_tone_override"
        private const val KEY_BUBBLE_ACTIVE = "flutter.tk_bubble_active"
        private const val KEY_ROMANIZATION = "flutter.tk_romanization"
        private const val KEY_TTS_RATE = "flutter.tk_tts_rate"
        // Local-only flag (not under flutter.* prefix) so we don't pollute
        // the Flutter SharedPreferences mirror with native-only state.
        internal const val KEY_SCAN_DISCLOSED = "tk_scan_disclosed"
        // Speaker's language for the voice picker (independent of translate
        // source-lang — what you DICTATE in may differ from what you
        // translate FROM, e.g. dictate JP, translate JP→EN).
        private const val KEY_VOICE_LANG = "tk_voice_lang"

        // Languages offered as pills in the voice picker. Kept short on
        // purpose — every entry needs an offline pack downloaded on the
        // device's Google Speech Services for non-network use.
        internal val VOICE_LANGS = listOf(
            "en", "vi", "ja", "ko", "zh", "fr", "de", "es", "pt", "ru", "th", "id",
        )

        // Tone codes — MUST match Flutter `toneOptions` in
        // lib/features/settings/providers/app_settings_provider.dart so that
        // a tone picked in the bubble shows up correctly in the in-app
        // Settings screen (and vice versa). Labels are resolved per-locale
        // via `toneLabel()` below.
        internal val TONE_CODES = listOf(
            "", "business", "casual", "formal", "polite", "technical", "neutral",
        )
        private val TONE_STRING_IDS = mapOf(
            "" to R.string.bubble_tone_auto,
            "business" to R.string.bubble_tone_business,
            "casual" to R.string.bubble_tone_casual,
            "formal" to R.string.bubble_tone_formal,
            "polite" to R.string.bubble_tone_polite,
            "technical" to R.string.bubble_tone_technical,
            "neutral" to R.string.bubble_tone_neutral,
        )

        // Speech rates — MUST match Flutter `speeds` list in tts_button.dart
        // so a rate set in the bubble is reflected when the in-app speak
        // button opens. Same set as desktop popup.ts RATE_OPTIONS.
        internal val TTS_RATES = listOf(0.25, 0.5, 0.75, 1.0, 1.25, 1.5)

        internal const val BUBBLE_SIZE_DP = 48

        // Drag-to-close target
        internal const val CLOSE_ZONE_SIZE_DP = 64
        internal const val CLOSE_ZONE_BOTTOM_MARGIN_DP = 80
        internal const val CLOSE_ZONE_HIT_RADIUS_DP = 80

        // Two taps within this window repeat the last lens action — chosen
        // to be short enough that an accidental "tap, then deliberate second
        // tap a half-second later" isn't misread as a double-tap.
        private const val DOUBLE_TAP_WINDOW_MS = 280L

        // "Hide bubble to screenshot" — how long the bubble stays hidden
        // before auto-returning. 5 s is enough to trigger the system
        // screenshot (key combo / 3-finger swipe) without the bubble being
        // gone long enough to feel lost.
        internal const val SCREENSHOT_HIDE_MS = 5000L

        /**
         * Static reader for the /features language catalog Dart mirrors to
         * `flutter.tk_lang_catalog` (JSON `[{code,label}, …]`). Static so BOTH
         * the bubble (instance, with its own cache via [readCatalogFromPrefs])
         * AND the keyboard (TransKeyIME, a separate service that can't call
         * instance methods) resolve the SAME server catalog — otherwise the
         * keyboard picker falls back to the short hardcoded list. Returns null
         * when the pref is absent (pre-login first-run, /features failed).
         */
        fun parseLangCatalog(
            prefs: android.content.SharedPreferences,
        ): Pair<List<String>, Map<String, String>>? {
            val raw = prefs.getString("flutter.tk_lang_catalog", null)
                ?.takeIf { it.isNotBlank() } ?: return null
            return try {
                val arr = org.json.JSONArray(raw)
                val codes = mutableListOf<String>()
                val labels = mutableMapOf<String, String>()
                for (i in 0 until arr.length()) {
                    val obj = arr.getJSONObject(i)
                    val code = obj.optString("code").takeIf { it.isNotBlank() } ?: continue
                    labels[code] = obj.optString("label").takeIf { it.isNotBlank() } ?: code
                    codes.add(code)
                }
                if (codes.isEmpty()) null else Pair(codes, labels)
            } catch (e: Throwable) {
                android.util.Log.w("TKBubble", "lang catalog parse failed: ${e.message}")
                null
            }
        }

        /** Full target-language list: server catalog, else hardcoded fallback. */
        fun effectiveTargetLangs(prefs: android.content.SharedPreferences): List<String> =
            parseLangCatalog(prefs)?.first ?: TARGET_LANGS

        /** Full source list (auto + catalog), else hardcoded fallback. */
        fun effectiveSourceLangs(prefs: android.content.SharedPreferences): List<String> =
            parseLangCatalog(prefs)?.first?.let { listOf("auto") + it } ?: SOURCE_LANGS

        /** Labels: built-in (for the Auto sentinel) overlaid with catalog labels. */
        fun effectiveLangLabels(prefs: android.content.SharedPreferences): Map<String, String> =
            parseLangCatalog(prefs)?.second?.let { LANG_LABELS + it } ?: LANG_LABELS

        @Volatile private var nextRequestId: Long = 0
    }

    // ─── Localization ───────────────────────────────────────────────────
    // The Flutter app lets the user pick a UI language independently of the
    // Android system locale; the choice is persisted to SharedPreferences
    // (`tk_ui_locale`). The bubble service is native code, so `getString()`
    // by default reads from the *system* locale — meaning the popup stays
    // English even after the user switched the app to Vietnamese.
    //
    // We work around this by wrapping `getString` in `localized()` which
    // resolves resources through a locale-aware Context built from the
    // user's stored preference. The Context is refreshed every time a popup
    // opens (`refreshLocale()`) so changes propagate without restarting the
    // service.
    internal var localizedContext: Context? = null
    private var lastLocaleCode: String? = null

    internal fun refreshLocale() {
        // Match Flutter's LocaleNotifier default ('en') when the user hasn't
        // picked a UI language yet. Falling back to the *device* locale here
        // would put the popup in e.g. Vietnamese on a Vietnamese phone while
        // the Flutter app shows English — visibly inconsistent on first run.
        val code = prefs.getString("flutter.tk_ui_locale", null) ?: "en"
        if (code == lastLocaleCode && localizedContext != null) return
        lastLocaleCode = code
        val locale = Locale.forLanguageTag(code)
        val config = android.content.res.Configuration(resources.configuration)
        config.setLocale(locale)
        localizedContext = createConfigurationContext(config)
    }

    internal fun localized(@androidx.annotation.StringRes resId: Int): String =
        (localizedContext ?: this).getString(resId)

    internal fun localized(@androidx.annotation.StringRes resId: Int, vararg args: Any): String =
        (localizedContext ?: this).getString(resId, *args)

    internal fun modeLabel(mode: String): String =
        MODE_STRING_IDS[mode]?.let { localized(it) } ?: mode

    internal fun modeIcon(mode: String): Int =
        MODE_ICON_IDS[mode] ?: R.drawable.ic_bubble_translate

    internal var windowManager: WindowManager? = null

    // Bubble icon (small floating button)
    internal var bubbleView: View? = null
    private var bubbleIcon: ImageView? = null
    private var badgeText: TextView? = null
    private var currentState: String = STATE_IDLE

    // Drag-to-close target shown while dragging the bubble
    internal var closeZoneView: View? = null
    internal var closeZoneIcon: TextView? = null
    internal var isOverCloseZone: Boolean = false

    // Floating result panel — see ResultPanel for field doc. When
    // `panel.fullscreen` is true, layout params switch to
    // MATCH_PARENT × MATCH_PARENT. Otherwise height defaults to
    // WRAP_CONTENT until the user drags the bottom handle; then
    // `panel.heightPx > 0` pins a custom height. `panel.sourceExpanded`
    // toggles between
    // collapsed (3 lines + ellipsis) and full text so the user can
    // line up source ↔ translation side by side.
    internal val panel = ResultPanel()
    // panel.langChip / panel.detectedLangTv / panel.sourceLangChip / panel.toneChip /
    // panel.loadingSpinner moved into ResultPanel (header chips + spinner).
    /**
     * One column entry in the result panel's mode-tab row. Matches the
     * bubble picker's column style: icon on top, label below, weight=1
     * across the row, primary-coloured background for the active mode.
     */
    // PanelModeTab data class + panel.modeButtons map moved into ResultPanel.
    internal var currentMode: String = MODE_TRANSLATE
    internal var currentSourceText: String? = null
    internal var currentOutput: String? = null
    internal var currentRomanization: String? = null
    internal var currentDetectedLang: String? = null
    // Bilingual quick-reply suggestions: first = source (reply text in the
    // conversation partner's language, copied on tap), second = target (the
    // same message in the user's target language, shown as a translation hint).
    internal var currentSuggestions: List<Pair<String, String>> = emptyList()
    // Fraud warning for the current result (null = safe / cleared).
    internal var currentScam: ScamInfo? = null
    internal var currentTargetLang: String = "en"
    private var currentRequestId: Long = -1

    // Per-translation settings (read from SharedPreferences)
    internal var currentSourceLang: String = "auto"
    internal var currentTone: String = ""

    // Translation in-progress guard (prevents spam clicks)
    internal var isTranslating = false

    // panel.sourceLangChip + panel.toneChip + panel.loadingSpinner: see ResultPanel.
    // The header chip used to be a tone-label TextView; it's now an
    // ImageView gear icon that opens the settings sheet — clearer
    // affordance for the bubble-side preferences (translate tone, reply
    // tone, TTS rate, romanization, suggestions).

    // Mode picker overlay (shown when bubble tapped)
    internal var modePickerView: View? = null
    internal var pendingPickerText: String? = null

    // Language picker overlays
    internal var langPickerView: View? = null
    internal var sourceLangPickerView: View? = null

    // Tone picker overlay
    internal var tonePickerView: View? = null

    // Text-input picker overlay (lets user type text without opening the app)
    // This window is FOCUSABLE — unlike the other pickers — so the soft
    // keyboard can attach to its EditText.
    internal var inputPickerView: View? = null

    // Voice-input picker overlay. Active SpeechRecognizer session and the
    // TextView we stream partial results into. Held here so onDestroy /
    // stopBubble can release the recognizer's audio focus.
    internal var voicePickerView: View? = null
    internal var voiceHelper: VoiceRecognitionHelper? = null
    internal var voiceTranscriptView: TextView? = null
    internal var voiceStatusView: TextView? = null
    internal var voiceMicIcon: TextView? = null

    // First-run disclosure overlay shown before the "Scan screen" / OCR flow
    // (MediaProjection) — explains what gets captured and where it goes.
    internal var scanDisclosureView: View? = null
    // Mode chooser shown after the user taps "Scan" or "Region" in the
    // bubble picker — lets them pick Translate (Lens overlay) vs Summarize
    // (text panel) before the screen capture grant kicks in.
    internal var scanModeChooserView: View? = null

    // Lens flow overlays. The progress card sits over the source app while
    // batch-translate is in flight; the LensOverlayView is the full-screen
    // bitmap + translated chips that replaces it on success. Both held so
    // lifecycle hooks can tear them down on stopBubble / onDestroy.
    internal var lensProgressView: View? = null
    internal var lensOverlayView: LensOverlayView? = null
    // Last Lens scan's inputs, kept so a source-mismatch banner tap can
    // re-run translation with the detected language WITHOUT re-capturing
    // or re-OCR'ing the screen.
    internal var lensTexts: List<String>? = null
    internal var lensTarget: String? = null
    // "Reopen last result" cache: when the user dismisses the overlay we
    // keep the screenshot + finished chips around briefly so an accidental
    // tap-to-close can be undone instantly (no re-capture / OCR / LLM).
    // The bitmap is OWNED here once detached from ScreenCaptureManager —
    // we recycle it in [discardLensCache].
    internal var lastLensBitmap: Bitmap? = null
    internal var lastLensItems: List<LensOverlayView.Item>? = null
    internal var reopenPillView: View? = null
    internal var reopenDismissRunnable: Runnable? = null
    // Tappable "re-grant for this app" pill shown when a single-app
    // MediaProjection grant couldn't capture the now-foreground app. The
    // re-consent MUST be launched from inside a user tap (MIUI aborts
    // background activity starts from a timer), so we surface this pill and
    // let the tap drive the fresh consent.
    internal var regrantPillView: View? = null
    // Full-translation popup opened by tapping a Lens chip.
    internal var lensDetailView: View? = null

    // Rubber-band region selector shown when user picks the "Translate
    // selected area" entry — sits between MediaProjection capture and OCR.
    private var regionSelectionView: RegionSelectionView? = null

    // Speaker language picked for the current voice session. Read fresh
    // from prefs (KEY_VOICE_LANG) each time the picker opens; mutated when
    // the user taps a different lang pill, which also persists + restarts
    // the recognizer with the new BCP-47 tag.
    internal var currentVoiceLang: String = "en"

    // Text-to-Speech
    private var tts: TextToSpeech? = null
    private var ttsReady = false

    // Bubble drag state
    internal var initialX = 0
    internal var initialY = 0
    internal var initialTouchX = 0f
    internal var initialTouchY = 0f
    internal var isDragging = false

    // Delayed snap-to-half-hidden (Messenger chat-head idle). Set by
    // [scheduleBubbleHalfHide] after the user releases the bubble and
    // cleared when the user touches it again or any popup is open.
    internal var bubbleHalfHideRunnable: Runnable? = null

    // Long-press bubble → open app home screen.
    internal var longPressFired = false
    internal val longPressRunnable = Runnable {
        longPressFired = true
        resetIdleTimer()
        val intent = Intent(this, MainActivity::class.java).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        }
        startActivity(intent)
    }

    // Idle auto-stop: stop the bubble after N minutes of no interaction.
    // Default 10 min. Read from SharedPrefs so the Flutter settings screen
    // can change it without a MethodChannel round-trip.
    private val idleAutoStopMs: Long
        get() = prefs.getInt("flutter.tk_bubble_idle_minutes", 10).coerceIn(0, 120).toLong() * 60_000L
    private val idleAutoStopRunnable = Runnable {
        if (idleAutoStopMs > 0) {
            android.util.Log.w("TKBubble", "bubble idle ${idleAutoStopMs / 60_000} min reached — stopping")
            stopBubble()
        }
    }

    /** Reset the idle auto-stop timer. Call on every user interaction. */
    internal fun resetIdleTimer() {
        handler.removeCallbacks(idleAutoStopRunnable)
        if (idleAutoStopMs > 0) {
            handler.postDelayed(idleAutoStopRunnable, idleAutoStopMs)
        }
    }

    // Double-tap → repeat last lens action (skip menu). Remembered for the
    // lifetime of the bubble session; cleared when the bubble stops.
    private data class LastLensAction(val regionMode: Boolean, val mode: String)
    private var lastLensAction: LastLensAction? = null
    private var lastBubbleTapTime: Long = 0L

    internal val handler = Handler(Looper.getMainLooper())

    // Lazy so the first access creates it (after the service Context is
    // attached); subsequent reads return the same instance. Replaces 30+
    // inline `getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)` calls
    // scattered through read*/write* settings helpers.
    internal val prefs by lazy { getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE) }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        isAlive = true
        createBubbleNotificationChannel()
        // On Android 14+ a FGS that captures mic must declare the microphone
        // type at startForeground time; declaring it only in the manifest is
        // not enough. Start with specialUse only — `enterMicrophoneFgs()`
        // escalates to specialUse|microphone right before SpeechRecognizer
        // listens and `leaveMicrophoneFgs()` drops back, so we don't hold
        // mic-typed FGS while idle (Play policy: only claim what's in use).
        if (Build.VERSION.SDK_INT >= 34) {
            startForeground(
                NOTIFICATION_ID,
                buildBubbleNotification(),
                ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE,
            )
        } else {
            startForeground(NOTIFICATION_ID, buildBubbleNotification())
        }
        tts = TextToSpeech(this) { status -> ttsReady = (status == TextToSpeech.SUCCESS) }

        // Pre-warm the Latin ML Kit recognizer so the first Lens scan doesn't
        // pay the ~100-200 ms TFLite model-load cold start. A 4×4 dummy bitmap
        // is enough to trigger the model initialisation; it's released right
        // after. ML Kit caches the model internally, so subsequent real scans
        // start at full speed. Run on a background thread — never block onCreate.
        Thread {
            try {
                val dummy = android.graphics.Bitmap.createBitmap(
                    4, 4, android.graphics.Bitmap.Config.ARGB_8888,
                )
                OcrHelper.warmUp(dummy)
            } catch (e: Throwable) {
                android.util.Log.w("TKBubble", "ML Kit warm-up failed: ${e.message}")
            }
        }.start()
    }

    /**
     * Escalate the FGS type to include `microphone` so SpeechRecognizer can
     * capture audio while another app is foreground. No-op below Android 14
     * where the type-enforcement was not yet introduced. Idempotent —
     * safe to call multiple times for the same picker session.
     */
    internal fun enterMicrophoneFgs() {
        if (Build.VERSION.SDK_INT < 34) return
        startForeground(
            NOTIFICATION_ID,
            buildBubbleNotification(),
            ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE
                or ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE,
        )
    }

    /**
     * Drop back to specialUse-only after the voice picker is dismissed.
     * Called from `cancelVoice()` / `hideVoicePicker()` teardown paths.
     */
    internal fun leaveMicrophoneFgs() {
        if (Build.VERSION.SDK_INT < 34) return
        startForeground(
            NOTIFICATION_ID,
            buildBubbleNotification(),
            ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE,
        )
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        // System-restart case (intent is null because START_STICKY redelivers
        // without the original intent). The OS killed us — typically while the
        // mediaProjection FGS was also alive and the user backgrounded the
        // app, after which Android reclaimed memory. Re-show the bubble so
        // the user doesn't have to manually toggle it off and on; we know
        // they wanted it on because saveBubbleActive(true) was persisted.
        if (intent == null) {
            val prefs = prefs
            if (prefs.getBoolean(KEY_BUBBLE_ACTIVE, false) && bubbleView == null) {
                showBubble()
            }
            return START_STICKY
        }
        when (intent.action) {
            ACTION_STOP -> {
                stopBubble()
                return START_NOT_STICKY
            }
            ACTION_SET_STATE -> {
                val state = intent.getStringExtra(EXTRA_STATE) ?: return START_NOT_STICKY
                setState(state)
            }
            ACTION_START -> {
                showBubble()
            }
            ACTION_TRANSLATE -> {
                val text = intent.getStringExtra(EXTRA_TEXT)
                val mode = intent.getStringExtra(EXTRA_MODE) ?: MODE_TRANSLATE
                val error = intent.getStringExtra(EXTRA_ERROR)
                if (!text.isNullOrBlank()) {
                    handleTranslateRequest(text, mode)
                } else if (!error.isNullOrBlank()) {
                    showResultPanel(loading = false, error = error)
                    setState(STATE_ERROR)
                }
            }
            ACTION_SHOW_RESULT -> {
                val translation = intent.getStringExtra(EXTRA_TRANSLATION)
                val romanization = intent.getStringExtra(EXTRA_ROMANIZATION)
                val detectedLang = intent.getStringExtra(EXTRA_DETECTED_LANG)
                val sources = intent.getStringArrayExtra(EXTRA_SUGGESTION_SOURCES)
                val targets = intent.getStringArrayExtra(EXTRA_SUGGESTION_TARGETS)
                val suggestions: List<Pair<String, String>> =
                    if (sources != null && targets != null) {
                        val n = minOf(sources.size, targets.size)
                        (0 until n).map { sources[it] to targets[it] }
                            .filter { it.first.isNotBlank() || it.second.isNotBlank() }
                    } else emptyList()
                val error = intent.getStringExtra(EXTRA_ERROR)
                val scam = ScamInfo.of(
                    intent.getStringExtra(EXTRA_SCAM_LEVEL),
                    intent.getStringExtra(EXTRA_SCAM_TYPE),
                    intent.getStringExtra(EXTRA_SCAM_REASON),
                )
                val reqId = intent.getLongExtra(EXTRA_REQUEST_ID, -1)
                if (reqId == currentRequestId) {
                    if (!translation.isNullOrBlank()) {
                        showResult(translation, romanization, detectedLang, suggestions, scam)
                    } else {
                        showError(error ?: localized(R.string.bubble_panel_translation_failed))
                    }
                }
            }
            ACTION_HIDE_PANEL -> hideResultPanel()
            ACTION_START_VOICE -> showVoicePicker(MODE_TRANSLATE)
            ACTION_DELIVER_OCR -> {
                val text = intent.getStringExtra(EXTRA_TEXT)
                val mode = intent.getStringExtra(EXTRA_MODE) ?: MODE_TRANSLATE
                handleOcrResult(text, mode)
            }
            ACTION_DELIVER_LENS -> handleLensReady()
            ACTION_DELIVER_REGION_READY -> handleRegionReady()
            ACTION_DELIVER_LENS_CHUNK -> {
                val startIdx = intent.getIntExtra(EXTRA_LENS_CHUNK_START, -1)
                val translations = intent.getStringArrayExtra(EXTRA_LENS_CHUNK_TRANSLATIONS)
                if (startIdx >= 0 && translations != null) {
                    lensOverlayView?.applyTranslations(startIdx, translations.toList())
                }
            }
            ACTION_DELIVER_LENS_MISMATCH -> {
                val detected = intent.getStringExtra(EXTRA_LENS_MISMATCH_DETECTED)
                if (!detected.isNullOrBlank()) {
                    val detectedLabel = getEffectiveLangLabels()[detected] ?: detected
                    lensOverlayView?.showSourceMismatch(
                        localized(R.string.lens_source_mismatch, detectedLabel),
                    ) { retranslateLens(detected) }
                }
            }
            ACTION_SCAN_CANCELLED -> {
                // User dismissed the system consent dialog — just put the
                // bubble back. Manager state is also cleared so the next
                // scan starts from scratch (no stale token reuse path).
                ScreenCaptureManager.clearAll()
                restoreBubbleVisibility()
            }
            ACTION_RECONSENT -> {
                // Single-app grant couldn't capture the current foreground
                // app (user switched apps + pressed capture). The capture
                // service already stopped its projection. Bring the bubble
                // back and float a pill the user taps to grant the app
                // they're on — launching consent from that tap satisfies
                // MIUI's background-activity-start grace, which a timer
                // launch does not.
                restoreBubbleVisibility()
                showRegrantPill()
            }
        }
        return START_STICKY
    }

    override fun onDestroy() {
        isAlive = false
        // Drop every queued postDelayed before we tear views down — the
        // pending Flutter-translate retry, the IME-show kick, the voice
        // pulse, the final-result safety net, etc. would otherwise fire
        // after the service is dead and either touch nulled views or
        // re-enter a torn-down MethodChannel.
        handler.removeCallbacksAndMessages(null)
        hideModePicker()
        hideLangPicker()
        hideSourceLangPicker()
        hideTonePicker()
        hideInputPicker()
        hideVoicePicker()
        hideScanDisclosure()
        hideScanModeChooser()
        hideLensProgress()
        hideLensDetailPopup()
        hideLensOverlay()
        discardLensCache()
        hideRegrantPill()
        hideRegionSelectionView()
        releaseScreenCapture()
        hideCloseZone()
        tts?.stop(); tts?.shutdown(); tts = null
        removeBubble()
        removeResultPanel()
        super.onDestroy()
    }

    // ── Notification ──

    // ── Bubble (small floating button) ──

    @SuppressLint("ClickableViewAccessibility")
    private fun showBubble() {
        if (bubbleView != null) return
        resetIdleTimer()
        ensureWindowManager()
        val dp = resources.displayMetrics.density
        val bubbleSize = (BUBBLE_SIZE_DP * dp).toInt()

        val container = FrameLayout(this).apply {
            layoutParams = FrameLayout.LayoutParams(bubbleSize, bubbleSize)
            // Coloured ring frames the logo and changes by state.
            background = GradientDrawable().apply {
                shape = GradientDrawable.OVAL
                setColor(Color.TRANSPARENT)
                setStroke((2 * dp).toInt(), Palette.ACCENT)
            }
            clipToOutline = true
            outlineProvider = object : android.view.ViewOutlineProvider() {
                override fun getOutline(view: View, outline: android.graphics.Outline) {
                    outline.setOval(0, 0, view.width, view.height)
                }
            }
            elevation = 8 * dp
        }

        // Logo fills the entire bubble — circular clip applied via container outline.
        bubbleIcon = ImageView(this).apply {
            setImageResource(R.mipmap.ic_launcher)
            scaleType = ImageView.ScaleType.CENTER_CROP
            layoutParams = FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT,
                Gravity.CENTER,
            )
        }

        // Status badge (top-right). Has its own coloured chip background.
        badgeText = TextView(this).apply {
            text = ""
            setTextColor(Color.WHITE)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 10f)
            typeface = Typeface.DEFAULT_BOLD
            gravity = Gravity.CENTER
            visibility = View.GONE
            background = GradientDrawable().apply {
                shape = GradientDrawable.OVAL
                setColor(Palette.ACCENT)
                setStroke((1.5f * dp).toInt(), Color.WHITE)
            }
            layoutParams = FrameLayout.LayoutParams(
                (18 * dp).toInt(), (18 * dp).toInt(), Gravity.END or Gravity.TOP,
            ).apply { setMargins(0, (-2 * dp).toInt(), (-2 * dp).toInt(), 0) }
        }

        container.addView(bubbleIcon)
        container.addView(badgeText)

        bubbleView = container
        windowManager?.addView(container, buildBubbleLayoutParams())

        container.setOnTouchListener { _, event -> handleBubbleTouch(event, dp) }
        saveBubbleActive(true)
        // Settle into the Messenger-style idle: shortly after creation
        // peek half-hidden against the closest edge.
        scheduleBubbleHalfHide(dp)
    }

    // Bubble touch + drag-to-close logic lives in BubbleDragHandling.kt
    // (extension on BubbleService) so this file stays focused on lifecycle
    // and intent routing.

    /**
     * Bubble tap:
     *  - picker showing      → dismiss picker
     *  - panel showing       → hide panel
     *  - otherwise           → show mode picker (cached result is reachable via
     *                          the "Show last result" shortcut inside the picker)
     *
     * NOTE: Android 10+ blocks clipboard reads from background services.
     * Clipboard is read inside ShareActivity (foreground) when user picks a mode.
     */
    internal fun onBubbleTapped() {
        resetIdleTimer()
        // Double-tap detect: two taps within DOUBLE_TAP_WINDOW_MS repeat the
        // last lens (screenshot-translate / region-translate) action so the
        // user doesn't have to walk Menu → Lens → Translate every time when
        // scanning a chat thread back-to-back. Only fires when a lens action
        // has been used this bubble session — otherwise there's nothing to
        // repeat and the tap falls through to normal menu/panel behaviour.
        val now = SystemClock.uptimeMillis()
        val sinceLastTap = now - lastBubbleTapTime
        val cached = lastLensAction
        if (sinceLastTap < DOUBLE_TAP_WINDOW_MS && cached != null) {
            lastBubbleTapTime = 0L
            // The first tap may have opened/closed something; clean up so the
            // capture pipeline doesn't paint into a stale overlay.
            if (modePickerView != null) hideModePicker()
            if (panel.view != null) hideResultPanel()
            // Re-check the plan gate before repeating. lastLensAction may have
            // been cached while the user was entitled, then their `lens` flag
            // flipped to false (trial expiry / downgrade / server toggle) while
            // this bubble session kept the cache alive. The mode picker locks
            // the Lens row correctly, but double-tap bypasses the picker — so
            // gate here too, else a now-free user re-runs a full capture+OCR
            // (the server 403s the translate, but the MediaProjection + OCR
            // work still fires). Locked → drop the stale cache and surface the
            // upsell instead of scanning, matching the picker's behaviour.
            if (!readFeatureEnabled("tk_feature_lens")) {
                lastLensAction = null
                openFeatureUpsell("Lens")
                return
            }
            android.util.Log.w("TKBubble", "bubble double-tap: repeating lens region=${cached.regionMode} mode=${cached.mode}")
            if (cached.regionMode) handleLensRegionRequest(cached.mode)
            else handleScanRequest(cached.mode)
            return
        }
        lastBubbleTapTime = now

        when {
            modePickerView != null -> { hideModePicker(); return }
            panel.view != null      -> { hideResultPanel(); return }
        }
        // Per the feature spec, the bubble-tap path is exclusively for
        // CLIPBOARD-driven input — the user has copied (or is about to)
        // and now picks an action. OCR / Region / Voice / Read-screen
        // are reached via their own picker rows; system Share and
        // ACTION_PROCESS_TEXT enter through ShareActivity directly.
        // So the bubble-tap itself never inspects accessibility state —
        // it just opens the picker.
        android.util.Log.w("TKBubble", "bubble-tap: opening picker")
        showModePicker()
    }

    private fun buildBubbleLayoutParams(): WindowManager.LayoutParams {
        val dp = resources.displayMetrics.density
        val bubbleSize = (BUBBLE_SIZE_DP * dp).toInt()
        return WindowManager.LayoutParams(
            bubbleSize, bubbleSize,
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
                WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
            else @Suppress("DEPRECATION") WindowManager.LayoutParams.TYPE_PHONE,
            // FLAG_LAYOUT_NO_LIMITS lets us push the bubble's x past
            // the screen edge so it can peek half-hidden (Messenger
            // chat-head idle). Without it Android clamps x to 0 / sw -
            // bubbleSize and the bubble stays fully on-screen no matter
            // what we set.
            //
            // NB: do NOT add FLAG_SECURE to hide the bubble from the user's
            // screenshots — on MIUI a FLAG_SECURE window in the stack makes
            // the system REFUSE the whole screenshot ("can't capture, blocked
            // by security policy"), not just omit the bubble. Tested on the
            // user's device 2026-05-29. Screenshot exclusion of the bubble
            // has to be done another way (detect + briefly hide).
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS,
            PixelFormat.TRANSLUCENT,
        ).apply {
            gravity = Gravity.TOP or Gravity.START
            x = 0
            y = 300
        }
    }

    // Drag-to-close target lives in BubbleDragHandling.kt.

    /**
     * Mode-picker button handler. Per the feature spec, source text
     * always comes from explicit user actions (Copy / OCR / Region /
     * Share / Menu) — we no longer snapshot accessibility-selection
     * events. Routes the request to ShareActivity, which is the only
     * component allowed to read primaryClip on Android 10+ (background
     * services are blocked). ShareActivity reads the clipboard and
     * forwards the text back via ACTION_TRANSLATE; if the clipboard
     * is empty it surfaces the "Copy text first" toast.
     */

    private fun readClipboardText(): String? {
        return try {
            val cm = getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
            cm.primaryClip?.takeIf { it.itemCount > 0 }
                ?.getItemAt(0)?.coerceToText(this)?.toString()?.trim()
        } catch (_: Exception) { null }
    }

    // ── State management ──

    fun setState(state: String) {
        currentState = state
        handler.post { updateBubbleVisuals() }
    }

    private fun updateBubbleVisuals() {
        val view = bubbleView ?: return
        val dp = resources.displayMetrics.density
        when (currentState) {
            STATE_IDLE -> {
                (view.background as? GradientDrawable)?.setStroke(
                    (2 * dp).toInt(), Palette.ACCENT,
                )
                view.alpha = 0.95f
                badgeText?.visibility = View.GONE
            }
            STATE_LOADING -> {
                (view.background as? GradientDrawable)?.setStroke(
                    (2.5f * dp).toInt(), Palette.ACCENT,
                )
                view.alpha = 1.0f
                badgeText?.apply {
                    text = "…"
                    visibility = View.VISIBLE
                    (background as? GradientDrawable)?.setColor(Palette.ACCENT)
                }
            }
            STATE_RESULT -> {
                (view.background as? GradientDrawable)?.setStroke(
                    (2.5f * dp).toInt(), Color.parseColor("#43E97B"),
                )
                view.alpha = 1.0f
                badgeText?.apply {
                    text = "✓"
                    visibility = View.VISIBLE
                    (background as? GradientDrawable)?.setColor(Color.parseColor("#43E97B"))
                }
            }
            STATE_ERROR -> {
                (view.background as? GradientDrawable)?.setStroke(
                    (2.5f * dp).toInt(), Color.parseColor("#FF6B6B"),
                )
                view.alpha = 1.0f
                badgeText?.apply {
                    text = "!"
                    visibility = View.VISIBLE
                    (background as? GradientDrawable)?.setColor(Color.parseColor("#FF6B6B"))
                }
            }
        }
    }

    // ── Result panel ──

    internal fun handleTranslateRequest(text: String, mode: String) {
        // Plan gate at the dispatch chokepoint. Every surface that lets the
        // user pick a mode funnels through here (result-panel mode tabs, the
        // type/voice input picker, and re-translate after a tone/lang change).
        // The mode picker locks paid modes visually, but those other surfaces
        // don't — so without this guard a free user could reach Summarize /
        // Explain / Refine / Reply directly. Gate here as the single source of
        // truth; the picker flow only ever forwards an already-unlocked mode so
        // it never double-prompts. TRANSLATE has no gate (always free).
        modeGateFor(mode)?.let { gate ->
            if (!readFeatureEnabled(gate.prefsKey)) {
                openFeatureUpsell(gate.displayName)
                return
            }
        }
        android.util.Log.w("TKBubble", "handleTranslateRequest: mode=$mode textLen=${text.length} preview='${text.take(60).replace("\n", "⏎")}'")
        isTranslating = true
        currentSourceText = text
        currentOutput = null
        currentRomanization = null
        currentDetectedLang = null
        currentSuggestions = emptyList()
        currentScam = null
        currentMode = mode

        currentTargetLang = readTargetLang()
        currentSourceLang = readSourceLang()
        currentTone = readTone()
        val reqId = ++nextRequestId
        currentRequestId = reqId
        showResultPanel(loading = true, error = null)
        val eng = TransKeyApp.engine
        if (eng != null) {
            invokeFlutterTranslate(eng, text, mode, currentTargetLang, reqId, replyToOriginal = null, attempt = 0)
        } else {
            showError(localized(R.string.bubble_panel_app_not_ready))
        }
    }

    internal fun readTargetLang(): String {
        return prefs.getString(KEY_TARGET_LANG, "en") ?: "en"
    }

    internal fun writeTargetLang(lang: String) {
        prefs
            .edit()
            .putString(KEY_TARGET_LANG, lang)
            .apply()
        notifyFlutterLangChanged()
    }

    /**
     * Push a "langChanged" notification down the bubble MethodChannel so the
     * Flutter side's languageSettingsProvider re-reads SharedPreferences
     * immediately instead of waiting for the next `didChangeAppLifecycleState
     * .resumed` cycle. Without this, the in-app language bar stays stale
     * while the user is actively switching between the bubble overlay and
     * the home tab — they'd think the change didn't take effect.
     *
     * No-op if Flutter engine isn't up yet (cold start). The Dart-side
     * pref-reload on resume is the safety net for that case.
     */
    private fun notifyFlutterLangChanged() {
        val engine = TransKeyApp.engine ?: return
        try {
            io.flutter.plugin.common.MethodChannel(
                engine.dartExecutor.binaryMessenger, METHOD_CHANNEL,
            ).invokeMethod("langChanged", null)
        } catch (e: Exception) {
            android.util.Log.w("TKBubble", "notifyFlutterLangChanged failed: ${e.message}")
        }
    }

    /**
     * Invoke Flutter's translateText with retry, since the Dart isolate might
     * not have registered its MethodCallHandler yet on a cold start.
     */
    private fun invokeFlutterTranslate(
        engine: io.flutter.embedding.engine.FlutterEngine,
        text: String,
        mode: String,
        targetLang: String,
        reqId: Long,
        replyToOriginal: String?,
        attempt: Int,
    ) {
        val channel = io.flutter.plugin.common.MethodChannel(
            engine.dartExecutor.binaryMessenger, METHOD_CHANNEL,
        )
        val args = mutableMapOf<String, Any?>(
            "text" to text,
            "mode" to mode,
            "targetLang" to targetLang,
            "requestId" to reqId,
        )
        if (replyToOriginal != null) {
            args["replyToOriginal"] = replyToOriginal
        }
        channel.invokeMethod(
            "translateText",
            args,
            object : io.flutter.plugin.common.MethodChannel.Result {
                override fun success(result: Any?) { /* Flutter will call back via deliverResult */ }
                override fun error(code: String, msg: String?, details: Any?) {
                    if (reqId != currentRequestId) return
                    showError(msg ?: "${localized(R.string.bubble_panel_translation_failed)} ($code)")
                }
                override fun notImplemented() {
                    if (attempt < 5 && reqId == currentRequestId) {
                        handler.postDelayed({
                            invokeFlutterTranslate(engine, text, mode, targetLang, reqId, replyToOriginal, attempt + 1)
                        }, 300L)
                    } else if (reqId == currentRequestId) {
                        showError(localized(R.string.bubble_panel_app_not_ready))
                    }
                }
            },
        )
    }


    // togglePanelSourceExpanded / applyPanelSourceExpansion /
    // refreshPanelSourceToggle / applyPanelLayoutMode / removeResultPanel
    // moved to ResultPanelExtensions.kt

    internal fun speakOutput() {
        val engine = tts ?: return
        // Tap-to-stop toggle: if the engine is already mid-utterance, the
        // user pressed the button to interrupt — kill playback instead of
        // restarting it. Without this, the only way to stop was to wait
        // out the full read (or close the panel) because QUEUE_FLUSH just
        // restarts the same audio from the top.
        if (engine.isSpeaking) {
            engine.stop()
            return
        }
        val text = currentOutput?.takeIf { it.isNotEmpty() } ?: return
        if (!ttsReady) { Toast.makeText(this, localized(R.string.bubble_panel_tts_not_ready), Toast.LENGTH_SHORT).show(); return }
        val locale = langToLocale(currentTargetLang)
        engine.language = locale
        // Match the speed the user picked inside the app's Settings →
        // Read aloud. Flutter writes it via shared_preferences as
        // flutter.tk_tts_rate (double). Default to normal speed when unset.
        val rate = readTtsRate().toFloat()
        engine.setSpeechRate(rate)
        @Suppress("DEPRECATION")
        engine.speak(text, TextToSpeech.QUEUE_FLUSH, null)
    }

    internal fun readTtsRate(): Double {
        // shared_preferences's encoding for doubles has changed across
        // plugin versions — sometimes Float, sometimes a String-encoded
        // Double, sometimes prefixed via the legacy codec. Read through
        // prefs.all and accept any numeric / string representation.
        // 1.0 = normal speed. The OS TextToSpeech engine treats 1.0 as normal,
        // and the in-app flutter_tts path persists the same user-facing
        // multiplier, so the bubble feeds this value to the engine as-is (no
        // ×0.5 conversion, unlike the flutter_tts path) and both sound the same.
        return when (val v = prefs.all["flutter.tk_tts_rate"]) {
            is Number -> v.toDouble()
            is String -> v.toDoubleOrNull() ?: 1.0
            else -> 1.0
        }
    }

    private fun langToLocale(lang: String): Locale = when (lang) {
        "en" -> Locale.ENGLISH
        "vi" -> Locale("vi")
        "ja" -> Locale.JAPANESE
        "zh" -> Locale.CHINESE
        "ko" -> Locale.KOREAN
        "fr" -> Locale.FRENCH
        "de" -> Locale.GERMAN
        "es" -> Locale("es")
        "pt" -> Locale("pt")
        "ru" -> Locale("ru")
        "th" -> Locale("th")
        "id" -> Locale("in")
        else -> Locale.ENGLISH
    }

    // ── Prefs helpers ──

    private fun saveBubbleActive(active: Boolean) {
        prefs.edit()
            .putBoolean(KEY_BUBBLE_ACTIVE, active).apply()
        // Push the new state down to Flutter so the in-app Settings toggle
        // reflects it immediately, regardless of which path flipped the
        // bubble: keyboard-setup auto-start, drag-to-close, notification
        // "Turn off", system restart. Without this, the Dart side has to
        // poll isRunning() at navigation boundaries, and any flow we
        // forget to instrument silently leaves the toggle stale.
        notifyFlutterBubbleState(active)
    }

    private fun notifyFlutterBubbleState(active: Boolean) {
        val engine = TransKeyApp.engine ?: return
        try {
            io.flutter.plugin.common.MethodChannel(
                engine.dartExecutor.binaryMessenger, METHOD_CHANNEL,
            ).invokeMethod("bubbleStateChanged", active)
        } catch (e: Exception) {
            android.util.Log.w("TKBubble", "notifyFlutterBubbleState failed: ${e.message}")
        }
    }

    internal fun readSourceLang(): String {
        return prefs.getString(KEY_SOURCE_LANG, "auto") ?: "auto"
    }

    internal fun writeSourceLang(lang: String) {
        prefs.edit()
            .putString(KEY_SOURCE_LANG, lang).apply()
        notifyFlutterLangChanged()
    }

    /**
     * Effective language catalog for the bubble pickers. Reads the
     * mirror of /features languages that [FeaturesNotifier.fetch] wrote
     * to `flutter.tk_lang_catalog` (JSON `[{code,label}, …]`), so the
     * bubble shows the SAME enabled languages as the home tab without
     * needing a MethodChannel round-trip per picker open. Falls back to
     * the hardcoded [TARGET_LANGS] / [LANG_LABELS] when the catalog
     * pref is missing (pre-login first-run, /features failed, etc.).
     *
     * Cached on the service instance so the JSON parse only happens
     * once per bubble session — pickers open frequently.
     */
    private var cachedCatalog: Pair<List<String>, Map<String, String>>? = null

    private fun readCatalogFromPrefs(): Pair<List<String>, Map<String, String>>? {
        cachedCatalog?.let { return it }
        return parseLangCatalog(prefs)?.also { cachedCatalog = it }
    }

    internal fun getEffectiveTargetLangs(): List<String> =
        readCatalogFromPrefs()?.first ?: TARGET_LANGS

    internal fun getEffectiveSourceLangs(): List<String> {
        val catalog = readCatalogFromPrefs()?.first ?: return SOURCE_LANGS
        return listOf("auto") + catalog
    }

    /**
     * Merged label lookup: server-catalog labels first (native names per
     * admin config), then the built-in LANG_LABELS for entries the
     * catalog didn't ship (the hardcoded "Auto" sentinel, mainly).
     */
    internal fun getEffectiveLangLabels(): Map<String, String> {
        val catalog = readCatalogFromPrefs()?.second ?: return LANG_LABELS
        return LANG_LABELS + catalog
    }

    internal fun readTone(): String {
        return prefs.getString(KEY_TONE_OVERRIDE, "") ?: ""
    }

    /**
     * Read the persisted speaker language for voice input. Falls back to a
     * sensible default in this order:
     *   1. Previously-chosen voice lang (persisted across sessions)
     *   2. System primary locale's ISO code (if it's one we offer)
     *   3. Translate source-lang (when not "auto")
     *   4. "en" — universal fallback
     */
    internal fun readVoiceLang(): String {
        val stored = prefs.getString(KEY_VOICE_LANG, null)
        if (!stored.isNullOrEmpty() && stored in VOICE_LANGS) return stored

        val systemLang = resources.configuration.locales.get(0).language
        if (systemLang in VOICE_LANGS) return systemLang

        val src = readSourceLang()
        if (src != "auto" && src in VOICE_LANGS) return src

        return "en"
    }

    internal fun writeVoiceLang(lang: String) {
        prefs.edit()
            .putString(KEY_VOICE_LANG, lang).apply()
    }

    internal fun writeTone(tone: String) {
        prefs.edit()
            .putString(KEY_TONE_OVERRIDE, tone).apply()
    }

    // ── Romanization / TTS rate ─────────
    // All persisted under `flutter.tk_*` prefix so Flutter's SharedPreferences
    // package reads them as the same `tk_*` keys the in-app Settings screen
    // writes to. Reading happens at app resume via appSettingsProvider.reload()
    // and ttsProvider._loadPersistedPrefs().

    internal fun readRomanization(): Boolean {
        return prefs.getBoolean(KEY_ROMANIZATION, false)
    }

    internal fun writeRomanization(value: Boolean) {
        prefs.edit()
            .putBoolean(KEY_ROMANIZATION, value).apply()
    }

    // readTtsRate() is defined above (with broader plugin-version handling) —
    // single source of truth for both the speakOutput path and settings sheet.

    internal fun writeTtsRate(rate: Double) {
        // Flutter stores doubles natively under SharedPreferences via Float
        // wrapper — but reading on the Flutter side uses getDouble which
        // accepts both. Writing as Double keeps full precision.
        prefs.edit()
            .putFloat(KEY_TTS_RATE, rate.toFloat()).apply()
    }

    internal fun toneLabel(code: String): String {
        val resId = TONE_STRING_IDS[code] ?: R.string.bubble_tone_auto
        return localized(resId)
    }

    internal fun formatRate(r: Double): String {
        // Match desktop / Flutter: "1×" instead of "1.0×".
        return if (r == r.toLong().toDouble()) "${r.toInt()}×" else "${r}×"
    }

    // ── Source language picker ──


    // ── Settings sheet ──
    // Single sheet that surfaces the 5 in-app settings the bubble cares about:
    // translate tone, reply tone, romanization, reply suggestions, TTS speed.
    // All writes go to the `flutter.tk_*` SharedPreferences keys so the
    // in-app Settings screen picks them up on resume (and vice versa — we
    // re-read every time the sheet opens).


    // ── Text input picker (type text without opening the app) ──

    /**
     * Build window params for a focusable overlay so the soft keyboard can
     * attach to an EditText. Mode/result pickers use FLAG_NOT_FOCUSABLE
     * (touch-only); this one explicitly does NOT set that flag and asks the
     * IME to appear and resize the window when it does.
     */

    /** Pulse animation runnable so we can cancel it on hide. */
    internal var voicePulseRunnable: Runnable? = null

    /** Error auto-dismiss runnable so we can cancel it on retry. */
    internal var voiceErrorRunnable: Runnable? = null

    @SuppressLint("ClickableViewAccessibility")

    internal fun handleScanRequest(mode: String = MODE_TRANSLATE) {
        // Gate a paid scan sub-mode (e.g. Summarize) BEFORE capturing, so a
        // locked feature never wastes a MediaProjection prompt + OCR. The lens
        // flag itself is gated upstream (picker row + double-tap guard);
        // TRANSLATE has no gate (always free). Don't cache a blocked action.
        modeGateFor(mode)?.let { gate ->
            if (!readFeatureEnabled(gate.prefsKey)) {
                openFeatureUpsell(gate.displayName)
                return
            }
        }
        ScreenCaptureManager.regionMode = false
        lastLensAction = LastLensAction(regionMode = false, mode = mode)
        if (prefs.getBoolean(KEY_SCAN_DISCLOSED, false)) {
            launchScanFlow(mode)
        } else {
            showScanDisclosure(mode)
        }
    }

    /**
     * Re-run the most recent scan/lens action. Used by the "re-grant for
     * this app" pill: the tap re-enters the normal scan flow, and because
     * the stale projection is already gone (isProjectionActive == false) it
     * opens a FRESH system consent — launched from inside this tap so MIUI
     * permits the activity start.
     */
    internal fun repeatLastScan() {
        val last = lastLensAction ?: return
        if (last.regionMode) handleLensRegionRequest(last.mode)
        else handleScanRequest(last.mode)
    }

    /** Open the Flutter camera screen for camera translate.
     *
     * Two steps — BOTH required:
     *   1. Push the /camera route on the shared cached FlutterEngine
     *      (MainActivity reuses this same engine via provideFlutterEngine,
     *      so the route we push here is what it will display).
     *   2. Bring MainActivity to the FOREGROUND. The bubble floats over
     *      other apps while our app is backgrounded — pushing the route
     *      alone leaves the camera invisible (the bug: "nhấn camera trên
     *      popup không thấy mở"). startActivity surfaces the app so the
     *      user actually sees the camera screen.
     */
    internal fun openCameraScreen() {
        val engine = TransKeyApp.engine
        if (engine != null) {
            try {
                io.flutter.plugin.common.MethodChannel(
                    engine.dartExecutor.binaryMessenger, METHOD_CHANNEL,
                ).invokeMethod("openCamera", null)
            } catch (error: Exception) {
                android.util.Log.w("TKBubble", "openCamera invoke failed: ${error.message}")
            }
        }
        try {
            val intent = Intent(this, MainActivity::class.java).apply {
                addFlags(
                    Intent.FLAG_ACTIVITY_NEW_TASK or
                        Intent.FLAG_ACTIVITY_REORDER_TO_FRONT or
                        Intent.FLAG_ACTIVITY_SINGLE_TOP,
                )
            }
            startActivity(intent)
        } catch (error: Exception) {
            android.util.Log.w("TKBubble", "openCamera bring-to-front failed: ${error.message}")
        }
    }

    /**
     * Plan-gate signal for the bubble's Camera mode entry. Mirrors the
     * `camera` flag from /features, persisted as a SharedPreferences
     * bool by Dart's featuresProvider after every fetch. Returns false
     * (locked) when:
     *   - the key is missing entirely (free defaults / cold start /
     *     pre-features-resolve user)
     *   - or it's been explicitly persisted as false (plan doesn't
     *     allow Camera)
     *
     * Read from SharedPreferences instead of a method-channel round-
     * trip to Dart so the picker still renders correctly when the
     * Flutter engine hasn't fully come up yet (the bubble runs as an
     * overlay foreground service, can outlive the activity).
     */
    internal fun readCameraFeatureEnabled(): Boolean =
        readFeatureEnabled("tk_feature_camera")

    /**
     * Read a mirrored feature flag from SharedPreferences. The Flutter
     * side persists each plan-gated flag (camera, lens, reply, summarize,
     * explain, refine) on every /features fetch; the bubble reads them
     * here to render lock icons on entries the user's plan doesn't
     * include. Missing key OR wrong type → false (locked) — pessimistic
     * default keeps free users from briefly seeing unlocked paid
     * features during a cold start.
     *
     * Pass the key WITHOUT the `flutter.` prefix; this helper adds it
     * since the shared_preferences plugin auto-prefixes on the Dart side.
     */
    internal fun readFeatureEnabled(key: String): Boolean {
        return try {
            prefs.getBoolean("flutter.$key", false)
        } catch (_: ClassCastException) {
            false
        }
    }

    /**
     * Bring the Flutter activity foreground and show the upgrade nudge
     * sheet for [featureName]. Same two-step pattern as the per-feature
     * open methods: invoke the Dart-side route then surface the
     * activity. Surfaces the SAME UpgradeNudgeSheet the in-app flow uses
     * when a free user hits a locked feature, so the upsell copy stays
     * consistent across entry points.
     *
     * [featureName] is a human-readable label (e.g. "Camera",
     * "Lens", "Summarize") — Flutter passes it straight into
     * `UpgradeNudgeSheet(featureName: ...)` for the headline copy.
     */
    internal fun openFeatureUpsell(featureName: String) {
        val engine = TransKeyApp.engine
        if (engine != null) {
            try {
                io.flutter.plugin.common.MethodChannel(
                    engine.dartExecutor.binaryMessenger, METHOD_CHANNEL,
                ).invokeMethod("showFeatureUpsell", mapOf("featureName" to featureName))
            } catch (error: Exception) {
                android.util.Log.w("TKBubble", "showFeatureUpsell invoke failed: ${error.message}")
            }
        }
        try {
            val intent = Intent(this, MainActivity::class.java).apply {
                addFlags(
                    Intent.FLAG_ACTIVITY_NEW_TASK or
                        Intent.FLAG_ACTIVITY_REORDER_TO_FRONT or
                        Intent.FLAG_ACTIVITY_SINGLE_TOP,
                )
            }
            startActivity(intent)
        } catch (error: Exception) {
            android.util.Log.w("TKBubble", "openFeatureUpsell bring-to-front failed: ${error.message}")
        }
    }

    /** Legacy alias kept for the existing Camera entry call site. */
    internal fun openCameraUpsell() = openFeatureUpsell("Camera")

    /**
     * Bring the Flutter activity foreground and open the "What is this?"
     * explain sheet for [text]. Used when the user long-presses a block in
     * the Lens overlay (region-select or full-screen scan) — the bubble's
     * native overlay can't host a sheet, so we hand control back to Flutter.
     * Mirrors [openCameraScreen]'s two-step pattern (invokeMethod first so
     * the Dart side queues navigation while MainActivity finishes coming to
     * front), with a `text` argument carried in both channels.
     */
    internal fun openExplainScreen(text: String) {
        val engine = TransKeyApp.engine
        if (engine != null) {
            try {
                io.flutter.plugin.common.MethodChannel(
                    engine.dartExecutor.binaryMessenger, METHOD_CHANNEL,
                ).invokeMethod("openExplain", mapOf("text" to text))
            } catch (error: Exception) {
                android.util.Log.w("TKBubble", "openExplain invoke failed: ${error.message}")
            }
        }
        try {
            val intent = Intent(this, MainActivity::class.java).apply {
                addFlags(
                    Intent.FLAG_ACTIVITY_NEW_TASK or
                        Intent.FLAG_ACTIVITY_REORDER_TO_FRONT or
                        Intent.FLAG_ACTIVITY_SINGLE_TOP,
                )
            }
            startActivity(intent)
        } catch (error: Exception) {
            android.util.Log.w("TKBubble", "openExplain bring-to-front failed: ${error.message}")
        }
    }

    /**
     * Variant of [handleScanRequest] that asks ScreenCaptureService to skip
     * immediate OCR. After capture, BubbleService receives a bitmap and
     * presents [RegionSelectionView] so the user can drag a rectangle;
     * only that sub-region is OCR'd + translated.
     */
    internal fun handleLensRegionRequest(mode: String = MODE_TRANSLATE) {
        // Same per-mode gate as handleScanRequest — block a paid scan sub-mode
        // before the region-capture flow starts. Don't cache a blocked action.
        modeGateFor(mode)?.let { gate ->
            if (!readFeatureEnabled(gate.prefsKey)) {
                openFeatureUpsell(gate.displayName)
                return
            }
        }
        ScreenCaptureManager.regionMode = true
        lastLensAction = LastLensAction(regionMode = true, mode = mode)
        if (prefs.getBoolean(KEY_SCAN_DISCLOSED, false)) {
            launchScanFlow(mode)
        } else {
            showScanDisclosure(mode)
        }
    }

    internal fun launchScanFlow(mode: String = MODE_TRANSLATE) {
        // A fresh scan supersedes any "reopen last result" cache.
        discardLensCache()
        // Translate → LENS overlay (visual: translation painted over original
        // text in-place on screen). Other modes (Summarize, Refine, Explain)
        // can't visualise inline so they use TEXT_INTO_INPUT — OCR text is
        // fed to the input picker, user confirms, BubbleService runs the
        // mode against the captured text and shows the result panel.
        ScreenCaptureManager.flow = if (mode == MODE_TRANSLATE)
            ScreenCaptureManager.Flow.LENS
        else
            ScreenCaptureManager.Flow.TEXT_INTO_INPUT
        // For Lens (full-screen visual translate) the screen content is
        // whatever app the user is on — could be ANY script regardless of
        // the app-level source-lang setting (which is the user's translate
        // *intent*, not a hint about what's on screen). Force auto-detect
        // so OcrHelper runs all 4 recognizers in parallel and picks the
        // best one — without this, scanning a Japanese chat with source
        // set to "vi" runs Latin-only recognition and garbles the kana
        // into things like "01ROTIxyCO20)ET Lt".
        //
        // For TEXT_INTO_INPUT (Summarize / Refine / Explain) we trust the
        // user's source-lang hint — they typed source=vi because they
        // mean Vietnamese, and the single-recognizer path is cheaper.
        // The user's pinned source language drives BOTH the ML Kit
        // recognizer choice AND the vision-vs-MLKit routing — without
        // it the script-routing matrix has no signal, so pinning
        // source=ar/th/ru never triggered vision and Lens silently fell
        // back to the Latin recognizer (returning garbage on
        // unsupported scripts). "auto" stays null so the existing
        // auto-mode behaviour (Latin recognizer + auto-fallback to
        // vision when ML Kit comes back empty) still kicks in.
        ScreenCaptureManager.languageHint = readSourceLang().takeIf { it != "auto" }
        ScreenCaptureManager.targetLang = readTargetLang()
        ScreenCaptureManager.pendingMode = mode
        // Hide everything we'd otherwise be painting OVER the source app
        // before the system grabs the next frame — bubble icon + open
        // pickers would all end up baked into the screenshot otherwise.
        hideOverlaysForCapture()

        // Reuse the MediaProjection grant if the user already approved it
        // earlier this bubble session — skips the "Start recording?" prompt
        // and the consent activity entirely. The persistent capture-service
        // notification (+ system casting indicator) keeps the user aware
        // that we still have screen-capture access.
        if (ScreenCaptureService.isProjectionActive) {
            // NB: do NOT show the progress overlay here, even with FLAG_SECURE.
            // On MIUI (and likely other OEMs) MediaProjection responds to any
            // FLAG_SECURE window in the layer stack by blanking the entire
            // captured frame to black — so users on Slack/etc would get a
            // pitch-black "Lens result". Progress is shown later in
            // handleLensReady once the bitmap is safely in hand.
            val captureIntent = Intent(this, ScreenCaptureService::class.java).apply {
                action = ScreenCaptureService.ACTION_CAPTURE
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                startForegroundService(captureIntent)
            } else {
                startService(captureIntent)
            }
            return
        }

        val intent = Intent(this, ScreenCapturePermissionActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                Intent.FLAG_ACTIVITY_NO_HISTORY or
                Intent.FLAG_ACTIVITY_EXCLUDE_FROM_RECENTS
        }
        try { startActivity(intent) } catch (_: Exception) {}
    }

    private fun hideOverlaysForCapture() {
        hideRegrantPill()
        bubbleView?.visibility = View.GONE
        hideModePicker()
        hideLangPicker()
        hideSourceLangPicker()
        hideTonePicker()
        hideInputPicker()
        hideVoicePicker()
        hideResultPanel()
    }

    internal fun restoreBubbleVisibility() {
        bubbleView?.visibility = View.VISIBLE
    }

    private var screenshotHideRunnable: Runnable? = null

    /**
     * Hide the floating bubble for [SCREENSHOT_HIDE_MS] so the user can take
     * a clean system screenshot, then bring it back automatically.
     *
     * Why this exists at all: the bubble is a third-party overlay, so it
     * lands in the user's own screenshots. There is no way to exclude just
     * the bubble on MIUI — FLAG_SECURE makes the system refuse the WHOLE
     * screenshot, and there's no pre-capture hook to auto-hide it in time.
     * So a manual, time-boxed hide is the only clean option. No toast or
     * countdown UI: any transient overlay we show would itself be captured.
     *
     * GONE (not removeView) keeps the window + drag position; a GONE view
     * draws nothing, so it's absent from the screenshot (same mechanism
     * hideOverlaysForCapture relies on for our own Lens capture).
     */
    internal fun hideBubbleForScreenshot() {
        cancelBubbleHalfHide()
        screenshotHideRunnable?.let { handler.removeCallbacks(it) }
        bubbleView?.visibility = View.GONE
        val restore = Runnable {
            screenshotHideRunnable = null
            // Guard: the user may have stopped the bubble during the window.
            if (bubbleView != null) {
                bubbleView?.visibility = View.VISIBLE
                snapBubbleToEdge(resources.displayMetrics.density, halfHidden = false)
            }
        }
        screenshotHideRunnable = restore
        handler.postDelayed(restore, SCREENSHOT_HIDE_MS)
    }


    /**
     * Callback path invoked by ScreenCaptureService once OCR completes.
     * Routes the recognised text into the input picker so the user can trim
     * before translating; toasts if the recognizer found nothing.
     */
    private fun handleOcrResult(text: String?, mode: String) {
        // Reachable from BOTH flows: TEXT_INTO_INPUT delivers the joined
        // text; LENS delivers null via ACTION_DELIVER_OCR only on capture
        // failure (success goes through ACTION_DELIVER_LENS). Either way
        // restore the bubble icon so the user can retry.
        restoreBubbleVisibility()
        if (text.isNullOrBlank()) {
            Toast.makeText(
                this,
                localized(R.string.bubble_scan_empty),
                Toast.LENGTH_LONG,
            ).show()
            return
        }
        showInputPicker(mode, prefillText = text)
    }

    // ── Lens flow ──

    /**
     * Invoked after ScreenCaptureService finishes OCR'ing for the Lens
     * flow. Bitmap + blocks are sitting in [ScreenCaptureManager]; we
     * call the Flutter side via the bubble channel to batch-translate all
     * blocks in one round-trip, then render the overlay.
     */
    private fun handleLensReady() {
        val bitmap = ScreenCaptureManager.screenshot
        val blocks = ScreenCaptureManager.blocks
        if (bitmap == null) {
            ScreenCaptureManager.clearAll()
            restoreBubbleVisibility()
            Toast.makeText(
                this,
                localized(R.string.bubble_scan_empty),
                Toast.LENGTH_LONG,
            ).show()
            return
        }

        // Vision route for unsupported scripts (Cyrillic/Thai/Arabic/...)
        // OR ML Kit returned nothing readable. The empty-OCR case includes
        // a wrong-source pin (e.g. source=ja while the screen is Arabic) —
        // ML Kit's JA recognizer can't read Arabic, returns empty, and
        // without this fallback the user would see a bare "no text" toast
        // with no hint to switch language. Vision reads any script, and
        // the server's sourceMismatch detector on the transcription tells
        // the user which language to actually pick.
        val hint = ScreenCaptureManager.languageHint
        var forceVision = OcrHelper.needsVisionForSource(hint)
        // Latin-override: source is pinned to a vision-only script (e.g. "ru"),
        // but ML Kit already returned dominantly Latin/ASCII content — the screen
        // is plain English. Sending this to vision would only add 2-5 s of latency
        // with no quality improvement. Override to the fast batch path; the server's
        // sourceMismatch detector will still surface the "Detected English — switch?"
        // banner so the user knows their pin is wrong.
        if (forceVision && !blocks.isEmpty() && blocksDominantlyLatin(blocks)) {
            android.util.Log.w("TKBubble", "lens: forceVision overridden — Latin blocks detected, hint=$hint")
            forceVision = false
            ScreenCaptureManager.languageHint = null // let server auto-detect source
        }
        // Hallucination gate: ML Kit's per-language recognizer doesn't refuse
        // unknown scripts — feed it Arabic / Thai / etc. with pin=ja and it
        // returns garbage Latin/digits PLUS the occasional fake kana char
        // from misreading a curve. Blocks are non-empty so the empty-OCR
        // path doesn't trigger, but the result has near-zero real pinned-
        // script content. Treat that as "ML Kit failed" and let vision read
        // what's actually there (so the server's sourceMismatch can fire).
        val hallucinated = ocrLooksHallucinated(blocks, hint)
        val emptyMlkitFallback = blocks.isEmpty() || hallucinated
        if (emptyMlkitFallback && !hint.isNullOrEmpty() && hint != "auto") {
            // Surface the wrong-pin signal early — vision is about to run
            // (~2-5s on Gemini) so the user understands why they're waiting.
            val hintLabel = getEffectiveLangLabels()[hint] ?: hint
            Toast.makeText(
                this,
                localized(R.string.lens_empty_for_source, hintLabel),
                Toast.LENGTH_SHORT,
            ).show()
        }
        // Show the in-flight spinner BEFORE branching — both the vision
        // fallback and the ML Kit batch path run an async translate that
        // can take seconds. Previously showLensProgress() lived only on the
        // batch path, so the vision route showed nothing during the wait
        // and the user couldn't tell it was working.
        // Pass the original hint (pre-Latin-override) so the "From: X" label
        // in the spinner reflects the user's actual selection even when the
        // override cleared languageHint for the server call.
        val progressSourceLabel = if (!hint.isNullOrEmpty() && hint != "auto")
            (getEffectiveLangLabels()[hint] ?: hint)
        else null
        showLensProgress(sourceLabel = progressSourceLabel)
        if (forceVision || emptyMlkitFallback) {
            runLensVisionTranslate(
                bitmap = bitmap,
                offsetX = 0,
                offsetY = 0,
                sourceLang = if (hint.isNullOrEmpty()) null else hint,
                onError = { msg ->
                    handler.post {
                        hideLensProgress()
                        ScreenCaptureManager.clearAll()
                        restoreBubbleVisibility()
                        if (!bitmap.isRecycled) bitmap.recycle()
                        Toast.makeText(this, msg ?: localized(R.string.bubble_panel_translation_failed), Toast.LENGTH_LONG).show()
                    }
                },
            )
            return
        }

        val engine = TransKeyApp.engine
        if (engine == null) {
            hideLensProgress()
            ScreenCaptureManager.clearAll()
            restoreBubbleVisibility()
            Toast.makeText(this, localized(R.string.bubble_panel_app_not_ready), Toast.LENGTH_LONG).show()
            return
        }
        val channel = io.flutter.plugin.common.MethodChannel(
            engine.dartExecutor.binaryMessenger, METHOD_CHANNEL,
        )
        val texts = blocks.map { it.text }
        val target = ScreenCaptureManager.targetLang
        val source = ScreenCaptureManager.languageHint
        // Stash for a possible source-mismatch re-translate.
        lensTexts = texts
        lensTarget = target
        android.util.Log.w(
            "TKBubble",
            "lens-translate: target=$target source=$source texts.size=${texts.size} " +
                "first='${texts.firstOrNull()?.take(40)?.replace('\n', '⏎')}'",
        )
        val args = mapOf(
            "texts" to texts,
            "targetLang" to target,
            "sourceLang" to (source ?: ""),
        )
        // Progressive UX: show the overlay IMMEDIATELY with the original
        // text in each chip as a placeholder, hide the spinner, and let
        // Flutter push translations chunk-by-chunk via
        // ACTION_DELIVER_LENS_CHUNK. User sees chips fill in within ~1-2s
        // instead of staring at a spinner for the slowest chunk.
        val placeholderItems = blocks.map { block ->
            LensOverlayView.Item(block.text, block.text, block.bounds)
        }
        hideLensProgress()
        showLensOverlay(bitmap, placeholderItems)

        channel.invokeMethod("translateBatch", args, object : io.flutter.plugin.common.MethodChannel.Result {
            override fun success(result: Any?) {
                handler.post {
                    val translations = (result as? List<*>)
                        ?.map { (it as? String).orEmpty() }
                        ?: emptyList()
                    android.util.Log.w(
                        "TKBubble",
                        "lens-translate: got ${translations.size} translations, " +
                            "first='${translations.firstOrNull()?.take(40)?.replace('\n', '⏎')}'",
                    )
                    // Final safety net: in case any progressive chunk emit
                    // was dropped, re-apply the full result. Idempotent —
                    // [LensOverlayView.applyTranslations] skips slots that
                    // already match.
                    lensOverlayView?.applyTranslations(0, translations)
                }
            }
            override fun error(code: String, message: String?, details: Any?) {
                handler.post {
                    // Overlay is already up showing originals — user still
                    // sees something useful. Toast the error but keep the
                    // overlay so they can dismiss with a tap.
                    Toast.makeText(
                        this@BubbleService,
                        message ?: localized(R.string.bubble_panel_translation_failed),
                        Toast.LENGTH_LONG,
                    ).show()
                }
            }
            override fun notImplemented() {
                handler.post {
                    hideLensProgress()
                    ScreenCaptureManager.clearAll()
                    restoreBubbleVisibility()
                    if (!bitmap.isRecycled) bitmap.recycle()
                }
            }
        })
    }

    /**
     * Re-run the Lens batch translate on the current overlay using a new
     * source language (the script the server detected). Reuses the stashed
     * [lensTexts] so we don't re-capture or re-OCR; resets chips to the
     * pending state, then progressive emit re-fills them under the new
     * source hint.
     */
    internal fun retranslateLens(newSource: String) {
        val texts = lensTexts ?: return
        val overlay = lensOverlayView ?: return
        val target = lensTarget ?: ScreenCaptureManager.targetLang
        val engine = TransKeyApp.engine ?: return
        overlay.resetForRetranslate()
        val channel = io.flutter.plugin.common.MethodChannel(
            engine.dartExecutor.binaryMessenger, METHOD_CHANNEL,
        )
        val args = mapOf(
            "texts" to texts,
            "targetLang" to target,
            "sourceLang" to newSource,
        )
        channel.invokeMethod("translateBatch", args, object : io.flutter.plugin.common.MethodChannel.Result {
            override fun success(result: Any?) {
                handler.post {
                    val translations = (result as? List<*>)
                        ?.map { (it as? String).orEmpty() }
                        ?: emptyList()
                    lensOverlayView?.applyTranslations(0, translations)
                }
            }
            override fun error(code: String, message: String?, details: Any?) {
                handler.post {
                    Toast.makeText(
                        this@BubbleService,
                        message ?: localized(R.string.bubble_panel_translation_failed),
                        Toast.LENGTH_LONG,
                    ).show()
                }
            }
            override fun notImplemented() {}
        })
    }

    /**
     * Detects the "ML Kit hallucinated" case: user pinned a CJK source
     * but the screen is a different (unsupported) script. ML Kit's per-
     * language recognizer doesn't refuse — it returns mostly Latin/digit
     * noise PLUS an occasional fake kana char from misreading a curve,
     * which (a) tricks the empty-OCR fallback into NOT running and (b)
     * tricks the server's script detector into agreeing with the pin.
     * Net effect: silently produces garbage instead of fall-throughing
     * to vision OCR + showing the source-mismatch banner.
     *
     * Heuristic: when the pin is ja/zh/ko AND the share of OCR'd chars
     * that are ACTUALLY in the pinned source's script falls below a
     * language-specific floor, treat the OCR as failed and force the
     * vision path. Latin / Cyrillic / etc. pins are skipped — there's
     * no script-class to count for those, and ML Kit doesn't hallucinate
     * the same way for Latin-based recognizers.
     */
    private fun ocrLooksHallucinated(blocks: List<OcrHelper.Block>, hint: String?): Boolean {
        val pin = hint?.lowercase()?.split("-", "_")?.first() ?: return false
        val threshold: Float = when (pin) {
            "ja" -> 0.25f   // ja real screens have kana+han ≥ 25% of text
            "zh" -> 0.50f   // zh is han-dominant
            "ko" -> 0.30f   // ko mixes hangul + occasional han
            else -> return false
        }
        val joined = blocks.joinToString(separator = "") { it.text }
        val significant = joined.filter { c -> !c.isWhitespace() && !c.isISOControl() && c.code > 32 }
        // Too little text to judge — fall back to existing empty-OCR check.
        if (significant.length < 10) return false
        val matching = significant.count { isInLangScript(it.code, pin) }
        return matching.toFloat() / significant.length < threshold
    }

    private fun isInLangScript(cp: Int, lang: String): Boolean = when (lang) {
        "ja" -> (cp in 0x3040..0x309F) || (cp in 0x30A0..0x30FF) ||
                (cp in 0xFF66..0xFF9F) || (cp in 0x4E00..0x9FFF) || (cp in 0x3400..0x4DBF)
        "zh" -> (cp in 0x4E00..0x9FFF) || (cp in 0x3400..0x4DBF)
        "ko" -> (cp in 0xAC00..0xD7AF) || (cp in 0x4E00..0x9FFF)
        else -> false
    }

    /**
     * Downscale [bitmap] to at most 1600 px on the long edge, then encode as
     * JPEG (q=85) and return the Base64 string. Matches the camera-service
     * `compressForVision` parameters so LLM token cost stays consistent across
     * both paths.
     *
     * Called inline from [runLensVisionTranslate] when the pre-computed result
     * from [ScreenCaptureManager.pendingVisionB64] is not available; otherwise
     * the caller picks up the future's value instead and skips this call.
     */
    private fun compressBitmapToB64(bitmap: Bitmap): String {
        val maxEdge = 1600
        val maxSide = maxOf(bitmap.width, bitmap.height)
        val upload = if (maxSide > maxEdge) {
            val scale = maxEdge.toFloat() / maxSide
            try {
                Bitmap.createScaledBitmap(
                    bitmap,
                    (bitmap.width * scale).toInt().coerceAtLeast(1),
                    (bitmap.height * scale).toInt().coerceAtLeast(1),
                    true,
                )
            } catch (e: Throwable) {
                android.util.Log.w("TKBubble", "lens-vision: scale failed: ${e.message}")
                bitmap
            }
        } else bitmap
        val baos = java.io.ByteArrayOutputStream()
        upload.compress(Bitmap.CompressFormat.JPEG, 85, baos)
        if (upload !== bitmap && !upload.isRecycled) upload.recycle()
        return android.util.Base64.encodeToString(baos.toByteArray(), android.util.Base64.NO_WRAP)
    }

    /**
     * Returns true when the OCR result is overwhelmingly ASCII/Latin, regardless
     * of the source-language pin. Used to bypass [OcrHelper.needsVisionForSource]
     * when the user has a vision-only language pinned (e.g. "ru") but the actual
     * screen content is plain English — ML Kit already read it correctly, so the
     * expensive vision path would only add latency with no quality gain.
     *
     * Threshold: >65% of non-whitespace codepoints in the Basic Latin (U+0020-U+007E)
     * or Latin Extended (U+00C0-U+024F) ranges. Minimum 15 chars to avoid flipping
     * on near-empty results.
     */
    private fun blocksDominantlyLatin(blocks: List<OcrHelper.Block>): Boolean {
        val joined = blocks.joinToString("") { it.text }.filter { c -> !c.isWhitespace() }
        if (joined.length < 15) return false
        val latinCount = joined.count { c ->
            c.code in 0x20..0x7E || c.code in 0xC0..0x024F
        }
        return latinCount.toFloat() / joined.length > 0.65f
    }

    /**
     * Region mode: capture done, bitmap is sitting in the manager. Show
     * the rubber-band selector. On confirm we crop the bitmap, OCR the
     * sub-image, OFFSET each block's bounds back into full-screen coords
     * (so the Lens overlay paints them at the right place on top of the
     * still-full screenshot), then reuse [handleLensReady] for the
     * batch-translate + overlay render.
     */

    /**
     * Vision-backed Lens path. Downscales [bitmap] to keep upload + vision
     * input cost in check, ships it through the Flutter bridge to
     * /translate-image?withBoxes=true (Gemini-routed), then builds the
     * positioned overlay from the per-block boxes the server returns.
     *
     * [offsetX]/[offsetY] are added to every block's bounds before render
     * (region mode passes the rectangle's top-left so the overlay still
     * lines up on the full screenshot).
     *
     * When [aggregateToSingleItem] is true the result is collapsed into
     * ONE LensOverlayView.Item that uses [aggregateBounds] (the rectangle
     * the user drew); matches the ML Kit region path's "one selection =
     * one chip" UX. [renderBitmap] is the bitmap the overlay is drawn
     * over — usually the same as [bitmap] for full-screen scans, but the
     * caller passes the FULL screenshot for region mode while [bitmap]
     * is the cropped sub-image we sent to vision.
     */
    private fun runLensVisionTranslate(
        bitmap: Bitmap,
        offsetX: Int,
        offsetY: Int,
        sourceLang: String?,
        aggregateToSingleItem: Boolean = false,
        aggregateBounds: android.graphics.Rect? = null,
        renderBitmap: Bitmap? = null,
        onSuccessRecycle: (() -> Unit)? = null,
        onError: (String?) -> Unit,
    ) {
        val engine = TransKeyApp.engine
        if (engine == null) {
            onError(localized(R.string.bubble_panel_app_not_ready))
            return
        }
        val origW = bitmap.width
        val origH = bitmap.height
        val target = ScreenCaptureManager.targetLang

        // Use pre-computed base64 when ScreenCaptureService started compression
        // in parallel with ML Kit OCR (vision-only source hint). getNow() returns
        // the result immediately if compression finished, or null if it's still
        // running — in the null case we compress synchronously (same as before).
        // Typical overlap: OCR ~200 ms, compress ~80 ms → getNow almost always hits.
        val precomputed = ScreenCaptureManager.pendingVisionB64?.getNow(null)
        ScreenCaptureManager.pendingVisionB64 = null // consume the slot
        val b64 = precomputed ?: compressBitmapToB64(bitmap)

        val channel = io.flutter.plugin.common.MethodChannel(
            engine.dartExecutor.binaryMessenger, METHOD_CHANNEL,
        )
        val args = mapOf<String, Any?>(
            "imageBase64" to b64,
            "targetLang"  to target,
            "sourceLang"  to (sourceLang ?: ""),
            // Pass the ORIGINAL bitmap dims (not the downscaled upload
            // dims) so the server hands us boxes in coords that match
            // the bitmap LensOverlayView will paint over.
            "imageWidth"  to origW,
            "imageHeight" to origH,
        )
        android.util.Log.w("TKBubble", "lens-vision: ${origW}x${origH} src=$sourceLang target=$target")
        channel.invokeMethod("lensVisionTranslate", args, object : io.flutter.plugin.common.MethodChannel.Result {
            override fun success(result: Any?) {
                handler.post {
                    val map = result as? Map<*, *>
                    val rawBlocks = map?.get("blocks") as? List<*>
                    val err = map?.get("error") as? String
                    if (err != null) {
                        android.util.Log.w("TKBubble", "lens-vision: server error=$err")
                        onError(localized(R.string.bubble_panel_translation_failed))
                        return@post
                    }
                    val items = mutableListOf<LensOverlayView.Item>()
                    rawBlocks?.forEach { raw ->
                        val b = raw as? Map<*, *> ?: return@forEach
                        val original = (b["original"] as? String).orEmpty()
                        val translation = (b["translation"] as? String).orEmpty()
                        val ymin = (b["ymin"] as? Number)?.toInt()
                        val xmin = (b["xmin"] as? Number)?.toInt()
                        val ymax = (b["ymax"] as? Number)?.toInt()
                        val xmax = (b["xmax"] as? Number)?.toInt()
                        if (ymin == null || xmin == null || ymax == null || xmax == null) return@forEach
                        if (xmax <= xmin || ymax <= ymin) return@forEach
                        items.add(LensOverlayView.Item(
                            original,
                            translation,
                            android.graphics.Rect(
                                xmin + offsetX, ymin + offsetY,
                                xmax + offsetX, ymax + offsetY,
                            ),
                        ))
                    }
                    if (items.isEmpty()) {
                        hideLensProgress()
                        ScreenCaptureManager.clearAll()
                        restoreBubbleVisibility()
                        val rb = renderBitmap ?: bitmap
                        if (!rb.isRecycled) rb.recycle()
                        Toast.makeText(this@BubbleService, localized(R.string.bubble_scan_empty), Toast.LENGTH_LONG).show()
                        return@post
                    }
                    val finalItems = if (aggregateToSingleItem && aggregateBounds != null) {
                        val joinedOriginal = items.joinToString(" ") { it.original }.trim()
                        val joinedTranslation = items.joinToString(" ") { it.translation }.trim()
                        listOf(LensOverlayView.Item(joinedOriginal, joinedTranslation, aggregateBounds))
                    } else dedupOverlappingItems(items)
                    // Stash the vision-transcribed originals so the lang-chip
                    // "switch source & re-translate" works after a vision scan
                    // too — re-translate goes through the text batch path using
                    // these already-transcribed strings (no re-OCR needed).
                    lensTexts = finalItems.map { it.original }
                    lensTarget = ScreenCaptureManager.targetLang
                    onSuccessRecycle?.invoke()
                    hideLensProgress()
                    showLensOverlay(renderBitmap ?: bitmap, finalItems)
                    // Vision path returns FULLY-translated items in one shot
                    // (no chunked progressive emit). Mark every chip processed
                    // so the "Đang dịch X/Y" pill hides and chips render with
                    // the white "done" background instead of pending amber.
                    lensOverlayView?.markAllProcessed()
                }
            }
            override fun error(code: String, message: String?, details: Any?) {
                handler.post { onError(message) }
            }
            override fun notImplemented() {
                handler.post { onError(localized(R.string.bubble_panel_app_not_ready)) }
            }
        })
    }

    /**
     * Merge Lens overlay items whose boxes overlap heavily (IoU > 0.6).
     * The vision LLM occasionally returns 2-3 near-identical boxes for
     * text that visually sits in one region (multi-line headline, brand
     * + tagline above each other), producing chips that render directly
     * on top of each other — LensOverlayView's collision-avoidance can't
     * push them apart when the bounds are nearly the same Rect.
     *
     * Merge texts in REVERSE iteration order so the result lists the
     * later (lower / right) blocks first when stacked — matches how the
     * user reads grouped signage top-to-bottom under the chip's first
     * line. We do NOT touch boxes that are merely close — only
     * effectively-coincident ones — so distinct adjacent items still
     * get their own chip and the render-side collision logic still
     * spreads them slightly when needed.
     */
    private fun dedupOverlappingItems(items: List<LensOverlayView.Item>): List<LensOverlayView.Item> {
        if (items.size < 2) return items
        val merged = BooleanArray(items.size)
        val out = mutableListOf<LensOverlayView.Item>()
        for (i in items.indices) {
            if (merged[i]) continue
            val baseBounds = items[i].bounds
            val originals = mutableListOf(items[i].original)
            val translations = mutableListOf(items[i].translation)
            var unionBounds = android.graphics.Rect(baseBounds)
            for (j in (i + 1) until items.size) {
                if (merged[j]) continue
                if (iouRect(baseBounds, items[j].bounds) > 0.6f) {
                    originals.add(items[j].original)
                    translations.add(items[j].translation)
                    unionBounds.union(items[j].bounds)
                    merged[j] = true
                }
            }
            val original = originals.filter { it.isNotBlank() }.joinToString("\n").trim()
            val translation = translations.filter { it.isNotBlank() }.joinToString("\n").trim()
            out.add(LensOverlayView.Item(original, translation, unionBounds))
        }
        return out
    }

    private fun iouRect(a: android.graphics.Rect, b: android.graphics.Rect): Float {
        val inter = android.graphics.Rect(a)
        if (!inter.intersect(b)) return 0f
        val interArea = inter.width().toFloat() * inter.height()
        val aArea = a.width().toFloat() * a.height()
        val bArea = b.width().toFloat() * b.height()
        val union = aArea + bArea - interArea
        return if (union <= 0f) 0f else interArea / union
    }

    private fun handleRegionReady() {
        val bitmap = ScreenCaptureManager.screenshot
        if (bitmap == null) {
            ScreenCaptureManager.clearAll()
            restoreBubbleVisibility()
            Toast.makeText(this, localized(R.string.bubble_scan_empty), Toast.LENGTH_LONG).show()
            return
        }
        showRegionSelectionView(bitmap)
    }

    @SuppressLint("ClickableViewAccessibility")
    private fun showRegionSelectionView(bitmap: Bitmap) {
        ensureWindowManager()
        val view = RegionSelectionView(
            context = this,
            bitmap = bitmap,
            onConfirm = { rect -> onRegionConfirmed(bitmap, rect) },
            onCancel = { hideRegionSelectionView(); ScreenCaptureManager.clearAll(); restoreBubbleVisibility() },
        )
        regionSelectionView = view
        windowManager?.addView(view, buildPickerLayoutParams())
    }

    private fun hideRegionSelectionView() {
        regionSelectionView?.let { try { windowManager?.removeView(it) } catch (_: Exception) {} }
        regionSelectionView = null
    }

    private fun onRegionConfirmed(bitmap: Bitmap, rect: android.graphics.Rect) {
        hideRegionSelectionView()
        // Take a defensive copy of the cropped pixels so the source bitmap
        // can stay live for the Lens overlay underneath.
        val cropped = try {
            Bitmap.createBitmap(bitmap, rect.left, rect.top, rect.width(), rect.height())
        } catch (error: Exception) {
            android.util.Log.w("BubbleService", "Region crop failed: ${error.message}")
            null
        }
        if (cropped == null) {
            ScreenCaptureManager.clearAll()
            restoreBubbleVisibility()
            Toast.makeText(this, localized(R.string.bubble_scan_empty), Toast.LENGTH_LONG).show()
            return
        }
        val regionHint = ScreenCaptureManager.languageHint
        val regionSourceLabel = if (!regionHint.isNullOrEmpty() && regionHint != "auto")
            (getEffectiveLangLabels()[regionHint] ?: regionHint)
        else null
        showLensProgress(sourceLabel = regionSourceLabel)
        // Always attempt ML Kit first, even when the source is pinned to a
        // vision-only script (e.g. "ru", "ar", "th"). If the on-screen text
        // is actually Latin/ASCII, blocksDominantlyLatin() inside handleLensReady()
        // will override forceVision and take the fast batch path — avoiding the
        // 2-5 s vision round-trip when it isn't needed.
        // Vision is only triggered here as a genuine last resort: ML Kit returned
        // empty blocks AND the source pin is a script ML Kit can't recognise.
        OcrHelper.recognizeBlocks(cropped, regionHint) { blocks ->
            handler.post {
                val offset = blocks
                    ?.map { block ->
                        val newBounds = android.graphics.Rect(
                            block.bounds.left + rect.left,
                            block.bounds.top + rect.top,
                            block.bounds.right + rect.left,
                            block.bounds.bottom + rect.top,
                        )
                        OcrHelper.Block(block.text, newBounds)
                    }
                    ?: emptyList()
                if (offset.isEmpty()) {
                    // ML Kit found nothing. If the source pin is a vision-only
                    // script, ML Kit's recognizer couldn't read those glyphs —
                    // fall back to vision so the server can transcribe and the
                    // sourceMismatch banner can fire. Otherwise just toast.
                    if (OcrHelper.needsVisionForSource(regionHint)) {
                        // Aggregate into a single overlay item (matches the ML Kit
                        // region behaviour: the user-drawn box = ONE chip).
                        runLensVisionTranslate(
                            bitmap = cropped,
                            offsetX = rect.left,
                            offsetY = rect.top,
                            sourceLang = if (regionHint.isNullOrEmpty()) null else regionHint,
                            aggregateToSingleItem = true,
                            aggregateBounds = rect,
                            renderBitmap = bitmap, // overlay sits on the FULL screenshot
                            onError = { msg ->
                                handler.post {
                                    hideLensProgress()
                                    ScreenCaptureManager.clearAll()
                                    restoreBubbleVisibility()
                                    if (!cropped.isRecycled) cropped.recycle()
                                    if (!bitmap.isRecycled) bitmap.recycle()
                                    Toast.makeText(this, msg ?: localized(R.string.bubble_panel_translation_failed), Toast.LENGTH_LONG).show()
                                }
                            },
                            onSuccessRecycle = { if (!cropped.isRecycled) cropped.recycle() },
                        )
                        return@post
                    }
                    // Not a vision-only pin — OCR should have worked; treat
                    // the empty result as "no readable text in the selection".
                    if (!cropped.isRecycled) cropped.recycle()
                    hideLensProgress()
                    ScreenCaptureManager.clearAll()
                    restoreBubbleVisibility()
                    Toast.makeText(
                        this,
                        localized(R.string.bubble_scan_empty),
                        Toast.LENGTH_LONG,
                    ).show()
                    return@post
                }
                // OCR succeeded — the cropped pixels are no longer needed.
                if (!cropped.isRecycled) cropped.recycle()
                // Branch on pendingMode: Translate uses the Lens visual
                // overlay; Summarize (and any future non-Translate mode
                // that supports Region) feeds OCR text into the input
                // picker so the user can review/trim before running.
                val mode = ScreenCaptureManager.pendingMode
                hideLensProgress()
                if (mode == MODE_TRANSLATE) {
                    // Region mode = the user deliberately drew a box around
                    // the exact text they want. Treat that selection as ONE
                    // unit: aggregate all OCR blocks inside the box into a
                    // single block so the overlay shows one coherent
                    // translation card (and the translator gets the full
                    // selected passage as one prompt) instead of N
                    // fragmented chips. Mirrors the camera's
                    // _aggregateBlocks for document/sign/auto scenes.
                    ScreenCaptureManager.blocks = aggregateRegionBlocks(offset)
                    handleLensReady()
                } else {
                    val joined = offset.joinToString("\n") { it.text }.trim()
                    ScreenCaptureManager.clearAll()
                    restoreBubbleVisibility()
                    handleOcrResult(joined.takeIf { it.isNotEmpty() }, mode)
                }
            }
        }
    }

    /**
     * Collapse the OCR blocks from a user-selected region into ONE block.
     * Text is concatenated in reading order (top-to-bottom; left-to-right
     * within a visual row using a 12 px row tolerance) joined by "\n";
     * the bounding box is the union of all blocks so the single overlay
     * card sits over the whole selected region.
     *
     * Why: in region mode the user has already done the segmentation by
     * drawing the box — splitting their selection back into multiple
     * cards is redundant and produces fragmented translations. One block
     * = one coherent translation, and the LLM sees the full passage.
     */
    private fun aggregateRegionBlocks(
        blocks: List<OcrHelper.Block>,
    ): List<OcrHelper.Block> {
        if (blocks.size < 2) return blocks
        val sorted = blocks.sortedWith(Comparator { a, b ->
            val dy = a.bounds.top - b.bounds.top
            if (kotlin.math.abs(dy) > 12) dy else a.bounds.left - b.bounds.left
        })
        val text = sorted
            .map { it.text.trim() }
            .filter { it.isNotEmpty() }
            .joinToString("\n")
            .trim()
        var left = Int.MAX_VALUE
        var top = Int.MAX_VALUE
        var right = Int.MIN_VALUE
        var bottom = Int.MIN_VALUE
        for (block in sorted) {
            left = minOf(left, block.bounds.left)
            top = minOf(top, block.bounds.top)
            right = maxOf(right, block.bounds.right)
            bottom = maxOf(bottom, block.bounds.bottom)
        }
        return listOf(
            OcrHelper.Block(text, android.graphics.Rect(left, top, right, bottom)),
        )
    }

    /**
     * Mode-picker entry for the voice flow. Requests RECORD_AUDIO via a
     * transparent activity since a Service can't show a runtime prompt.
     * The activity calls back via ACTION_START_VOICE.
     */


    // ── Lifecycle ──

    fun stopBubble() {
        handler.removeCallbacks(idleAutoStopRunnable)
        hideModePicker()
        hideLangPicker()
        hideInputPicker()
        hideVoicePicker()
        hideScanDisclosure()
        hideScanModeChooser()
        hideLensProgress()
        hideLensOverlay()
        hideRegionSelectionView()
        releaseScreenCapture()
        removeResultPanel()
        removeBubble()
        // Forget the double-tap cache between sessions — the user's "last
        // action" doesn't survive a manual bubble stop.
        lastLensAction = null
        lastBubbleTapTime = 0L
        saveBubbleActive(false)
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    /**
     * Tell the screen-capture service to drop the MediaProjection grant.
     * Called when the user closes the bubble — keeping the grant alive
     * past that would leave the system casting indicator on with no
     * obvious way to dismiss it.
     */
    private fun releaseScreenCapture() {
        if (!ScreenCaptureService.isProjectionActive) return
        val intent = Intent(this, ScreenCaptureService::class.java).apply {
            action = ScreenCaptureService.ACTION_STOP_PROJECTION
        }
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                startForegroundService(intent)
            } else {
                startService(intent)
            }
        } catch (_: Exception) {
            // Service may already be dying; nothing to do.
        }
    }

    private fun removeBubble() {
        bubbleView?.let {
            try { windowManager?.removeView(it) } catch (_: Exception) {}
        }
        bubbleView = null
        bubbleIcon = null
        badgeText = null
    }

    internal fun ensureWindowManager() {
        if (windowManager == null) {
            windowManager = getSystemService(WINDOW_SERVICE) as WindowManager
        }
    }
}
