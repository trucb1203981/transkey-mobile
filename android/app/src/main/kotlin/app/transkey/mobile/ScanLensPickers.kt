package app.transkey.mobile

import android.annotation.SuppressLint
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.graphics.Bitmap
import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.util.TypedValue
import android.view.Gravity
import android.view.View
import android.view.WindowManager
import android.widget.FrameLayout
import android.widget.ScrollView
import android.widget.LinearLayout
import android.widget.ProgressBar
import android.widget.TextView
import android.widget.Toast
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
        text = "📱  ${localized(R.string.bubble_scan_disclosure_title)}"
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
internal fun BubbleService.showLensProgress(sourceLabel: String? = null) {
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
    // Vertical stack: main label on top, optional "From: Language" hint below.
    val textStack = LinearLayout(this).apply {
        orientation = LinearLayout.VERTICAL
        setPadding((12 * dp).toInt(), 0, 0, 0)
    }
    textStack.addView(TextView(this).apply {
        text = localized(R.string.bubble_lens_translating)
        setTextColor(textCol)
        setTextSize(TypedValue.COMPLEX_UNIT_SP, 13f)
        typeface = Typeface.DEFAULT_BOLD
    })
    if (sourceLabel != null) {
        // Shown at 67% alpha so it's readable but clearly secondary.
        // Lets the user notice a wrong source-language selection at a glance.
        textStack.addView(TextView(this).apply {
            text = localized(R.string.lens_source_from, sourceLabel)
            setTextColor((textCol and 0x00FFFFFF) or 0xAA000000.toInt())
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 11f)
            setPadding(0, (2 * dp).toInt(), 0, 0)
        })
    }
    card.addView(textStack)
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
    // Resolve current source/target into display labels for the always-on
    // language chip so the user can verify (and catch a wrong pick the
    // mismatch banner can't detect — Latin-vs-Latin source, or wrong target).
    val labels = getEffectiveLangLabels()
    val srcHint = ScreenCaptureManager.languageHint
    val srcLabel = if (srcHint.isNullOrEmpty() || srcHint == "auto")
        localized(R.string.bubble_tone_auto)
    else (labels[srcHint] ?: srcHint)
    val tgtCode = ScreenCaptureManager.targetLang
    val tgtLabel = labels[tgtCode] ?: tgtCode
    val overlay = LensOverlayView(
        this, bitmap, items,
        // Outside tap = the "accidental dismiss" case — offer a quick undo
        // so re-opening the same result is instant.
        onDismissOutsideTap = { hideLensOverlay(offerReopen = true) },
        // Long-press any block → close the overlay + send the original
        // (source-language) text to Flutter, which opens the "What is this?"
        // sheet. Lets the user explain a 1-2 word region selection — handy
        // for unfamiliar names on a menu / sign that the translation alone
        // doesn't reveal the meaning of.
        onLongPressBlock = { sourceText ->
            hideLensOverlay()
            openExplainScreen(sourceText)
        },
        // Single tap → readable popup with the FULL translation + original,
        // so long results that get truncated in the in-place chip are never
        // lost.
        onBlockTap = { original, translation ->
            showLensDetailPopup(original, translation)
        },
        sourceLabel = srcLabel,
        targetLabel = tgtLabel,
        // Tap the chip → open the source-language picker ON TOP of the
        // overlay (do NOT tear the overlay down — cancelling the picker
        // must keep the current translation). Picking a language
        // re-translates the SAME scan in place via the stashed texts.
        onLangChipTap = {
            showSourceLangPicker(onPicked = { newSource ->
                val newLabel = if (newSource == "auto")
                    localized(R.string.bubble_tone_auto)
                else (getEffectiveLangLabels()[newSource] ?: newSource)
                lensOverlayView?.setSourceLabel(newLabel)
                retranslateLens(newSource)
            })
        },
        copyAllLabel = localized(R.string.bubble_panel_copy),
        // Copies every block's ORIGINAL text — screen-text extraction for
        // content the source app won't let the user select (mirrors the
        // desktop overlay's copy-all).
        onCopyAllTap = {
            val all = lensOverlayView?.snapshotItems()
                ?.joinToString("\n") { it.original }
                .orEmpty()
            if (all.isNotBlank()) {
                val cm = getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
                cm.setPrimaryClip(ClipData.newPlainText("TransKey", all))
                Toast.makeText(
                    this,
                    localized(R.string.bubble_panel_copied),
                    Toast.LENGTH_SHORT,
                ).show()
            }
        },
    )
    lensOverlayView = overlay
    windowManager?.addView(overlay, buildPickerLayoutParams())
}

