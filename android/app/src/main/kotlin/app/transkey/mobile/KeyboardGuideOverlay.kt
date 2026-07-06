package app.transkey.mobile

import android.content.Context
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.view.Gravity
import android.view.View
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView

/**
 * First-run guide shown once over the keyboard, explaining the action chips
 * (Dịch / Trả lời / Trau chuốt). Same one-time overlay as the iOS keyboard's
 * first-run guide - the two platforms stay in parity. Built as an inline panel
 * (title, scrollable feature rows, a "Got it" button) in the same visual style
 * as [HistoryPanelView] / [ClipboardReadPanel] so it reads as one keyboard
 * surface; tapping "Got it" (or switching field) dismisses it.
 *
 * Rows are passed in pre-localized and pre-filtered to the chips the user
 * actually sees, so a free user is never shown a paid-only chip.
 */
class KeyboardGuideOverlay(context: Context) : LinearLayout(context) {

    var onDismiss: (() -> Unit)? = null

    private val d = resources.displayMetrics.density
    private fun dp(v: Int) = (v * d).toInt()

    private val panelBg = 0xFF1C1D21.toInt()
    private val titleColor = 0xFFFFFFFF.toInt()
    private val accent = 0xFF8B8DF5.toInt()
    private val muted = 0xFF9AA0A6.toInt()

    init {
        orientation = VERTICAL
        setBackgroundColor(panelBg)
        isClickable = true
        isFocusable = true
        setPadding(dp(20), dp(16), dp(20), dp(14))
    }

    fun setPanelHeight(px: Int) {
        layoutParams = LayoutParams(LayoutParams.MATCH_PARENT, px)
    }

    /** rows = (chip label, what-the-user-does description), already localized. */
    fun configure(title: String, rows: List<Pair<String, String>>, dismissLabel: String) {
        removeAllViews()

        addView(TextView(context).apply {
            text = title
            textSize = 17f
            setTextColor(titleColor)
            setTypeface(typeface, Typeface.BOLD)
            setPadding(0, 0, 0, dp(10))
        })

        val list = LinearLayout(context).apply { orientation = VERTICAL }
        for ((label, desc) in rows) list.addView(featureRow(label, desc))
        addView(
            ScrollView(context).apply { isFillViewport = true; addView(list) },
            LayoutParams(LayoutParams.MATCH_PARENT, 0, 1f),
        )

        addView(dismissButton(dismissLabel))
    }

    private fun featureRow(label: String, desc: String): View =
        LinearLayout(context).apply {
            orientation = VERTICAL
            setPadding(0, dp(8), 0, dp(8))
            addView(TextView(context).apply {
                text = label
                textSize = 15f
                setTextColor(accent)
                setTypeface(typeface, Typeface.BOLD)
            })
            addView(TextView(context).apply {
                text = desc
                textSize = 13f
                setTextColor(muted)
                setPadding(0, dp(3), 0, 0)
            })
        }

    private fun dismissButton(label: String): View =
        TextView(context).apply {
            text = label
            textSize = 15f
            setTextColor(0xFFFFFFFF.toInt())
            gravity = Gravity.CENTER
            setTypeface(typeface, Typeface.BOLD)
            // Brand gradient, same #6366F1 -> #A855F7 as the action chips.
            background = GradientDrawable(
                GradientDrawable.Orientation.LEFT_RIGHT,
                intArrayOf(0xFF6366F1.toInt(), 0xFFA855F7.toInt()),
            ).apply { cornerRadius = dp(12).toFloat() }
            setPadding(dp(16), dp(12), dp(16), dp(12))
            isClickable = true
            setOnClickListener { onDismiss?.invoke() }
            layoutParams = LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.WRAP_CONTENT)
                .apply { topMargin = dp(14) }
        }
}
