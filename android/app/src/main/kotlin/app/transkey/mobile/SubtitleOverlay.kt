package app.transkey.mobile

import android.content.Context
import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.text.TextUtils
import android.util.TypedValue
import android.view.Gravity
import android.view.View
import android.view.WindowManager
import android.widget.TextView

/**
 * Floating bar at the bottom of the screen that shows the translated
 * subtitle for the live video-subtitle mode.
 *
 * Drawn with [WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE] so every touch
 * falls through to the video app underneath — the user keeps full control
 * of playback while our translation floats on top.
 *
 * Critical for the no-feedback-loop design: this bar sits BELOW the OCR
 * band (see [ScreenCaptureService] OCR_BAND_*), so the next captured frame
 * never re-reads our own translated text. Keep this bar's top edge under
 * the OCR band's bottom edge.
 */
class SubtitleOverlay(private val context: Context) {

    private val wm = context.getSystemService(Context.WINDOW_SERVICE) as WindowManager
    private var view: TextView? = null

    fun show() {
        if (view != null) return
        val screenW = context.resources.displayMetrics.widthPixels
        val tv = TextView(context).apply {
            setTextColor(Color.WHITE)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 20f)
            gravity = Gravity.CENTER
            typeface = Typeface.DEFAULT_BOLD
            // Rounded semi-opaque pill so subtitles stay legible over any video.
            background = GradientDrawable().apply {
                setColor(Color.parseColor("#CC000000"))
                cornerRadius = dp(14).toFloat()
            }
            val padH = dp(18)
            val padV = dp(10)
            setPadding(padH, padV, padH, padV)
            // Shadow keeps light text readable over bright frames.
            setShadowLayer(dp(3).toFloat(), 0f, dp(1).toFloat(), Color.BLACK)
            // Constrain width so long lines wrap instead of touching the edges.
            maxWidth = (screenW * 0.92f).toInt()
            maxLines = 3
            ellipsize = TextUtils.TruncateAt.END
            visibility = View.GONE
        }
        view = tv

        val params = WindowManager.LayoutParams(
            WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.WRAP_CONTENT,
            overlayType(),
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE or
                WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
            PixelFormat.TRANSLUCENT,
        ).apply {
            gravity = Gravity.BOTTOM or Gravity.CENTER_HORIZONTAL
            // Lift the bar above the gesture/nav area so it isn't cut off.
            y = dp(72)
        }
        try {
            wm.addView(tv, params)
        } catch (_: Exception) {
            view = null
        }
    }

    /** Show a translated (or status) line. Empty/blank hides the bar. */
    fun setText(text: String?) {
        val tv = view ?: return
        if (text.isNullOrBlank()) {
            tv.visibility = View.GONE
        } else {
            tv.text = text
            tv.visibility = View.VISIBLE
        }
    }

    fun clearText() {
        view?.visibility = View.GONE
    }

    fun hide() {
        view?.let { v -> try { wm.removeView(v) } catch (_: Exception) {} }
        view = null
    }

    private fun overlayType(): Int =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        } else {
            @Suppress("DEPRECATION")
            WindowManager.LayoutParams.TYPE_PHONE
        }

    private fun dp(value: Int): Int =
        (value * context.resources.displayMetrics.density).toInt()
}