/**
 * Readable popup showing one block's full translation (and its original
 * source text below). Opened by tapping a chip in the Lens overlay — the
 * in-place chips stay size-bounded for a clean overlay, this is where the
 * complete text lives. Tap anywhere to dismiss.
 */
@SuppressLint("ClickableViewAccessibility")
internal fun BubbleService.showLensDetailPopup(original: String, translation: String) {
    hideLensDetailPopup()
    ensureWindowManager()
    val style = BubbleStyle.of(this)
    val dp = style.dp
    val backdrop = FrameLayout(this).apply {
        setBackgroundColor(0xAA000000.toInt())
        isClickable = true
        setOnClickListener { hideLensDetailPopup() }
    }
    val scroll = ScrollView(this).apply {
        isFillViewport = false
        overScrollMode = View.OVER_SCROLL_NEVER
    }
    val card = LinearLayout(this).apply {
        orientation = LinearLayout.VERTICAL
        background = GradientDrawable().apply { setColor(style.bg); cornerRadius = 16 * dp }
        elevation = 22 * dp
        setPadding((20 * dp).toInt(), (18 * dp).toInt(), (20 * dp).toInt(), (18 * dp).toInt())
        // Swallow taps on the card itself so they don't fall through to the
        // backdrop's dismiss handler.
        isClickable = true
    }
    card.addView(TextView(this).apply {
        text = translation.ifBlank { original }
        setTextColor(style.text)
        setTextSize(TypedValue.COMPLEX_UNIT_SP, 17f)
        typeface = Typeface.DEFAULT_BOLD
        setTextIsSelectable(true)
    })
    if (original.isNotBlank() && original.trim() != translation.trim()) {
        card.addView(TextView(this).apply {
            text = original
            setTextColor((style.text and 0x00FFFFFF) or 0x99000000.toInt())
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 13f)
            setTextIsSelectable(true)
            setPadding(0, (12 * dp).toInt(), 0, 0)
        })
    }
    // Copy buttons. The overlay window is FLAG_NOT_FOCUSABLE, so the
    // selectable-text handles above never actually engage (text selection
    // needs window focus) — explicit buttons are the only reliable copy
    // path from an overlay.
    val copyRow = LinearLayout(this).apply {
        orientation = LinearLayout.HORIZONTAL
        setPadding(0, (14 * dp).toInt(), 0, 0)
    }
    fun addCopyButton(label: String, value: String) {
        if (value.isBlank()) return
        val btn = TextView(this).apply {
            text = label
            setTextColor(style.text)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 13f)
            typeface = Typeface.DEFAULT_BOLD
            background = GradientDrawable().apply {
                setColor((style.text and 0x00FFFFFF) or 0x16000000)
                cornerRadius = 18 * dp
            }
            setPadding((14 * dp).toInt(), (8 * dp).toInt(), (14 * dp).toInt(), (8 * dp).toInt())
            isClickable = true
        }
        btn.setOnClickListener {
            val cm = getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
            cm.setPrimaryClip(ClipData.newPlainText("TransKey", value))
            // In-button feedback instead of a Toast: some OEMs suppress
            // Toasts from overlay services (see bugs.md), and Android 13+
            // already shows its own clipboard confirmation.
            btn.text = localized(R.string.bubble_panel_copied)
            btn.postDelayed({ btn.text = label }, 1_400)
        }
        btn.layoutParams = LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.WRAP_CONTENT,
            LinearLayout.LayoutParams.WRAP_CONTENT,
        ).apply { if (copyRow.childCount > 0) marginStart = (8 * dp).toInt() }
        copyRow.addView(btn)
    }
    addCopyButton(localized(R.string.bubble_panel_copy), translation.ifBlank { original })
    if (original.isNotBlank() && original.trim() != translation.trim()) {
        addCopyButton(localized(R.string.lens_copy_original), original)
    }
    card.addView(copyRow)
    scroll.addView(card)
    // WRAP_CONTENT height lets a short translation show a compact card while
    // a long one grows up to the screen and scrolls inside the ScrollView.
    backdrop.addView(scroll, FrameLayout.LayoutParams(
        (320 * dp).toInt().coerceAtMost(
            (resources.displayMetrics.widthPixels * 0.9f).toInt(),
        ),
        FrameLayout.LayoutParams.WRAP_CONTENT,
        Gravity.CENTER,
    ))
    lensDetailView = backdrop
    windowManager?.addView(backdrop, buildPickerLayoutParams())
}

