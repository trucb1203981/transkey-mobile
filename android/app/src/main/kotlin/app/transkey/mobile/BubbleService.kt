package app.transkey.mobile

import android.annotation.SuppressLint
import android.app.Service
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
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
        // Region mode: capture finished but OCR deferred — show the
        // rubber-band selector on top of the bitmap so the user can crop
        // before we OCR + translate.
        const val ACTION_DELIVER_REGION_READY = "transkey.bubble.DELIVER_REGION_READY"
        const val EXTRA_STATE = "bubble_state"
        const val EXTRA_TEXT = "text"
        const val EXTRA_MODE = "mode"
        const val EXTRA_TRANSLATION = "translation"
        const val EXTRA_ROMANIZATION = "romanization"
        const val EXTRA_DETECTED_LANG = "detectedLang"
        const val EXTRA_SUGGESTION_SOURCES = "suggestion_sources"
        const val EXTRA_SUGGESTION_TARGETS = "suggestion_targets"
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
        const val MODE_REPLY = "reply"
        const val MODE_SUMMARIZE = "summarize"
        const val MODE_EXPLAIN = "explain"
        const val MODE_REFINE = "refine"
        internal val ALL_MODES = listOf(MODE_TRANSLATE, MODE_SUMMARIZE, MODE_EXPLAIN, MODE_REFINE, MODE_REPLY)
        // Mode → (string-resource id, drawable-resource id) for the picker and
        // result panel. Keeping resources here (instead of inline `when`) makes
        // it cheap to add a new mode in one place.
        private val MODE_STRING_IDS = mapOf(
            MODE_TRANSLATE to R.string.bubble_mode_translate,
            MODE_REPLY to R.string.bubble_mode_reply,
            MODE_SUMMARIZE to R.string.bubble_mode_summarize,
            MODE_EXPLAIN to R.string.bubble_mode_explain,
            MODE_REFINE to R.string.bubble_mode_refine,
        )
        private val MODE_ICON_IDS = mapOf(
            MODE_TRANSLATE to R.drawable.ic_bubble_translate,
            MODE_REPLY to R.drawable.ic_bubble_reply,
            MODE_SUMMARIZE to R.drawable.ic_bubble_summarize,
            MODE_EXPLAIN to R.drawable.ic_bubble_explain,
            MODE_REFINE to R.drawable.ic_bubble_refine,
        )

        // Target languages user can cycle through in the overlay.
        // Persisted to Flutter SharedPreferences via the "flutter.tk_target_lang" key.
        internal val TARGET_LANGS = listOf(
            "en", "vi", "ja", "zh", "ko", "fr", "de", "es", "pt", "ru", "th", "id",
        )
        internal val LANG_LABELS = mapOf(
            "auto" to "Auto", "en" to "English", "vi" to "Tiếng Việt",
            "ja" to "日本語", "zh" to "中文", "ko" to "한국어",
            "fr" to "Français", "de" to "Deutsch", "es" to "Español",
            "pt" to "Português", "ru" to "Русский", "th" to "ไทย", "id" to "Indonesia",
        )
        private const val PREFS_NAME = "FlutterSharedPreferences"
        private const val KEY_TARGET_LANG = "flutter.tk_target_lang"
        private const val KEY_SOURCE_LANG = "flutter.tk_source_lang"
        private const val KEY_TONE_OVERRIDE = "flutter.tk_tone_override"
        private const val KEY_REPLY_TONE_OVERRIDE = "flutter.tk_reply_tone_override"
        private const val KEY_REPLY_LANG = "flutter.tk_reply_lang"
        private const val KEY_BUBBLE_ACTIVE = "flutter.tk_bubble_active"
        private const val KEY_ROMANIZATION = "flutter.tk_romanization"
        private const val KEY_REPLY_SUGGESTIONS = "flutter.tk_reply_suggestions"
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

        internal val SOURCE_LANGS = listOf("auto", "en", "vi", "ja", "zh", "ko", "fr", "de", "es", "pt", "ru", "th", "id")

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
    // `panel.heightPx > 0` pins a custom height. `panel.a11yWarning`
    // is the Reply-only banner shown above the action row when
    // Accessibility is off — Paste relies on the a11y service to
    // inject text into the currently-focused EditText. Without it the
    // button is greyed out. `panel.sourceExpanded` toggles between
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
    internal var currentTargetLang: String = "en"
    private var currentRequestId: Long = -1

    // Per-translation settings (read from SharedPreferences)
    internal var currentSourceLang: String = "auto"
    internal var currentTone: String = ""

    // Translation in-progress guard (prevents spam clicks)
    internal var isTranslating = false

    // Last translation context (used by Reply mode to determine target language + original message)
    internal var lastOriginalText: String? = null
    internal var lastDetectedLang: String? = null

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
        createBubbleNotificationChannel()
        startForeground(NOTIFICATION_ID, buildBubbleNotification())
        tts = TextToSpeech(this) { status -> ttsReady = (status == TextToSpeech.SUCCESS) }
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
                val reqId = intent.getLongExtra(EXTRA_REQUEST_ID, -1)
                if (reqId == currentRequestId) {
                    if (!translation.isNullOrBlank()) {
                        showResult(translation, romanization, detectedLang, suggestions)
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
            ACTION_SCAN_CANCELLED -> {
                // User dismissed the system consent dialog — just put the
                // bubble back. Manager state is also cleared so the next
                // scan starts from scratch (no stale token reuse path).
                ScreenCaptureManager.clearAll()
                restoreBubbleVisibility()
            }
        }
        return START_STICKY
    }

    override fun onDestroy() {
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
        hideLensOverlay()
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
        ensureWindowManager()
        val dp = resources.displayMetrics.density
        val bubbleSize = (BUBBLE_SIZE_DP * dp).toInt()

        val container = FrameLayout(this).apply {
            layoutParams = FrameLayout.LayoutParams(bubbleSize, bubbleSize)
            // Coloured ring frames the logo and changes by state.
            background = GradientDrawable().apply {
                shape = GradientDrawable.OVAL
                setColor(Color.TRANSPARENT)
                setStroke((2 * dp).toInt(), Color.parseColor("#6C63FF"))
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
                setColor(Color.parseColor("#6C63FF"))
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
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE,
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
                    (2 * dp).toInt(), Color.parseColor("#6C63FF"),
                )
                view.alpha = 0.95f
                badgeText?.visibility = View.GONE
            }
            STATE_LOADING -> {
                (view.background as? GradientDrawable)?.setStroke(
                    (2.5f * dp).toInt(), Color.parseColor("#6C63FF"),
                )
                view.alpha = 1.0f
                badgeText?.apply {
                    text = "…"
                    visibility = View.VISIBLE
                    (background as? GradientDrawable)?.setColor(Color.parseColor("#6C63FF"))
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
        android.util.Log.w("TKBubble", "handleTranslateRequest: mode=$mode textLen=${text.length} preview='${text.take(60).replace("\n", "⏎")}'")
        isTranslating = true
        currentSourceText = text
        currentOutput = null
        currentRomanization = null
        currentDetectedLang = null
        currentSuggestions = emptyList()
        currentMode = mode

        // Reply mode target language priority:
        //   1. Reply Language setting (if user picked a specific one) — always wins
        //   2. Sender's detected language (if a prior translation gave us context)
        //   3. General target language
        val replyToOriginal: String?
        if (mode == MODE_REPLY) {
            val replyLang = readReplyLang()
            currentTargetLang = when {
                replyLang.isNotEmpty() -> replyLang
                lastDetectedLang != null -> lastDetectedLang!!
                else -> readTargetLang()
            }
            replyToOriginal = lastOriginalText
        } else {
            currentTargetLang = readTargetLang()
            replyToOriginal = null
        }

        currentSourceLang = readSourceLang()
        currentTone = readTone()
        val reqId = ++nextRequestId
        currentRequestId = reqId
        showResultPanel(loading = true, error = null)
        val eng = TransKeyApp.engine
        if (eng != null) {
            invokeFlutterTranslate(eng, text, mode, currentTargetLang, reqId, replyToOriginal, attempt = 0)
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
    }

    internal fun readSourceLang(): String {
        return prefs.getString(KEY_SOURCE_LANG, "auto") ?: "auto"
    }

    internal fun writeSourceLang(lang: String) {
        prefs.edit()
            .putString(KEY_SOURCE_LANG, lang).apply()
        notifyFlutterLangChanged()
    }

    internal fun readTone(): String {
        return prefs.getString(KEY_TONE_OVERRIDE, "") ?: ""
    }

    internal fun readReplyLang(): String {
        return prefs.getString(KEY_REPLY_LANG, "") ?: ""
    }

    internal fun writeReplyLang(lang: String) {
        prefs.edit()
            .putString(KEY_REPLY_LANG, lang).apply()
        notifyFlutterLangChanged()
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

    // ── Reply tone / Romanization / Reply suggestions / TTS rate ─────────
    // All persisted under `flutter.tk_*` prefix so Flutter's SharedPreferences
    // package reads them as the same `tk_*` keys the in-app Settings screen
    // writes to. Reading happens at app resume via appSettingsProvider.reload()
    // and ttsProvider._loadPersistedPrefs().

    internal fun readReplyTone(): String {
        return prefs.getString(KEY_REPLY_TONE_OVERRIDE, "") ?: ""
    }

    internal fun writeReplyTone(tone: String) {
        prefs.edit()
            .putString(KEY_REPLY_TONE_OVERRIDE, tone).apply()
    }

    internal fun readRomanization(): Boolean {
        return prefs.getBoolean(KEY_ROMANIZATION, false)
    }

    internal fun writeRomanization(value: Boolean) {
        prefs.edit()
            .putBoolean(KEY_ROMANIZATION, value).apply()
    }

    internal fun readReplySuggestions(): Boolean {
        return prefs.getBoolean(KEY_REPLY_SUGGESTIONS, false)
    }

    internal fun writeReplySuggestions(value: Boolean) {
        prefs.edit()
            .putBoolean(KEY_REPLY_SUGGESTIONS, value).apply()
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

    @SuppressLint("ClickableViewAccessibility")

    internal fun handleScanRequest(mode: String = MODE_TRANSLATE) {
        ScreenCaptureManager.regionMode = false
        lastLensAction = LastLensAction(regionMode = false, mode = mode)
        if (prefs.getBoolean(KEY_SCAN_DISCLOSED, false)) {
            launchScanFlow(mode)
        } else {
            showScanDisclosure(mode)
        }
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
        ScreenCaptureManager.regionMode = true
        lastLensAction = LastLensAction(regionMode = true, mode = mode)
        if (prefs.getBoolean(KEY_SCAN_DISCLOSED, false)) {
            launchScanFlow(mode)
        } else {
            showScanDisclosure(mode)
        }
    }

    internal fun launchScanFlow(mode: String = MODE_TRANSLATE) {
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
        ScreenCaptureManager.languageHint = when (ScreenCaptureManager.flow) {
            ScreenCaptureManager.Flow.LENS              -> null
            ScreenCaptureManager.Flow.TEXT_INTO_INPUT   -> readSourceLang().takeIf { it != "auto" }
        }
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
        // OR auto-mode where ML Kit returned nothing readable. Sends the
        // bitmap through /translate-image?withBoxes=true so the overlay
        // still shows positioned chips — the only path Lens has for
        // scripts ML Kit literally cannot read.
        val hint = ScreenCaptureManager.languageHint
        val forceVision = OcrHelper.needsVisionForSource(hint)
        val autoFallback = blocks.isEmpty() && (hint.isNullOrEmpty() || hint == "auto")
        if (forceVision || autoFallback) {
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

        if (blocks.isEmpty()) {
            ScreenCaptureManager.clearAll()
            restoreBubbleVisibility()
            Toast.makeText(
                this,
                localized(R.string.bubble_scan_empty),
                Toast.LENGTH_LONG,
            ).show()
            return
        }

        showLensProgress()

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
                    val items = blocks.mapIndexed { idx, block ->
                        val t = translations.getOrNull(idx).takeUnless { it.isNullOrBlank() } ?: block.text
                        LensOverlayView.Item(block.text, t, block.bounds)
                    }
                    hideLensProgress()
                    showLensOverlay(bitmap, items)
                }
            }
            override fun error(code: String, message: String?, details: Any?) {
                handler.post {
                    hideLensProgress()
                    ScreenCaptureManager.clearAll()
                    restoreBubbleVisibility()
                    if (!bitmap.isRecycled) bitmap.recycle()
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
        // Cap long edge for the upload to keep token cost predictable
        // (vision input tokens scale with image pixels). 1600 px tracks
        // the camera-service compressForVision long-edge cap so behaviour
        // stays consistent between camera and Lens.
        val maxEdge = 1600
        val origW = bitmap.width
        val origH = bitmap.height
        val maxSide = maxOf(origW, origH)
        val upload = if (maxSide > maxEdge) {
            val scale = maxEdge.toFloat() / maxSide
            try {
                Bitmap.createScaledBitmap(
                    bitmap,
                    (origW * scale).toInt().coerceAtLeast(1),
                    (origH * scale).toInt().coerceAtLeast(1),
                    true,
                )
            } catch (e: Throwable) {
                android.util.Log.w("TKBubble", "lens-vision: scale failed: ${e.message}")
                bitmap
            }
        } else bitmap
        // Encode to JPEG q=85: balance between upload size and OCR
        // legibility. Quality below ~80 starts chewing fine-print
        // characters on dense menus; above 85 only adds bytes.
        val baos = java.io.ByteArrayOutputStream()
        upload.compress(Bitmap.CompressFormat.JPEG, 85, baos)
        if (upload !== bitmap && !upload.isRecycled) upload.recycle()
        val b64 = android.util.Base64.encodeToString(baos.toByteArray(), android.util.Base64.NO_WRAP)
        val target = ScreenCaptureManager.targetLang

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
                    } else items
                    onSuccessRecycle?.invoke()
                    hideLensProgress()
                    showLensOverlay(renderBitmap ?: bitmap, finalItems)
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
        showLensProgress()
        // Region mode + unsupported script: route the CROPPED bitmap
        // through vision. We keep the full screenshot (`bitmap`) live for
        // the underlying Lens overlay; the cropped pixels are only used
        // for the network call. Server returns boxes in the cropped's
        // pixel space, then runLensVisionTranslate adds rect.left/top so
        // the chips line up with the full screenshot beneath.
        val regionHint = ScreenCaptureManager.languageHint
        if (OcrHelper.needsVisionForSource(regionHint)) {
            // Aggregate into a single overlay item (matches the ML Kit
            // region behaviour: the user-drawn box is treated as ONE
            // unit, so one chip covers the whole selection).
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
            return
        }
        OcrHelper.recognizeBlocks(cropped, ScreenCaptureManager.languageHint) { blocks ->
            handler.post {
                // The cropped bitmap was only needed for OCR — recycle it
                // immediately so we don't hold ~MBs of pixels alongside the
                // still-live full screenshot.
                if (!cropped.isRecycled) cropped.recycle()
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
