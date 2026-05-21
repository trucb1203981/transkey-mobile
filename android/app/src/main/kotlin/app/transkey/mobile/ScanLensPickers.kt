package app.transkey.mobile

import android.annotation.SuppressLint
import android.graphics.Bitmap
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.util.TypedValue
import android.view.Gravity
import android.view.View
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.ProgressBar
import android.widget.TextView
import app.transkey.mobile.BubbleService.Companion.KEY_SCAN_DISCLOSED
import app.transkey.mobile.BubbleService.Companion.MODE_SUMMARIZE
import app.transkey.mobile.BubbleService.Companion.MODE_TRANSLATE

/**
 * Scan / Lens flow overlays — pre-OCR mode chooser, MediaProjection
 * consent disclosure, in-flight progress card, and the final Lens
 * translation overlay. Pulled out of BubbleService.kt so the
 * MediaProjection state machine and the Service lifecycle plumbing
 * don't share file space with rendering details.
 *
 * Each `show*` writes to the corresponding `*View` field on the
 * service (promoted to `internal`) and calls `windowManager.addView`;
 * each `hide*` is the symmetric removeView + null-out.
 */
internal fun BubbleService.showScanModeChooser(isRegion: Boolean) {
    ensureWindowManager()
    refreshLocale()
    val style = BubbleStyle.of(this)
    val dp = style.dp
    val isDark = style.isDark
    val bg = style.bg
    val textCol = style.text
    val mutedCol = style.muted
    val accent = style.accent

    val backdrop = FrameLayout(this).apply {
        setBackgroundColor(Palette.BACKDROP_DIM)
        setOnClickListener { hideScanModeChooser() }
    }
    val card = LinearLayout(this).apply {
        orientation = LinearLayout.VERTICAL
        background = GradientDrawable().apply { setColor(bg); cornerRadius = 18 * dp }
        elevation = 22 * dp
        setPadding((20 * dp).toInt(), (16 * dp).toInt(), (20 * dp).toInt(), (16 * dp).toInt())
        isClickable = true
    }
    card.addView(TextView(this).apply {
        text = localized(R.string.bubble_choose_action)
        setTextColor(textCol)
        setTextSize(TypedValue.COMPLEX_UNIT_SP, 14f)
        typeface = Typeface.DEFAULT_BOLD
        setPadding(0, 0, 0, (12 * dp).toInt())
    })

    fun modeButton(mode: String, label: String): TextView = TextView(this).apply {
        text = label
        setTextColor(if (mode == MODE_TRANSLATE) Color.WHITE else textCol)
        setTextSize(TypedValue.COMPLEX_UNIT_SP, 14f)
        typeface = Typeface.DEFAULT_BOLD
        gravity = Gravity.CENTER
        background = GradientDrawable().apply {
            setColor(if (mode == MODE_TRANSLATE) accent else Color.parseColor(if (isDark) "#2A2A40" else "#F0EFFF"))
            cornerRadius = 12 * dp
        }
        setPadding(0, (12 * dp).toInt(), 0, (12 * dp).toInt())
        isClickable = true
        isFocusable = true
        layoutParams = LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT,
            LinearLayout.LayoutParams.WRAP_CONTENT,
        ).apply { topMargin = (8 * dp).toInt() }
        setOnClickListener {
            hideScanModeChooser()
            if (isRegion) handleLensRegionRequest(mode) else handleScanRequest(mode)
        }
    }
    card.addView(modeButton(MODE_TRANSLATE, modeLabel(MODE_TRANSLATE)))
    card.addView(modeButton(MODE_SUMMARIZE, modeLabel(MODE_SUMMARIZE)))

    card.addView(TextView(this).apply {
        text = localized(R.string.bubble_cancel)
        setTextColor(mutedCol)
        setTextSize(TypedValue.COMPLEX_UNIT_SP, 13f)
        gravity = Gravity.CENTER
        setPadding(0, (12 * dp).toInt(), 0, 0)
        isClickable = true
        isFocusable = true
        setOnClickListener { hideScanModeChooser() }
    })

    val screenWidth = resources.displayMetrics.widthPixels
    val cardWidth = (screenWidth - (40 * dp).toInt()).coerceAtMost((360 * dp).toInt())
    backdrop.addView(card, FrameLayout.LayoutParams(
        cardWidth, FrameLayout.LayoutParams.WRAP_CONTENT, Gravity.CENTER,
    ))
    scanModeChooserView = backdrop
    try { windowManager?.addView(backdrop, buildPickerLayoutParams()) }
    catch (e: Exception) { android.util.Log.w("TKBubble", "scan-mode-chooser add failed: ${e.message}") }
}

