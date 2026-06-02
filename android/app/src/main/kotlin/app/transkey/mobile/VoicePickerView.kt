package app.transkey.mobile

import android.content.Context
import android.graphics.drawable.GradientDrawable
import android.view.Gravity
import android.view.View
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView

/**
 * Voice-recognition language picker shown in place of the keyboard (opened by
 * long-pressing the strip mic). A single scrollable list of the supported
 * speech languages; the active one is highlighted. Tapping a language persists
 * it (host writes tk_voice_lang) so the next dictation recognises that language.
 */
class VoicePickerView(context: Context) : LinearLayout(context) {

    var onPick: ((String) -> Unit)? = null
    var onClose: (() -> Unit)? = null
    // "Back to keyboard" label (host sets it localized; defaults to the Gboard
    // convention). Shown on the close button at the bottom-left of the panel.
    var backLabel: String = "ABC"

    private val d = resources.displayMetrics.density
    private fun dp(v: Int) = (v * d).toInt()
    private fun dpf(v: Float) = v * d

    private val panelBg = 0xFF1C1D21.toInt()
    private val barBg = 0xFF17181C.toInt()
    private val muted = 0xFF9AA0A6.toInt()
    private val rowText = 0xFFE2E2E9.toInt()
    private val gradStart = 0xFF6366F1.toInt()
    private val gradEnd = 0xFFA855F7.toInt()

    init {
        orientation = VERTICAL
        setBackgroundColor(panelBg)
        isClickable = true
        isFocusable = true
    }

    fun setPanelHeight(px: Int) {
        layoutParams = LayoutParams(LayoutParams.MATCH_PARENT, px)
    }

    /** [langs] = (code, label); [current] = the selected code (highlighted). */
    fun configure(title: String, langs: List<Pair<String, String>>, current: String) {
        removeAllViews()
        addView(titleBar(title))
        val list = LinearLayout(context).apply { orientation = VERTICAL }
        for ((code, label) in langs) list.addView(langRow(code, label, code == current))
        addView(
            ScrollView(context).apply { isFillViewport = true; addView(list) },
            LayoutParams(LayoutParams.MATCH_PARENT, 0, 1f),
        )
        addView(bottomBar())
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

    private fun langRow(code: String, label: String, selected: Boolean): View =
        TextView(context).apply {
            text = if (selected) "$label  ✓" else label
            textSize = 15f
            // Keep every row left-aligned like Gboard. START/VIEW_START resolve
            // against the view's layoutDirection, which an RTL name (العربية)
            // flips to RTL -> the label floats to the right edge. Pin the row to a
            // full-width, LTR, ABSOLUTE-left box so the Arabic name hugs the left
            // with all the others (its glyphs still shape RTL internally).
            layoutParams = LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.WRAP_CONTENT)
            layoutDirection = View.LAYOUT_DIRECTION_LTR
            textDirection = View.TEXT_DIRECTION_LTR
            gravity = Gravity.CENTER_VERTICAL or Gravity.LEFT
            isClickable = true
            setPadding(dp(16), dp(12), dp(16), dp(12))
            if (selected) {
                setTextColor(0xFFFFFFFF.toInt())
                setTypeface(typeface, android.graphics.Typeface.BOLD)
                background = GradientDrawable(
                    GradientDrawable.Orientation.TL_BR, intArrayOf(gradStart, gradEnd),
                ).apply { cornerRadius = dpf(12f) }
            } else {
                setTextColor(rowText)
            }
            setOnClickListener { onPick?.invoke(code) }
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
}
