package app.transkey.mobile

import android.content.Context
import android.view.Gravity
import android.view.View
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView

/**
 * Inline translation-history panel shown in place of the keyboard. Lists the
 * recent translations (newest first); tapping one commits its translation into
 * the field so the user can re-use a past result without opening the app.
 * Entries are (translation, sourceText) pairs the host fetches from Dart.
 */
class HistoryPanelView(context: Context) : LinearLayout(context) {

    var onPick: ((String) -> Unit)? = null
    var onClose: (() -> Unit)? = null
    // "Back to keyboard" label (host sets it localized; defaults to Gboard's "ABC").
    var backLabel: String = "ABC"

    private val d = resources.displayMetrics.density
    private fun dp(v: Int) = (v * d).toInt()

    private val panelBg = 0xFF1C1D21.toInt()
    private val barBg = 0xFF17181C.toInt()
    private val muted = 0xFF9AA0A6.toInt()
    private val rowText = 0xFFE2E2E9.toInt()

    init {
        orientation = VERTICAL
        setBackgroundColor(panelBg)
        isClickable = true
        isFocusable = true
    }

    fun setPanelHeight(px: Int) {
        layoutParams = LayoutParams(LayoutParams.MATCH_PARENT, px)
    }

    fun configure(title: String, emptyLabel: String, entries: List<Pair<String, String>>) {
        removeAllViews()
        addView(titleBar(title))

        if (entries.isEmpty()) {
            addView(TextView(context).apply {
                text = emptyLabel
                textSize = 14f
                gravity = Gravity.CENTER
                setTextColor(muted)
            }, LayoutParams(LayoutParams.MATCH_PARENT, 0, 1f))
        } else {
            val list = LinearLayout(context).apply { orientation = VERTICAL }
            for ((translation, source) in entries) list.addView(entryRow(translation, source))
            addView(
                ScrollView(context).apply { isFillViewport = true; addView(list) },
                LayoutParams(LayoutParams.MATCH_PARENT, 0, 1f),
            )
        }
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

    private fun entryRow(translation: String, source: String): View =
        LinearLayout(context).apply {
            orientation = VERTICAL
            isClickable = true
            setPadding(dp(16), dp(10), dp(16), dp(10))
            setOnClickListener { onPick?.invoke(translation) }
            addView(TextView(context).apply {
                text = translation
                textSize = 15f
                maxLines = 2
                ellipsize = android.text.TextUtils.TruncateAt.END
                setTextColor(rowText)
            })
            if (source.isNotEmpty()) {
                addView(TextView(context).apply {
                    text = source
                    textSize = 12f
                    maxLines = 1
                    ellipsize = android.text.TextUtils.TruncateAt.END
                    setTextColor(muted)
                    setPadding(0, dp(2), 0, 0)
                })
            }
            // Subtle divider.
            addView(View(context).apply { setBackgroundColor(0x14FFFFFF) },
                LayoutParams(LayoutParams.MATCH_PARENT, 1).apply { topMargin = dp(10) })
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
