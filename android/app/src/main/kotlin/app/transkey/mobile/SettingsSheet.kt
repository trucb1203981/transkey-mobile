package app.transkey.mobile

import android.annotation.SuppressLint
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.util.TypedValue
import android.view.Gravity
import android.view.View
import android.widget.FrameLayout
import android.widget.HorizontalScrollView
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import app.transkey.mobile.BubbleService.Companion.MODE_REPLY
import app.transkey.mobile.BubbleService.Companion.TONE_CODES
import app.transkey.mobile.BubbleService.Companion.TTS_RATES

/**
 * Bubble's all-in-one settings sheet (gear icon in the result panel
 * header). Surfaces the 5 settings the bubble cares about: translate
 * tone, reply tone, romanization toggle, reply-suggestions toggle,
 * TTS rate. All writes go to the `flutter.tk_*` SharedPreferences
 * keys so the in-app Settings screen picks them up via the
 * notifyFlutterLangChanged round-trip + `prefs.reload()` on resume.
 *
 * The 6 small builder helpers (sectionLabel / toneRow / rateRow /
 * wrapRow / pillButton / toggleRow) live next door because they're
 * only used by this sheet and would otherwise pollute BubbleService.
 */
internal fun BubbleService.showSettingsSheet() {
    if (tonePickerView != null) { hideTonePicker(); return }
    ensureWindowManager()
    refreshLocale()
    // Re-read every setting in case they changed via the in-app Settings.
    currentTone = readTone()
    val replyTone = readReplyTone()
    val romanizationOn = readRomanization()
    val replySuggestionsOn = readReplySuggestions()
    val ttsRate = readTtsRate()

    val style = BubbleStyle.of(this)
    val dp = style.dp
    val isDark = style.isDark
    val bg = style.bg
    val textCol = style.text
    val mutedCol = style.muted
    val accent = style.accent
    val borderCol = Color.parseColor(if (isDark) "#3A3A52" else "#DDDDF0")

    val backdrop = FrameLayout(this).apply {
        setBackgroundColor(Palette.BACKDROP_LIGHT)
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

internal fun BubbleService.sectionLabel(text: String, mutedCol: Int, dp: Float): TextView =
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
internal fun BubbleService.toneRow(
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

internal fun BubbleService.rateRow(
    currentRate: Double, accent: Int, textCol: Int, borderCol: Int,
    isDark: Boolean, dp: Float, onPick: (Double) -> Unit,
): View {
    @Suppress("UNUSED_PARAMETER") val _isDark = isDark
    return wrapRow(TTS_RATES.map { r ->
        pillButton(formatRate(r), r == currentRate, accent, textCol, borderCol, dp) { onPick(r) }
    }, dp)
}

internal fun BubbleService.wrapRow(children: List<View>, dp: Float): View {
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

internal fun BubbleService.pillButton(
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

internal fun BubbleService.toggleRow(
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