internal fun BubbleService.hideScanModeChooser() {
    scanModeChooserView?.let { try { windowManager?.removeView(it) } catch (_: Exception) {} }
    scanModeChooserView = null
}

@SuppressLint("ClickableViewAccessibility")
internal fun BubbleService.showScanDisclosure(mode: String = MODE_TRANSLATE) {
    if (scanDisclosureView != null) { hideScanDisclosure(); return }
    ensureWindowManager()
    refreshLocale()

    val style = BubbleStyle.of(this)
    val dp = style.dp
    val isDark = style.isDark
    val bg = style.bg
    val textCol = style.text
    val mutedCol = style.muted
    val accent = style.accent

    val backdrop = FrameLayout(this).apply {
        setBackgroundColor(Palette.BACKDROP_DIM)
        setOnClickListener { hideScanDisclosure() }
    }
    val card = LinearLayout(this).apply {
        orientation = LinearLayout.VERTICAL
        background = GradientDrawable().apply { setColor(bg); cornerRadius = 18 * dp }
        elevation = 22 * dp
        setPadding((20 * dp).toInt(), (18 * dp).toInt(), (20 * dp).toInt(), (16 * dp).toInt())
        isClickable = true
    }
    card.addView(TextView(this).apply {
        text = "📷  ${localized(R.string.bubble_scan_disclosure_title)}"
        setTextColor(textCol)
        setTextSize(TypedValue.COMPLEX_UNIT_SP, 15f)
        typeface = Typeface.DEFAULT_BOLD
        setPadding(0, 0, 0, (10 * dp).toInt())
    })
    card.addView(TextView(this).apply {
        text = localized(R.string.bubble_scan_disclosure_body)
        setTextColor(mutedCol)
        setTextSize(TypedValue.COMPLEX_UNIT_SP, 13f)
        setLineSpacing(2 * dp, 1f)
        setPadding(0, 0, 0, (16 * dp).toInt())
    })

    val actions = LinearLayout(this).apply {
        orientation = LinearLayout.HORIZONTAL
        gravity = Gravity.END
    }
    actions.addView(TextView(this).apply {
        text = localized(R.string.bubble_cancel)
        setTextColor(mutedCol)
        setTextSize(TypedValue.COMPLEX_UNIT_SP, 13f)
        typeface = Typeface.DEFAULT_BOLD
        setPadding((14 * dp).toInt(), (10 * dp).toInt(), (14 * dp).toInt(), (10 * dp).toInt())
        isClickable = true
        isFocusable = true
        setOnClickListener { hideScanDisclosure() }
    })
    actions.addView(TextView(this).apply {
        text = localized(R.string.bubble_scan_continue)
        setTextColor(Color.WHITE)
        setTextSize(TypedValue.COMPLEX_UNIT_SP, 13f)
        typeface = Typeface.DEFAULT_BOLD
        background = GradientDrawable().apply {
            setColor(accent)
            cornerRadius = 12 * dp
        }
        setPadding((18 * dp).toInt(), (10 * dp).toInt(), (18 * dp).toInt(), (10 * dp).toInt())
        isClickable = true
        isFocusable = true
        layoutParams = LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.WRAP_CONTENT,
            LinearLayout.LayoutParams.WRAP_CONTENT,
        ).apply { marginStart = (8 * dp).toInt() }
        setOnClickListener {
            prefs.edit()
                .putBoolean(KEY_SCAN_DISCLOSED, true).apply()
            hideScanDisclosure()
            launchScanFlow(mode)
        }
    })
    card.addView(actions)

    val screenWidth = resources.displayMetrics.widthPixels
    val cardWidth = (screenWidth - (40 * dp).toInt()).coerceAtMost((360 * dp).toInt())
    backdrop.addView(card, FrameLayout.LayoutParams(
        cardWidth, FrameLayout.LayoutParams.WRAP_CONTENT, Gravity.CENTER,
    ))
    scanDisclosureView = backdrop
    windowManager?.addView(backdrop, buildPickerLayoutParams())
}

