package app.transkey.mobile

import android.annotation.SuppressLint
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.util.TypedValue
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import android.view.inputmethod.EditorInfo
import android.widget.EditText
import android.widget.FrameLayout
import android.widget.HorizontalScrollView
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.TextView
import android.widget.Toast
import app.transkey.mobile.BubbleService.Companion.ALL_MODES
import app.transkey.mobile.BubbleService.Companion.LANG_LABELS
import app.transkey.mobile.BubbleService.Companion.MODE_REFINE
import app.transkey.mobile.BubbleService.Companion.MODE_REPLY
import app.transkey.mobile.BubbleService.Companion.MODE_TRANSLATE
import app.transkey.mobile.BubbleService.Companion.STATE_IDLE
import app.transkey.mobile.BubbleService.Companion.VOICE_LANGS

/**
 * Input + voice pickers — the two "user-types/speaks the source text"
 * flows triggered from the bubble's mode picker, plus the voice helper
 * setup/teardown (mic permission gate, VoiceRecognitionHelper lifecycle,
 * the breathing mic-icon animation).
 *
 * showInputPicker: focusable overlay with an EditText so the soft
 * keyboard attaches; user types + taps action → handleTranslateRequest.
 *
 * showVoicePicker: speaks-to-text picker — mic gating via
 * MicPermissionActivity, lang selector, VoiceRecognitionHelper for
 * partial / final results.
 */
internal fun BubbleService.buildInputPickerLayoutParams(): WindowManager.LayoutParams {
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
internal fun BubbleService.showInputPicker(initialMode: String, prefillText: String? = null) {
    val service: BubbleService = this
    if (inputPickerView != null) { hideInputPicker(); return }
    ensureWindowManager()
    refreshLocale()

    val style = BubbleStyle.of(this)
    val dp = style.dp
    val isDark = style.isDark
    val bg = style.bg
    val textCol = style.text
    val mutedCol = style.muted
    val accent = style.accent
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
            val cm = getSystemService(Context.CLIPBOARD_SERVICE) as android.content.ClipboardManager
            val clip = cm.primaryClip
            val pasted = if (clip != null && clip.itemCount > 0) {
                clip.getItemAt(0).coerceToText(service)?.toString().orEmpty()
            } else ""
            if (pasted.isEmpty()) {
                Toast.makeText(service, localized(R.string.bubble_panel_clipboard_empty), Toast.LENGTH_SHORT).show()
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
        val imm = getSystemService(Context.INPUT_METHOD_SERVICE) as? android.view.inputmethod.InputMethodManager
        imm?.showSoftInput(input, android.view.inputmethod.InputMethodManager.SHOW_IMPLICIT)
    }, 80)
}

internal fun BubbleService.hideInputPicker() {
    // Drop the keyboard explicitly — the window is FOCUSABLE so the IME
    // doesn't always animate out when we just remove the view.
    val view = inputPickerView
    if (view != null) {
        val imm = getSystemService(Context.INPUT_METHOD_SERVICE) as? android.view.inputmethod.InputMethodManager
        imm?.hideSoftInputFromWindow(view.windowToken, 0)
        try { windowManager?.removeView(view) } catch (_: Exception) {}
    }
    inputPickerView = null
}

// ── Voice input picker ──

internal fun BubbleService.showVoicePicker(initialMode: String) {
    if (voicePickerView != null) { hideVoicePicker(); return }
    ensureWindowManager()
    refreshLocale()

    val style = BubbleStyle.of(this)
    val dp = style.dp
    val isDark = style.isDark
    val bg = style.bg
    val textCol = style.text
    val mutedCol = style.muted
    val accent = style.accent
    val borderCol = Color.parseColor(if (isDark) "#3A3A52" else "#DDDDF0")

    val backdrop = FrameLayout(this).apply {
        setBackgroundColor(Palette.BACKDROP_DIM)
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
internal fun BubbleService.startVoiceRecognizer(initialMode: String) {
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

internal fun BubbleService.startMicPulse() {
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

internal fun BubbleService.stopMicPulse() {
    voicePulseRunnable?.let { handler.removeCallbacks(it) }
    voicePulseRunnable = null
    voiceMicIcon?.animate()?.cancel()
    voiceMicIcon?.alpha = 1f
}

internal fun BubbleService.cancelVoice() {
    voiceHelper?.cancel()
    voiceHelper = null
    hideVoicePicker()
}

internal fun BubbleService.hideVoicePicker() {
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
/**
 * Mode chooser shown right after the user taps "Scan screen" or
 * "Region select" in the bubble picker. Translate runs the Lens
 * visual overlay; Summarize routes OCR text into the input picker
 * (then result panel). Other modes (Refine/Explain/Reply) aren't
 * exposed here per the feature spec — they only accept text the
 * user has already drafted/copied, not images of arbitrary screens.
 */
@SuppressLint("ClickableViewAccessibility")

internal fun BubbleService.handleVoiceRequest() {
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
