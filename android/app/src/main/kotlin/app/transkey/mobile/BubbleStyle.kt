package app.transkey.mobile

import android.content.Context
import android.content.res.Configuration
import android.graphics.Color

/**
 * Shared visual tokens for the floating-bubble overlays. Previously these
 * five theme values + the `isDark` check were inlined at the top of every
 * `show*Picker()` / `showResultPanel()` method in BubbleService — same five
 * `Color.parseColor("#…")` calls duplicated 9-13 times, with the occasional
 * subtle drift (e.g. one picker used "#1E1E30" while another used "#1F1F32").
 *
 * Build once per UI presentation via [of] and pass the resulting object
 * down. The named constants in [Palette] cover state / accent / backdrop
 * shades that are NOT theme-dependent — kept here so a future restyle has
 * one file to touch instead of grepping 60+ hex literals.
 */
data class BubbleStyle(
    val isDark: Boolean,
    val dp:      Float,
    val bg:      Int,
    val text:    Int,
    val muted:   Int,
    val accent:  Int,
) {
    companion object {
        fun of(context: Context): BubbleStyle {
            val isDark = (context.resources.configuration.uiMode and
                Configuration.UI_MODE_NIGHT_MASK) == Configuration.UI_MODE_NIGHT_YES
            return BubbleStyle(
                isDark = isDark,
                dp     = context.resources.displayMetrics.density,
                bg     = if (isDark) Palette.SURFACE_DARK    else Color.WHITE,
                text   = if (isDark) Palette.TEXT_DARK_FG    else Palette.TEXT_LIGHT_FG,
                muted  = if (isDark) Palette.MUTED_DARK_FG   else Palette.MUTED_LIGHT_FG,
                accent = Palette.ACCENT,
            )
        }
    }
}

/**
 * Theme-independent colors used across bubble overlays.
 * Keep the four "STATE" colors in sync with the in-app `app_theme.dart`
 * palette so the bubble visually matches the rest of the app.
 */
object Palette {
    // Theme surfaces
    const val SURFACE_DARK   = 0xFF1E1E30.toInt()
    const val TEXT_DARK_FG   = 0xFFE8E8F0.toInt()
    const val TEXT_LIGHT_FG  = 0xFF1A1A2E.toInt()
    const val MUTED_DARK_FG  = 0xFF9090A0.toInt()
    const val MUTED_LIGHT_FG = 0xFF6B6B7A.toInt()

    // Brand
    const val ACCENT         = 0xFF6C63FF.toInt()  // bubble idle stroke + buttons

    // State (loading / success / error)
    const val STATE_LOADING  = 0xFF43E97B.toInt()  // green pulse
    const val STATE_SUCCESS  = 0xFF16A34A.toInt()  // saved-history toast
    const val STATE_ERROR    = 0xFFFF6B6B.toInt()  // red error stroke

    // Backdrops for picker modals
    const val BACKDROP_DIM   = 0x66000000.toInt()  // standard picker scrim
    const val BACKDROP_LIGHT = 0x55000000.toInt()  // language picker (lighter)

    // Close-zone bubble: high-opacity dark pill
    const val CLOSE_ZONE     = 0xCC222230.toInt()

    // Hint banner (Accessibility prompt etc.)
    const val HINT_BG_DARK   = 0xFF3A2E10.toInt()
    const val HINT_BG_LIGHT  = 0xFFFFF6D6.toInt()
    const val HINT_FG_DARK   = 0xFFFFD86E.toInt()
    const val HINT_FG_LIGHT  = 0xFF7A5A00.toInt()
}
