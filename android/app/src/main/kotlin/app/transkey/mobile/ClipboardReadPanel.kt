package app.transkey.mobile

import android.content.Context
import android.view.Gravity
import android.view.View
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView

/**
 * Read-only panel shown in place of the keyboard after the "Dịch" chip
 * translates the clipboard. Ported from the iOS keyboard's clipboard reading
 * panel (KeyboardViewController.showClipboardPanel): a title bar, the
 * translated text in a scrollable, selectable area, and a back-to-keyboard
 * bar. It NEVER edits the field - it is purely for reading the incoming
 * message the user copied, so no undo is armed.
 *
 * Visual style matches [HistoryPanelView] so the two inline panels read as
 * one keyboard surface.
 */
class ClipboardReadPanel(context: Context) : LinearLayout(context) {

    var onClose: (() -> Unit)? = null
    // Copy the translated result to the clipboard (host writes the clip + toast).
    var onCopy: (() -> Unit)? = null
    // "Back to keyboard" label (host sets it localized; defaults to Gboard's "ABC").
    var backLabel: String = "ABC"
    // "Copy" label for the result-copy button (host sets it localized).
    var copyLabel: String = "Copy"

    private val d = resources.displayMetrics.density
    private fun dp(v: Int) = (v * d).toInt()

    private val panelBg = 0xFF1C1D21.toInt()
    private val barBg = 0xFF17181C.toInt()
    private val bodyText = 0xFFE2E2E9.toInt()
    private val scamRed = 0xFFFF6B6B.toInt()
    private val scamAmber = 0xFFF59E0B.toInt()
    private val scamDetailText = 0xFFB6B8C0.toInt()

    init {
        orientation = VERTICAL
        setBackgroundColor(panelBg)
        isClickable = true
        isFocusable = true
    }

    fun setPanelHeight(px: Int) {
        layoutParams = LayoutParams(LayoutParams.MATCH_PARENT, px)
    }

    /**
     * [scamTitle]/[scamDetail] populate a fraud-warning banner above the
     * translated text when the server flagged the copied message; null = safe.
     * [scamHigh] picks red (high) vs amber (softer caution).
     */
    fun configure(
        title: String,
        body: String,
        scamTitle: String? = null,
        scamDetail: String? = null,
        scamHigh: Boolean = false,
    ) {
        removeAllViews()
        addView(titleBar(title))
        if (scamTitle != null) addView(scamBanner(scamTitle, scamDetail, scamHigh))
        val text = TextView(context).apply {
            text = body
            textSize = 16f
            setTextColor(bodyText)
            setTextIsSelectable(true)
            setLineSpacing(dp(2).toFloat(), 1f)
            setPadding(dp(16), dp(12), dp(16), dp(12))
        }
        addView(
            ScrollView(context).apply { isFillViewport = true; addView(text) },
            LayoutParams(LayoutParams.MATCH_PARENT, 0, 1f),
        )
        addView(bottomBar())
    }

    private fun scamBanner(title: String, detail: String?, high: Boolean): View {
        val accent = if (high) scamRed else scamAmber
        return LinearLayout(context).apply {
            orientation = VERTICAL
            // ~12% alpha tint of the accent behind the banner.
            setBackgroundColor((0x1F shl 24) or (accent and 0x00FFFFFF))
            setPadding(dp(16), dp(10), dp(16), dp(10))
            val lp = LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.WRAP_CONTENT)
            lp.setMargins(dp(10), dp(8), dp(10), 0)
            layoutParams = lp
            addView(TextView(context).apply {
                text = "🛡 $title" // shield emoji + title
                textSize = 13.5f
                setTextColor(accent)
                setTypeface(typeface, android.graphics.Typeface.BOLD)
                setLineSpacing(dp(1).toFloat(), 1f)
            })
            if (!detail.isNullOrBlank()) {
                addView(TextView(context).apply {
                    text = detail
                    textSize = 12.5f
                    setTextColor(scamDetailText)
                    setPadding(0, dp(2), 0, 0)
                    setLineSpacing(dp(1).toFloat(), 1f)
                })
            }
        }
    }

    private fun titleBar(title: String): View =
        TextView(context).apply {
            text = title
            textSize = 14f
            setTextColor(bodyText)
            setTypeface(typeface, android.graphics.Typeface.BOLD)
            setBackgroundColor(barBg)
            gravity = Gravity.CENTER_VERTICAL
            setPadding(dp(16), dp(10), dp(16), dp(10))
        }

    private fun bottomBar(): View =
        LinearLayout(context).apply {
            orientation = HORIZONTAL
            setBackgroundColor(barBg)
            gravity = Gravity.CENTER_VERTICAL
            // "Back to keyboard" on the left.
            addView(TextView(context).apply {
                text = backLabel
                textSize = 14f
                gravity = Gravity.CENTER
                setTextColor(0xFFC4C7CE.toInt())
                setPadding(dp(16), 0, dp(16), 0)
                isClickable = true
                setOnClickListener { onClose?.invoke() }
            }, LayoutParams(LayoutParams.WRAP_CONTENT, dp(46)))
            // Spacer pushes Copy to the right edge.
            addView(View(context), LayoutParams(0, dp(46), 1f))
            // "Copy" the translation to the clipboard, on the right (brand accent
            // so it reads as the primary action of this read-only panel).
            addView(TextView(context).apply {
                text = copyLabel
                textSize = 14f
                gravity = Gravity.CENTER
                setTextColor(0xFFA78BFA.toInt())
                setTypeface(typeface, android.graphics.Typeface.BOLD)
                setPadding(dp(16), 0, dp(16), 0)
                isClickable = true
                setOnClickListener { onCopy?.invoke() }
            }, LayoutParams(LayoutParams.WRAP_CONTENT, dp(46)))
        }
}
