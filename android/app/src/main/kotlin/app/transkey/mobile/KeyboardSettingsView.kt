package app.transkey.mobile

import android.content.Context
import android.graphics.drawable.GradientDrawable
import android.view.Gravity
import android.view.View
import android.widget.HorizontalScrollView
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView

/**
 * Keyboard settings panel shown in place of the keyboard (same slot as the
 * emoji / language panels), opened from the strip's grid icon. Surfaces the
 * keyboard-relevant settings + shortcuts so the user rarely opens the app:
 *   - autocorrect toggle / key vibration toggle (IME-local prefs)
 *   - app UI language picker (flutter.tk_ui_locale)
 *   - translate tone (flutter.tk_tone_override)
 *   - shortcut row: translation history (inline) / explain / full settings
 *
 * The host (TransKeyIME) owns the prefs and routing; this view only reports taps.
 */
class KeyboardSettingsView(context: Context) : LinearLayout(context) {

    var onAutocorrectChange: ((Boolean) -> Unit)? = null
    var onHapticChange: ((Boolean) -> Unit)? = null
    var onAutocapChange: ((Boolean) -> Unit)? = null
    var onDoubleSpaceChange: ((Boolean) -> Unit)? = null
    var onAppLangPick: ((String) -> Unit)? = null
    var onTonePick: ((String) -> Unit)? = null
    var onBubble: (() -> Unit)? = null
    var onHistory: (() -> Unit)? = null
    var onExplain: (() -> Unit)? = null
    var onOpenApp: (() -> Unit)? = null
    var onClose: (() -> Unit)? = null
    // "Back to keyboard" label (host sets it localized; defaults to Gboard's "ABC").
    var backLabel: String = "ABC"

    private val d = resources.displayMetrics.density
    private fun dp(v: Int) = (v * d).toInt()
    private fun dpf(v: Float) = v * d

    private val panelBg = 0xFF1C1D21.toInt()
    private val barBg = 0xFF17181C.toInt()
    private val muted = 0xFF9AA0A6.toInt()
    private val rowText = 0xFFE2E2E9.toInt()
    // Brand gradient shared with the home feature buttons + the strip's
    // Dịch / Trau chuốt chips (#6366F1 -> #A855F7, diagonal).
    private val gradStart = 0xFF6366F1.toInt()
    private val gradEnd = 0xFFA855F7.toInt()

    private val appLangPills = HashMap<String, TextView>()
    private val tonePills = HashMap<String, TextView>()
    private var curAppLang = "en"
    private var curTone = ""
    private var scroll: ScrollView? = null

    init {
        orientation = VERTICAL
        setBackgroundColor(panelBg)
        // Consume taps on empty areas so they don't fall through to the
        // keyboard sitting behind this panel.
        isClickable = true
        isFocusable = true
    }

    fun setPanelHeight(px: Int) {
        layoutParams = LayoutParams(LayoutParams.MATCH_PARENT, px)
    }

