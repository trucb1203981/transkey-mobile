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
        const val EXTRA_STATE = "bubble_state"
        const val EXTRA_TEXT = "text"
        const val EXTRA_MODE = "mode"
        const val EXTRA_TRANSLATION = "translation"
        const val EXTRA_ROMANIZATION = "romanization"
        const val EXTRA_DETECTED_LANG = "detectedLang"
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
        private val MODE_LABELS = mapOf(
            MODE_TRANSLATE to "Translate",
            MODE_REPLY to "Reply",
            MODE_SUMMARIZE to "Summarize",
            MODE_EXPLAIN to "Explain",
            MODE_REFINE to "Refine",
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
        private const val KEY_REPLY_LANG = "flutter.tk_reply_lang"
        private const val KEY_BUBBLE_ACTIVE = "flutter.tk_bubble_active"

        private val SOURCE_LANGS = listOf("auto", "en", "vi", "ja", "zh", "ko", "fr", "de", "es", "pt", "ru", "th", "id")
        private val TONE_OPTIONS = listOf(
            "" to "Default",
            "formal" to "Formal",
            "casual" to "Casual",
            "professional" to "Professional",
            "friendly" to "Friendly",
            "academic" to "Academic",
        )

        private const val BUBBLE_SIZE_DP = 48

        // Drag-to-close target
        private const val CLOSE_ZONE_SIZE_DP = 64
        private const val CLOSE_ZONE_BOTTOM_MARGIN_DP = 80
        private const val CLOSE_ZONE_HIT_RADIUS_DP = 80

        @Volatile private var nextRequestId: Long = 0
    }

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
    private var toneChip: TextView? = null

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
        when (intent?.action) {
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
                val error = intent.getStringExtra(EXTRA_ERROR)
                val reqId = intent.getLongExtra(EXTRA_REQUEST_ID, -1)
                if (reqId == currentRequestId) {
                    if (!translation.isNullOrBlank()) {
                        showResult(translation, romanization, detectedLang)
                    } else {
                        showError(error ?: "Translation failed")
                    }
                }
            }
            ACTION_HIDE_PANEL -> hideResultPanel()
        }
        return START_STICKY
    }

    override fun onDestroy() {
        unregisterClipboardListener()
        hideModePicker()
        hideLangPicker()
        hideSourceLangPicker()
        hideTonePicker()
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

        // If clipboard changed since last translation, auto-translate with last mode
        if (hasNewClipText) {
            hasNewClipText = false
            autoTranslateFromClipboard()
        } else {
            showModePicker()
        }
    }

    @SuppressLint("ClickableViewAccessibility")
    private fun showModePicker() {
        ensureWindowManager()

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
            text = "Choose action"
            setTextColor(textCol)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 13f)
            typeface = Typeface.DEFAULT_BOLD
            setPadding(0, 0, 0, (8 * dp).toInt())
        })
        card.addView(TextView(this).apply {
            text = if (pendingSelectedText != null) {
                "Using your selected text."
            } else {
                "Select or copy text first, then pick an action below."
            }
            setTextColor(mutedCol)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 11f)
            setPadding(0, 0, 0, (12 * dp).toInt())
        })

        // 5 mode buttons
        val modesRow = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER
        }
        for (mode in ALL_MODES) {
            val btn = TextView(this).apply {
                text = MODE_LABELS[mode]
                setTextColor(accent)
                setTextSize(TypedValue.COMPLEX_UNIT_SP, 12f)
                gravity = Gravity.CENTER
                typeface = Typeface.DEFAULT_BOLD
                setPadding((6 * dp).toInt(), (12 * dp).toInt(), (6 * dp).toInt(), (12 * dp).toInt())
                background = GradientDrawable().apply {
                    val btnBg = if (isDark) "#2A2A40" else "#F0EFFF"
                    setColor(Color.parseColor(btnBg))
                    cornerRadius = 14 * dp
                }
                setOnClickListener {
                    val selected = pendingSelectedText
                    hideModePicker()
                    if (!selected.isNullOrBlank()) {
                        // Selection captured via AccessibilityService — translate
                        // directly, no clipboard / ShareActivity round-trip needed.
                        handleTranslateRequest(selected, mode)
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
                    .apply { marginEnd = (6 * dp).toInt() }
            }
            modesRow.addView(btn)
        }
        card.addView(modesRow)

        // "Last result" shortcut if we have a cached output
        if (currentOutput != null) {
            card.addView(View(this).apply {
                val dividerBg = if (isDark) "#3A3A50" else "#E0DFF8"
                layoutParams = LinearLayout.LayoutParams(
                    LinearLayout.LayoutParams.MATCH_PARENT, (1 * dp).toInt()
                ).apply { topMargin = (12 * dp).toInt(); bottomMargin = (8 * dp).toInt() }
                setBackgroundColor(Color.parseColor(dividerBg))
            })
            card.addView(TextView(this).apply {
                text = "Show last result"
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
        // Sync from prefs so the picker reflects any change made in Flutter UI.
        currentTargetLang = readTargetLang()

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

    private fun showResult(output: String, romanization: String?, detectedLang: String?) {
        isTranslating = false
        currentOutput = output
        currentRomanization = romanization
        currentDetectedLang = detectedLang
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

            toneChip = TextView(this).apply {
                setTextSize(TypedValue.COMPLEX_UNIT_SP, 10f)
                setTextColor(mutedCol)
                setPadding((6 * dp).toInt(), (3 * dp).toInt(), (6 * dp).toInt(), (3 * dp).toInt())
                background = GradientDrawable().apply {
                    setColor(Color.TRANSPARENT)
                    setStroke(1, mutedCol)
                    cornerRadius = 10 * dp
                }
                setOnClickListener { showTonePicker() }
                layoutParams = LinearLayout.LayoutParams(
                    LinearLayout.LayoutParams.WRAP_CONTENT,
                    LinearLayout.LayoutParams.WRAP_CONTENT,
                ).apply { marginStart = (6 * dp).toInt(); marginEnd = (6 * dp).toInt() }
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
            header.addView(closeBtn)

            // Mode tabs (Translate / Summarize / Explain / Refine)
            val tabsRow = LinearLayout(this).apply {
                orientation = LinearLayout.HORIZONTAL
                setPadding(0, (8 * dp).toInt(), 0, (4 * dp).toInt())
            }
            modeButtons.clear()
            for (mode in ALL_MODES) {
                val btn = TextView(this).apply {
                    text = MODE_LABELS[mode]
                    setTextSize(TypedValue.COMPLEX_UNIT_SP, 12f)
                    gravity = Gravity.CENTER
                    setPadding((10 * dp).toInt(), (6 * dp).toInt(), (10 * dp).toInt(), (6 * dp).toInt())
                    setOnClickListener {
                        if (isTranslating) return@setOnClickListener
                        val src = currentSourceText ?: return@setOnClickListener
                        handleTranslateRequest(src, mode)
                    }
                    layoutParams = LinearLayout.LayoutParams(
                        0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f,
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
                    // Hide panel first so it doesn't sit over the input, then
                    // replace the focused text in the host app.
                    hideResultPanel()
                    handler.postDelayed({
                        val ok = svc.replaceFocusedText(t)
                        if (!ok) {
                            Toast.makeText(
                                this@BubbleService,
                                "No editable field focused",
                                Toast.LENGTH_SHORT,
                            ).show()
                        }
                    }, 80)
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
            toneChip?.visibility = View.GONE
            return
        }

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

        // Tone chip: only show when a tone is set
        val toneLabel = TONE_OPTIONS.find { it.first == currentTone }?.second
        toneChip?.apply {
            if (toneLabel != null && toneLabel != "Default") {
                text = toneLabel
                visibility = View.VISIBLE
            } else {
                text = "Tone"
                visibility = View.VISIBLE
            }
        }
    }

    private fun updateModeTabs(accent: Int, mutedCol: Int) {
        val dp = resources.displayMetrics.density
        for ((mode, btn) in modeButtons) {
            if (mode == currentMode) {
                btn.setTextColor(Color.WHITE)
                btn.typeface = Typeface.DEFAULT_BOLD
                btn.background = GradientDrawable().apply {
                    setColor(accent)
                    cornerRadius = 8 * dp
                }
            } else {
                btn.setTextColor(mutedCol)
                btn.typeface = Typeface.DEFAULT
                btn.background = GradientDrawable().apply {
                    setColor(Color.TRANSPARENT)
                    setStroke(1, mutedCol)
                    cornerRadius = 8 * dp
                }
            }
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
        modeButtons.clear()
    }

    private fun speakOutput() {
        val text = currentOutput?.takeIf { it.isNotEmpty() } ?: return
        if (!ttsReady) { Toast.makeText(this, "TTS not ready", Toast.LENGTH_SHORT).show(); return }
        val locale = langToLocale(currentTargetLang)
        tts?.language = locale
        @Suppress("DEPRECATION")
        tts?.speak(text, TextToSpeech.QUEUE_FLUSH, null)
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

    private fun writeTone(tone: String) {
        getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE).edit()
            .putString(KEY_TONE_OVERRIDE, tone).apply()
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

    // ── Tone picker ──

    private fun showTonePicker() {
        if (tonePickerView != null) { hideTonePicker(); return }
        ensureWindowManager()
        val dp = resources.displayMetrics.density
        val isDark = (resources.configuration.uiMode and android.content.res.Configuration.UI_MODE_NIGHT_MASK) ==
            android.content.res.Configuration.UI_MODE_NIGHT_YES
        val bg      = if (isDark) Color.parseColor("#1E1E30") else Color.WHITE
        val textCol = if (isDark) Color.parseColor("#E8E8F0") else Color.parseColor("#1A1A2E")
        val accent  = Color.parseColor("#6C63FF")

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
        card.addView(TextView(this).apply {
            text = "Translation tone"
            setTextColor(accent)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 12f)
            typeface = Typeface.DEFAULT_BOLD
            setPadding(0, 0, 0, (10 * dp).toInt())
        })

        for ((value, label) in TONE_OPTIONS) {
            val isSelected = value == currentTone
            card.addView(TextView(this).apply {
                text = label
                setTextColor(if (isSelected) Color.WHITE else textCol)
                setTextSize(TypedValue.COMPLEX_UNIT_SP, 13f)
                gravity = Gravity.CENTER
                setPadding((12 * dp).toInt(), (10 * dp).toInt(), (12 * dp).toInt(), (10 * dp).toInt())
                background = GradientDrawable().apply {
                    setColor(if (isSelected) accent else Color.TRANSPARENT)
                    if (!isSelected) setStroke(1, Color.parseColor(if (isDark) "#3A3A52" else "#DDDDF0"))
                    cornerRadius = 10 * dp
                }
                layoutParams = LinearLayout.LayoutParams(
                    LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT,
                ).apply { bottomMargin = (4 * dp).toInt() }
                setOnClickListener {
                    currentTone = value
                    writeTone(value)
                    hideTonePicker()
                    updateLangChip()
                    currentSourceText?.let { src -> handleTranslateRequest(src, currentMode) }
                }
            })
        }

        val screenWidth = resources.displayMetrics.widthPixels
        val cardWidth = (screenWidth - (80 * dp).toInt()).coerceAtMost((260 * dp).toInt())
        backdrop.addView(card, FrameLayout.LayoutParams(cardWidth, FrameLayout.LayoutParams.WRAP_CONTENT, Gravity.CENTER))
        tonePickerView = backdrop
        windowManager?.addView(backdrop, buildPickerLayoutParams())
    }

    private fun hideTonePicker() {
        tonePickerView?.let { try { windowManager?.removeView(it) } catch (_: Exception) {} }
        tonePickerView = null
    }

    // ── Lifecycle ──

    fun stopBubble() {
        unregisterClipboardListener()
        hasNewClipText = false
        hideModePicker()
        hideLangPicker()
        removeResultPanel()
        removeBubble()
        saveBubbleActive(false)
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
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
