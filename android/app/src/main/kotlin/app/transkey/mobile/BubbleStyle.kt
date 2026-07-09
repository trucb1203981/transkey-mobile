package app.transkey.mobile

import android.content.Context
import android.content.res.Configuration
import android.graphics.drawable.GradientDrawable

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
                bg     = if (isDark) Glass.PANEL_DARK else Glass.PANEL_LIGHT,
                text   = if (isDark) Glass.TEXT_DARK  else Glass.TEXT_LIGHT,
                muted  = if (isDark) Glass.MUTED_DARK else Glass.MUTED_LIGHT,
                accent = Palette.ACCENT,
            )
        }
    }
}

/**
 * Liquid Glass tokens for native overlay surfaces (bubble pickers + IME
 * keyboard), ported from the Flutter redesign's `GlassPalette.dark/light`
 * (`lib/shared/theme/app_glass.dart`). Native panels float over ARBITRARY app
 * content, not the app's own aurora backdrop, so a translucent see-through
 * fill (like Flutter's white-alpha-over-aurora fills) would be illegible and
 * have no violet to tint. The honest native adaptation: an OPAQUE aurora-dark
 * (or pale-violet, light mode) panel carrying its own tint, topped with a
 * top-lit specular gradient + a 1px light hairline border - the same "fake
 * glass" look Flutter uses for every non-scrolling surface, just opaque
 * instead of translucent. Brand gradient colors are untouched (see
 * [Palette.ACCENT] / [Palette.ACCENT_END]).
 */
object Glass {
    // Opaque panel fill (replaces the old flat Palette.SURFACE_DARK / white).
    const val PANEL_DARK  = 0xFF14121F.toInt() // between GlassPalette.dark.auroraBase/auroraTop
    const val PANEL_LIGHT = 0xFFF3F2FD.toInt() // GlassPalette.light.auroraTop

    // Top-lit specular: panel color blended with white @ 10% (dark) / 30%
    // (light), mirroring AppGlass._topLit. Precomputed since Kotlin has no
    // Color.alphaBlend at this call site.
    const val PANEL_DARK_SPECULAR  = 0xFF2C2A35.toInt()
    const val PANEL_LIGHT_SPECULAR = 0xFFF7F6FE.toInt()

    // Hairline border drawn as a stroke over the opaque panel.
    const val BORDER_DARK  = 0x29FFFFFF // white @ 16%, matches GlassPalette.dark.border
    const val BORDER_LIGHT = 0x33000000 // black @ 20% - a translucent white edge would
                                         // be invisible against the near-white opaque panel

    // Text-on-glass, matches GlassPalette.dark/light textPrimary/textSecondary.
    const val TEXT_DARK   = 0xFFF3F2FF.toInt()
    const val TEXT_LIGHT  = 0xFF1A1A2E.toInt()
    const val MUTED_DARK  = 0xFFB6B4CE.toInt()
    const val MUTED_LIGHT = 0xFF4F4D6B.toInt()

    // Accent readable ON a glass panel (brighter than Palette.ACCENT in dark
    // mode), matches GlassPalette.dark/light accent.
    const val ACCENT_ON_GLASS_DARK  = 0xFFA99BFF.toInt()
    const val ACCENT_ON_GLASS_LIGHT = 0xFF6C63FF.toInt()

    // Secondary "chip" fill — one step lighter/darker than the panel, for
    // unselected lang chips / mode tiles / tabs sitting ON TOP of a panel.
    const val CHIP_DARK  = 0xFF23213A.toInt()
    const val CHIP_LIGHT = 0xFFEAE8F9.toInt()

    /**
     * The reusable fake-glass panel: opaque top-lit vertical gradient fill +
     * rounded corners + 1px hairline border. Use as `background` for any
     * bubble picker/panel root. [radiusDp] in dp, [dp] = density from
     * [BubbleStyle.dp].
     */
    fun panel(dp: Float, radiusDp: Float, isDark: Boolean): GradientDrawable {
        val base = if (isDark) PANEL_DARK else PANEL_LIGHT
        val top = if (isDark) PANEL_DARK_SPECULAR else PANEL_LIGHT_SPECULAR
        val border = if (isDark) BORDER_DARK else BORDER_LIGHT
        return GradientDrawable(
            GradientDrawable.Orientation.TOP_BOTTOM,
            intArrayOf(top, base),
        ).apply {
            cornerRadius = radiusDp * dp
            setStroke((1f * dp).toInt().coerceAtLeast(1), border)
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

    // Brand - matches app gradient #6366F1 → #A855F7 (see lib/.../theme & landing page)
    const val ACCENT         = 0xFF6366F1.toInt()  // bubble idle stroke + buttons (indigo)
    const val ACCENT_END     = 0xFFA855F7.toInt()  // purple end-stop for gradient surfaces

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