    fun configure(
        title: String,
        featuresLabel: String, optionsLabel: String,
        autocorrectLabel: String, autocorrect: Boolean,
        hapticLabel: String, haptic: Boolean,
        autocapLabel: String, autocap: Boolean,
        doubleSpaceLabel: String, doubleSpace: Boolean,
        appLangSectionLabel: String, appLangs: List<Pair<String, String>>, appLangCode: String,
        toneSectionLabel: String, tones: List<Pair<String, String>>, toneCode: String,
        bubbleLabel: String, bubbleOn: Boolean,
        historyLabel: String, explainLabel: String, openAppLabel: String,
        onText: String, offText: String,
    ) {
        // Preserve scroll across a re-configure (e.g. live re-localize after
        // an app-language change) so the panel doesn't jump back to the top.
        val savedScrollY = scroll?.scrollY ?: 0
        curAppLang = appLangCode
        curTone = toneCode
        removeAllViews()
        appLangPills.clear()
        tonePills.clear()

        addView(titleBar(title))

        val content = LinearLayout(context).apply {
            orientation = VERTICAL
            setPadding(dp(16), dp(4), dp(16), dp(4))
        }
        // Group 1 - FEATURES (things you do now): solid gradient tiles under a
        // "Features" header so they read as actions, distinct from settings.
        content.addView(sectionLabel(featuresLabel))
        content.addView(
            featureRow(
                listOf(
                    Triple(explainLabel, true) { onExplain?.invoke() },
                    Triple(historyLabel, true) { onHistory?.invoke() },
                    // Bubble is a toggle: gradient when ON, muted when OFF (like home).
                    Triple(bubbleLabel, bubbleOn) { onBubble?.invoke() },
                ),
            ),
        )
        // Group 2 - OPTIONS (things you configure): toggles + pickers, then a
        // subtle outlined link to the full in-app settings (NOT a gradient tile,
        // so it doesn't look like a feature).
        content.addView(sectionLabel(optionsLabel))
        content.addView(toggleRow(autocorrectLabel, autocorrect, onText, offText) { onAutocorrectChange?.invoke(it) })
        content.addView(toggleRow(hapticLabel, haptic, onText, offText) { onHapticChange?.invoke(it) })
        content.addView(toggleRow(autocapLabel, autocap, onText, offText) { onAutocapChange?.invoke(it) })
        content.addView(toggleRow(doubleSpaceLabel, doubleSpace, onText, offText) { onDoubleSpaceChange?.invoke(it) })
        content.addView(sectionLabel(appLangSectionLabel))
        content.addView(pickerRow(appLangs, appLangPills) { code ->
            curAppLang = code; styleAppLangs(); onAppLangPick?.invoke(code)
        })
        content.addView(sectionLabel(toneSectionLabel))
        content.addView(pickerRow(tones, tonePills) { code ->
            curTone = code; styleTones(); onTonePick?.invoke(code)
        })
        content.addView(settingsLink(openAppLabel) { onOpenApp?.invoke() })

        val s = ScrollView(context).apply { isFillViewport = true; addView(content) }
        scroll = s
        addView(s, LayoutParams(LayoutParams.MATCH_PARENT, 0, 1f))
        addView(bottomBar())
        styleAppLangs()
        styleTones()
        if (savedScrollY > 0) s.post { s.scrollTo(0, savedScrollY) }
    }

    private fun titleBar(title: String): View =
        TextView(context).apply {
            text = title
            textSize = 14f
            setTextColor(rowText)
            setTypeface(typeface, android.graphics.Typeface.BOLD)
            setBackgroundColor(barBg)
            gravity = Gravity.CENTER_VERTICAL
            setPadding(dp(16), dp(10), dp(16), dp(10))
        }

    private fun sectionLabel(text: String): View =
        TextView(context).apply {
            this.text = text
            textSize = 11f
            isAllCaps = true
            letterSpacing = 0.06f
            setTextColor(muted)
            setPadding(0, dp(12), 0, dp(7))
        }

    /** A label + an on/off pill that toggles on tap. */
    private fun toggleRow(
        label: String, initial: Boolean, onText: String, offText: String,
        onChange: (Boolean) -> Unit,
    ): View {
        var state = initial
        val pill = TextView(context).apply {
            textSize = 12f
            gravity = Gravity.CENTER
            setPadding(dp(16), dp(7), dp(16), dp(7))
            isClickable = true
        }
        fun render() {
            pill.text = if (state) onText else offText
            pill.setTextColor(if (state) 0xFFFFFFFF.toInt() else muted)
            pill.background = if (state) gradientBg(18f) else pillBg(0x22FFFFFF)
        }
        render()
        pill.setOnClickListener { state = !state; render(); onChange(state) }

        return LinearLayout(context).apply {
            orientation = HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(0, dp(7), 0, dp(7))
            addView(TextView(context).apply {
                text = label
                textSize = 15f
                setTextColor(rowText)
            }, LayoutParams(0, LayoutParams.WRAP_CONTENT, 1f))
            addView(pill)
        }
    }

    /** Horizontal scrollable row of selectable pills (app language / tone). */
    private fun pickerRow(
        items: List<Pair<String, String>>,
        pillMap: HashMap<String, TextView>,
        onPick: (String) -> Unit,
    ): View {
        val row = LinearLayout(context).apply { orientation = HORIZONTAL }
        for ((code, label) in items) {
            val pill = TextView(context).apply {
                text = label
                textSize = 13f
                gravity = Gravity.CENTER
                setPadding(dp(14), dp(8), dp(14), dp(8))
                isClickable = true
                setOnClickListener { onPick(code) }
            }
            pillMap[code] = pill
            val lp = LayoutParams(LayoutParams.WRAP_CONTENT, LayoutParams.WRAP_CONTENT)
            lp.rightMargin = dp(8)
            row.addView(pill, lp)
        }
        return HorizontalScrollView(context).apply {
            isHorizontalScrollBarEnabled = false
            addView(row)
        }
    }