internal fun BubbleService.hideLensDetailPopup() {
    lensDetailView?.let { try { windowManager?.removeView(it) } catch (_: Exception) {} }
    lensDetailView = null
}

/**
 * @param offerReopen when true (outside-tap dismiss), keep the screenshot
 * + finished chips in the reopen cache and float a brief "reopen" pill so
 * an accidental close can be undone instantly. When false (long-press →
 * explain, stop, new scan), tear everything down as before.
 */
internal fun BubbleService.hideLensOverlay(offerReopen: Boolean = false) {
    hideLensDetailPopup()
    val overlay = lensOverlayView
    lensOverlayView?.let { try { windowManager?.removeView(it) } catch (_: Exception) {} }
    lensOverlayView = null
    if (offerReopen && overlay != null) {
        val ovBmp = overlay.bitmap
        if (!ovBmp.isRecycled) {
            // Drop any OLDER cached scan first (recycles its bitmap). Safe
            // because a restored overlay already nulled the cache, so this
            // never frees the bitmap we're about to re-cache.
            discardLensCache()
            // If this bitmap is still the live SCM screenshot, detach it so
            // clearAll() below won't recycle it out from under the cache.
            if (ScreenCaptureManager.screenshot === ovBmp) {
                ScreenCaptureManager.detachScreenshot()
            }
            lastLensBitmap = ovBmp
            lastLensItems = overlay.snapshotItems()
            ScreenCaptureManager.clearAll()
            restoreBubbleVisibility()
            showReopenPill()
            return
        }
    }
    ScreenCaptureManager.clearAll()
    restoreBubbleVisibility()
}

/** Recycle + forget any cached "reopen last result" scan. */
internal fun BubbleService.discardLensCache() {
    hideReopenPill()
    lastLensBitmap?.let { if (!it.isRecycled) it.recycle() }
    lastLensBitmap = null
    lastLensItems = null
}

internal fun BubbleService.hideReopenPill() {
    reopenDismissRunnable?.let { handler.removeCallbacks(it) }
    reopenDismissRunnable = null
    reopenPillView?.let { try { windowManager?.removeView(it) } catch (_: Exception) {} }
    reopenPillView = null
}

/**
 * Float a tappable "grant for this app" pill after a single-app
 * MediaProjection grant failed to capture the now-foreground app (the user
 * switched apps and pressed capture). The re-consent CANNOT be opened off a
 * timer — MIUI aborts background activity starts that aren't tied to a live
 * user gesture — so we surface this pill and let the user's TAP drive the
 * fresh consent (via [BubbleService.repeatLastScan]). By then the stale
 * projection is already stopped, so the new consent creates a fresh
 * projection instead of crashing SystemUI on its reuse branch.
 *
 * No auto-dismiss: it stays until tapped, until the next scan
 * ([hideOverlaysForCapture]), or service teardown.
 */
