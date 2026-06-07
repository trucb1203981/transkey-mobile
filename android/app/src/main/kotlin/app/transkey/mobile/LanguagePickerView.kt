package app.transkey.mobile

import android.content.Context
import android.view.Gravity
import android.view.View
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView

/**
 * Keyboard language picker shown in place of the keyboard (same slot as the
 * emoji panel). Two scrollable columns - source (with "Auto" on top) and
 * target - let the user set translate from/to without opening the app. The
 * host (TransKeyIME) owns the prefs; this view only reports taps via callbacks
 * and reflects the current selection that the host pushes back via
 * [setSelection].
 */
class LanguagePickerView(context: Context) : LinearLayout(context) {

    var onSourcePick: ((String) -> Unit)? = null
    var onTargetPick: ((String) -> Unit)? = null
    var onSwap: (() -> Unit)? = null
    var onClose: (() -> Unit)? = null
    // "Back to keyboard" label (host sets it localized; defaults to Gboard's "ABC").
    var backLabel: String = "ABC"

    private val d = resources.displayMetrics.density
    private fun dp(v: Int) = (v * d).toInt()

    private val panelBg = 0xFF1C1D21.toInt()
    private val barBg = 0xFF17181C.toInt()
    private val headerText = 0xFF9AA0A6.toInt()
    private val rowText = 0xFFE2E2E9.toInt()
    private val selText = 0xFF8AB4F8.toInt()
    private val selBg = 0x308AB4F8

    private val srcColumn = LinearLayout(context).apply { orientation = VERTICAL }
    private val tgtColumn = LinearLayout(context).apply { orientation = VERTICAL }
    private val srcRows = HashMap<String, TextView>()
    private val tgtRows = HashMap<String, TextView>()

    private var curSource = "auto"
    private var curTarget = "en"

    init {
        orientation = VERTICAL
        setBackgroundColor(panelBg)
    }

    /** Force the panel to the keyboard's pixel height so the IME doesn't resize. */
    fun setPanelHeight(px: Int) {
        layoutParams = LayoutParams(LayoutParams.MATCH_PARENT, px)
    }

    /**
     * Build the two columns. [sources]/[targets] are (code, nativeLabel) pairs.
     * Safe to call once; the host rebuilds a fresh view each show.
     */
    fun configure(
        sources: List<Pair<String, String>>,
        targets: List<Pair<String, String>>,
        source: String,
        target: String,
        fromLabel: String,
        toLabel: String,
        swapLabel: String,
    ) {
        curSource = source
        curTarget = target
        removeAllViews()
        srcRows.clear()
        tgtRows.clear()
        srcColumn.removeAllViews()
        tgtColumn.removeAllViews()

        addView(buildHeader(fromLabel, toLabel))
        addView(buildBody(sources, targets), LayoutParams(LayoutParams.MATCH_PARENT, 0, 1f))
        addView(buildBottomBar(swapLabel))
        applyHighlight()
    }

    /** Host pushes the current selection back (e.g. after a swap). */
    fun setSelection(source: String, target: String) {
        curSource = source
        curTarget = target
        applyHighlight()
    }

    private fun buildHeader(fromLabel: String, toLabel: String): View =
        LinearLayout(context).apply {
            orientation = HORIZONTAL
            setBackgroundColor(barBg)
            addView(columnHeader(fromLabel), LayoutParams(0, dp(34), 1f))
            addView(columnHeader(toLabel), LayoutParams(0, dp(34), 1f))
        }

    private fun columnHeader(label: String): TextView =
        TextView(context).apply {
            text = label
            textSize = 12f
            gravity = Gravity.CENTER
            setTextColor(headerText)
            isAllCaps = true
        }

    private fun buildBody(
        sources: List<Pair<String, String>>,
        targets: List<Pair<String, String>>,
    ): View {
        for ((code, label) in sources) srcColumn.addView(langRow(code, label, isSource = true))
        for ((code, label) in targets) tgtColumn.addView(langRow(code, label, isSource = false))

        val srcScroll = ScrollView(context).apply { isFillViewport = true; addView(srcColumn) }
        val tgtScroll = ScrollView(context).apply { isFillViewport = true; addView(tgtColumn) }

        return LinearLayout(context).apply {
            orientation = HORIZONTAL
            addView(srcScroll, LayoutParams(0, LayoutParams.MATCH_PARENT, 1f))
            addView(View(context).apply { setBackgroundColor(0x1AFFFFFF) },
                LayoutParams(dp(1), LayoutParams.MATCH_PARENT))
            addView(tgtScroll, LayoutParams(0, LayoutParams.MATCH_PARENT, 1f))
        }
    }

    private fun langRow(code: String, label: String, isSource: Boolean): TextView {
        val tv = TextView(context).apply {
            text = label
            textSize = 16f
            // Keep every row absolute-left like Gboard. START gravity resolves
            // against layoutDirection, which an RTL name (العربية / اردو) flips
            // to RTL so the label floats to the right edge, out of line with the
            // others. Pin to a full-width, LTR, ABSOLUTE-left box so RTL names
            // hug the left too (glyphs still shape RTL internally). Mirrors the
            // same fix in VoicePickerView.langRow.
            layoutParams = LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.WRAP_CONTENT)
            layoutDirection = View.LAYOUT_DIRECTION_LTR
            textDirection = View.TEXT_DIRECTION_LTR
            gravity = Gravity.CENTER_VERTICAL or Gravity.LEFT
            setPadding(dp(18), dp(11), dp(18), dp(11))
            setTextColor(rowText)
            isClickable = true
            setOnClickListener {
                if (isSource) onSourcePick?.invoke(code) else onTargetPick?.invoke(code)
            }
        }
        if (isSource) srcRows[code] = tv else tgtRows[code] = tv
        return tv
    }

    private fun buildBottomBar(swapLabel: String): View =
        LinearLayout(context).apply {
            orientation = HORIZONTAL
            setBackgroundColor(barBg)
            gravity = Gravity.CENTER_VERTICAL
            addView(
                barButton(backLabel) { onClose?.invoke() }.apply { setPadding(dp(16), 0, dp(16), 0) },
                LayoutParams(LayoutParams.WRAP_CONTENT, dp(46)),
            )
            addView(View(context), LayoutParams(0, dp(46), 1f)) // spacer
            addView(barButton("⇄  $swapLabel") { onSwap?.invoke() }, barLp(140))
        }

    private fun barButton(label: String, onClick: () -> Unit): TextView =
        TextView(context).apply {
            text = label
            textSize = 14f
            gravity = Gravity.CENTER
            setTextColor(0xFFC4C7CE.toInt())
            isClickable = true
            setOnClickListener { onClick() }
        }

    private fun barLp(widthDp: Int) = LayoutParams(dp(widthDp), dp(46))

    /** Repaint the selected row in each column (text colour + bold + bg tint). */
    private fun applyHighlight() {
        for ((code, tv) in srcRows) styleRow(tv, code == curSource)
        for ((code, tv) in tgtRows) styleRow(tv, code == curTarget)
    }

    private fun styleRow(tv: TextView, selected: Boolean) {
        tv.setTextColor(if (selected) selText else rowText)
        tv.setTypeface(null, if (selected) android.graphics.Typeface.BOLD else android.graphics.Typeface.NORMAL)
        tv.setBackgroundColor(if (selected) selBg else 0x00000000)
    }
}