    private fun styleAppLangs() = stylePills(appLangPills, curAppLang)
    private fun styleTones() = stylePills(tonePills, curTone)

    private fun stylePills(pills: HashMap<String, TextView>, current: String) {
        for ((code, tv) in pills) {
            val sel = code == current
            tv.setTextColor(if (sel) 0xFFFFFFFF.toInt() else muted)
            tv.background = if (sel) gradientBg(18f) else pillBg(0x18FFFFFF)
        }
    }

    /**
     * One row of equal-width feature tiles (explain / history / bubble). A tile
     * is brand-gradient when [active] (an action, or a toggle that's ON) and a
     * muted translucent chip when off - matching the home header's quick toggles
     * (the bubble tile flips gradient<->muted with the bubble on/off state).
     */
    private fun featureRow(items: List<Triple<String, Boolean, () -> Unit>>): View {
        val row = LinearLayout(context).apply {
            orientation = HORIZONTAL
            val lp = LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.WRAP_CONTENT)
            lp.topMargin = dp(4)
            layoutParams = lp
        }
        items.forEachIndexed { i, (label, active, onClick) ->
            row.addView(featureTile(label, active, onClick), tileLp(if (i == 0) 0 else dp(8)))
        }
        return row
    }

    private fun tileLp(leftMargin: Int) =
        LayoutParams(0, LayoutParams.WRAP_CONTENT, 1f).apply { this.leftMargin = leftMargin }

    private fun featureTile(label: String, active: Boolean, onClick: () -> Unit): TextView =
        TextView(context).apply {
            text = label
            textSize = 14f
            gravity = Gravity.CENTER
            maxLines = 2
            setTypeface(typeface, android.graphics.Typeface.BOLD)
            setPadding(dp(6), dp(14), dp(6), dp(14))
            isClickable = true
            if (active) {
                setTextColor(0xFFFFFFFF.toInt())
                background = gradientBg()
            } else {
                setTextColor(muted)
                background = pillBg(0x18FFFFFF)
            }
            setOnClickListener { onClick() }
        }

    /**
     * Full-width subtle outlined link to the in-app settings screen. Deliberately
     * NOT a gradient tile - an outline + tinted text reads as "settings", not a
     * feature you trigger from here.
     */
    private fun settingsLink(label: String, onClick: () -> Unit): View {
        val btn = TextView(context).apply {
            text = label
            textSize = 14f
            gravity = Gravity.CENTER
            setTextColor(0xFFBFC0FF.toInt())
            setPadding(dp(12), dp(13), dp(12), dp(13))
            isClickable = true
            background = GradientDrawable().apply {
                setColor(0x12FFFFFF)
                setStroke(dp(1), 0x55A855F7.toInt())
                cornerRadius = dpf(14f)
            }
            setOnClickListener { onClick() }
        }
        return LinearLayout(context).apply {
            orientation = VERTICAL
            val lp = LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.WRAP_CONTENT)
            lp.topMargin = dp(14)
            layoutParams = lp
            addView(btn, LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.WRAP_CONTENT))
        }
    }

    private fun bottomBar(): View =
        LinearLayout(context).apply {
            orientation = HORIZONTAL
            setBackgroundColor(barBg)
            gravity = Gravity.CENTER_VERTICAL
            addView(TextView(context).apply {
                text = backLabel
                textSize = 14f
                gravity = Gravity.CENTER
                setTextColor(0xFFC4C7CE.toInt())
                setPadding(dp(16), 0, dp(16), 0)
                isClickable = true
                setOnClickListener { onClose?.invoke() }
            }, LayoutParams(LayoutParams.WRAP_CONTENT, dp(46)))
        }

    private fun pillBg(color: Int): GradientDrawable =
        GradientDrawable().apply { setColor(color); cornerRadius = dpf(18f) }

    /** Brand diagonal gradient (top-left -> bottom-right) for tiles + selected pills. */
    private fun gradientBg(corner: Float = 14f): GradientDrawable =
        GradientDrawable(
            GradientDrawable.Orientation.TL_BR,
            intArrayOf(gradStart, gradEnd),
        ).apply { cornerRadius = dpf(corner) }
}
