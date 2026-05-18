package app.transkey.mobile

import android.os.Build
import android.graphics.PixelFormat
import android.view.Gravity
import android.view.View
import android.view.WindowManager
import android.widget.LinearLayout

/**
 * Extension functions for the result-panel lifecycle / geometry.
 *
 * Phase 2 of the showResultPanel extraction (B1.2). Step 1 grouped the
 * 19 loose `panel*` fields into a `ResultPanel` holder; this step
 * pulls the *pure* helpers — the ones that read/mutate panel state
 * without needing the full BubbleService callback surface — out of
 * BubbleService.kt so the file shrinks ~100 lines and the panel-only
 * logic is easier to scan.
 *
 * The heavyweight builders (showResultPanel itself = ~720 lines,
 * showResult, showError) stay in BubbleService for now — they
 * depend on too many other private callbacks (showSourceLangPicker,
 * showLangPicker, showSettingsSheet, handleTranslateRequest, the
 * Flutter MethodChannel, the accessibility-paste path) to extract
 * cleanly without first promoting ~30 more visibilities to internal.
 *
 * `internal` extension functions can only see `internal`+ members,
 * which is why panel / windowManager / isTranslating / localized()
 * had to be promoted from `private` in BubbleService.
 */

/**
 * Build the WindowManager layout params for the result panel root.
 * `panel.fullscreen` toggles edge-to-edge mode; `panel.heightPx > 0`
 * pins a custom drag-resized height; otherwise WRAP_CONTENT.
 */
internal fun BubbleService.buildPanelLayoutParams(): WindowManager.LayoutParams {
    val dp = resources.displayMetrics.density
    val screenWidth = resources.displayMetrics.widthPixels
    val screenHeight = resources.displayMetrics.heightPixels

    val width: Int
    val height: Int
    val yOffset: Int
    if (panel.fullscreen) {
        // Fullscreen: side-to-side, top to ~24dp from bottom (leave room
        // for system nav). Don't go absolutely edge-to-edge — corners
        // and status bar look better with a tiny margin.
        width = screenWidth - (8 * dp).toInt()
        height = screenHeight - (24 * dp).toInt()
        yOffset = (4 * dp).toInt()
    } else {
        width = (screenWidth - (32 * dp).toInt()).coerceAtMost((360 * dp).toInt())
        height = if (panel.heightPx > 0) panel.heightPx
            else WindowManager.LayoutParams.WRAP_CONTENT
        yOffset = (80 * dp).toInt()
    }

    return WindowManager.LayoutParams(
        width,
        height,
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        else @Suppress("DEPRECATION") WindowManager.LayoutParams.TYPE_PHONE,
        WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE,
        PixelFormat.TRANSLUCENT,
    ).apply {
        gravity = Gravity.TOP or Gravity.CENTER_HORIZONTAL
        y = yOffset
    }
}

/**
 * Switch the panel content scroll between WRAP_CONTENT (default
 * sizing, capped at ~220dp via onMeasure) and weight=1 (fills the
 * remaining space inside a parent that has a fixed height). Called
 * after fullscreen toggle and drag-resize so the body grows / shrinks
 * with the panel instead of leaving white space below the actions row.
 */
internal fun BubbleService.applyPanelLayoutMode() {
    val scroll = panel.contentScroll ?: return
    val lp = scroll.layoutParams as LinearLayout.LayoutParams
    if (panel.fullscreen || panel.heightPx > 0) {
        lp.height = 0
        lp.weight = 1f
    } else {
        lp.height = LinearLayout.LayoutParams.WRAP_CONTENT
        lp.weight = 0f
    }
    scroll.layoutParams = lp
}

/**
 * Flip the source text between collapsed (3 lines + ellipsis) and
 * expanded (full text). Used so the user can line up the original
 * against the translation when the source is longer than 3 lines.
 */
internal fun BubbleService.togglePanelSourceExpanded() {
    panel.sourceExpanded = !panel.sourceExpanded
    applyPanelSourceExpansion()
}

internal fun BubbleService.applyPanelSourceExpansion() {
    val src = panel.source ?: return
    if (panel.sourceExpanded) {
        src.maxLines = Int.MAX_VALUE
        src.ellipsize = null
    } else {
        src.maxLines = 3
        src.ellipsize = android.text.TextUtils.TruncateAt.END
    }
    refreshPanelSourceToggle()
}

/**
 * Show / hide the "Show more / Show less" affordance. Hidden when
 * the source fits in 3 lines (no toggle needed); otherwise shows
 * the inverse label (expanded → "Show less", collapsed → "Show more").
 */
internal fun BubbleService.refreshPanelSourceToggle() {
    val src = panel.source ?: return
    val toggle = panel.sourceToggle ?: return
    // Defer to a post() so getLineCount() reads the laid-out value
    // rather than the pre-measure 0.
    src.post {
        val text = src.text?.toString().orEmpty()
        // Cheap pre-check: if the raw text has fewer than 3 newlines
        // AND is short, skip the layout-based check.
        val needsToggle = text.length > 120 ||
            text.count { it == '\n' } >= 2 ||
            (src.lineCount > 3 || (src.layout?.let { it.lineCount > 3 } == true))
        if (!needsToggle) {
            toggle.visibility = View.GONE
            return@post
        }
        toggle.visibility = View.VISIBLE
        toggle.text = if (panel.sourceExpanded) "▴ ${localized(R.string.bubble_show_less)}"
                      else                     "▾ ${localized(R.string.bubble_show_more)}"
    }
}

/**
 * Reset the panel's resize state and dismiss the overlay. Used by
 * hideResultPanel + the close-button action. Doesn't touch
 * isTranslating / setState — those belong to BubbleService's
 * higher-level lifecycle.
 */
internal fun BubbleService.removeResultPanel() {
    panel.view?.let {
        try { windowManager?.removeView(it) } catch (_: Exception) {}
    }
    panel.view = null
    panel.source = null
    panel.output = null
    panel.romanization = null
    panel.status = null
    panel.copyBtn = null
    panel.pasteBtn = null
    panel.ttsBtn = null
    panel.langChip = null
    panel.sourceLangChip = null
    panel.toneChip = null
    panel.loadingSpinner = null
    panel.detectedLangTv = null
    panel.suggestionsLabel = null
    panel.suggestionsContainer = null
    panel.modeButtons.clear()
}