@SuppressLint("ClickableViewAccessibility")
internal fun BubbleService.showRegrantPill() {
    hideRegrantPill()
    ensureWindowManager()
    refreshLocale()
    val style = BubbleStyle.of(this)
    val dp = style.dp
    val pill = LinearLayout(this).apply {
        orientation = LinearLayout.HORIZONTAL
        gravity = Gravity.CENTER_VERTICAL
        background = GradientDrawable().apply {
            setColor(style.accent); cornerRadius = 22 * dp
        }
        elevation = 18 * dp
        setPadding((18 * dp).toInt(), (12 * dp).toInt(), (18 * dp).toInt(), (12 * dp).toInt())
        addView(TextView(this@showRegrantPill).apply {
            text = localized(R.string.lens_regrant_prompt)
            setTextColor(Color.WHITE)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 13f)
            typeface = Typeface.DEFAULT_BOLD
        })
        setOnClickListener {
            hideRegrantPill()
            repeatLastScan()
        }
    }
    regrantPillView = pill
    // Dedicated WRAP_CONTENT window with FLAG_NOT_TOUCH_MODAL so taps outside
    // the pill fall through to the app behind it (same rationale as the
    // reopen pill).
    val lp = WindowManager.LayoutParams(
        WindowManager.LayoutParams.WRAP_CONTENT,
        WindowManager.LayoutParams.WRAP_CONTENT,
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        else @Suppress("DEPRECATION") WindowManager.LayoutParams.TYPE_PHONE,
        WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
            WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL,
        PixelFormat.TRANSLUCENT,
    ).apply {
        gravity = Gravity.BOTTOM or Gravity.CENTER_HORIZONTAL
        y = (90 * dp).toInt()
    }
    try { windowManager?.addView(pill, lp) }
    catch (e: Exception) { android.util.Log.w("TKBubble", "regrant pill add failed: ${e.message}") }
}

internal fun BubbleService.hideRegrantPill() {
    regrantPillView?.let { try { windowManager?.removeView(it) } catch (_: Exception) {} }
    regrantPillView = null
}

/**
 * Float a small tappable "Reopen translation" pill near the bubble for a
 * few seconds after an accidental dismiss. Tap → restore the cached
 * overlay instantly; ignore → auto-hide and recycle the cached bitmap.
 */
@SuppressLint("ClickableViewAccessibility")
internal fun BubbleService.showReopenPill() {
    if (reopenPillView != null) return
    ensureWindowManager()
    val style = BubbleStyle.of(this)
    val dp = style.dp
    val pill = LinearLayout(this).apply {
        orientation = LinearLayout.HORIZONTAL
        gravity = Gravity.CENTER_VERTICAL
        background = GradientDrawable().apply {
            setColor(style.bg); cornerRadius = 22 * dp
        }
        elevation = 18 * dp
        setPadding((18 * dp).toInt(), (12 * dp).toInt(), (18 * dp).toInt(), (12 * dp).toInt())
        addView(TextView(this@showReopenPill).apply {
            text = localized(R.string.lens_reopen_result)
            setTextColor(style.text)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 13f)
            typeface = Typeface.DEFAULT_BOLD
        })
        setOnClickListener { restoreLensFromCache() }
    }
    reopenPillView = pill
    // IMPORTANT: a dedicated WRAP_CONTENT window — NOT buildPickerLayoutParams
    // (which is MATCH_PARENT). A full-screen window here would stretch the
    // pill across the screen and make its click listener fire on ANY tap.
    // FLAG_NOT_TOUCH_MODAL lets taps outside the small pill fall through to
    // the app behind it.
    val lp = WindowManager.LayoutParams(
        WindowManager.LayoutParams.WRAP_CONTENT,
        WindowManager.LayoutParams.WRAP_CONTENT,
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        else @Suppress("DEPRECATION") WindowManager.LayoutParams.TYPE_PHONE,
        WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
            WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL,
        PixelFormat.TRANSLUCENT,
    ).apply {
        gravity = Gravity.BOTTOM or Gravity.CENTER_HORIZONTAL
        y = (90 * dp).toInt()
    }
    windowManager?.addView(pill, lp)
    // Auto-dismiss after 6s — drop the cache if the user didn't undo.
    // Stored so a re-armed pill can cancel the previous timeout (otherwise
    // a stale callback would recycle a freshly re-cached bitmap).
    val dismiss = Runnable { discardLensCache() }
    reopenDismissRunnable = dismiss
    handler.postDelayed(dismiss, 6000L)
}

/** Re-show the cached scan instantly (no re-capture/OCR/LLM). */
internal fun BubbleService.restoreLensFromCache() {
    val bmp = lastLensBitmap ?: return
    val items = lastLensItems ?: return
    hideReopenPill()
    bubbleView?.visibility = View.GONE
    // Transfer logical ownership of the bitmap to the live overlay BEFORE
    // showing it; do NOT recycle here. On the overlay's own dismiss,
    // [hideLensOverlay] reads overlay.bitmap again to re-cache or recycle.
    lastLensBitmap = null
    lastLensItems = null
    showLensOverlay(bmp, items)
    lensOverlayView?.markAllProcessed()
}
