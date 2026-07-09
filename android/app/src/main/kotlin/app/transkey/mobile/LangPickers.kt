package app.transkey.mobile

import android.annotation.SuppressLint
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.util.TypedValue
import android.view.Gravity
import android.view.View
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.TextView
// (LANG_LABELS removed — read via getEffectiveLangLabels() per call.)
// SOURCE_LANGS / TARGET_LANGS / LANG_LABELS are NO LONGER imported as
// static fallbacks — the pickers below read via instance helpers
// (getEffectiveTargetLangs / getEffectiveSourceLangs /
// getEffectiveLangLabels) so the server-mirrored catalog drives the
// list. The static lists in BubbleService stay as last-resort fallback
// used INSIDE those helpers when the catalog pref is empty.

/**
 * Floating bubble's lang / source-lang / tone picker overlays —
 * pulled out of BubbleService.kt to keep that file focused on the
 * Service lifecycle + intent-routing surface.
 *
 * Each picker writes to the `flutter.tk_*` SharedPreferences keys
 * via writeXxx() so the Flutter side picks the change up via
 * notifyFlutterLangChanged() → MethodChannel "langChanged" →
 * languageSettingsProvider.reload() round-trip.
 */
internal fun BubbleService.showLangPicker(onPicked: ((String) -> Unit)? = null) {
    if (langPickerView != null) { hideLangPicker(); return }
    ensureWindowManager()
    // Sync from prefs so the picker reflects any change made in Flutter UI.
    currentTargetLang = readTargetLang()

    val style = BubbleStyle.of(this)
    val dp = style.dp
    val isDark = style.isDark
    val textCol = style.text
    val accent = style.accent
    val selBg = style.accent

    val backdrop = FrameLayout(this).apply {
        setBackgroundColor(Palette.BACKDROP_LIGHT)
        setOnClickListener { hideLangPicker() }
    }

    val card = LinearLayout(this).apply {
        orientation = LinearLayout.VERTICAL
        background = Glass.panel(dp, 18f, isDark)
        elevation = 22 * dp
        setPadding((14 * dp).toInt(), (14 * dp).toInt(), (14 * dp).toInt(), (14 * dp).toInt())
        isClickable = true
    }

    card.addView(TextView(this).apply {
        text = localized(R.string.bubble_panel_target_lang)
        setTextColor(accent)
        setTextSize(TypedValue.COMPLEX_UNIT_SP, 12f)
        typeface = Typeface.DEFAULT_BOLD
        setPadding(0, 0, 0, (10 * dp).toInt())
    })

    // Grid: 3 columns
    var row: LinearLayout? = null
    val effectiveTargetLangs = getEffectiveTargetLangs()
    val effectiveLabels = getEffectiveLangLabels()
    effectiveTargetLangs.forEachIndexed { idx, lang ->
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
            text = effectiveLabels[lang] ?: lang.uppercase()
            setTextColor(if (isSelected) Color.WHITE else textCol)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 11f)
            gravity = Gravity.CENTER
            setPadding((8 * dp).toInt(), (8 * dp).toInt(), (8 * dp).toInt(), (8 * dp).toInt())
            background = GradientDrawable().apply {
                setColor(if (isSelected) selBg else Color.TRANSPARENT)
                setStroke(1, if (isSelected) selBg else if (isDark) Glass.BORDER_DARK else Glass.BORDER_LIGHT)
                cornerRadius = 10 * dp
            }
            setOnClickListener {
                currentTargetLang = lang
                writeTargetLang(lang)
                hideLangPicker()
                updateLangChip()
                onPicked?.invoke(lang)
                // When called from the input picker (onPicked != null), don't
                // auto-translate — let the user press Translate manually.
                if (onPicked != null) return@setOnClickListener
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
    // Wrap the grid in a ScrollView so the picker still fits on screen
    // when we expand the language list past what one viewport can hold.
    // Cap to 70% of screen height — enough headroom for the 30-entry
    // grid without covering the source app entirely.
    val maxPickerHeight = (resources.displayMetrics.heightPixels * 0.7f).toInt()
    val scroll = android.widget.ScrollView(this).apply {
        isFillViewport = false
        addView(card, android.widget.FrameLayout.LayoutParams(
            android.widget.FrameLayout.LayoutParams.MATCH_PARENT,
            android.widget.FrameLayout.LayoutParams.WRAP_CONTENT,
        ))
    }
    backdrop.addView(scroll, FrameLayout.LayoutParams(cardWidth, maxPickerHeight, Gravity.CENTER))

    langPickerView = backdrop
    windowManager?.addView(backdrop, buildPickerLayoutParams())
}

internal fun BubbleService.hideLangPicker() {
    langPickerView?.let { try { windowManager?.removeView(it) } catch (_: Exception) {} }
    langPickerView = null
}

internal fun BubbleService.showSourceLangPicker(onPicked: ((String) -> Unit)? = null) {
    if (sourceLangPickerView != null) { hideSourceLangPicker(); return }
    ensureWindowManager()
    // Sync from prefs so the picker reflects any change made in Flutter UI.
    currentSourceLang = readSourceLang()
    val style = BubbleStyle.of(this)
    val dp = style.dp
    val isDark = style.isDark
    val textCol = style.text
    val accent = style.accent
    val selBg = style.accent

    val backdrop = FrameLayout(this).apply {
        setBackgroundColor(Palette.BACKDROP_LIGHT)
        setOnClickListener { hideSourceLangPicker() }
    }
    val card = LinearLayout(this).apply {
        orientation = LinearLayout.VERTICAL
        background = Glass.panel(dp, 18f, isDark)
        elevation = 22 * dp
        setPadding((14 * dp).toInt(), (14 * dp).toInt(), (14 * dp).toInt(), (14 * dp).toInt())
        isClickable = true
    }
    card.addView(TextView(this).apply {
        text = localized(R.string.bubble_panel_source_lang)
        setTextColor(accent)
        setTextSize(TypedValue.COMPLEX_UNIT_SP, 12f)
        typeface = Typeface.DEFAULT_BOLD
        setPadding(0, 0, 0, (10 * dp).toInt())
    })

    var row: LinearLayout? = null
    val effectiveSourceLangs = getEffectiveSourceLangs()
    val effectiveSourceLabels = getEffectiveLangLabels()
    effectiveSourceLangs.forEachIndexed { idx, lang ->
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
        val label = if (lang == "auto") "Auto" else (effectiveSourceLabels[lang] ?: lang.uppercase())
        val chip = TextView(this).apply {
            text = label
            setTextColor(if (isSelected) Color.WHITE else textCol)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 11f)
            gravity = Gravity.CENTER
            setPadding((8 * dp).toInt(), (8 * dp).toInt(), (8 * dp).toInt(), (8 * dp).toInt())
            background = GradientDrawable().apply {
                setColor(if (isSelected) selBg else Color.TRANSPARENT)
                setStroke(1, if (isSelected) selBg else if (isDark) Glass.BORDER_DARK else Glass.BORDER_LIGHT)
                cornerRadius = 10 * dp
            }
            setOnClickListener {
                currentSourceLang = lang
                writeSourceLang(lang)
                hideSourceLangPicker()
                updateLangChip()
                if (onPicked != null) {
                    // Caller (e.g. Lens overlay lang chip) handles the
                    // re-translate itself — don't fall into the bubble
                    // text-translate path.
                    onPicked(lang)
                } else {
                    currentSourceText?.let { src -> handleTranslateRequest(src, currentMode) }
                }
            }
            layoutParams = LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f)
                .apply { marginEnd = if (idx % 3 != 2) (6 * dp).toInt() else 0 }
        }
        row?.addView(chip)
    }

    val screenWidth = resources.displayMetrics.widthPixels
    val cardWidth = (screenWidth - (48 * dp).toInt()).coerceAtMost((360 * dp).toInt())
    val maxPickerHeight = (resources.displayMetrics.heightPixels * 0.7f).toInt()
    val scroll = android.widget.ScrollView(this).apply {
        isFillViewport = false
        addView(card, android.widget.FrameLayout.LayoutParams(
            android.widget.FrameLayout.LayoutParams.MATCH_PARENT,
            android.widget.FrameLayout.LayoutParams.WRAP_CONTENT,
        ))
    }
    backdrop.addView(scroll, FrameLayout.LayoutParams(cardWidth, maxPickerHeight, Gravity.CENTER))
    sourceLangPickerView = backdrop
    windowManager?.addView(backdrop, buildPickerLayoutParams())
}

internal fun BubbleService.hideSourceLangPicker() {
    sourceLangPickerView?.let { try { windowManager?.removeView(it) } catch (_: Exception) {} }
    sourceLangPickerView = null
}

internal fun BubbleService.showTonePicker() {
    showSettingsSheet()
}

internal fun BubbleService.hideTonePicker() {
    tonePickerView?.let { try { windowManager?.removeView(it) } catch (_: Exception) {} }
    tonePickerView = null
}