internal fun BubbleService.hideScanDisclosure() {
    scanDisclosureView?.let { try { windowManager?.removeView(it) } catch (_: Exception) {} }
    scanDisclosureView = null
}

@SuppressLint("ClickableViewAccessibility")
internal fun BubbleService.showLensProgress() {
    if (lensProgressView != null) return
    ensureWindowManager()
    val style = BubbleStyle.of(this)
    val dp = style.dp
    val bg = style.bg
    val textCol = style.text

    val backdrop = FrameLayout(this).apply {
        setBackgroundColor(0x88000000.toInt())
        isClickable = true  // swallow taps so user can't dismiss mid-translate
    }
    val card = LinearLayout(this).apply {
        orientation = LinearLayout.HORIZONTAL
        gravity = Gravity.CENTER_VERTICAL
        background = GradientDrawable().apply { setColor(bg); cornerRadius = 14 * dp }
        elevation = 20 * dp
        setPadding((18 * dp).toInt(), (14 * dp).toInt(), (20 * dp).toInt(), (14 * dp).toInt())
    }
    card.addView(ProgressBar(this, null, android.R.attr.progressBarStyleSmall).apply {
        isIndeterminate = true
        layoutParams = LinearLayout.LayoutParams(
            (22 * dp).toInt(), (22 * dp).toInt(),
        )
    })
    card.addView(TextView(this).apply {
        text = localized(R.string.bubble_lens_translating)
        setTextColor(textCol)
        setTextSize(TypedValue.COMPLEX_UNIT_SP, 13f)
        typeface = Typeface.DEFAULT_BOLD
        setPadding((12 * dp).toInt(), 0, 0, 0)
    })
    backdrop.addView(card, FrameLayout.LayoutParams(
        FrameLayout.LayoutParams.WRAP_CONTENT,
        FrameLayout.LayoutParams.WRAP_CONTENT,
        Gravity.CENTER,
    ))
    lensProgressView = backdrop
    windowManager?.addView(backdrop, buildPickerLayoutParams())
}

internal fun BubbleService.hideLensProgress() {
    lensProgressView?.let { try { windowManager?.removeView(it) } catch (_: Exception) {} }
    lensProgressView = null
}

internal fun BubbleService.showLensOverlay(bitmap: Bitmap, items: List<LensOverlayView.Item>) {
    ensureWindowManager()
    val overlay = LensOverlayView(
        this, bitmap, items,
        onDismissOutsideTap = { hideLensOverlay() },
        // Long-press any block → close the overlay + send the original
        // (source-language) text to Flutter, which opens the "What is this?"
        // sheet. Lets the user explain a 1-2 word region selection — handy
        // for unfamiliar names on a menu / sign that the translation alone
        // doesn't reveal the meaning of.
        onLongPressBlock = { sourceText ->
            hideLensOverlay()
            openExplainScreen(sourceText)
        },
    )
    lensOverlayView = overlay
    windowManager?.addView(overlay, buildPickerLayoutParams())
}

internal fun BubbleService.hideLensOverlay() {
    lensOverlayView?.let { try { windowManager?.removeView(it) } catch (_: Exception) {} }
    lensOverlayView = null
    // Recycling the bitmap + clearing manager state is done together
    // here (NOT in service.cleanup) so the bitmap survives until the
    // user actually dismisses the overlay.
    ScreenCaptureManager.clearAll()
    restoreBubbleVisibility()
}
