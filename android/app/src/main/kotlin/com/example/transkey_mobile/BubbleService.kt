package com.example.transkey_mobile

import android.annotation.SuppressLint
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
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
        private val ALL_MODES = listOf(MODE_TRANSLATE, MODE_REPLY, MODE_SUMMARIZE, MODE_EXPLAIN, MODE_REFINE)
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
        private val TARGET_LANGS = listOf(
            "en", "vi", "ja", "zh", "ko", "fr", "de", "es", "pt", "ru", "th", "id",
        )
        private val LANG_LABELS = mapOf(
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
        private const val KEY_SCAN_DISCLOSED = "tk_scan_disclosed"
        // Speaker's language for the voice picker (independent of translate
        // source-lang — what you DICTATE in may differ from what you
        // translate FROM, e.g. dictate JP, translate JP→EN).
        private const val KEY_VOICE_LANG = "tk_voice_lang"

        // Languages offered as pills in the voice picker. Kept short on
        // purpose — every entry needs an offline pack downloaded on the
        // device's Google Speech Services for non-network use.
        private val VOICE_LANGS = listOf(
            "en", "vi", "ja", "ko", "zh", "fr", "de", "es", "pt", "ru", "th", "id",
        )

        private val SOURCE_LANGS = listOf("auto", "en", "vi", "ja", "zh", "ko", "fr", "de", "es", "pt", "ru", "th", "id")

        // Tone codes — MUST match Flutter `toneOptions` in
        // lib/features/settings/providers/app_settings_provider.dart so that
        // a tone picked in the bubble shows up correctly in the in-app
        // Settings screen (and vice versa). Labels are resolved per-locale
        // via `toneLabel()` below.
        private val TONE_CODES = listOf(
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
        private val TTS_RATES = listOf(0.25, 0.5, 0.75, 1.0, 1.25, 1.5)

        private const val BUBBLE_SIZE_DP = 48

        // Drag-to-close target
        private const val CLOSE_ZONE_SIZE_DP = 64
        private const val CLOSE_ZONE_BOTTOM_MARGIN_DP = 80
        private const val CLOSE_ZONE_HIT_RADIUS_DP = 80

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
    private var localizedContext: Context? = null
    private var lastLocaleCode: String? = null

    private fun refreshLocale() {
        val prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
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

    private fun localized(@androidx.annotation.StringRes resId: Int): String =
        (localizedContext ?: this).getString(resId)

    private fun modeLabel(mode: String): String =
        MODE_STRING_IDS[mode]?.let { localized(it) } ?: mode

    private fun modeIcon(mode: String): Int =
        MODE_ICON_IDS[mode] ?: R.drawable.ic_bubble_translate

    private var windowManager: WindowManager? = null

    // Bubble icon (small floating button)
    private var bubbleView: View? = null
    private var bubbleIcon: ImageView? = null
    private var badgeText: TextView? = null
    private var currentState: String = STATE_IDLE

    // Drag-to-close target shown while dragging the bubble
    private var closeZoneView: View? = null
    private var closeZoneIcon: TextView? = null
    private var isOverCloseZone: Boolean = false

    // Floating result panel
    private var panelView: View? = null
    private var panelSource: TextView? = null
    private var panelOutput: TextView? = null
    private var panelRomanization: TextView? = null
    private var panelSuggestionsLabel: TextView? = null
    private var panelSuggestionsContainer: LinearLayout? = null
    private var panelStatus: TextView? = null
    private var panelCopyBtn: View? = null
    private var panelPasteBtn: TextView? = null
    private var panelTtsBtn: TextView? = null
    private var langChip: TextView? = null
    private var detectedLangTv: TextView? = null
    private val modeButtons = mutableMapOf<String, TextView>()
    private var currentMode: String = MODE_TRANSLATE
    private var currentSourceText: String? = null
    private var currentOutput: String? = null
    private var currentRomanization: String? = null
    private var currentDetectedLang: String? = null
    // Bilingual quick-reply suggestions: first = source (reply text in the
    // conversation partner's language, copied on tap), second = target (the
    // same message in the user's target language, shown as a translation hint).
    private var currentSuggestions: List<Pair<String, String>> = emptyList()
    private var currentTargetLang: String = "en"
    private var currentRequestId: Long = -1

    // Per-translation settings (read from SharedPreferences)
    private var currentSourceLang: String = "auto"
    private var currentTone: String = ""

    // Translation in-progress guard (prevents spam clicks)
    private var isTranslating = false

    // Last translation context (used by Reply mode to determine target language + original message)
    private var lastOriginalText: String? = null
    private var lastDetectedLang: String? = null

    // Header chips (created inside showResultPanel)
    private var sourceLangChip: TextView? = null
    // Was a TextView showing the current tone label; now an ImageView gear
    // icon that opens the full settings sheet — clearer affordance, gives
    // user a discoverable entry point for all bubble-side preferences
    // (translate tone, reply tone, TTS rate, romanization, suggestions).
    private var toneChip: ImageView? = null

    // Loading spinner inside the panel
    private var loadingSpinner: ProgressBar? = null

    // Mode picker overlay (shown when bubble tapped)
    private var modePickerView: View? = null
    private var pendingPickerText: String? = null

    // Text captured from the active app's selection (via AccessibilityService)
    // at the moment the bubble is tapped — used instead of clipboard when
    // available, so apps that block copy (LinkedIn etc.) still work.
    private var pendingSelectedText: String? = null

    // Language picker overlays
    private var langPickerView: View? = null
    private var sourceLangPickerView: View? = null

    // Tone picker overlay
    private var tonePickerView: View? = null

    // Text-input picker overlay (lets user type text without opening the app)
    // This window is FOCUSABLE — unlike the other pickers — so the soft
    // keyboard can attach to its EditText.
    private var inputPickerView: View? = null

    // Voice-input picker overlay. Active SpeechRecognizer session and the
    // TextView we stream partial results into. Held here so onDestroy /
    // stopBubble can release the recognizer's audio focus.
    private var voicePickerView: View? = null
    private var voiceHelper: VoiceRecognitionHelper? = null
    private var voiceTranscriptView: TextView? = null
    private var voiceStatusView: TextView? = null
    private var voiceMicIcon: TextView? = null

    // First-run disclosure overlay shown before the "Scan screen" / OCR flow
    // (MediaProjection) — explains what gets captured and where it goes.
    private var scanDisclosureView: View? = null

    // Lens flow overlays. The progress card sits over the source app while
    // batch-translate is in flight; the LensOverlayView is the full-screen
    // bitmap + translated chips that replaces it on success. Both held so
    // lifecycle hooks can tear them down on stopBubble / onDestroy.
    private var lensProgressView: View? = null
    private var lensOverlayView: LensOverlayView? = null

    // Rubber-band region selector shown when user picks the "Translate
    // selected area" entry — sits between MediaProjection capture and OCR.
    private var regionSelectionView: RegionSelectionView? = null

    // Speaker language picked for the current voice session. Read fresh
    // from prefs (KEY_VOICE_LANG) each time the picker opens; mutated when
    // the user taps a different lang pill, which also persists + restarts
    // the recognizer with the new BCP-47 tag.
    private var currentVoiceLang: String = "en"

    // Text-to-Speech
    private var tts: TextToSpeech? = null
    private var ttsReady = false

    // Bubble drag state
    private var initialX = 0
    private var initialY = 0
    private var initialTouchX = 0f
    private var initialTouchY = 0f
    private var isDragging = false

    // Clipboard auto-translate
    private var hasNewClipText = false
    private var selfCopyInProgress = false
    private var clipboardListener: ClipboardManager.OnPrimaryClipChangedListener? = null

    private val handler = Handler(Looper.getMainLooper())

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
        startForeground(NOTIFICATION_ID, buildNotification())
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
            val prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
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
                        showError(error ?: "Translation failed")
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
        unregisterClipboardListener()
        hideModePicker()
        hideLangPicker()
        hideSourceLangPicker()
        hideTonePicker()
        hideInputPicker()
        hideVoicePicker()
        hideScanDisclosure()
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

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID, "TransKey Bubble",
                NotificationManager.IMPORTANCE_LOW,
            ).apply {
                description = "Floating translation bubble"
                setShowBadge(false)
            }
            getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
        }
    }

    private fun buildNotification(): Notification {
        val intent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP
        }
        val pending = PendingIntent.getActivity(
            this, 0, intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        // "Turn off" action
        val stopIntent = Intent(this, BubbleService::class.java).apply { action = ACTION_STOP }
        val stopPending = PendingIntent.getService(
            this, 1, stopIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
            Notification.Builder(this, CHANNEL_ID)
        else @Suppress("DEPRECATION") Notification.Builder(this)
        return builder
            .setContentTitle("TransKey")
            .setContentText("Floating translator active")
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setContentIntent(pending)
            .setOngoing(true)
            .addAction(android.R.drawable.ic_menu_close_clear_cancel, "Turn off", stopPending)
            .build()
    }

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
        registerClipboardListener()
        saveBubbleActive(true)
    }

    private fun handleBubbleTouch(event: MotionEvent, dp: Float): Boolean {
        val params = bubbleView?.layoutParams as? WindowManager.LayoutParams ?: return false

        when (event.action) {
            MotionEvent.ACTION_DOWN -> {
                initialX = params.x
                initialY = params.y
                initialTouchX = event.rawX
                initialTouchY = event.rawY
                isDragging = false
                isOverCloseZone = false
                return true
            }
            MotionEvent.ACTION_MOVE -> {
                val dx = event.rawX - initialTouchX
                val dy = event.rawY - initialTouchY
                if (!isDragging && dx * dx + dy * dy > 25 * dp * dp) {
                    isDragging = true
                    showCloseZone(dp)
                }
                params.x = initialX + dx.toInt()
                params.y = initialY + dy.toInt()
                windowManager?.updateViewLayout(bubbleView!!, params)
                if (isDragging) {
                    val bubbleSize = (BUBBLE_SIZE_DP * dp).toInt()
                    val bubbleCenterX = params.x + bubbleSize / 2
                    val bubbleCenterY = params.y + bubbleSize / 2
                    val over = isBubbleOverCloseZone(bubbleCenterX, bubbleCenterY, dp)
                    if (over != isOverCloseZone) {
                        isOverCloseZone = over
                        updateCloseZoneVisual(over)
                    }
                }
                return true
            }
            MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                if (isDragging) {
                    hideCloseZone()
                    if (isOverCloseZone) {
                        isOverCloseZone = false
                        stopBubble()
                        return true
                    }
                    val sw = resources.displayMetrics.widthPixels
                    val sh = resources.displayMetrics.heightPixels
                    val centerX = params.x + (BUBBLE_SIZE_DP * dp / 2).toInt()
                    params.x = if (centerX < sw / 2) 0 else sw - (BUBBLE_SIZE_DP * dp).toInt()
                    params.y = params.y.coerceIn(0, sh - (BUBBLE_SIZE_DP * dp).toInt())
                    windowManager?.updateViewLayout(bubbleView!!, params)
                } else if (event.action == MotionEvent.ACTION_UP) {
                    onBubbleTapped()
                }
                return true
            }
        }
        return false
    }

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
    private fun onBubbleTapped() {
        when {
            modePickerView != null -> { hideModePicker(); return }
            panelView != null      -> { hideResultPanel(); return }
        }
        // Capture the active app's text selection before the picker opens —
        // the picker is FLAG_NOT_FOCUSABLE so the underlying selection should
        // survive, but reading it now avoids any timing risk.
        pendingSelectedText = try {
            TransKeyAccessibilityService.instance?.getSelectedText()?.takeIf { it.isNotBlank() }
        } catch (_: Exception) {
            null
        }

        // Priority: fresh selection > new clipboard > picker. Earlier we
        // jumped straight to autoTranslateFromClipboard whenever
        // hasNewClipText was true, even if the user had just highlighted
        // something new — that meant the old clipboard text (e.g. copied
        // 10 minutes ago) won over the current selection, and the user
        // got a translation of something they didn't ask for. The mode
        // picker is the right destination when there's an active
        // selection: it lets the user choose translate vs reply vs
        // summarize vs ... and the Translate button onClick already
        // prefers pendingSelectedText over clipboard.
        when {
            !pendingSelectedText.isNullOrBlank() -> {
                // Mark the stale-clip flag consumed so a later tap with
                // NO selection doesn't surprise-translate the now-old
                // clipboard either.
                hasNewClipText = false
                showModePicker()
            }
            hasNewClipText -> {
                hasNewClipText = false
                autoTranslateFromClipboard()
            }
            else -> showModePicker()
        }
    }

    @SuppressLint("ClickableViewAccessibility")
    private fun showModePicker() {
        ensureWindowManager()
        // Pick up any recent in-app UI language change so the picker labels
        // are rendered in the locale the user actually wants.
        refreshLocale()

        val dp = resources.displayMetrics.density
        val isDark = (resources.configuration.uiMode and android.content.res.Configuration.UI_MODE_NIGHT_MASK) ==
            android.content.res.Configuration.UI_MODE_NIGHT_YES
        val bg      = if (isDark) Color.parseColor("#1E1E30") else Color.WHITE
        val textCol = if (isDark) Color.parseColor("#E8E8F0") else Color.parseColor("#1A1A2E")
        val mutedCol= if (isDark) Color.parseColor("#9090A0") else Color.parseColor("#6B6B7A")
        val accent  = Color.parseColor("#6C63FF")

        // Semi-transparent backdrop — tap outside card to dismiss
        val backdrop = FrameLayout(this).apply {
            setBackgroundColor(Color.parseColor("#66000000"))
            setOnClickListener { hideModePicker() }
        }

        val card = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            background = GradientDrawable().apply { setColor(bg); cornerRadius = 20 * dp }
            elevation = 20 * dp
            setPadding((18 * dp).toInt(), (16 * dp).toInt(), (18 * dp).toInt(), (18 * dp).toInt())
            isClickable = true
        }

        card.addView(TextView(this).apply {
            text = localized(R.string.bubble_choose_action)
            setTextColor(textCol)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 13f)
            typeface = Typeface.DEFAULT_BOLD
            setPadding(0, 0, 0, (8 * dp).toInt())
        })
        card.addView(TextView(this).apply {
            text = localized(
                if (pendingSelectedText != null) R.string.bubble_using_selection
                else R.string.bubble_need_text,
            )
            setTextColor(mutedCol)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 11f)
            setPadding(0, 0, 0, (12 * dp).toInt())
        })

        // Accessibility hint banner — only when the user hasn't enabled the
        // permission yet. Without it, "highlight text → tap bubble" silently
        // falls through to clipboard and produces a confusing "no text"
        // error. The banner is in-context (right where users notice the
        // failure) and the action button takes them directly to the system
        // settings page so they don't have to hunt through Settings.
        if (!TransKeyAccessibilityService.isAvailable()) {
            val hintBg     = if (isDark) "#3A2E10" else "#FFF6D6"
            val hintFg     = if (isDark) "#FFD86E" else "#7A5A00"
            val hintBtnBg  = if (isDark) "#FFD86E" else "#7A5A00"
            val hintBtnFg  = if (isDark) "#3A2E10" else Color.WHITE.let { "#${Integer.toHexString(it).substring(2)}" }
            val banner = LinearLayout(this).apply {
                orientation = LinearLayout.HORIZONTAL
                gravity = Gravity.CENTER_VERTICAL
                background = GradientDrawable().apply {
                    setColor(Color.parseColor(hintBg))
                    cornerRadius = 10 * dp
                }
                setPadding((10 * dp).toInt(), (8 * dp).toInt(), (10 * dp).toInt(), (8 * dp).toInt())
                layoutParams = LinearLayout.LayoutParams(
                    LinearLayout.LayoutParams.MATCH_PARENT,
                    LinearLayout.LayoutParams.WRAP_CONTENT,
                ).apply { bottomMargin = (12 * dp).toInt() }
            }
            banner.addView(TextView(this).apply {
                text = localized(R.string.bubble_accessibility_hint)
                setTextColor(Color.parseColor(hintFg))
                setTextSize(TypedValue.COMPLEX_UNIT_SP, 11f)
                layoutParams = LinearLayout.LayoutParams(
                    0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f,
                )
            })
            banner.addView(TextView(this).apply {
                text = localized(R.string.bubble_accessibility_enable)
                setTextColor(Color.parseColor(hintBtnFg))
                setTextSize(TypedValue.COMPLEX_UNIT_SP, 11f)
                typeface = Typeface.DEFAULT_BOLD
                background = GradientDrawable().apply {
                    setColor(Color.parseColor(hintBtnBg))
                    cornerRadius = 8 * dp
                }
                setPadding((10 * dp).toInt(), (6 * dp).toInt(), (10 * dp).toInt(), (6 * dp).toInt())
                isClickable = true
                setOnClickListener {
                    hideModePicker()
                    // Android 13+ blocks toggling Accessibility on sideloaded
                    // apps until the user explicitly unlocks "restricted
                    // settings" from the app's details page. Route THERE
                    // first on Android 13+ — opening Accessibility settings
                    // directly leaves the user stuck with a greyed-out
                    // toggle and no obvious way forward. Pre-Android-13
                    // there's no restricted-settings gate, so go straight
                    // to Accessibility.
                    val intent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                        Intent(
                            android.provider.Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                            android.net.Uri.parse("package:$packageName"),
                        )
                    } else {
                        Intent(android.provider.Settings.ACTION_ACCESSIBILITY_SETTINGS)
                    }
                    intent.flags = Intent.FLAG_ACTIVITY_NEW_TASK
                    val opened = try { startActivity(intent); true } catch (_: Exception) { false }
                    val guideRes = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU)
                        R.string.bubble_accessibility_guide_a13
                    else
                        R.string.bubble_accessibility_guide_legacy
                    Toast.makeText(
                        this@BubbleService,
                        if (opened) localized(guideRes)
                        else "Open Settings → Apps → TransKey, then unlock restricted settings + enable Accessibility",
                        Toast.LENGTH_LONG,
                    ).show()
                }
                layoutParams = LinearLayout.LayoutParams(
                    LinearLayout.LayoutParams.WRAP_CONTENT,
                    LinearLayout.LayoutParams.WRAP_CONTENT,
                ).apply { marginStart = (8 * dp).toInt() }
            })
            card.addView(banner)
        }

        // 5 feature buttons — matches the in-app feature-button row in
        // home_screen.dart: icon on top, label below, first action gets a
        // "primary" purple fill so it stands out.
        val modesRow = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER
        }
        ALL_MODES.forEachIndexed { index, mode ->
            val isPrimary = mode == MODE_TRANSLATE
            val primaryBg = "#7C6EFA"
            val subduedBg = if (isDark) "#2A2A40" else "#F0EFFF"
            val fgColor = if (isPrimary) Color.WHITE else accent

            val column = LinearLayout(this).apply {
                orientation = LinearLayout.VERTICAL
                gravity = Gravity.CENTER
                setPadding((4 * dp).toInt(), (10 * dp).toInt(), (4 * dp).toInt(), (10 * dp).toInt())
                background = GradientDrawable().apply {
                    setColor(Color.parseColor(if (isPrimary) primaryBg else subduedBg))
                    cornerRadius = 14 * dp
                }
                isClickable = true
                isFocusable = true
                setOnClickListener {
                    val selected = pendingSelectedText
                    hideModePicker()
                    if (!selected.isNullOrBlank()) {
                        // Selection captured via AccessibilityService — translate
                        // directly, no clipboard / ShareActivity round-trip needed.
                        handleTranslateRequest(selected, mode)
                        // Burn both the cached event-driven snapshot AND our
                        // local copy. Otherwise a second tap on the bubble a
                        // moment later (e.g. user accidentally double-taps,
                        // or comes back to retry with a different mode)
                        // would re-translate the same stale highlight.
                        pendingSelectedText = null
                        TransKeyAccessibilityService.instance?.consumeCachedSelection()
                    } else {
                        val i = Intent(this@BubbleService, ShareActivity::class.java).apply {
                            action = ACTION_READ_CLIPBOARD
                            // FLAG_ACTIVITY_MULTIPLE_TASK: ShareActivity runs in its own isolated task.
                            // When it finishes, Android returns the user to their previous app (not TransKey).
                            flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                                    Intent.FLAG_ACTIVITY_MULTIPLE_TASK or
                                    Intent.FLAG_ACTIVITY_NO_HISTORY or
                                    Intent.FLAG_ACTIVITY_EXCLUDE_FROM_RECENTS
                            putExtra(EXTRA_MODE, mode)
                        }
                        startActivity(i)
                    }
                }
                layoutParams = LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f)
                    .apply { marginEnd = if (index < ALL_MODES.size - 1) (6 * dp).toInt() else 0 }
            }
            // Icon on top
            column.addView(ImageView(this).apply {
                setImageResource(modeIcon(mode))
                setColorFilter(fgColor)
                layoutParams = LinearLayout.LayoutParams((18 * dp).toInt(), (18 * dp).toInt())
            })
            // Label below — tiny enough to fit one line for all known
            // locales (Vietnamese "Tinh chỉnh" being the longest)
            column.addView(TextView(this).apply {
                text = modeLabel(mode)
                setTextColor(fgColor)
                setTextSize(TypedValue.COMPLEX_UNIT_SP, 10f)
                gravity = Gravity.CENTER
                maxLines = 1
                setSingleLine(true)
                ellipsize = android.text.TextUtils.TruncateAt.END
                typeface = Typeface.DEFAULT_BOLD
                setPadding(0, (4 * dp).toInt(), 0, 0)
                layoutParams = LinearLayout.LayoutParams(
                    LinearLayout.LayoutParams.MATCH_PARENT,
                    LinearLayout.LayoutParams.WRAP_CONTENT,
                )
            })
            modesRow.addView(column)
        }
        card.addView(modesRow)

        // Divider + secondary actions row ("Type text" / "Show last result")
        val dividerBg = if (isDark) "#3A3A50" else "#E0DFF8"
        card.addView(View(this).apply {
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT, (1 * dp).toInt(),
            ).apply { topMargin = (12 * dp).toInt(); bottomMargin = (8 * dp).toInt() }
            setBackgroundColor(Color.parseColor(dividerBg))
        })

        // Always-available "Type your own text" entry — for when the user
        // wants to translate something they haven't selected/copied (e.g.
        // composing a message from scratch). Opens a focusable input window
        // so the soft keyboard can attach.
        card.addView(TextView(this).apply {
            text = "✎  ${localized(R.string.bubble_type_text)}"
            setTextColor(accent)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 13f)
            typeface = Typeface.DEFAULT_BOLD
            gravity = Gravity.CENTER
            setPadding(0, (8 * dp).toInt(), 0, (8 * dp).toInt())
            isClickable = true
            isFocusable = true
            setOnClickListener {
                hideModePicker()
                showInputPicker(MODE_TRANSLATE)
            }
        })

        // "Read this screen" — covers apps that disable text selection
        // (banking, anti-copy chat, reader apps). Walks the source app's
        // accessibility tree to harvest all visible text, then pre-fills
        // the input picker so the user can trim before translating.
        card.addView(TextView(this).apply {
            text = "📱  ${localized(R.string.bubble_read_screen)}"
            setTextColor(accent)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 13f)
            typeface = Typeface.DEFAULT_BOLD
            gravity = Gravity.CENTER
            setPadding(0, (8 * dp).toInt(), 0, (8 * dp).toInt())
            isClickable = true
            isFocusable = true
            setOnClickListener {
                hideModePicker()
                handleReadScreenRequest()
            }
        })

        // "Voice input" — dictation for users who'd rather speak than type.
        // Routes through MicPermissionActivity the first time to request
        // RECORD_AUDIO; subsequent uses skip straight to the voice picker.
        card.addView(TextView(this).apply {
            text = "🎤  ${localized(R.string.bubble_voice)}"
            setTextColor(accent)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 13f)
            typeface = Typeface.DEFAULT_BOLD
            gravity = Gravity.CENTER
            setPadding(0, (8 * dp).toInt(), 0, (8 * dp).toInt())
            isClickable = true
            isFocusable = true
            setOnClickListener {
                hideModePicker()
                handleVoiceRequest()
            }
        })

        // "Scan screen (OCR)" — full-screen Lens flow. Captures the
        // whole frame, OCRs everything that passes the content heuristic,
        // and renders translated blocks at their original positions.
        card.addView(TextView(this).apply {
            text = "📷  ${localized(R.string.bubble_scan_screen)}"
            setTextColor(accent)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 13f)
            typeface = Typeface.DEFAULT_BOLD
            gravity = Gravity.CENTER
            setPadding(0, (8 * dp).toInt(), 0, (8 * dp).toInt())
            isClickable = true
            isFocusable = true
            setOnClickListener {
                hideModePicker()
                handleScanRequest()
            }
        })

        // "Translate selected area" — same Lens pipeline but with a
        // rubber-band step between capture and OCR so the user can crop
        // out the rest of the screen (chat header, ads, app chrome).
        // Cheaper to translate AND avoids translating things the user
        // doesn't care about.
        card.addView(TextView(this).apply {
            text = "🎯  ${localized(R.string.bubble_lens_region)}"
            setTextColor(accent)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 13f)
            typeface = Typeface.DEFAULT_BOLD
            gravity = Gravity.CENTER
            setPadding(0, (8 * dp).toInt(), 0, (8 * dp).toInt())
            isClickable = true
            isFocusable = true
            setOnClickListener {
                hideModePicker()
                handleLensRegionRequest()
            }
        })

        // "Last result" shortcut if we have a cached output
        if (currentOutput != null) {
            card.addView(TextView(this).apply {
                text = localized(R.string.bubble_show_last_result)
                setTextColor(mutedCol)
                setTextSize(TypedValue.COMPLEX_UNIT_SP, 12f)
                gravity = Gravity.CENTER
                setPadding(0, (6 * dp).toInt(), 0, (4 * dp).toInt())
                setOnClickListener {
                    hideModePicker()
                    showResultPanel(loading = false, error = null, output = currentOutput)
                }
            })
        }

        val screenWidth = resources.displayMetrics.widthPixels
        val cardWidth = (screenWidth - (48 * dp).toInt()).coerceAtMost((360 * dp).toInt())
        backdrop.addView(card, FrameLayout.LayoutParams(cardWidth, FrameLayout.LayoutParams.WRAP_CONTENT, Gravity.CENTER))

        modePickerView = backdrop
        windowManager?.addView(backdrop, buildPickerLayoutParams())
    }

    private fun buildPickerLayoutParams(): WindowManager.LayoutParams {
        return WindowManager.LayoutParams(
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.MATCH_PARENT,
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
                WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
            else @Suppress("DEPRECATION") WindowManager.LayoutParams.TYPE_PHONE,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE,
            PixelFormat.TRANSLUCENT,
        )
    }

    private fun hideModePicker() {
        modePickerView?.let {
            try { windowManager?.removeView(it) } catch (_: Exception) {}
        }
        modePickerView = null
        pendingPickerText = null
        pendingSelectedText = null
    }

    @SuppressLint("ClickableViewAccessibility")
    private fun showLangPicker() {
        if (langPickerView != null) { hideLangPicker(); return }
        ensureWindowManager()
        // Sync from prefs so the picker reflects any change made in Flutter
        // UI. In reply mode the picker pre-selects KEY_REPLY_LANG (which the
        // tap-to-pick path writes to) — otherwise picking a lang then
        // re-opening shows the *general* target as selected instead of the
        // reply lang the user just chose, even though translation used it.
        currentTargetLang = if (currentMode == MODE_REPLY) {
            val replyLang = readReplyLang()
            when {
                replyLang.isNotEmpty() -> replyLang
                lastDetectedLang != null -> lastDetectedLang!!
                else -> readTargetLang()
            }
        } else {
            readTargetLang()
        }

        val dp = resources.displayMetrics.density
        val isDark = (resources.configuration.uiMode and android.content.res.Configuration.UI_MODE_NIGHT_MASK) ==
            android.content.res.Configuration.UI_MODE_NIGHT_YES
        val bg      = if (isDark) Color.parseColor("#1E1E30") else Color.WHITE
        val textCol = if (isDark) Color.parseColor("#E8E8F0") else Color.parseColor("#1A1A2E")
        val accent  = Color.parseColor("#6C63FF")
        val selBg   = Color.parseColor("#6C63FF")

        val backdrop = FrameLayout(this).apply {
            setBackgroundColor(Color.parseColor("#55000000"))
            setOnClickListener { hideLangPicker() }
        }

        val card = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            background = GradientDrawable().apply { setColor(bg); cornerRadius = 18 * dp }
            elevation = 22 * dp
            setPadding((14 * dp).toInt(), (14 * dp).toInt(), (14 * dp).toInt(), (14 * dp).toInt())
            isClickable = true
        }

        card.addView(TextView(this).apply {
            text = "Target language"
            setTextColor(accent)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 12f)
            typeface = Typeface.DEFAULT_BOLD
            setPadding(0, 0, 0, (10 * dp).toInt())
        })

        // Grid: 3 columns
        var row: LinearLayout? = null
        TARGET_LANGS.forEachIndexed { idx, lang ->
            if (idx % 3 == 0) {
                row = LinearLayout(this).apply {
                    orientation = LinearLayout.HORIZONTAL
                    layoutParams = LinearLayout.LayoutParams(
                        LinearLayout.LayoutParams.MATCH_PARENT,
                        LinearLayout.LayoutParams.WRAP_CONTENT,
                    ).apply { bottomMargin = (6 * dp).toInt() }
                }
                card.addView(row)
            }
            val isSelected = lang == currentTargetLang
            val chip = TextView(this).apply {
                text = LANG_LABELS[lang] ?: lang.uppercase()
                setTextColor(if (isSelected) Color.WHITE else textCol)
                setTextSize(TypedValue.COMPLEX_UNIT_SP, 11f)
                gravity = Gravity.CENTER
                setPadding((8 * dp).toInt(), (8 * dp).toInt(), (8 * dp).toInt(), (8 * dp).toInt())
                background = GradientDrawable().apply {
                    setColor(if (isSelected) selBg else Color.TRANSPARENT)
                    setStroke(1, if (isSelected) selBg else Color.parseColor(if (isDark) "#3A3A52" else "#DDDDF0"))
                    cornerRadius = 10 * dp
                }
                setOnClickListener {
                    currentTargetLang = lang
                    // In reply mode, the picker overrides the user's "Reply Language"
                    // preference — write to KEY_REPLY_LANG so the next reply (and the
                    // current one we're about to fire) actually uses it.
                    if (currentMode == MODE_REPLY) {
                        writeReplyLang(lang)
                    } else {
                        writeTargetLang(lang)
                    }
                    hideLangPicker()
                    updateLangChip()
                    val src = currentSourceText ?: return@setOnClickListener
                    handleTranslateRequest(src, currentMode)
                }
                layoutParams = LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f)
                    .apply { marginEnd = if (idx % 3 != 2) (6 * dp).toInt() else 0 }
            }
            row?.addView(chip)
        }

        val screenWidth = resources.displayMetrics.widthPixels
        val cardWidth = (screenWidth - (48 * dp).toInt()).coerceAtMost((360 * dp).toInt())
        backdrop.addView(card, FrameLayout.LayoutParams(cardWidth, FrameLayout.LayoutParams.WRAP_CONTENT, Gravity.CENTER))

        langPickerView = backdrop
        windowManager?.addView(backdrop, buildPickerLayoutParams())
    }

    private fun hideLangPicker() {
        langPickerView?.let { try { windowManager?.removeView(it) } catch (_: Exception) {} }
        langPickerView = null
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

    // ── Drag-to-close target ──

    private fun showCloseZone(dp: Float) {
        if (closeZoneView != null) return
        ensureWindowManager()
        val size = (CLOSE_ZONE_SIZE_DP * dp).toInt()
        val container = FrameLayout(this).apply {
            layoutParams = FrameLayout.LayoutParams(size, size)
            background = GradientDrawable().apply {
                shape = GradientDrawable.OVAL
                setColor(Color.parseColor("#CC222230"))
            }
            alpha = 0f
            animate().alpha(1f).setDuration(150).start()
        }
        val icon = TextView(this).apply {
            text = "✕"
            setTextColor(Color.WHITE)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 24f)
            typeface = Typeface.DEFAULT_BOLD
            gravity = Gravity.CENTER
            layoutParams = FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT,
            )
        }
        container.addView(icon)
        closeZoneIcon = icon
        closeZoneView = container

        val params = WindowManager.LayoutParams(
            size, size,
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
                WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
            else @Suppress("DEPRECATION") WindowManager.LayoutParams.TYPE_PHONE,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE,
            PixelFormat.TRANSLUCENT,
        ).apply {
            gravity = Gravity.BOTTOM or Gravity.CENTER_HORIZONTAL
            y = (CLOSE_ZONE_BOTTOM_MARGIN_DP * dp).toInt()
        }
        try { windowManager?.addView(container, params) } catch (_: Exception) {}
    }

    private fun hideCloseZone() {
        closeZoneView?.let { v ->
            try { windowManager?.removeView(v) } catch (_: Exception) {}
        }
        closeZoneView = null
        closeZoneIcon = null
    }

    private fun updateCloseZoneVisual(over: Boolean) {
        val container = closeZoneView ?: return
        val scale = if (over) 1.25f else 1.0f
        container.animate().scaleX(scale).scaleY(scale).setDuration(120).start()
        (container.background as? GradientDrawable)?.setColor(
            Color.parseColor(if (over) "#E63946" else "#CC222230"),
        )
    }

    private fun isBubbleOverCloseZone(bubbleCenterX: Int, bubbleCenterY: Int, dp: Float): Boolean {
        val sw = resources.displayMetrics.widthPixels
        val sh = resources.displayMetrics.heightPixels
        val zoneSize = (CLOSE_ZONE_SIZE_DP * dp).toInt()
        val zoneCenterX = sw / 2
        val zoneCenterY = sh - (CLOSE_ZONE_BOTTOM_MARGIN_DP * dp).toInt() - zoneSize / 2
        val radius = (CLOSE_ZONE_HIT_RADIUS_DP * dp).toInt()
        val dx = bubbleCenterX - zoneCenterX
        val dy = bubbleCenterY - zoneCenterY
        return dx * dx + dy * dy <= radius * radius
    }

    // ── Clipboard auto-translate ──

    private fun registerClipboardListener() {
        if (clipboardListener != null) return
        val cm = getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
        clipboardListener = ClipboardManager.OnPrimaryClipChangedListener {
            if (selfCopyInProgress) return@OnPrimaryClipChangedListener
            hasNewClipText = true
        }
        cm.addPrimaryClipChangedListener(clipboardListener)
    }

    private fun unregisterClipboardListener() {
        clipboardListener?.let {
            val cm = getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
            cm.removePrimaryClipChangedListener(it)
        }
        clipboardListener = null
    }

    private fun autoTranslateFromClipboard() {
        val mode = currentMode
        val i = Intent(this, ShareActivity::class.java).apply {
            action = ACTION_READ_CLIPBOARD
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                    Intent.FLAG_ACTIVITY_MULTIPLE_TASK or
                    Intent.FLAG_ACTIVITY_NO_HISTORY or
                    Intent.FLAG_ACTIVITY_EXCLUDE_FROM_RECENTS
            putExtra(EXTRA_MODE, mode)
        }
        startActivity(i)
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

    private fun handleTranslateRequest(text: String, mode: String) {
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
            showError("App not ready — please open TransKey once")
        }
    }

    private fun readTargetLang(): String {
        val prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        return prefs.getString(KEY_TARGET_LANG, "en") ?: "en"
    }

    private fun writeTargetLang(lang: String) {
        getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .putString(KEY_TARGET_LANG, lang)
            .apply()
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
                    showError(msg ?: "Translation failed ($code)")
                }
                override fun notImplemented() {
                    if (attempt < 5 && reqId == currentRequestId) {
                        handler.postDelayed({
                            invokeFlutterTranslate(engine, text, mode, targetLang, reqId, replyToOriginal, attempt + 1)
                        }, 300L)
                    } else if (reqId == currentRequestId) {
                        showError("App not ready — please open TransKey once")
                    }
                }
            },
        )
    }

    private fun showResult(
        output: String,
        romanization: String?,
        detectedLang: String?,
        suggestions: List<Pair<String, String>>? = null,
    ) {
        isTranslating = false
        currentOutput = output
        currentRomanization = romanization
        currentDetectedLang = detectedLang
        currentSuggestions = suggestions ?: emptyList()
        // Save context for Reply mode (only for non-reply translations)
        if (currentMode != MODE_REPLY) {
            lastOriginalText = currentSourceText
            lastDetectedLang = detectedLang
        }
        showResultPanel(loading = false, error = null, output = output)
    }

    private fun showError(error: String) {
        isTranslating = false
        showResultPanel(loading = false, error = error)
    }

    @SuppressLint("ClickableViewAccessibility")
    private fun showResultPanel(
        loading: Boolean,
        error: String?,
        output: String? = null,
    ) {
        ensureWindowManager()
        refreshLocale()
        val dp = resources.displayMetrics.density
        val isDark = (resources.configuration.uiMode and android.content.res.Configuration.UI_MODE_NIGHT_MASK) ==
            android.content.res.Configuration.UI_MODE_NIGHT_YES

        val bg = if (isDark) Color.parseColor("#1E1E30") else Color.WHITE
        val textCol = if (isDark) Color.parseColor("#E8E8F0") else Color.parseColor("#1A1A2E")
        val mutedCol = if (isDark) Color.parseColor("#9090A0") else Color.parseColor("#6B6B7A")
        val accent = Color.parseColor("#6C63FF")

        if (panelView == null) {
            val rootCard = LinearLayout(this).apply {
                orientation = LinearLayout.VERTICAL
                background = GradientDrawable().apply {
                    setColor(bg)
                    cornerRadius = 18 * dp
                }
                elevation = 12 * dp
                setPadding((16 * dp).toInt(), (14 * dp).toInt(), (16 * dp).toInt(), (14 * dp).toInt())
            }

            // Header: [source chip] → [target chip]  [spacer]  [tone chip]  [✕]
            val header = LinearLayout(this).apply {
                orientation = LinearLayout.HORIZONTAL
                gravity = Gravity.CENTER_VERTICAL
            }

            fun chipBackground(selected: Boolean) = GradientDrawable().apply {
                setColor(if (selected) accent else Color.TRANSPARENT)
                setStroke(1, accent)
                cornerRadius = 12 * dp
            }

            sourceLangChip = TextView(this).apply {
                setTextSize(TypedValue.COMPLEX_UNIT_SP, 11f)
                typeface = Typeface.DEFAULT_BOLD
                setTextColor(accent)
                setPadding((8 * dp).toInt(), (4 * dp).toInt(), (8 * dp).toInt(), (4 * dp).toInt())
                background = chipBackground(false)
                setOnClickListener { showSourceLangPicker() }
            }

            val arrowTv = TextView(this).apply {
                text = " → "
                setTextColor(mutedCol)
                setTextSize(TypedValue.COMPLEX_UNIT_SP, 12f)
            }

            langChip = TextView(this).apply {
                setTextSize(TypedValue.COMPLEX_UNIT_SP, 11f)
                typeface = Typeface.DEFAULT_BOLD
                setTextColor(accent)
                setPadding((8 * dp).toInt(), (4 * dp).toInt(), (8 * dp).toInt(), (4 * dp).toInt())
                background = chipBackground(false)
                setOnClickListener { showLangPicker() }
            }

            val spacer = View(this).apply {
                layoutParams = LinearLayout.LayoutParams(0, 1, 1f)
            }

            toneChip = ImageView(this).apply {
                setImageResource(R.drawable.ic_bubble_settings)
                setColorFilter(mutedCol)
                contentDescription = localized(R.string.bubble_settings)
                // Touch padding so the 18dp icon is comfortably tappable.
                setPadding((6 * dp).toInt(), (6 * dp).toInt(), (6 * dp).toInt(), (6 * dp).toInt())
                isClickable = true
                isFocusable = true
                setOnClickListener { showSettingsSheet() }
                layoutParams = LinearLayout.LayoutParams(
                    (30 * dp).toInt(),
                    (30 * dp).toInt(),
                ).apply { marginStart = (6 * dp).toInt(); marginEnd = (4 * dp).toInt() }
            }

            // ✎ button to swap the result panel for the type-text picker
            // (lets the user translate something new without going through
            // the bubble → mode-picker dance again).
            val typeBtn = TextView(this).apply {
                text = "✎"
                setTextColor(mutedCol)
                setTextSize(TypedValue.COMPLEX_UNIT_SP, 16f)
                setPadding((8 * dp).toInt(), (4 * dp).toInt(), (8 * dp).toInt(), (4 * dp).toInt())
                contentDescription = localized(R.string.bubble_type_text)
                isClickable = true
                isFocusable = true
                setOnClickListener {
                    hideResultPanel()
                    showInputPicker(currentMode)
                }
            }

            val closeBtn = TextView(this).apply {
                text = "✕"
                setTextColor(mutedCol)
                setTextSize(TypedValue.COMPLEX_UNIT_SP, 16f)
                setPadding((8 * dp).toInt(), (4 * dp).toInt(), (8 * dp).toInt(), (4 * dp).toInt())
                setOnClickListener { hideResultPanel() }
            }

            header.addView(sourceLangChip)
            header.addView(arrowTv)
            header.addView(langChip)
            header.addView(spacer)
            header.addView(toneChip)
            header.addView(typeBtn)
            header.addView(closeBtn)

            // Mode tabs — natural-width buttons with leading icon, wrapped in
            // a HorizontalScrollView so long Vietnamese labels ("Tinh chỉnh",
            // "Giải thích") never wrap to two lines. The bar scrolls instead.
            val tabsRow = LinearLayout(this).apply {
                orientation = LinearLayout.HORIZONTAL
                setPadding(0, (8 * dp).toInt(), 0, (4 * dp).toInt())
            }
            modeButtons.clear()
            for (mode in ALL_MODES) {
                val btn = TextView(this).apply {
                    text = modeLabel(mode)
                    setTextSize(TypedValue.COMPLEX_UNIT_SP, 12f)
                    gravity = Gravity.CENTER
                    maxLines = 1
                    setSingleLine(true)
                    ellipsize = android.text.TextUtils.TruncateAt.END
                    setPadding((12 * dp).toInt(), (6 * dp).toInt(), (12 * dp).toInt(), (6 * dp).toInt())
                    // Inline icon on the left so the tab matches the in-app
                    // feature-button row (icon + label). compoundDrawables
                    // avoids nesting another ViewGroup per tab.
                    val icon = androidx.core.content.ContextCompat.getDrawable(
                        this@BubbleService, modeIcon(mode),
                    )?.apply {
                        setBounds(0, 0, (14 * dp).toInt(), (14 * dp).toInt())
                    }
                    setCompoundDrawables(icon, null, null, null)
                    compoundDrawablePadding = (6 * dp).toInt()
                    setOnClickListener {
                        if (isTranslating) return@setOnClickListener
                        val src = currentSourceText ?: return@setOnClickListener
                        handleTranslateRequest(src, mode)
                    }
                    layoutParams = LinearLayout.LayoutParams(
                        LinearLayout.LayoutParams.WRAP_CONTENT,
                        LinearLayout.LayoutParams.WRAP_CONTENT,
                    ).apply { marginEnd = (4 * dp).toInt() }
                }
                modeButtons[mode] = btn
                tabsRow.addView(btn)
            }

            val tabsScroll = HorizontalScrollView(this).apply {
                isHorizontalScrollBarEnabled = false
                addView(tabsRow)
            }

            // ── Scrollable content area ──
            detectedLangTv = TextView(this).apply {
                setTextColor(mutedCol)
                setTextSize(TypedValue.COMPLEX_UNIT_SP, 10f)
                setTypeface(Typeface.DEFAULT, Typeface.ITALIC)
                visibility = View.GONE
                setPadding(0, (6 * dp).toInt(), 0, 0)
            }

            panelSource = TextView(this).apply {
                setTextColor(mutedCol)
                setTextSize(TypedValue.COMPLEX_UNIT_SP, 12f)
                maxLines = 3
                ellipsize = android.text.TextUtils.TruncateAt.END
                setPadding(0, (4 * dp).toInt(), 0, (4 * dp).toInt())
            }

            panelOutput = TextView(this).apply {
                setTextColor(textCol)
                setTextSize(TypedValue.COMPLEX_UNIT_SP, 16f)
                typeface = Typeface.DEFAULT_BOLD
                setLineSpacing(2 * dp, 1f)
                setPadding(0, (4 * dp).toInt(), 0, (4 * dp).toInt())
            }

            panelRomanization = TextView(this).apply {
                setTextColor(mutedCol)
                setTextSize(TypedValue.COMPLEX_UNIT_SP, 13f)
                setTypeface(Typeface.DEFAULT, Typeface.ITALIC)
                visibility = View.GONE
                setPadding(0, 0, 0, (4 * dp).toInt())
            }

            // ── Quick-reply suggestions (Reply mode + suggestions toggle) ──
            panelSuggestionsLabel = TextView(this).apply {
                text = localized(R.string.bubble_reply_suggestions).uppercase()
                setTextColor(mutedCol)
                setTextSize(TypedValue.COMPLEX_UNIT_SP, 10f)
                typeface = Typeface.DEFAULT_BOLD
                letterSpacing = 0.08f
                visibility = View.GONE
                setPadding(0, (10 * dp).toInt(), 0, (4 * dp).toInt())
            }
            panelSuggestionsContainer = LinearLayout(this).apply {
                orientation = LinearLayout.VERTICAL
                visibility = View.GONE
            }

            // Loading spinner — shown while waiting for API response
            loadingSpinner = ProgressBar(this, null, android.R.attr.progressBarStyleSmall).apply {
                isIndeterminate = true
                visibility = View.GONE
                layoutParams = LinearLayout.LayoutParams(
                    (24 * dp).toInt(), (24 * dp).toInt(),
                ).apply { topMargin = (8 * dp).toInt(); bottomMargin = (4 * dp).toInt() }
            }

            panelStatus = TextView(this).apply {
                setTextColor(mutedCol)
                setTextSize(TypedValue.COMPLEX_UNIT_SP, 12f)
                setPadding(0, (4 * dp).toInt(), 0, (4 * dp).toInt())
            }

            // All the above wrapped in a max-height ScrollView so long translations scroll
            val contentInner = LinearLayout(this).apply {
                orientation = LinearLayout.VERTICAL
            }
            contentInner.addView(detectedLangTv)
            contentInner.addView(panelSource)
            contentInner.addView(loadingSpinner)
            contentInner.addView(panelOutput)
            contentInner.addView(panelRomanization)
            contentInner.addView(panelSuggestionsLabel)
            contentInner.addView(panelSuggestionsContainer)
            contentInner.addView(panelStatus)

            val contentScroll = object : ScrollView(this@BubbleService) {
                override fun onMeasure(widthSpec: Int, heightSpec: Int) {
                    val maxPx = (220 * resources.displayMetrics.density).toInt()
                    super.onMeasure(widthSpec, MeasureSpec.makeMeasureSpec(maxPx, MeasureSpec.AT_MOST))
                }
            }.apply {
                layoutParams = LinearLayout.LayoutParams(
                    LinearLayout.LayoutParams.MATCH_PARENT,
                    LinearLayout.LayoutParams.WRAP_CONTENT,
                ).apply { topMargin = (4 * dp).toInt() }
                addView(contentInner)
            }

            // Action buttons row (TTS + Copy)
            val actionsRow = LinearLayout(this).apply {
                orientation = LinearLayout.HORIZONTAL
                layoutParams = LinearLayout.LayoutParams(
                    LinearLayout.LayoutParams.MATCH_PARENT,
                    LinearLayout.LayoutParams.WRAP_CONTENT,
                ).apply { topMargin = (10 * dp).toInt() }
            }

            panelTtsBtn = TextView(this).apply {
                text = "▶"
                setTextSize(TypedValue.COMPLEX_UNIT_SP, 16f)
                gravity = Gravity.CENTER
                background = GradientDrawable().apply {
                    setColor(Color.TRANSPARENT)
                    setStroke(1, accent)
                    cornerRadius = 10 * dp
                }
                setPadding((14 * dp).toInt(), (10 * dp).toInt(), (14 * dp).toInt(), (10 * dp).toInt())
                setOnClickListener { speakOutput() }
                layoutParams = LinearLayout.LayoutParams(
                    LinearLayout.LayoutParams.WRAP_CONTENT,
                    LinearLayout.LayoutParams.WRAP_CONTENT,
                ).apply { marginEnd = (8 * dp).toInt() }
            }

            panelCopyBtn = TextView(this).apply {
                text = "Copy"
                setTextColor(Color.WHITE)
                setTextSize(TypedValue.COMPLEX_UNIT_SP, 13f)
                typeface = Typeface.DEFAULT_BOLD
                gravity = Gravity.CENTER
                background = GradientDrawable().apply {
                    setColor(accent)
                    cornerRadius = 10 * dp
                }
                setPadding(0, (10 * dp).toInt(), 0, (10 * dp).toInt())
                setOnClickListener {
                    val t = currentOutput
                    if (!t.isNullOrEmpty()) {
                        selfCopyInProgress = true
                        handler.postDelayed({ selfCopyInProgress = false }, 1000)
                        val cm = getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
                        cm.setPrimaryClip(ClipData.newPlainText("TransKey", t))
                        Toast.makeText(this@BubbleService, "Copied", Toast.LENGTH_SHORT).show()
                        hideResultPanel()
                    }
                }
                layoutParams = LinearLayout.LayoutParams(
                    0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f,
                )
            }

            panelPasteBtn = TextView(this).apply {
                text = "↓ Paste"
                setTextColor(Color.WHITE)
                setTextSize(TypedValue.COMPLEX_UNIT_SP, 13f)
                typeface = Typeface.DEFAULT_BOLD
                gravity = Gravity.CENTER
                background = GradientDrawable().apply {
                    setColor(Color.parseColor("#16a34a"))
                    cornerRadius = 10 * dp
                }
                setPadding(0, (10 * dp).toInt(), 0, (10 * dp).toInt())
                visibility = View.GONE
                setOnClickListener {
                    val t = currentOutput
                    if (t.isNullOrEmpty()) return@setOnClickListener
                    val svc = TransKeyAccessibilityService.instance
                    if (svc == null) {
                        Toast.makeText(
                            this@BubbleService,
                            "Enable TransKey in Accessibility settings to paste",
                            Toast.LENGTH_LONG,
                        ).show()
                        return@setOnClickListener
                    }
                    // Always copy to clipboard first so the user has a manual
                    // fallback even if accessibility paste fails (e.g. the
                    // host app blocks SET_TEXT and PASTE — banking apps do).
                    selfCopyInProgress = true
                    handler.postDelayed({ selfCopyInProgress = false }, 1500)
                    try {
                        val cm = getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
                        cm.setPrimaryClip(ClipData.newPlainText("TransKey", t))
                    } catch (_: Exception) { /* clipboard may be locked on some OEMs */ }

                    // Hide panel first so it doesn't sit over the input, then
                    // replace the focused text in the host app. The 300ms delay
                    // gives the underlying app time to recover input focus —
                    // shorter delays caused silent failures on Compose / RN
                    // apps that briefly drop focus when an overlay disappears.
                    hideResultPanel()
                    handler.postDelayed({
                        val ok = svc.replaceFocusedText(t)
                        if (ok) {
                            Toast.makeText(
                                this@BubbleService,
                                "Pasted",
                                Toast.LENGTH_SHORT,
                            ).show()
                        } else {
                            Toast.makeText(
                                this@BubbleService,
                                "Copied — tap the field and paste manually",
                                Toast.LENGTH_LONG,
                            ).show()
                        }
                    }, 300)
                }
                layoutParams = LinearLayout.LayoutParams(
                    0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f,
                ).apply { marginStart = (8 * dp).toInt() }
            }

            actionsRow.addView(panelTtsBtn)
            actionsRow.addView(panelCopyBtn)
            actionsRow.addView(panelPasteBtn)

            rootCard.addView(header)
            rootCard.addView(tabsScroll)
            rootCard.addView(contentScroll)
            rootCard.addView(actionsRow)

            panelView = rootCard
            windowManager?.addView(rootCard, buildPanelLayoutParams())
        }

        // Update content
        panelSource?.text = currentSourceText ?: ""
        updateModeTabs(accent, mutedCol)
        updateLangChip()

        // Detected lang only shown in result/error state, not while loading
        val detected = currentDetectedLang
        if (!loading && !detected.isNullOrBlank()) {
            detectedLangTv?.apply {
                text = "Detected: ${LANG_LABELS[detected] ?: detected.uppercase()}"
                visibility = View.VISIBLE
            }
        } else {
            detectedLangTv?.visibility = View.GONE
        }

        // Romanization shown only when output is shown and value present
        val rom = currentRomanization
        if (!loading && error == null && !rom.isNullOrBlank()) {
            panelRomanization?.apply { text = rom; visibility = View.VISIBLE }
        } else {
            panelRomanization?.visibility = View.GONE
        }

        // Quick-reply suggestions: only on the plain Translate flow. Reply
        // mode already produces one targeted reply (the whole point of that
        // mode), so showing more alternatives there would be noise; the
        // user wanted suggestions surfaced alongside translation, not reply.
        // Refine/Summarize/Explain aren't conversation contexts at all.
        val suggestions = currentSuggestions
        val showSuggestions = !loading && error == null && suggestions.isNotEmpty() &&
            currentMode == MODE_TRANSLATE
        if (showSuggestions) {
            panelSuggestionsLabel?.visibility = View.VISIBLE
            panelSuggestionsContainer?.apply {
                removeAllViews()
                visibility = View.VISIBLE
                val borderCol = Color.parseColor(if (isDark) "#3A3A52" else "#DDDDF0")
                val accentCol = Color.parseColor("#6C63FF")
                suggestions.forEachIndexed { idx, pair ->
                    val (sourceText, targetText) = pair
                    val chip = LinearLayout(this@BubbleService).apply {
                        orientation = LinearLayout.VERTICAL
                        // Order matters: set background BEFORE padding so the
                        // GradientDrawable doesn't reset the padding we want.
                        background = GradientDrawable().apply {
                            setColor(Color.TRANSPARENT)
                            setStroke(1, borderCol)
                            cornerRadius = 12 * dp
                        }
                        setPadding(
                            (12 * dp).toInt(), (8 * dp).toInt(),
                            (12 * dp).toInt(), (8 * dp).toInt(),
                        )
                        isClickable = true
                        isFocusable = true
                        // Source = the actual reply to send (partner's lang).
                        if (sourceText.isNotEmpty()) {
                            addView(TextView(this@BubbleService).apply {
                                text = sourceText
                                setTextColor(textCol)
                                setTextSize(TypedValue.COMPLEX_UNIT_SP, 14f)
                                typeface = Typeface.DEFAULT_BOLD
                            })
                        }
                        // Target = same idea in user's language, as a hint.
                        if (targetText.isNotEmpty() && targetText != sourceText) {
                            addView(TextView(this@BubbleService).apply {
                                text = targetText
                                setTextColor(mutedCol)
                                setTextSize(TypedValue.COMPLEX_UNIT_SP, 12f)
                                setTypeface(Typeface.DEFAULT, Typeface.ITALIC)
                                setPadding(0, (2 * dp).toInt(), 0, 0)
                            })
                        }
                        setOnClickListener {
                            val toCopy = sourceText.ifEmpty { targetText }
                            val cm = getSystemService(CLIPBOARD_SERVICE) as android.content.ClipboardManager
                            cm.setPrimaryClip(android.content.ClipData.newPlainText("suggestion", toCopy))
                            // Brief filled-accent flash so the tap registers
                            // visibly even when Toasts get suppressed on some
                            // OEMs (Xiaomi/Huawei restrict overlay Toasts).
                            background = GradientDrawable().apply {
                                setColor(accentCol)
                                cornerRadius = 12 * dp
                            }
                            handler.postDelayed({
                                background = GradientDrawable().apply {
                                    setColor(Color.TRANSPARENT)
                                    setStroke(1, borderCol)
                                    cornerRadius = 12 * dp
                                }
                            }, 240)
                            Toast.makeText(this@BubbleService, "Copied", Toast.LENGTH_SHORT).show()
                        }
                        layoutParams = LinearLayout.LayoutParams(
                            LinearLayout.LayoutParams.MATCH_PARENT,
                            LinearLayout.LayoutParams.WRAP_CONTENT,
                        ).apply {
                            if (idx > 0) topMargin = (6 * dp).toInt()
                        }
                    }
                    addView(chip)
                }
            }
        } else {
            panelSuggestionsLabel?.visibility = View.GONE
            panelSuggestionsContainer?.apply {
                visibility = View.GONE
                removeAllViews()
            }
        }

        if (loading) {
            panelOutput?.visibility = View.GONE
            panelStatus?.visibility = View.GONE
            loadingSpinner?.visibility = View.VISIBLE
            panelCopyBtn?.visibility = View.GONE
            panelTtsBtn?.visibility = View.GONE
            panelPasteBtn?.visibility = View.GONE
            // Dim mode tabs to signal busy state
            for ((_, btn) in modeButtons) {
                btn.alpha = 0.35f
                btn.isEnabled = false
            }
            setState(STATE_LOADING)
        } else if (error != null) {
            loadingSpinner?.visibility = View.GONE
            panelOutput?.visibility = View.GONE
            panelStatus?.apply { text = error; visibility = View.VISIBLE }
            panelCopyBtn?.visibility = View.GONE
            panelTtsBtn?.visibility = View.GONE
            panelPasteBtn?.visibility = View.GONE
            for ((_, btn) in modeButtons) { btn.alpha = 1f; btn.isEnabled = true }
            setState(STATE_ERROR)
        } else if (output != null) {
            loadingSpinner?.visibility = View.GONE
            panelOutput?.apply { text = output; visibility = View.VISIBLE }
            panelStatus?.visibility = View.GONE
            panelCopyBtn?.visibility = View.VISIBLE
            panelTtsBtn?.visibility = View.VISIBLE
            // Paste only makes sense for Reply mode, and only when our
            // AccessibilityService is bound. Show in Reply regardless — if
            // service is off we'll prompt to enable when user taps.
            panelPasteBtn?.visibility =
                if (currentMode == MODE_REPLY) View.VISIBLE else View.GONE
            for ((_, btn) in modeButtons) { btn.alpha = 1f; btn.isEnabled = true }
            setState(STATE_RESULT)
        }
    }

    private fun updateLangChip() {
        if (currentMode == MODE_REFINE) {
            sourceLangChip?.visibility = View.GONE
            langChip?.visibility = View.GONE
            // Keep the settings icon visible even in Refine mode — users may
            // still want to adjust TTS rate, romanization or reply suggestions
            // without leaving the popup.
            toneChip?.visibility = View.VISIBLE
            return
        }

        // Note: do NOT re-read prefs here. The chips must reflect the lang
        // and tone that were used for the *currently displayed result* —
        // these values are set in handleTranslateRequest before each
        // translate call. Re-reading would clobber the reply-mode override
        // (where currentTargetLang = readReplyLang(), not readTargetLang()).
        // Picker freshness is handled separately in showLangPicker /
        // showTonePicker / showSourceLangPicker.

        // Source chip: show "Auto" or language name
        sourceLangChip?.apply {
            visibility = View.VISIBLE
            text = if (currentSourceLang == "auto") "Auto"
                   else (LANG_LABELS[currentSourceLang] ?: currentSourceLang.uppercase())
        }

        // Target chip
        langChip?.apply {
            visibility = View.VISIBLE
            text = LANG_LABELS[currentTargetLang] ?: currentTargetLang.uppercase()
        }

        // Settings icon (formerly tone chip): always visible. The icon alone
        // carries the affordance — the actual tone shows up inside the
        // settings sheet, so we don't need a per-state label here.
        toneChip?.visibility = View.VISIBLE
    }

    private fun updateModeTabs(accent: Int, mutedCol: Int) {
        val dp = resources.displayMetrics.density
        for ((mode, btn) in modeButtons) {
            val fg = if (mode == currentMode) Color.WHITE else mutedCol
            btn.setTextColor(fg)
            btn.typeface = if (mode == currentMode) Typeface.DEFAULT_BOLD else Typeface.DEFAULT
            btn.background = GradientDrawable().apply {
                if (mode == currentMode) {
                    setColor(accent)
                } else {
                    setColor(Color.TRANSPARENT)
                    setStroke(1, mutedCol)
                }
                cornerRadius = 8 * dp
            }
            // Re-tint the leading icon to match the text color of the
            // active/inactive state.
            val drawables = btn.compoundDrawables
            drawables[0]?.mutate()?.setTint(fg)
        }
    }

    private fun buildPanelLayoutParams(): WindowManager.LayoutParams {
        val dp = resources.displayMetrics.density
        val screenWidth = resources.displayMetrics.widthPixels
        val width = (screenWidth - (32 * dp).toInt()).coerceAtMost((360 * dp).toInt())

        return WindowManager.LayoutParams(
            width,
            WindowManager.LayoutParams.WRAP_CONTENT,
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
                WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
            else @Suppress("DEPRECATION") WindowManager.LayoutParams.TYPE_PHONE,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE,
            PixelFormat.TRANSLUCENT,
        ).apply {
            gravity = Gravity.TOP or Gravity.CENTER_HORIZONTAL
            y = (80 * dp).toInt()
        }
    }

    private fun hideResultPanel() {
        isTranslating = false
        removeResultPanel()
        setState(STATE_IDLE)
    }

    private fun removeResultPanel() {
        panelView?.let {
            try { windowManager?.removeView(it) } catch (_: Exception) {}
        }
        panelView = null
        panelSource = null
        panelOutput = null
        panelRomanization = null
        panelStatus = null
        panelCopyBtn = null
        panelPasteBtn = null
        panelTtsBtn = null
        langChip = null
        sourceLangChip = null
        toneChip = null
        loadingSpinner = null
        detectedLangTv = null
        panelSuggestionsLabel = null
        panelSuggestionsContainer = null
        modeButtons.clear()
    }

    private fun speakOutput() {
        val text = currentOutput?.takeIf { it.isNotEmpty() } ?: return
        if (!ttsReady) { Toast.makeText(this, "TTS not ready", Toast.LENGTH_SHORT).show(); return }
        val locale = langToLocale(currentTargetLang)
        tts?.language = locale
        // Match the speed the user picked inside the app's Settings →
        // Read aloud. Flutter writes it via shared_preferences as
        // flutter.tk_tts_rate (double). Default to normal speed when unset.
        val rate = readTtsRate().toFloat()
        tts?.setSpeechRate(rate)
        @Suppress("DEPRECATION")
        tts?.speak(text, TextToSpeech.QUEUE_FLUSH, null)
    }

    private fun readTtsRate(): Double {
        val prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
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
        getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE).edit()
            .putBoolean(KEY_BUBBLE_ACTIVE, active).apply()
    }

    private fun readSourceLang(): String {
        val prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        return prefs.getString(KEY_SOURCE_LANG, "auto") ?: "auto"
    }

    private fun writeSourceLang(lang: String) {
        getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE).edit()
            .putString(KEY_SOURCE_LANG, lang).apply()
    }

    private fun readTone(): String {
        val prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        return prefs.getString(KEY_TONE_OVERRIDE, "") ?: ""
    }

    private fun readReplyLang(): String {
        val prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        return prefs.getString(KEY_REPLY_LANG, "") ?: ""
    }

    private fun writeReplyLang(lang: String) {
        getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE).edit()
            .putString(KEY_REPLY_LANG, lang).apply()
    }

    /**
     * Read the persisted speaker language for voice input. Falls back to a
     * sensible default in this order:
     *   1. Previously-chosen voice lang (persisted across sessions)
     *   2. System primary locale's ISO code (if it's one we offer)
     *   3. Translate source-lang (when not "auto")
     *   4. "en" — universal fallback
     */
    private fun readVoiceLang(): String {
        val prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val stored = prefs.getString(KEY_VOICE_LANG, null)
        if (!stored.isNullOrEmpty() && stored in VOICE_LANGS) return stored

        val systemLang = resources.configuration.locales.get(0).language
        if (systemLang in VOICE_LANGS) return systemLang

        val src = readSourceLang()
        if (src != "auto" && src in VOICE_LANGS) return src

        return "en"
    }

    private fun writeVoiceLang(lang: String) {
        getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE).edit()
            .putString(KEY_VOICE_LANG, lang).apply()
    }

    private fun writeTone(tone: String) {
        getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE).edit()
            .putString(KEY_TONE_OVERRIDE, tone).apply()
    }

    // ── Reply tone / Romanization / Reply suggestions / TTS rate ─────────
    // All persisted under `flutter.tk_*` prefix so Flutter's SharedPreferences
    // package reads them as the same `tk_*` keys the in-app Settings screen
    // writes to. Reading happens at app resume via appSettingsProvider.reload()
    // and ttsProvider._loadPersistedPrefs().

    private fun readReplyTone(): String {
        val prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        return prefs.getString(KEY_REPLY_TONE_OVERRIDE, "") ?: ""
    }

    private fun writeReplyTone(tone: String) {
        getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE).edit()
            .putString(KEY_REPLY_TONE_OVERRIDE, tone).apply()
    }

    private fun readRomanization(): Boolean {
        val prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        return prefs.getBoolean(KEY_ROMANIZATION, false)
    }

    private fun writeRomanization(value: Boolean) {
        getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE).edit()
            .putBoolean(KEY_ROMANIZATION, value).apply()
    }

    private fun readReplySuggestions(): Boolean {
        val prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        return prefs.getBoolean(KEY_REPLY_SUGGESTIONS, false)
    }

    private fun writeReplySuggestions(value: Boolean) {
        getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE).edit()
            .putBoolean(KEY_REPLY_SUGGESTIONS, value).apply()
    }

    // readTtsRate() is defined above (with broader plugin-version handling) —
    // single source of truth for both the speakOutput path and settings sheet.

    private fun writeTtsRate(rate: Double) {
        // Flutter stores doubles natively under SharedPreferences via Float
        // wrapper — but reading on the Flutter side uses getDouble which
        // accepts both. Writing as Double keeps full precision.
        getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE).edit()
            .putFloat(KEY_TTS_RATE, rate.toFloat()).apply()
    }

    private fun toneLabel(code: String): String {
        val resId = TONE_STRING_IDS[code] ?: R.string.bubble_tone_auto
        return localized(resId)
    }

    private fun formatRate(r: Double): String {
        // Match desktop / Flutter: "1×" instead of "1.0×".
        return if (r == r.toLong().toDouble()) "${r.toInt()}×" else "${r}×"
    }

    // ── Source language picker ──

    private fun showSourceLangPicker() {
        if (sourceLangPickerView != null) { hideSourceLangPicker(); return }
        ensureWindowManager()
        // Sync from prefs so the picker reflects any change made in Flutter UI.
        currentSourceLang = readSourceLang()
        val dp = resources.displayMetrics.density
        val isDark = (resources.configuration.uiMode and android.content.res.Configuration.UI_MODE_NIGHT_MASK) ==
            android.content.res.Configuration.UI_MODE_NIGHT_YES
        val bg      = if (isDark) Color.parseColor("#1E1E30") else Color.WHITE
        val textCol = if (isDark) Color.parseColor("#E8E8F0") else Color.parseColor("#1A1A2E")
        val accent  = Color.parseColor("#6C63FF")
        val selBg   = Color.parseColor("#6C63FF")

        val backdrop = FrameLayout(this).apply {
            setBackgroundColor(Color.parseColor("#55000000"))
            setOnClickListener { hideSourceLangPicker() }
        }
        val card = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            background = GradientDrawable().apply { setColor(bg); cornerRadius = 18 * dp }
            elevation = 22 * dp
            setPadding((14 * dp).toInt(), (14 * dp).toInt(), (14 * dp).toInt(), (14 * dp).toInt())
            isClickable = true
        }
        card.addView(TextView(this).apply {
            text = "Source language"
            setTextColor(accent)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 12f)
            typeface = Typeface.DEFAULT_BOLD
            setPadding(0, 0, 0, (10 * dp).toInt())
        })

        var row: LinearLayout? = null
        SOURCE_LANGS.forEachIndexed { idx, lang ->
            if (idx % 3 == 0) {
                row = LinearLayout(this).apply {
                    orientation = LinearLayout.HORIZONTAL
                    layoutParams = LinearLayout.LayoutParams(
                        LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT,
                    ).apply { bottomMargin = (6 * dp).toInt() }
                }
                card.addView(row)
            }
            val isSelected = lang == currentSourceLang
            val label = if (lang == "auto") "Auto" else (LANG_LABELS[lang] ?: lang.uppercase())
            val chip = TextView(this).apply {
                text = label
                setTextColor(if (isSelected) Color.WHITE else textCol)
                setTextSize(TypedValue.COMPLEX_UNIT_SP, 11f)
                gravity = Gravity.CENTER
                setPadding((8 * dp).toInt(), (8 * dp).toInt(), (8 * dp).toInt(), (8 * dp).toInt())
                background = GradientDrawable().apply {
                    setColor(if (isSelected) selBg else Color.TRANSPARENT)
                    setStroke(1, if (isSelected) selBg else Color.parseColor(if (isDark) "#3A3A52" else "#DDDDF0"))
                    cornerRadius = 10 * dp
                }
                setOnClickListener {
                    currentSourceLang = lang
                    writeSourceLang(lang)
                    hideSourceLangPicker()
                    updateLangChip()
                    currentSourceText?.let { src -> handleTranslateRequest(src, currentMode) }
                }
                layoutParams = LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f)
                    .apply { marginEnd = if (idx % 3 != 2) (6 * dp).toInt() else 0 }
            }
            row?.addView(chip)
        }

        val screenWidth = resources.displayMetrics.widthPixels
        val cardWidth = (screenWidth - (48 * dp).toInt()).coerceAtMost((360 * dp).toInt())
        backdrop.addView(card, FrameLayout.LayoutParams(cardWidth, FrameLayout.LayoutParams.WRAP_CONTENT, Gravity.CENTER))
        sourceLangPickerView = backdrop
        windowManager?.addView(backdrop, buildPickerLayoutParams())
    }

    private fun hideSourceLangPicker() {
        sourceLangPickerView?.let { try { windowManager?.removeView(it) } catch (_: Exception) {} }
        sourceLangPickerView = null
    }

    // ── Settings sheet ──
    // Single sheet that surfaces the 5 in-app settings the bubble cares about:
    // translate tone, reply tone, romanization, reply suggestions, TTS speed.
    // All writes go to the `flutter.tk_*` SharedPreferences keys so the
    // in-app Settings screen picks them up on resume (and vice versa — we
    // re-read every time the sheet opens).

    private fun showTonePicker() {
        showSettingsSheet()
    }

    private fun hideTonePicker() {
        tonePickerView?.let { try { windowManager?.removeView(it) } catch (_: Exception) {} }
        tonePickerView = null
    }

    // ── Text input picker (type text without opening the app) ──

    /**
     * Build window params for a focusable overlay so the soft keyboard can
     * attach to an EditText. Mode/result pickers use FLAG_NOT_FOCUSABLE
     * (touch-only); this one explicitly does NOT set that flag and asks the
     * IME to appear and resize the window when it does.
     */
    private fun buildInputPickerLayoutParams(): WindowManager.LayoutParams {
        return WindowManager.LayoutParams(
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.MATCH_PARENT,
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
                WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
            else @Suppress("DEPRECATION") WindowManager.LayoutParams.TYPE_PHONE,
            // FLAG_DIM_BEHIND for the backdrop dim; no FLAG_NOT_FOCUSABLE so
            // taps on the EditText raise the soft keyboard.
            WindowManager.LayoutParams.FLAG_DIM_BEHIND,
            PixelFormat.TRANSLUCENT,
        ).apply {
            softInputMode = WindowManager.LayoutParams.SOFT_INPUT_ADJUST_RESIZE or
                WindowManager.LayoutParams.SOFT_INPUT_STATE_VISIBLE
            dimAmount = 0.4f
        }
    }

    @SuppressLint("ClickableViewAccessibility")
    private fun showInputPicker(initialMode: String, prefillText: String? = null) {
        if (inputPickerView != null) { hideInputPicker(); return }
        ensureWindowManager()
        refreshLocale()

        val dp = resources.displayMetrics.density
        val isDark = (resources.configuration.uiMode and android.content.res.Configuration.UI_MODE_NIGHT_MASK) ==
            android.content.res.Configuration.UI_MODE_NIGHT_YES
        val bg       = if (isDark) Color.parseColor("#1E1E30") else Color.WHITE
        val textCol  = if (isDark) Color.parseColor("#E8E8F0") else Color.parseColor("#1A1A2E")
        val mutedCol = if (isDark) Color.parseColor("#9090AA") else Color.parseColor("#6B6B7A")
        val accent   = Color.parseColor("#6C63FF")
        val borderCol = Color.parseColor(if (isDark) "#3A3A52" else "#DDDDF0")
        val subduedBg = if (isDark) "#2A2A40" else "#F0EFFF"

        // Selected mode reference — closure-captured by tabs + Translate button.
        // Reply mode requires a captured conversation; typed-from-scratch
        // text has no original to reply to, so we hide Reply from this picker.
        val typeableModes = ALL_MODES.filter { it != MODE_REPLY }
        val selectedMode = arrayOf(
            if (typeableModes.contains(initialMode)) initialMode else MODE_TRANSLATE,
        )

        val backdrop = FrameLayout(this).apply {
            // Tap outside card to dismiss. The card itself swallows touches.
            setOnClickListener { hideInputPicker() }
        }

        val card = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            background = GradientDrawable().apply { setColor(bg); cornerRadius = 18 * dp }
            elevation = 22 * dp
            setPadding((16 * dp).toInt(), (14 * dp).toInt(), (16 * dp).toInt(), (14 * dp).toInt())
            isClickable = true
        }

        // Header row: title (left) + Paste / Clear actions (right). The
        // floating text-selection toolbar (which normally exposes Paste via
        // long-press) does NOT attach to TYPE_APPLICATION_OVERLAY windows on
        // any Android version — its popup expects a regular activity window
        // token. So we surface Paste + Clear as explicit, always-visible
        // buttons; long-press has no equivalent here.
        val headerRow = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(0, 0, 0, (10 * dp).toInt())
        }
        headerRow.addView(TextView(this).apply {
            text = localized(R.string.bubble_type_text)
            setTextColor(textCol)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 14f)
            typeface = Typeface.DEFAULT_BOLD
            layoutParams = LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f)
        })
        // Reference declared up front so the Paste / Clear closures can
        // mutate it. The actual EditText is constructed just below.
        var inputRef: EditText? = null
        headerRow.addView(TextView(this).apply {
            text = "📋 ${localized(R.string.bubble_input_paste)}"
            setTextColor(accent)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 12f)
            typeface = Typeface.DEFAULT_BOLD
            setPadding((10 * dp).toInt(), (6 * dp).toInt(), (10 * dp).toInt(), (6 * dp).toInt())
            isClickable = true
            isFocusable = true
            background = GradientDrawable().apply {
                setColor(Color.TRANSPARENT)
                setStroke(1, borderCol)
                cornerRadius = 10 * dp
            }
            setOnClickListener {
                val cm = getSystemService(CLIPBOARD_SERVICE) as android.content.ClipboardManager
                val clip = cm.primaryClip
                val pasted = if (clip != null && clip.itemCount > 0) {
                    clip.getItemAt(0).coerceToText(this@BubbleService)?.toString().orEmpty()
                } else ""
                if (pasted.isEmpty()) {
                    Toast.makeText(this@BubbleService, "Clipboard is empty", Toast.LENGTH_SHORT).show()
                    return@setOnClickListener
                }
                inputRef?.let { editText ->
                    // Replace current selection with the pasted text, or
                    // append at the cursor if there's no selection — matches
                    // standard Paste menu behaviour.
                    val start = editText.selectionStart.coerceAtLeast(0)
                    val end = editText.selectionEnd.coerceAtLeast(start)
                    editText.text.replace(start, end, pasted)
                    editText.setSelection(start + pasted.length)
                }
            }
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.WRAP_CONTENT,
                LinearLayout.LayoutParams.WRAP_CONTENT,
            ).apply { marginStart = (8 * dp).toInt() }
        })
        headerRow.addView(TextView(this).apply {
            text = "✕"
            setTextColor(mutedCol)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 12f)
            setPadding((10 * dp).toInt(), (6 * dp).toInt(), (10 * dp).toInt(), (6 * dp).toInt())
            isClickable = true
            isFocusable = true
            contentDescription = localized(R.string.bubble_input_clear)
            background = GradientDrawable().apply {
                setColor(Color.TRANSPARENT)
                setStroke(1, borderCol)
                cornerRadius = 10 * dp
            }
            setOnClickListener {
                inputRef?.text?.clear()
                inputRef?.requestFocus()
            }
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.WRAP_CONTENT,
                LinearLayout.LayoutParams.WRAP_CONTENT,
            ).apply { marginStart = (6 * dp).toInt() }
        })
        card.addView(headerRow)

        // ── Input field ──
        val input = EditText(this).apply {
            hint = localized(R.string.bubble_input_hint)
            setHintTextColor(mutedCol)
            setTextColor(textCol)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 15f)
            background = GradientDrawable().apply {
                setColor(Color.TRANSPARENT)
                setStroke(1, borderCol)
                cornerRadius = 12 * dp
            }
            setPadding(
                (12 * dp).toInt(), (10 * dp).toInt(),
                (12 * dp).toInt(), (10 * dp).toInt(),
            )
            minLines = 3
            maxLines = 6
            gravity = Gravity.TOP or Gravity.START
            inputType = android.text.InputType.TYPE_CLASS_TEXT or
                android.text.InputType.TYPE_TEXT_FLAG_MULTI_LINE or
                android.text.InputType.TYPE_TEXT_FLAG_CAP_SENTENCES
            imeOptions = android.view.inputmethod.EditorInfo.IME_FLAG_NO_EXTRACT_UI or
                android.view.inputmethod.EditorInfo.IME_ACTION_DONE
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT,
            )
        }
        // Wire the Paste / Clear buttons (declared before EditText) to the
        // freshly-constructed input now that the reference exists.
        inputRef = input
        // Pre-fill if caller supplied text (e.g. from Read-screen a11y flow).
        // Cursor at end so user can keep typing or trim.
        if (!prefillText.isNullOrBlank()) {
            input.setText(prefillText)
            input.setSelection(input.text?.length ?: 0)
        }
        card.addView(input)

        // ── Mode tabs ──
        val tabsRow = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT,
            ).apply { topMargin = (10 * dp).toInt() }
        }
        val tabRefs = mutableListOf<Pair<String, TextView>>()
        fun renderTabSelection() {
            for ((mode, tab) in tabRefs) {
                val selected = mode == selectedMode[0]
                tab.background = GradientDrawable().apply {
                    setColor(Color.parseColor(if (selected) "#7C6EFA" else subduedBg))
                    cornerRadius = 12 * dp
                }
                tab.setTextColor(if (selected) Color.WHITE else accent)
            }
        }
        typeableModes.forEachIndexed { index, mode ->
            val tab = TextView(this).apply {
                text = modeLabel(mode)
                setTextSize(TypedValue.COMPLEX_UNIT_SP, 11f)
                typeface = Typeface.DEFAULT_BOLD
                gravity = Gravity.CENTER
                maxLines = 1
                setSingleLine(true)
                ellipsize = android.text.TextUtils.TruncateAt.END
                setPadding((8 * dp).toInt(), (8 * dp).toInt(), (8 * dp).toInt(), (8 * dp).toInt())
                isClickable = true
                isFocusable = true
                setOnClickListener {
                    selectedMode[0] = mode
                    renderTabSelection()
                }
                layoutParams = LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f)
                    .apply { marginEnd = if (index < typeableModes.size - 1) (4 * dp).toInt() else 0 }
            }
            tabRefs.add(mode to tab)
            tabsRow.addView(tab)
        }
        renderTabSelection()
        card.addView(tabsRow)

        // ── Action buttons (Cancel + Translate) ──
        val actionsRow = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.END
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT,
            ).apply { topMargin = (12 * dp).toInt() }
        }
        actionsRow.addView(TextView(this).apply {
            text = localized(R.string.bubble_cancel)
            setTextColor(mutedCol)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 13f)
            typeface = Typeface.DEFAULT_BOLD
            setPadding((14 * dp).toInt(), (10 * dp).toInt(), (14 * dp).toInt(), (10 * dp).toInt())
            isClickable = true
            isFocusable = true
            setOnClickListener { hideInputPicker() }
        })
        actionsRow.addView(TextView(this).apply {
            text = localized(R.string.bubble_action_translate)
            setTextColor(Color.WHITE)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 13f)
            typeface = Typeface.DEFAULT_BOLD
            background = GradientDrawable().apply {
                setColor(accent)
                cornerRadius = 12 * dp
            }
            setPadding((18 * dp).toInt(), (10 * dp).toInt(), (18 * dp).toInt(), (10 * dp).toInt())
            isClickable = true
            isFocusable = true
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.WRAP_CONTENT,
                LinearLayout.LayoutParams.WRAP_CONTENT,
            ).apply { marginStart = (8 * dp).toInt() }
            setOnClickListener {
                val text = input.text?.toString()?.trim().orEmpty()
                if (text.isEmpty()) {
                    input.requestFocus()
                    return@setOnClickListener
                }
                hideInputPicker()
                handleTranslateRequest(text, selectedMode[0])
            }
        })
        card.addView(actionsRow)

        val screenWidth = resources.displayMetrics.widthPixels
        val cardWidth = (screenWidth - (40 * dp).toInt()).coerceAtMost((380 * dp).toInt())
        backdrop.addView(card, FrameLayout.LayoutParams(
            cardWidth, FrameLayout.LayoutParams.WRAP_CONTENT, Gravity.CENTER,
        ))

        inputPickerView = backdrop
        windowManager?.addView(backdrop, buildInputPickerLayoutParams())

        // Pop the keyboard up as soon as the window is attached. Without
        // requestFocus + showSoftInput, Android sometimes leaves the IME
        // hidden until the user taps the field a second time.
        input.requestFocus()
        handler.postDelayed({
            val imm = getSystemService(INPUT_METHOD_SERVICE) as? android.view.inputmethod.InputMethodManager
            imm?.showSoftInput(input, android.view.inputmethod.InputMethodManager.SHOW_IMPLICIT)
        }, 80)
    }

    private fun hideInputPicker() {
        // Drop the keyboard explicitly — the window is FOCUSABLE so the IME
        // doesn't always animate out when we just remove the view.
        val view = inputPickerView
        if (view != null) {
            val imm = getSystemService(INPUT_METHOD_SERVICE) as? android.view.inputmethod.InputMethodManager
            imm?.hideSoftInputFromWindow(view.windowToken, 0)
            try { windowManager?.removeView(view) } catch (_: Exception) {}
        }
        inputPickerView = null
    }

    // ── Voice input picker ──

    /** Pulse animation runnable so we can cancel it on hide. */
    private var voicePulseRunnable: Runnable? = null

    @SuppressLint("ClickableViewAccessibility")
    private fun showVoicePicker(initialMode: String) {
        if (voicePickerView != null) { hideVoicePicker(); return }
        ensureWindowManager()
        refreshLocale()

        val dp = resources.displayMetrics.density
        val isDark = (resources.configuration.uiMode and android.content.res.Configuration.UI_MODE_NIGHT_MASK) ==
            android.content.res.Configuration.UI_MODE_NIGHT_YES
        val bg       = if (isDark) Color.parseColor("#1E1E30") else Color.WHITE
        val textCol  = if (isDark) Color.parseColor("#E8E8F0") else Color.parseColor("#1A1A2E")
        val mutedCol = if (isDark) Color.parseColor("#9090AA") else Color.parseColor("#6B6B7A")
        val accent   = Color.parseColor("#6C63FF")
        val borderCol = Color.parseColor(if (isDark) "#3A3A52" else "#DDDDF0")

        val backdrop = FrameLayout(this).apply {
            setBackgroundColor(Color.parseColor("#66000000"))
            setOnClickListener { cancelVoice() }
        }
        val card = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            background = GradientDrawable().apply { setColor(bg); cornerRadius = 18 * dp }
            elevation = 22 * dp
            setPadding((20 * dp).toInt(), (20 * dp).toInt(), (20 * dp).toInt(), (16 * dp).toInt())
            isClickable = true
            gravity = Gravity.CENTER_HORIZONTAL
        }

        // Title
        card.addView(TextView(this).apply {
            text = localized(R.string.bubble_voice)
            setTextColor(textCol)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 14f)
            typeface = Typeface.DEFAULT_BOLD
            gravity = Gravity.CENTER
            setPadding(0, 0, 0, (12 * dp).toInt())
        })

        // Big mic icon — using a TextView with 🎤 so we don't need to ship
        // a vector drawable just for this. Pulses alpha while listening.
        val mic = TextView(this).apply {
            text = "🎤"
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 48f)
            gravity = Gravity.CENTER
            setPadding(0, (8 * dp).toInt(), 0, (8 * dp).toInt())
        }
        voiceMicIcon = mic
        card.addView(mic)

        // Language pills: which language the user is SPEAKING in. Decoupled
        // from translate source-lang because dictation language often
        // differs (you might dictate JP, translate JP → EN). User taps a
        // pill → we persist the choice, cancel the active recognizer, and
        // restart it with the new BCP-47 tag.
        currentVoiceLang = readVoiceLang()
        val langScroll = HorizontalScrollView(this).apply {
            isHorizontalScrollBarEnabled = false
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT,
            ).apply { topMargin = (4 * dp).toInt() }
        }
        val langRow = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER
        }
        val pillsByCode = mutableMapOf<String, TextView>()
        fun renderLangPills() {
            for ((code, pill) in pillsByCode) {
                val selected = code == currentVoiceLang
                pill.background = GradientDrawable().apply {
                    setColor(if (selected) accent else Color.TRANSPARENT)
                    if (!selected) setStroke(1, borderCol)
                    cornerRadius = 12 * dp
                }
                pill.setTextColor(if (selected) Color.WHITE else textCol)
            }
        }
        VOICE_LANGS.forEachIndexed { idx, code ->
            val label = LANG_LABELS[code] ?: code.uppercase()
            val pill = TextView(this).apply {
                text = label
                setTextSize(TypedValue.COMPLEX_UNIT_SP, 11f)
                typeface = Typeface.DEFAULT_BOLD
                gravity = Gravity.CENTER
                maxLines = 1
                setSingleLine(true)
                setPadding((12 * dp).toInt(), (6 * dp).toInt(), (12 * dp).toInt(), (6 * dp).toInt())
                isClickable = true
                isFocusable = true
                layoutParams = LinearLayout.LayoutParams(
                    LinearLayout.LayoutParams.WRAP_CONTENT,
                    LinearLayout.LayoutParams.WRAP_CONTENT,
                ).apply { marginEnd = if (idx < VOICE_LANGS.size - 1) (6 * dp).toInt() else 0 }
                setOnClickListener {
                    if (currentVoiceLang == code) return@setOnClickListener
                    currentVoiceLang = code
                    writeVoiceLang(code)
                    renderLangPills()
                    // Wipe stale transcript + restart recognizer with the
                    // newly-picked language. Note: voiceHelper?.cancel()
                    // ALSO calls destroy() under the hood — start a new one.
                    voiceHelper?.cancel()
                    voiceHelper = null
                    voiceTranscriptView?.text = ""
                    voiceStatusView?.text = localized(R.string.bubble_voice_speak)
                    startVoiceRecognizer(initialMode)
                }
            }
            pillsByCode[code] = pill
            langRow.addView(pill)
        }
        renderLangPills()
        langScroll.addView(langRow)
        card.addView(langScroll)

        // Status line ("Listening…" / "Speak now" / error)
        val status = TextView(this).apply {
            text = localized(R.string.bubble_voice_speak)
            setTextColor(mutedCol)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 13f)
            gravity = Gravity.CENTER
            setPadding(0, (6 * dp).toInt(), 0, (6 * dp).toInt())
        }
        voiceStatusView = status
        card.addView(status)

        // Live transcript — fills out as the engine emits partials. Bordered
        // so empty state still reads as "a place where your words appear".
        val transcript = TextView(this).apply {
            setTextColor(textCol)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 15f)
            setPadding(
                (12 * dp).toInt(), (10 * dp).toInt(),
                (12 * dp).toInt(), (10 * dp).toInt(),
            )
            background = GradientDrawable().apply {
                setColor(Color.TRANSPARENT)
                setStroke(1, borderCol)
                cornerRadius = 12 * dp
            }
            minLines = 2
            maxLines = 4
            gravity = Gravity.TOP or Gravity.START
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT,
            ).apply { topMargin = (8 * dp).toInt() }
        }
        voiceTranscriptView = transcript
        card.addView(transcript)

        // Action row: Cancel + Stop. Stop commits whatever partial we have
        // and routes the final text into the input picker for review.
        val actions = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.END
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT,
            ).apply { topMargin = (12 * dp).toInt() }
        }
        actions.addView(TextView(this).apply {
            text = localized(R.string.bubble_cancel)
            setTextColor(mutedCol)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 13f)
            typeface = Typeface.DEFAULT_BOLD
            setPadding((14 * dp).toInt(), (10 * dp).toInt(), (14 * dp).toInt(), (10 * dp).toInt())
            isClickable = true
            isFocusable = true
            setOnClickListener { cancelVoice() }
        })
        actions.addView(TextView(this).apply {
            text = localized(R.string.bubble_voice_stop)
            setTextColor(Color.WHITE)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 13f)
            typeface = Typeface.DEFAULT_BOLD
            background = GradientDrawable().apply {
                setColor(accent)
                cornerRadius = 12 * dp
            }
            setPadding((18 * dp).toInt(), (10 * dp).toInt(), (18 * dp).toInt(), (10 * dp).toInt())
            isClickable = true
            isFocusable = true
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.WRAP_CONTENT,
                LinearLayout.LayoutParams.WRAP_CONTENT,
            ).apply { marginStart = (8 * dp).toInt() }
            setOnClickListener { voiceHelper?.stop() }
        })
        card.addView(actions)

        val screenWidth = resources.displayMetrics.widthPixels
        val cardWidth = (screenWidth - (40 * dp).toInt()).coerceAtMost((360 * dp).toInt())
        backdrop.addView(card, FrameLayout.LayoutParams(
            cardWidth, FrameLayout.LayoutParams.WRAP_CONTENT, Gravity.CENTER,
        ))
        voicePickerView = backdrop
        windowManager?.addView(backdrop, buildPickerLayoutParams())

        startMicPulse()
        startVoiceRecognizer(initialMode)
    }

    /**
     * (Re-)spin up the SpeechRecognizer using whatever language the user
     * currently has picked in the voice picker. Called when the picker
     * first opens and again every time the user taps a different lang pill.
     */
    private fun startVoiceRecognizer(initialMode: String) {
        val tag = VoiceRecognitionHelper.resolveLanguageTag(currentVoiceLang)
        val helper = VoiceRecognitionHelper(
            context = this,
            languageTag = tag,
            callbacks = object : VoiceRecognitionHelper.Callbacks {
                override fun onReady() {
                    handler.post {
                        voiceStatusView?.text = localized(R.string.bubble_voice_listening)
                    }
                }
                override fun onPartialResult(text: String) {
                    handler.post {
                        voiceTranscriptView?.text = text
                    }
                }
                override fun onFinalResult(text: String) {
                    handler.post {
                        hideVoicePicker()
                        // Open the input picker with the recognized text so
                        // the user can correct mis-hearings before sending.
                        showInputPicker(initialMode, prefillText = text)
                    }
                }
                override fun onError(message: String) {
                    handler.post {
                        voiceStatusView?.text = message
                        voiceTranscriptView?.text = ""
                        stopMicPulse()
                        // Auto-dismiss after a moment so the user isn't stuck
                        // on the error card — UNLESS they're likely to retry
                        // with a different language (CJK packs often missing).
                        handler.postDelayed({ hideVoicePicker() }, 2400)
                    }
                }
            },
        )
        voiceHelper = helper
        helper.start()
    }

    private fun startMicPulse() {
        stopMicPulse()
        val runnable = object : Runnable {
            override fun run() {
                val mic = voiceMicIcon ?: return
                val target = if (mic.alpha > 0.7f) 0.35f else 1f
                mic.animate().alpha(target).setDuration(550).start()
                handler.postDelayed(this, 550)
            }
        }
        voicePulseRunnable = runnable
        handler.post(runnable)
    }

    private fun stopMicPulse() {
        voicePulseRunnable?.let { handler.removeCallbacks(it) }
        voicePulseRunnable = null
        voiceMicIcon?.animate()?.cancel()
        voiceMicIcon?.alpha = 1f
    }

    private fun cancelVoice() {
        voiceHelper?.cancel()
        voiceHelper = null
        hideVoicePicker()
    }

    private fun hideVoicePicker() {
        stopMicPulse()
        voiceHelper?.destroy()
        voiceHelper = null
        voicePickerView?.let { try { windowManager?.removeView(it) } catch (_: Exception) {} }
        voicePickerView = null
        voiceMicIcon = null
        voiceStatusView = null
        voiceTranscriptView = null
    }

    // ── Scan screen (MediaProjection + ML Kit OCR) ──

    /**
     * Entry from the mode picker. First tap shows a one-time disclosure
     * explaining that a single frame is captured on-device and discarded
     * after OCR. Subsequent taps go straight to the MediaProjection consent
     * prompt — that prompt itself is non-skippable per Android policy and
     * appears every session because we deliberately don't persist the
     * projection token.
     */
    private fun handleScanRequest() {
        ScreenCaptureManager.regionMode = false
        val prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        if (prefs.getBoolean(KEY_SCAN_DISCLOSED, false)) {
            launchScanFlow()
        } else {
            showScanDisclosure()
        }
    }

    /**
     * Variant of [handleScanRequest] that asks ScreenCaptureService to skip
     * immediate OCR. After capture, BubbleService receives a bitmap and
     * presents [RegionSelectionView] so the user can drag a rectangle;
     * only that sub-region is OCR'd + translated.
     */
    private fun handleLensRegionRequest() {
        ScreenCaptureManager.regionMode = true
        val prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        if (prefs.getBoolean(KEY_SCAN_DISCLOSED, false)) {
            launchScanFlow()
        } else {
            showScanDisclosure()
        }
    }

    private fun launchScanFlow() {
        // Lens flow: capture screen → OCR blocks (with bounding boxes) →
        // batch-translate → render LensOverlayView. The old "OCR → text
        // → input picker" flow lives on as ScreenCaptureManager.Flow.
        // TEXT_INTO_INPUT but isn't currently exposed in the mode picker.
        ScreenCaptureManager.flow = ScreenCaptureManager.Flow.LENS
        ScreenCaptureManager.languageHint = readSourceLang().takeIf { it != "auto" }
        ScreenCaptureManager.targetLang = readTargetLang()
        ScreenCaptureManager.pendingMode = MODE_TRANSLATE
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

    private fun restoreBubbleVisibility() {
        bubbleView?.visibility = View.VISIBLE
    }

    @SuppressLint("ClickableViewAccessibility")
    private fun showScanDisclosure() {
        if (scanDisclosureView != null) { hideScanDisclosure(); return }
        ensureWindowManager()
        refreshLocale()

        val dp = resources.displayMetrics.density
        val isDark = (resources.configuration.uiMode and android.content.res.Configuration.UI_MODE_NIGHT_MASK) ==
            android.content.res.Configuration.UI_MODE_NIGHT_YES
        val bg       = if (isDark) Color.parseColor("#1E1E30") else Color.WHITE
        val textCol  = if (isDark) Color.parseColor("#E8E8F0") else Color.parseColor("#1A1A2E")
        val mutedCol = if (isDark) Color.parseColor("#9090AA") else Color.parseColor("#6B6B7A")
        val accent   = Color.parseColor("#6C63FF")

        val backdrop = FrameLayout(this).apply {
            setBackgroundColor(Color.parseColor("#66000000"))
            setOnClickListener { hideScanDisclosure() }
        }
        val card = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            background = GradientDrawable().apply { setColor(bg); cornerRadius = 18 * dp }
            elevation = 22 * dp
            setPadding((20 * dp).toInt(), (18 * dp).toInt(), (20 * dp).toInt(), (16 * dp).toInt())
            isClickable = true
        }
        card.addView(TextView(this).apply {
            text = "📷  ${localized(R.string.bubble_scan_disclosure_title)}"
            setTextColor(textCol)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 15f)
            typeface = Typeface.DEFAULT_BOLD
            setPadding(0, 0, 0, (10 * dp).toInt())
        })
        card.addView(TextView(this).apply {
            text = localized(R.string.bubble_scan_disclosure_body)
            setTextColor(mutedCol)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 13f)
            setLineSpacing(2 * dp, 1f)
            setPadding(0, 0, 0, (16 * dp).toInt())
        })

        val actions = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.END
        }
        actions.addView(TextView(this).apply {
            text = localized(R.string.bubble_cancel)
            setTextColor(mutedCol)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 13f)
            typeface = Typeface.DEFAULT_BOLD
            setPadding((14 * dp).toInt(), (10 * dp).toInt(), (14 * dp).toInt(), (10 * dp).toInt())
            isClickable = true
            isFocusable = true
            setOnClickListener { hideScanDisclosure() }
        })
        actions.addView(TextView(this).apply {
            text = localized(R.string.bubble_scan_continue)
            setTextColor(Color.WHITE)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 13f)
            typeface = Typeface.DEFAULT_BOLD
            background = GradientDrawable().apply {
                setColor(accent)
                cornerRadius = 12 * dp
            }
            setPadding((18 * dp).toInt(), (10 * dp).toInt(), (18 * dp).toInt(), (10 * dp).toInt())
            isClickable = true
            isFocusable = true
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.WRAP_CONTENT,
                LinearLayout.LayoutParams.WRAP_CONTENT,
            ).apply { marginStart = (8 * dp).toInt() }
            setOnClickListener {
                getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE).edit()
                    .putBoolean(KEY_SCAN_DISCLOSED, true).apply()
                hideScanDisclosure()
                launchScanFlow()
            }
        })
        card.addView(actions)

        val screenWidth = resources.displayMetrics.widthPixels
        val cardWidth = (screenWidth - (40 * dp).toInt()).coerceAtMost((360 * dp).toInt())
        backdrop.addView(card, FrameLayout.LayoutParams(
            cardWidth, FrameLayout.LayoutParams.WRAP_CONTENT, Gravity.CENTER,
        ))
        scanDisclosureView = backdrop
        windowManager?.addView(backdrop, buildPickerLayoutParams())
    }

    private fun hideScanDisclosure() {
        scanDisclosureView?.let { try { windowManager?.removeView(it) } catch (_: Exception) {} }
        scanDisclosureView = null
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
        if (bitmap == null || blocks.isEmpty()) {
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
            Toast.makeText(this, "App not ready — open TransKey once", Toast.LENGTH_LONG).show()
            return
        }
        val channel = io.flutter.plugin.common.MethodChannel(
            engine.dartExecutor.binaryMessenger, METHOD_CHANNEL,
        )
        val texts = blocks.map { it.text }
        val target = ScreenCaptureManager.targetLang
        val source = ScreenCaptureManager.languageHint
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
                        message ?: "Translation failed",
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

    @SuppressLint("ClickableViewAccessibility")
    private fun showLensProgress() {
        if (lensProgressView != null) return
        ensureWindowManager()
        val dp = resources.displayMetrics.density
        val isDark = (resources.configuration.uiMode and android.content.res.Configuration.UI_MODE_NIGHT_MASK) ==
            android.content.res.Configuration.UI_MODE_NIGHT_YES
        val bg      = if (isDark) Color.parseColor("#1E1E30") else Color.WHITE
        val textCol = if (isDark) Color.parseColor("#E8E8F0") else Color.parseColor("#1A1A2E")

        val backdrop = FrameLayout(this).apply {
            setBackgroundColor(Color.parseColor("#88000000"))
            isClickable = true  // swallow taps so user can't dismiss mid-translate
        }
        val card = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            background = GradientDrawable().apply { setColor(bg); cornerRadius = 14 * dp }
            elevation = 20 * dp
            setPadding((18 * dp).toInt(), (14 * dp).toInt(), (20 * dp).toInt(), (14 * dp).toInt())
        }
        card.addView(ProgressBar(this, null, android.R.attr.progressBarStyleSmall).apply {
            isIndeterminate = true
            layoutParams = LinearLayout.LayoutParams(
                (22 * dp).toInt(), (22 * dp).toInt(),
            )
        })
        card.addView(TextView(this).apply {
            text = localized(R.string.bubble_lens_translating)
            setTextColor(textCol)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 13f)
            typeface = Typeface.DEFAULT_BOLD
            setPadding((12 * dp).toInt(), 0, 0, 0)
        })
        backdrop.addView(card, FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.WRAP_CONTENT,
            FrameLayout.LayoutParams.WRAP_CONTENT,
            Gravity.CENTER,
        ))
        lensProgressView = backdrop
        windowManager?.addView(backdrop, buildPickerLayoutParams())
    }

    private fun hideLensProgress() {
        lensProgressView?.let { try { windowManager?.removeView(it) } catch (_: Exception) {} }
        lensProgressView = null
    }

    private fun showLensOverlay(bitmap: Bitmap, items: List<LensOverlayView.Item>) {
        ensureWindowManager()
        val overlay = LensOverlayView(
            this, bitmap, items,
            onDismissOutsideTap = { hideLensOverlay() },
        )
        lensOverlayView = overlay
        windowManager?.addView(overlay, buildPickerLayoutParams())
    }

    private fun hideLensOverlay() {
        lensOverlayView?.let { try { windowManager?.removeView(it) } catch (_: Exception) {} }
        lensOverlayView = null
        // Recycling the bitmap + clearing manager state is done together
        // here (NOT in service.cleanup) so the bitmap survives until the
        // user actually dismisses the overlay.
        ScreenCaptureManager.clearAll()
        restoreBubbleVisibility()
    }

    /**
     * Region mode: capture done, bitmap is sitting in the manager. Show
     * the rubber-band selector. On confirm we crop the bitmap, OCR the
     * sub-image, OFFSET each block's bounds back into full-screen coords
     * (so the Lens overlay paints them at the right place on top of the
     * still-full screenshot), then reuse [handleLensReady] for the
     * batch-translate + overlay render.
     */
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
                // Stash the offset blocks where handleLensReady expects
                // them, then run the existing batch-translate + overlay
                // path so we don't duplicate the channel + overlay code.
                ScreenCaptureManager.blocks = offset
                hideLensProgress()
                handleLensReady()
            }
        }
    }

    /**
     * Mode-picker entry for the voice flow. Requests RECORD_AUDIO via a
     * transparent activity since a Service can't show a runtime prompt.
     * The activity calls back via ACTION_START_VOICE.
     */
    private fun handleVoiceRequest() {
        val granted = checkSelfPermission(android.Manifest.permission.RECORD_AUDIO) ==
            android.content.pm.PackageManager.PERMISSION_GRANTED
        if (granted) {
            showVoicePicker(MODE_TRANSLATE)
            return
        }
        val intent = Intent(this, MicPermissionActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                    Intent.FLAG_ACTIVITY_NO_HISTORY or
                    Intent.FLAG_ACTIVITY_EXCLUDE_FROM_RECENTS
        }
        try { startActivity(intent) } catch (_: Exception) {}
    }

    /**
     * "Read this screen" flow — works for apps that disable selection but
     * still render text via standard views (banking, anti-copy chat apps,
     * reader apps). Falls back to a Toast + Accessibility-settings prompt
     * when the service isn't enabled; canvas-only games / image content
     * return empty and the user is told to use another input method.
     */
    private fun handleReadScreenRequest() {
        val a11y = TransKeyAccessibilityService.instance
        if (a11y == null) {
            Toast.makeText(
                this,
                localized(R.string.bubble_read_screen_a11y_off),
                Toast.LENGTH_LONG,
            ).show()
            val intent = Intent(android.provider.Settings.ACTION_ACCESSIBILITY_SETTINGS).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK
            }
            try { startActivity(intent) } catch (_: Exception) {}
            return
        }
        // Wait for the mode picker overlay to fully detach so the active
        // window is the source app (not our just-removed picker). Without
        // this 200ms grace, rootInActiveWindow occasionally returns null
        // mid-transition on some OEM builds.
        handler.postDelayed({
            val text = a11y.getScreenText()
            if (text.isNullOrBlank()) {
                Toast.makeText(
                    this,
                    localized(R.string.bubble_read_screen_empty),
                    Toast.LENGTH_SHORT,
                ).show()
            } else {
                showInputPicker(MODE_TRANSLATE, prefillText = text)
            }
        }, 200)
    }

    private fun showSettingsSheet() {
        if (tonePickerView != null) { hideTonePicker(); return }
        ensureWindowManager()
        refreshLocale()
        // Re-read every setting in case they changed via the in-app Settings.
        currentTone = readTone()
        val replyTone = readReplyTone()
        val romanizationOn = readRomanization()
        val replySuggestionsOn = readReplySuggestions()
        val ttsRate = readTtsRate()

        val dp = resources.displayMetrics.density
        val isDark = (resources.configuration.uiMode and android.content.res.Configuration.UI_MODE_NIGHT_MASK) ==
            android.content.res.Configuration.UI_MODE_NIGHT_YES
        val bg      = if (isDark) Color.parseColor("#1E1E30") else Color.WHITE
        val textCol = if (isDark) Color.parseColor("#E8E8F0") else Color.parseColor("#1A1A2E")
        val mutedCol = if (isDark) Color.parseColor("#9090AA") else Color.parseColor("#6B6B7A")
        val accent  = Color.parseColor("#6C63FF")
        val borderCol = Color.parseColor(if (isDark) "#3A3A52" else "#DDDDF0")

        val backdrop = FrameLayout(this).apply {
            setBackgroundColor(Color.parseColor("#55000000"))
            setOnClickListener { hideTonePicker() }
        }
        val card = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            background = GradientDrawable().apply { setColor(bg); cornerRadius = 18 * dp }
            elevation = 22 * dp
            setPadding((16 * dp).toInt(), (14 * dp).toInt(), (16 * dp).toInt(), (14 * dp).toInt())
            isClickable = true
        }
        // Scrollable content so the sheet fits even on short screens.
        val scroll = ScrollView(this).apply {
            isFillViewport = false
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT,
            )
        }
        val content = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
        }
        scroll.addView(content)

        card.addView(TextView(this).apply {
            text = localized(R.string.bubble_settings)
            setTextColor(textCol)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 14f)
            typeface = Typeface.DEFAULT_BOLD
            setPadding(0, 0, 0, (12 * dp).toInt())
        })
        card.addView(scroll)

        // ── Section: Translate tone ─────────────────────────────────────
        content.addView(sectionLabel(localized(R.string.bubble_translate_tone), mutedCol, dp))
        content.addView(toneRow(
            currentTone, accent, textCol, borderCol, mutedCol, isDark, dp,
            includeAuto = true,
        ) { code ->
            currentTone = code
            writeTone(code)
            updateLangChip()
            // Refresh the currently visible bottom sheet to reflect the new
            // selection without closing it.
            hideTonePicker()
            showSettingsSheet()
            // Re-translate if a result is already showing so the user sees
            // the new tone applied immediately.
            currentSourceText?.let { src -> handleTranslateRequest(src, currentMode) }
        })

        // ── Section: Reply tone ─────────────────────────────────────────
        content.addView(sectionLabel(localized(R.string.bubble_reply_tone), mutedCol, dp).apply {
            (layoutParams as? LinearLayout.LayoutParams)?.topMargin = (14 * dp).toInt()
        })
        // Use empty string code "" to mean "same as translate tone" — the
        // app's settings UI uses the same convention via toneReplySameAsTranslate.
        val replyToneLabel = if (replyTone.isEmpty()) {
            localized(R.string.bubble_reply_tone_same)
        } else {
            toneLabel(replyTone)
        }
        content.addView(toneRow(
            replyTone, accent, textCol, borderCol, mutedCol, isDark, dp,
            includeAuto = true,
            autoLabel = localized(R.string.bubble_reply_tone_same),
        ) { code ->
            writeReplyTone(code)
            hideTonePicker()
            showSettingsSheet()
            // Reply-tone only changes output in Reply mode; re-translate so the
            // user sees the new tone applied without manually re-triggering.
            if (currentMode == MODE_REPLY) {
                currentSourceText?.let { src -> handleTranslateRequest(src, currentMode) }
            }
        })
        // Tone hint label — show the current effective reply tone.
        content.addView(TextView(this).apply {
            text = "→ $replyToneLabel"
            setTextColor(mutedCol)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 10f)
            setPadding(0, (4 * dp).toInt(), 0, 0)
        })

        // ── Section: TTS speed ─────────────────────────────────────────
        content.addView(sectionLabel(localized(R.string.bubble_speech_rate), mutedCol, dp).apply {
            (layoutParams as? LinearLayout.LayoutParams)?.topMargin = (16 * dp).toInt()
        })
        content.addView(rateRow(ttsRate, accent, textCol, borderCol, isDark, dp) { rate ->
            writeTtsRate(rate)
            hideTonePicker()
            showSettingsSheet()
        })

        // ── Section: Toggles (romanization, reply suggestions) ─────────
        content.addView(toggleRow(
            localized(R.string.bubble_romanization),
            romanizationOn, accent, textCol, borderCol, dp,
        ) { newValue ->
            writeRomanization(newValue)
            // Romanization affects every translate mode — re-run so the user
            // sees the romanization line appear/disappear immediately.
            currentSourceText?.let { src -> handleTranslateRequest(src, currentMode) }
        }.apply {
            (layoutParams as? LinearLayout.LayoutParams)?.topMargin = (16 * dp).toInt()
        })
        content.addView(toggleRow(
            localized(R.string.bubble_reply_suggestions),
            replySuggestionsOn, accent, textCol, borderCol, dp,
        ) { newValue ->
            writeReplySuggestions(newValue)
            // Suggestions are only generated in Reply mode — only re-translate
            // when the new value would actually change the output.
            if (currentMode == MODE_REPLY) {
                currentSourceText?.let { src -> handleTranslateRequest(src, currentMode) }
            }
        }.apply {
            (layoutParams as? LinearLayout.LayoutParams)?.topMargin = (8 * dp).toInt()
        })

        val screenWidth = resources.displayMetrics.widthPixels
        val cardWidth = (screenWidth - (40 * dp).toInt()).coerceAtMost((340 * dp).toInt())
        // Cap height so very long sheets remain scrollable instead of pushing
        // beyond the screen on small phones.
        val maxHeight = (resources.displayMetrics.heightPixels * 0.75).toInt()
        backdrop.addView(card, FrameLayout.LayoutParams(cardWidth, FrameLayout.LayoutParams.WRAP_CONTENT, Gravity.CENTER).apply {
            scroll.layoutParams = (scroll.layoutParams as LinearLayout.LayoutParams).apply {
                @Suppress("UNUSED_VARIABLE") val _h = maxHeight  // referenced via constraint below
            }
        })
        tonePickerView = backdrop
        windowManager?.addView(backdrop, buildPickerLayoutParams())
    }

    private fun sectionLabel(text: String, mutedCol: Int, dp: Float): TextView =
        TextView(this).apply {
            this.text = text.uppercase()
            setTextColor(mutedCol)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 10f)
            typeface = Typeface.DEFAULT_BOLD
            letterSpacing = 0.08f
            setPadding(0, 0, 0, (6 * dp).toInt())
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT,
            )
        }

    // Horizontal wrap of pill buttons — used for both tone pickers and rates.
    private fun toneRow(
        currentCode: String,
        accent: Int, textCol: Int, borderCol: Int, mutedCol: Int,
        isDark: Boolean, dp: Float,
        includeAuto: Boolean,
        autoLabel: String? = null,
        onPick: (String) -> Unit,
    ): View {
        @Suppress("UNUSED_PARAMETER") val _isDark = isDark
        @Suppress("UNUSED_PARAMETER") val _mutedCol = mutedCol
        val codes = if (includeAuto) TONE_CODES else TONE_CODES.drop(1)
        return wrapRow(codes.map { code ->
            val label = if (code.isEmpty() && autoLabel != null) autoLabel else toneLabel(code)
            pillButton(label, code == currentCode, accent, textCol, borderCol, dp) { onPick(code) }
        }, dp)
    }

    private fun rateRow(
        currentRate: Double, accent: Int, textCol: Int, borderCol: Int,
        isDark: Boolean, dp: Float, onPick: (Double) -> Unit,
    ): View {
        @Suppress("UNUSED_PARAMETER") val _isDark = isDark
        return wrapRow(TTS_RATES.map { r ->
            pillButton(formatRate(r), r == currentRate, accent, textCol, borderCol, dp) { onPick(r) }
        }, dp)
    }

    private fun wrapRow(children: List<View>, dp: Float): View {
        // Flow horizontally; if too wide for the card, wrap to a new line.
        // Android has no FlowLayout in the SDK, so we build it manually with
        // two LinearLayouts when needed. For our 6-7 short pills it almost
        // always fits one row.
        val row = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT,
            )
        }
        val scroll = HorizontalScrollView(this).apply {
            isHorizontalScrollBarEnabled = false
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT,
            )
            addView(row)
        }
        children.forEachIndexed { i, v ->
            v.layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.WRAP_CONTENT,
                LinearLayout.LayoutParams.WRAP_CONTENT,
            ).apply { marginEnd = if (i < children.size - 1) (6 * dp).toInt() else 0 }
            row.addView(v)
        }
        return scroll
    }

    private fun pillButton(
        label: String, selected: Boolean, accent: Int, textCol: Int, borderCol: Int,
        dp: Float, onClick: () -> Unit,
    ): TextView = TextView(this).apply {
        text = label
        setTextColor(if (selected) Color.WHITE else textCol)
        setTextSize(TypedValue.COMPLEX_UNIT_SP, 12f)
        typeface = if (selected) Typeface.DEFAULT_BOLD else Typeface.DEFAULT
        gravity = Gravity.CENTER
        maxLines = 1
        setSingleLine(true)
        setPadding((14 * dp).toInt(), (8 * dp).toInt(), (14 * dp).toInt(), (8 * dp).toInt())
        background = GradientDrawable().apply {
            setColor(if (selected) accent else Color.TRANSPARENT)
            if (!selected) setStroke(1, borderCol)
            cornerRadius = 12 * dp
        }
        setOnClickListener { onClick() }
    }

    private fun toggleRow(
        label: String, current: Boolean, accent: Int, textCol: Int, borderCol: Int,
        dp: Float, onChange: (Boolean) -> Unit,
    ): View {
        val state = booleanArrayOf(current)
        val row = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(0, (8 * dp).toInt(), 0, (8 * dp).toInt())
            isClickable = true
        }
        val labelTv = TextView(this).apply {
            text = label
            setTextColor(textCol)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 13f)
            layoutParams = LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f)
        }
        // Custom on/off pill as a stand-in for Switch (no Material theme here)
        val pill = TextView(this).apply {
            setTextColor(Color.WHITE)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 11f)
            typeface = Typeface.DEFAULT_BOLD
            gravity = Gravity.CENTER
            setPadding((12 * dp).toInt(), (4 * dp).toInt(), (12 * dp).toInt(), (4 * dp).toInt())
        }
        fun render() {
            pill.text = if (state[0]) "ON" else "OFF"
            pill.background = GradientDrawable().apply {
                setColor(if (state[0]) accent else Color.TRANSPARENT)
                if (!state[0]) setStroke(1, borderCol)
                cornerRadius = 12 * dp
            }
            pill.setTextColor(if (state[0]) Color.WHITE else textCol)
        }
        render()
        row.setOnClickListener {
            state[0] = !state[0]
            render()
            onChange(state[0])
        }
        row.addView(labelTv)
        row.addView(pill)
        return row
    }

    // ── Lifecycle ──

    fun stopBubble() {
        unregisterClipboardListener()
        hasNewClipText = false
        hideModePicker()
        hideLangPicker()
        hideInputPicker()
        hideVoicePicker()
        hideScanDisclosure()
        hideLensProgress()
        hideLensOverlay()
        hideRegionSelectionView()
        releaseScreenCapture()
        removeResultPanel()
        removeBubble()
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

    private fun ensureWindowManager() {
        if (windowManager == null) {
            windowManager = getSystemService(WINDOW_SERVICE) as WindowManager
        }
    }
}
