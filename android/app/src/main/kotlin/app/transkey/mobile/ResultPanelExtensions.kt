package app.transkey.mobile

import android.annotation.SuppressLint
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.util.TypedValue
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.ProgressBar
import android.widget.ScrollView
import android.widget.TextView
import android.widget.Toast
import app.transkey.mobile.BubbleService.Companion.ALL_MODES
// LANG_LABELS replaced by getEffectiveLangLabels() so the chip text
// reflects the server-mirrored catalog (admin-enabled language list)
// instead of the hardcoded fallback set.
import app.transkey.mobile.BubbleService.Companion.MODE_REFINE
import app.transkey.mobile.BubbleService.Companion.MODE_REPLY
import app.transkey.mobile.BubbleService.Companion.MODE_TRANSLATE
import app.transkey.mobile.BubbleService.Companion.STATE_ERROR
import app.transkey.mobile.BubbleService.Companion.STATE_IDLE
import app.transkey.mobile.BubbleService.Companion.STATE_LOADING
import app.transkey.mobile.BubbleService.Companion.STATE_RESULT

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

internal fun BubbleService.showResult(
    output: String,
    romanization: String?,
    detectedLang: String?,
    suggestions: List<Pair<String, String>>? = null,
) {
    isTranslating = false
    currentOutput = output
    currentRomanization = romanization
    currentDetectedLang = detectedLang
    currentSuggestions = suggestions ?: emptyList()
    // Save context for Reply mode (only for non-reply translations)
    if (currentMode != MODE_REPLY) {
        lastOriginalText = currentSourceText
        lastDetectedLang = detectedLang
    }
    // Refine mode: the output IS the improved source text — replace the
    // source so the user can translate or refine again on the improved text.
    if (currentMode == MODE_REFINE) {
        currentSourceText = output
    }
    showResultPanel(loading = false, error = null, output = output)
}

internal fun BubbleService.showError(error: String) {
    isTranslating = false
    showResultPanel(loading = false, error = error)
}

@SuppressLint("ClickableViewAccessibility")
internal fun BubbleService.showResultPanel(
    loading: Boolean,
    error: String?,
    output: String? = null,
) {
    val service: BubbleService = this
    ensureWindowManager()
    refreshLocale()
    // Keep the bubble fully on-screen while the result panel is up —
    // otherwise it sits half-hidden against the edge under the panel,
    // which looks broken when the panel closes and we re-anchor.
    cancelBubbleHalfHide()
    snapBubbleToEdge(resources.displayMetrics.density, halfHidden = false)
    val style = BubbleStyle.of(this)
    val dp = style.dp
    val isDark = style.isDark
    val bg = style.bg
    val textCol = style.text
    val mutedCol = style.muted
    val accent = style.accent

    if (panel.view == null) {
        val rootCard = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            // Layered background: 3dp brand-gradient strip across the top
            // (visible only above the inset bg layer) + solid surface fill
            // below. Mirrors the ResultCard top-accent strip in
            // lib/.../widgets/result_card.dart so popup + app share the
            // same brand affordance.
            val stripPx = (3 * dp).toInt()
            val cornerR = 18 * dp
            val gradientLayer = GradientDrawable().apply {
                colors = intArrayOf(Palette.ACCENT, Palette.ACCENT_END)
                orientation = GradientDrawable.Orientation.LEFT_RIGHT
                cornerRadius = cornerR
            }
            val bgLayer = GradientDrawable().apply {
                setColor(bg)
                cornerRadii = floatArrayOf(
                    0f, 0f,            // top-left
                    0f, 0f,            // top-right
                    cornerR, cornerR,  // bottom-right
                    cornerR, cornerR,  // bottom-left
                )
            }
            background = android.graphics.drawable.LayerDrawable(
                arrayOf(gradientLayer, bgLayer)
            ).apply { setLayerInset(1, 0, stripPx, 0, 0) }
            elevation = 12 * dp
            setPadding(
                (16 * dp).toInt(),
                (14 * dp).toInt() + stripPx,
                (16 * dp).toInt(),
                (14 * dp).toInt(),
            )
        }

        // Header: [source chip] → [target chip]  [spacer]  [tone chip]  [✕]
        val header = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
        }

        fun chipBackground(selected: Boolean) = GradientDrawable().apply {
            setColor(if (selected) accent else Color.TRANSPARENT)
            setStroke(1, accent)
            cornerRadius = 12 * dp
        }

        panel.sourceLangChip = TextView(this).apply {
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 11f)
            typeface = Typeface.DEFAULT_BOLD
            setTextColor(accent)
            setPadding((8 * dp).toInt(), (4 * dp).toInt(), (8 * dp).toInt(), (4 * dp).toInt())
            background = chipBackground(false)
            setOnClickListener { showSourceLangPicker() }
        }

        val arrowTv = TextView(this).apply {
            text = " → "
            setTextColor(mutedCol)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 12f)
        }

        panel.langChip = TextView(this).apply {
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 11f)
            typeface = Typeface.DEFAULT_BOLD
            setTextColor(accent)
            setPadding((8 * dp).toInt(), (4 * dp).toInt(), (8 * dp).toInt(), (4 * dp).toInt())
            background = chipBackground(false)
            setOnClickListener { showLangPicker() }
        }

        val spacer = View(this).apply {
            layoutParams = LinearLayout.LayoutParams(0, 1, 1f)
        }

        // Uniform header-icon factory: every header button is a 36dp
        // square with the same padding, gravity, and margin so the
        // ⚙ / ✎ / ⤢ / ✕ row reads as a single coherent group
        // rather than a settings icon next to three text glyphs of
        // varying widths.
        val iconSize = (36 * dp).toInt()
        val iconMargin = (2 * dp).toInt()
        fun headerIconParams() = LinearLayout.LayoutParams(iconSize, iconSize).apply {
            marginStart = iconMargin; marginEnd = iconMargin
        }
        fun headerTextIcon(glyph: String, sizeSp: Float = 18f, onClick: () -> Unit): TextView =
            TextView(this).apply {
                text = glyph
                setTextColor(mutedCol)
                setTextSize(TypedValue.COMPLEX_UNIT_SP, sizeSp)
                typeface = Typeface.DEFAULT_BOLD
                gravity = Gravity.CENTER
                isClickable = true
                isFocusable = true
                setOnClickListener { onClick() }
                layoutParams = headerIconParams()
            }

        panel.toneChip = ImageView(this).apply {
            setImageResource(R.drawable.ic_bubble_settings)
            setColorFilter(mutedCol)
            contentDescription = localized(R.string.bubble_settings)
            setPadding((9 * dp).toInt(), (9 * dp).toInt(), (9 * dp).toInt(), (9 * dp).toInt())
            isClickable = true
            isFocusable = true
            setOnClickListener { showSettingsSheet() }
            layoutParams = headerIconParams()
        }

        val typeBtn = headerTextIcon("✎") {
            hideResultPanel()
            showInputPicker(currentMode)
        }.apply { contentDescription = localized(R.string.bubble_type_text) }

        // Switched from text-glyph TextView ("⤢" / "⤡") to a vector
        // drawable because the diagonal-arrow Unicode glyphs render
        // visually thinner than ✎ / ✕ on most fonts and broke the
        // even-weight header row. Vector renders consistently at the
        // same visual weight as ⚙ (settings) next door.
        val fullscreenBtn = ImageView(this).apply {
            setImageResource(
                if (panel.fullscreen) R.drawable.ic_bubble_fullscreen_exit
                else R.drawable.ic_bubble_fullscreen,
            )
            setColorFilter(mutedCol)
            setPadding((9 * dp).toInt(), (9 * dp).toInt(), (9 * dp).toInt(), (9 * dp).toInt())
            isClickable = true
            isFocusable = true
            layoutParams = headerIconParams()
            setOnClickListener {
                panel.fullscreen = !panel.fullscreen
                panel.heightPx = 0
                setImageResource(
                    if (panel.fullscreen) R.drawable.ic_bubble_fullscreen_exit
                    else R.drawable.ic_bubble_fullscreen,
                )
                applyPanelLayoutMode()
                panel.view?.let { v ->
                    try { windowManager?.updateViewLayout(v, buildPanelLayoutParams()) }
                    catch (e: Exception) {
                        android.util.Log.w("TKBubble", "panel fullscreen toggle failed: ${e.message}")
                    }
                }
            }
        }
        panel.fullscreenBtn = fullscreenBtn

        val closeBtn = headerTextIcon("✕") { hideResultPanel() }

        header.addView(panel.sourceLangChip)
        header.addView(arrowTv)
        header.addView(panel.langChip)
        header.addView(spacer)
        header.addView(panel.toneChip)
        header.addView(typeBtn)
        header.addView(fullscreenBtn)
        header.addView(closeBtn)

        // Mode tabs — column style matching the bubble picker
        // (LinearLayout VERTICAL with icon on top + label below,
        // weight=1 across the row so all 5 columns are equal width).
        // No more HorizontalScrollView since equal columns fit in the
        // panel width by design.
        val tabsRow = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER
            setPadding(0, (8 * dp).toInt(), 0, (4 * dp).toInt())
        }
        panel.modeButtons.clear()
        ALL_MODES.forEachIndexed { index, mode ->
            val container = LinearLayout(this).apply {
                orientation = LinearLayout.VERTICAL
                gravity = Gravity.CENTER
                setPadding((4 * dp).toInt(), (8 * dp).toInt(), (4 * dp).toInt(), (8 * dp).toInt())
                isClickable = true
                isFocusable = true
                setOnClickListener {
                    if (isTranslating) return@setOnClickListener
                    // Translate tab is the panel's primary entry — users
                    // expect tapping it to translate THE LATEST CLIPBOARD,
                    // not re-translate the previous source (the "I copied
                    // new text but still see the old translation" bug).
                    // Route through ShareActivity like the bubble menu so a
                    // fresh primaryClip read happens with focus. The other
                    // tabs (Reply / Summarize / Explain / Refine) keep the
                    // "switch mode on the same text" behaviour — that's the
                    // useful follow-up flow after a translation.
                    if (mode == MODE_TRANSLATE) {
                        onTranslateModePicked(mode)
                        return@setOnClickListener
                    }
                    val src = currentSourceText ?: return@setOnClickListener
                    handleTranslateRequest(src, mode)
                }
                layoutParams = LinearLayout.LayoutParams(
                    0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f,
                ).apply {
                    marginEnd = if (index < ALL_MODES.size - 1) (4 * dp).toInt() else 0
                }
            }
            val iconView = ImageView(this).apply {
                setImageResource(modeIcon(mode))
                layoutParams = LinearLayout.LayoutParams(
                    (18 * dp).toInt(), (18 * dp).toInt(),
                )
            }
            val labelView = TextView(this).apply {
                text = modeLabel(mode)
                setTextSize(TypedValue.COMPLEX_UNIT_SP, 10f)
                gravity = Gravity.CENTER
                maxLines = 1
                setSingleLine(true)
                ellipsize = android.text.TextUtils.TruncateAt.END
                typeface = Typeface.DEFAULT_BOLD
                setPadding(0, (4 * dp).toInt(), 0, 0)
                layoutParams = LinearLayout.LayoutParams(
                    LinearLayout.LayoutParams.MATCH_PARENT,
                    LinearLayout.LayoutParams.WRAP_CONTENT,
                )
            }
            container.addView(iconView)
            container.addView(labelView)
            panel.modeButtons[mode] = PanelModeTab(container, iconView, labelView)
            tabsRow.addView(container)
        }

        // ── Scrollable content area ──
        panel.detectedLangTv = TextView(this).apply {
            setTextColor(mutedCol)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 10f)
            setTypeface(Typeface.DEFAULT, Typeface.ITALIC)
            visibility = View.GONE
            setPadding(0, (6 * dp).toInt(), 0, 0)
        }

        panel.source = TextView(this).apply {
            setTextColor(mutedCol)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 12f)
            maxLines = 3
            ellipsize = android.text.TextUtils.TruncateAt.END
            setPadding(0, (4 * dp).toInt(), 0, (4 * dp).toInt())
            isClickable = true
            isFocusable = true
            setOnClickListener { togglePanelSourceExpanded() }
        }
        // Tiny "Show more / Show less" affordance under the source —
        // makes the tap target discoverable without crowding the
        // header chip row. Hidden when source text fits in 3 lines.
        panel.sourceToggle = TextView(this).apply {
            setTextColor(accent)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 11f)
            typeface = Typeface.DEFAULT_BOLD
            setPadding(0, 0, 0, (4 * dp).toInt())
            visibility = View.GONE
            isClickable = true
            isFocusable = true
            setOnClickListener { togglePanelSourceExpanded() }
        }

        panel.output = TextView(this).apply {
            setTextColor(textCol)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 16f)
            typeface = Typeface.DEFAULT_BOLD
            setLineSpacing(2 * dp, 1f)
            setPadding(0, (4 * dp).toInt(), 0, (4 * dp).toInt())
        }

        panel.romanization = TextView(this).apply {
            setTextColor(mutedCol)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 13f)
            setTypeface(Typeface.DEFAULT, Typeface.ITALIC)
            visibility = View.GONE
            setPadding(0, 0, 0, (4 * dp).toInt())
        }

        // ── Quick-reply suggestions (Reply mode + suggestions toggle) ──
        panel.suggestionsLabel = TextView(this).apply {
            text = localized(R.string.bubble_reply_suggestions).uppercase()
            setTextColor(mutedCol)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 10f)
            typeface = Typeface.DEFAULT_BOLD
            letterSpacing = 0.08f
            visibility = View.GONE
            setPadding(0, (10 * dp).toInt(), 0, (4 * dp).toInt())
        }
        panel.suggestionsContainer = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            visibility = View.GONE
        }

        // Loading spinner — shown while waiting for API response
        panel.loadingSpinner = ProgressBar(this, null, android.R.attr.progressBarStyleSmall).apply {
            isIndeterminate = true
            visibility = View.GONE
            layoutParams = LinearLayout.LayoutParams(
                (24 * dp).toInt(), (24 * dp).toInt(),
            ).apply { topMargin = (8 * dp).toInt(); bottomMargin = (4 * dp).toInt() }
        }

        panel.status = TextView(this).apply {
            setTextColor(mutedCol)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 12f)
            setPadding(0, (4 * dp).toInt(), 0, (4 * dp).toInt())
        }

        // All the above wrapped in a max-height ScrollView so long translations scroll
        val contentInner = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
        }
        contentInner.addView(panel.detectedLangTv)
        contentInner.addView(panel.source)
        panel.sourceToggle?.let { contentInner.addView(it) }
        contentInner.addView(panel.loadingSpinner)
        contentInner.addView(panel.output)
        contentInner.addView(panel.romanization)
        contentInner.addView(panel.suggestionsLabel)
        contentInner.addView(panel.suggestionsContainer)
        contentInner.addView(panel.status)

        val contentScroll = object : ScrollView(service) {
            override fun onMeasure(widthSpec: Int, heightSpec: Int) {
                // Cap height in default mode so a long translation doesn't
                // make the floating panel taller than the screen. When the
                // user has resized or fullscreen'd the panel, let it
                // expand to the parent's fixed height instead.
                if (panel.fullscreen || panel.heightPx > 0) {
                    super.onMeasure(widthSpec, heightSpec)
                } else {
                    val maxPx = (220 * resources.displayMetrics.density).toInt()
                    super.onMeasure(widthSpec, MeasureSpec.makeMeasureSpec(maxPx, MeasureSpec.AT_MOST))
                }
            }
        }.apply {
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT,
            ).apply { topMargin = (4 * dp).toInt() }
            addView(contentInner)
        }
        panel.contentScroll = contentScroll

        // Action buttons row (TTS + Copy)
        val actionsRow = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT,
            ).apply { topMargin = (10 * dp).toInt() }
        }

        // Uniform action-row buttons: all three (TTS / Copy / Paste)
        // share the same weight, vertical padding, corner radius, and
        // text size so the row reads as a single coherent group —
        // matching the bubble's mode-picker columns where every entry
        // is the same size.
        fun actionRowParams(marginStart: Int = 0): LinearLayout.LayoutParams =
            LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f)
                .apply { this.marginStart = marginStart }

        panel.ttsBtn = TextView(this).apply {
            text = "▶"
            setTextColor(accent)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 13f)
            typeface = Typeface.DEFAULT_BOLD
            gravity = Gravity.CENTER
            background = GradientDrawable().apply {
                setColor(Color.TRANSPARENT)
                setStroke(1, accent)
                cornerRadius = 10 * dp
            }
            setPadding(0, (10 * dp).toInt(), 0, (10 * dp).toInt())
            setOnClickListener { speakOutput() }
            layoutParams = actionRowParams()
        }

        panel.copyBtn = TextView(this).apply {
            text = localized(R.string.bubble_panel_copy)
            setTextColor(Color.WHITE)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 13f)
            typeface = Typeface.DEFAULT_BOLD
            gravity = Gravity.CENTER
            background = GradientDrawable().apply {
                setColor(accent)
                cornerRadius = 10 * dp
            }
            setPadding(0, (10 * dp).toInt(), 0, (10 * dp).toInt())
            setOnClickListener {
                val t = currentOutput
                if (!t.isNullOrEmpty()) {
                    val cm = getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
                    cm.setPrimaryClip(ClipData.newPlainText("TransKey", t))
                    Toast.makeText(service, localized(R.string.bubble_panel_copied), Toast.LENGTH_SHORT).show()
                    hideResultPanel()
                }
            }
            layoutParams = actionRowParams(marginStart = (8 * dp).toInt())
        }

        panel.pasteBtn = TextView(this).apply {
            text = "↓ ${localized(R.string.bubble_panel_paste)}"
            setTextColor(Color.WHITE)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 13f)
            typeface = Typeface.DEFAULT_BOLD
            gravity = Gravity.CENTER
            background = GradientDrawable().apply {
                setColor(Color.parseColor("#16a34a"))
                cornerRadius = 10 * dp
            }
            setPadding(0, (10 * dp).toInt(), 0, (10 * dp).toInt())
            visibility = View.GONE
            setOnClickListener {
                val t = currentOutput
                if (t.isNullOrEmpty()) return@setOnClickListener
                val svc = TransKeyAccessibilityService.instance
                if (svc == null) {
                    Toast.makeText(
                        service,
                        localized(R.string.bubble_panel_paste_a11y_off),
                        Toast.LENGTH_LONG,
                    ).show()
                    return@setOnClickListener
                }
                // Always copy to clipboard first so the user has a manual
                // fallback even if accessibility paste fails (e.g. the
                // host app blocks SET_TEXT and PASTE — banking apps do).
                try {
                    val cm = getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
                    cm.setPrimaryClip(ClipData.newPlainText("TransKey", t))
                } catch (_: Exception) { /* clipboard may be locked on some OEMs */ }

                // Hide panel first so it doesn't sit over the input, then
                // replace the focused text in the host app. The 300ms delay
                // gives the underlying app time to recover input focus —
                // shorter delays caused silent failures on Compose / RN
                // apps that briefly drop focus when an overlay disappears.
                hideResultPanel()
                handler.postDelayed({
                    val ok = svc.replaceFocusedText(t)
                    if (ok) {
                        Toast.makeText(
                            service,
                            localized(R.string.bubble_panel_pasted),
                            Toast.LENGTH_SHORT,
                        ).show()
                    } else {
                        Toast.makeText(
                            service,
                            localized(R.string.bubble_panel_paste_manual_fallback),
                            Toast.LENGTH_LONG,
                        ).show()
                    }
                }, 300)
            }
            layoutParams = actionRowParams(marginStart = (8 * dp).toInt())
        }

        actionsRow.addView(panel.ttsBtn)
        actionsRow.addView(panel.copyBtn)
        actionsRow.addView(panel.pasteBtn)

        // Reply-only a11y warning. Visible only when MODE_REPLY is the
        // active mode AND TransKey accessibility service is OFF. Lets
        // the user jump straight into the permission walkthrough so
        // the disabled Paste button becomes usable.
        val hintBg = if (isDark) Color.parseColor("#3A2E10") else Color.parseColor("#FFF6D6")
        val hintFg = if (isDark) Color.parseColor("#FFD86E") else Color.parseColor("#7A5A00")
        val hintBtnBg = if (isDark) Color.parseColor("#FFD86E") else Color.parseColor("#7A5A00")
        val hintBtnFg = if (isDark) Color.parseColor("#3A2E10") else Color.WHITE
        val warningView = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            background = GradientDrawable().apply {
                setColor(hintBg)
                cornerRadius = 10 * dp
            }
            setPadding((10 * dp).toInt(), (8 * dp).toInt(), (10 * dp).toInt(), (8 * dp).toInt())
            visibility = View.GONE
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT,
            ).apply { topMargin = (8 * dp).toInt() }
        }
        warningView.addView(TextView(this).apply {
            text = localized(R.string.bubble_paste_a11y_required)
            setTextColor(hintFg)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 11f)
            layoutParams = LinearLayout.LayoutParams(
                0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f,
            )
        })
        warningView.addView(TextView(this).apply {
            text = localized(R.string.bubble_accessibility_enable)
            setTextColor(hintBtnFg)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 11f)
            typeface = Typeface.DEFAULT_BOLD
            background = GradientDrawable().apply {
                setColor(hintBtnBg)
                cornerRadius = 8 * dp
            }
            setPadding((10 * dp).toInt(), (6 * dp).toInt(), (10 * dp).toInt(), (6 * dp).toInt())
            isClickable = true
            isFocusable = true
            setOnClickListener {
                hideResultPanel()
                val intent = Intent(service, MainActivity::class.java).apply {
                    action = MainActivity.ACTION_OPEN_PERMISSIONS
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP)
                }
                try { startActivity(intent) } catch (_: Exception) {}
            }
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.WRAP_CONTENT,
                LinearLayout.LayoutParams.WRAP_CONTENT,
            ).apply { marginStart = (8 * dp).toInt() }
        })
        panel.a11yWarning = warningView

        // Bottom resize handle: drag to make the panel taller. A thin
        // bar centered horizontally; touch radius is the full bottom
        // strip of the card so users don't have to aim precisely.
        val resizeHandle = FrameLayout(this).apply {
            setPadding(0, (6 * dp).toInt(), 0, (4 * dp).toInt())
            addView(View(service).apply {
                background = GradientDrawable().apply {
                    setColor(mutedCol)
                    cornerRadius = 2 * dp
                }
                alpha = 0.5f
                layoutParams = FrameLayout.LayoutParams(
                    (40 * dp).toInt(), (3 * dp).toInt(), Gravity.CENTER,
                )
            })
            isClickable = true
            isFocusable = false
            var dragStartY = 0f
            var dragStartHeight = 0
            setOnTouchListener { _, ev ->
                val v = panel.view ?: return@setOnTouchListener false
                val lp = v.layoutParams as? WindowManager.LayoutParams
                    ?: return@setOnTouchListener false
                when (ev.action) {
                    MotionEvent.ACTION_DOWN -> {
                        dragStartY = ev.rawY
                        // Snapshot CURRENT height — WRAP_CONTENT resolves
                        // to the actual measured height, which we need as
                        // the baseline for the drag delta.
                        dragStartHeight = if (lp.height > 0) lp.height else v.height
                        true
                    }
                    MotionEvent.ACTION_MOVE -> {
                        val dy = (ev.rawY - dragStartY).toInt()
                        val newHeight = (dragStartHeight + dy).coerceAtLeast((120 * dp).toInt())
                        panel.heightPx = newHeight
                        panel.fullscreen = false
                        applyPanelLayoutMode()
                        try {
                            windowManager?.updateViewLayout(v, buildPanelLayoutParams())
                        } catch (_: Exception) {}
                        true
                    }
                    MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> true
                    else -> false
                }
            }
        }

        rootCard.addView(header)
        rootCard.addView(tabsRow)
        rootCard.addView(contentScroll)
        rootCard.addView(actionsRow)
        warningView.let { rootCard.addView(it) }
        rootCard.addView(resizeHandle)

        panel.view = rootCard
        windowManager?.addView(rootCard, buildPanelLayoutParams())
    }

    // Update content
    panel.source?.text = currentSourceText ?: ""
    refreshPanelSourceToggle()
    updateModeTabs(accent, mutedCol)
    updateLangChip()

    // Detected lang only shown in result/error state, not while loading
    val detected = currentDetectedLang
    if (!loading && !detected.isNullOrBlank()) {
        panel.detectedLangTv?.apply {
            text = (localizedContext ?: service).getString(
                R.string.bubble_panel_detected,
                getEffectiveLangLabels()[detected] ?: detected.uppercase(),
            )
            visibility = View.VISIBLE
        }
    } else {
        panel.detectedLangTv?.visibility = View.GONE
    }

    // Romanization shown only when output is shown and value present
    val rom = currentRomanization
    if (!loading && error == null && !rom.isNullOrBlank()) {
        panel.romanization?.apply { text = rom; visibility = View.VISIBLE }
    } else {
        panel.romanization?.visibility = View.GONE
    }

    // Quick-reply suggestions: only on the plain Translate flow. Reply
    // mode already produces one targeted reply (the whole point of that
    // mode), so showing more alternatives there would be noise; the
    // user wanted suggestions surfaced alongside translation, not reply.
    // Refine/Summarize/Explain aren't conversation contexts at all.
    val suggestions = currentSuggestions
    val showSuggestions = !loading && error == null && suggestions.isNotEmpty() &&
        currentMode == MODE_TRANSLATE
    if (showSuggestions) {
        panel.suggestionsLabel?.visibility = View.VISIBLE
        panel.suggestionsContainer?.apply {
            removeAllViews()
            visibility = View.VISIBLE
            val borderCol = Color.parseColor(if (isDark) "#3A3A52" else "#DDDDF0")
            val accentCol = Palette.ACCENT
            suggestions.forEachIndexed { idx, pair ->
                val (sourceText, targetText) = pair
                val chip = LinearLayout(service).apply {
                    orientation = LinearLayout.VERTICAL
                    // Order matters: set background BEFORE padding so the
                    // GradientDrawable doesn't reset the padding we want.
                    background = GradientDrawable().apply {
                        setColor(Color.TRANSPARENT)
                        setStroke(1, borderCol)
                        cornerRadius = 12 * dp
                    }
                    setPadding(
                        (12 * dp).toInt(), (8 * dp).toInt(),
                        (12 * dp).toInt(), (8 * dp).toInt(),
                    )
                    isClickable = true
                    isFocusable = true
                    // Source = the actual reply to send (partner's lang).
                    if (sourceText.isNotEmpty()) {
                        addView(TextView(service).apply {
                            text = sourceText
                            setTextColor(textCol)
                            setTextSize(TypedValue.COMPLEX_UNIT_SP, 14f)
                            typeface = Typeface.DEFAULT_BOLD
                        })
                    }
                    // Target = same idea in user's language, as a hint.
                    if (targetText.isNotEmpty() && targetText != sourceText) {
                        addView(TextView(service).apply {
                            text = targetText
                            setTextColor(mutedCol)
                            setTextSize(TypedValue.COMPLEX_UNIT_SP, 12f)
                            setTypeface(Typeface.DEFAULT, Typeface.ITALIC)
                            setPadding(0, (2 * dp).toInt(), 0, 0)
                        })
                    }
                    setOnClickListener {
                        val toCopy = sourceText.ifEmpty { targetText }
                        val cm = getSystemService(Context.CLIPBOARD_SERVICE) as android.content.ClipboardManager
                        cm.setPrimaryClip(android.content.ClipData.newPlainText("suggestion", toCopy))
                        // Brief filled-accent flash so the tap registers
                        // visibly even when Toasts get suppressed on some
                        // OEMs (Xiaomi/Huawei restrict overlay Toasts).
                        background = GradientDrawable().apply {
                            setColor(accentCol)
                            cornerRadius = 12 * dp
                        }
                        handler.postDelayed({
                            background = GradientDrawable().apply {
                                setColor(Color.TRANSPARENT)
                                setStroke(1, borderCol)
                                cornerRadius = 12 * dp
                            }
                        }, 240)
                        Toast.makeText(service, localized(R.string.bubble_panel_copied), Toast.LENGTH_SHORT).show()
                    }
                    layoutParams = LinearLayout.LayoutParams(
                        LinearLayout.LayoutParams.MATCH_PARENT,
                        LinearLayout.LayoutParams.WRAP_CONTENT,
                    ).apply {
                        if (idx > 0) topMargin = (6 * dp).toInt()
                    }
                }
                addView(chip)
            }
        }
    } else {
        panel.suggestionsLabel?.visibility = View.GONE
        panel.suggestionsContainer?.apply {
            visibility = View.GONE
            removeAllViews()
        }
    }

    if (loading) {
        panel.output?.visibility = View.GONE
        panel.status?.visibility = View.GONE
        panel.loadingSpinner?.visibility = View.VISIBLE
        panel.copyBtn?.visibility = View.GONE
        panel.ttsBtn?.visibility = View.GONE
        panel.pasteBtn?.visibility = View.GONE
        panel.a11yWarning?.visibility = View.GONE
        // Dim mode tabs to signal busy state
        for ((_, tab) in panel.modeButtons) {
            tab.container.alpha = 0.35f
            tab.container.isEnabled = false
        }
        setState(STATE_LOADING)
    } else if (error != null) {
        panel.loadingSpinner?.visibility = View.GONE
        panel.output?.visibility = View.GONE
        panel.status?.apply { text = error; visibility = View.VISIBLE }
        panel.copyBtn?.visibility = View.GONE
        panel.ttsBtn?.visibility = View.GONE
        panel.pasteBtn?.visibility = View.GONE
        panel.a11yWarning?.visibility = View.GONE
        for ((_, tab) in panel.modeButtons) { tab.container.alpha = 1f; tab.container.isEnabled = true }
        setState(STATE_ERROR)
    } else if (output != null) {
        panel.loadingSpinner?.visibility = View.GONE
        panel.output?.apply { text = output; visibility = View.VISIBLE }
        panel.status?.visibility = View.GONE
        panel.copyBtn?.visibility = View.VISIBLE
        panel.ttsBtn?.visibility = View.VISIBLE
        // Paste only makes sense for Reply mode. In Reply mode, if
        // accessibility is OFF the button is greyed out and the
        // warning banner below the action row prompts the user to
        // enable it. Other modes don't expose Paste at all.
        val isReply = currentMode == MODE_REPLY
        val a11yOn = TransKeyAccessibilityService.isAvailable()
        panel.pasteBtn?.visibility = if (isReply) View.VISIBLE else View.GONE
        panel.pasteBtn?.isEnabled = isReply && a11yOn
        panel.pasteBtn?.alpha = if (isReply && !a11yOn) 0.4f else 1f
        panel.a11yWarning?.visibility =
            if (isReply && !a11yOn) View.VISIBLE else View.GONE
        for ((_, tab) in panel.modeButtons) { tab.container.alpha = 1f; tab.container.isEnabled = true }
        setState(STATE_RESULT)
    }
}

internal fun BubbleService.updateLangChip() {
    // Refine mode: source/target langs are still shown so the user can
    // verify or change them before translating the refined text.
    // Tone chip stays visible too (users adjust TTS / tone here).

    // Note: do NOT re-read prefs here. The chips must reflect the lang
    // and tone that were used for the *currently displayed result* —
    // these values are set in handleTranslateRequest before each
    // translate call. Re-reading would clobber the reply-mode override
    // (where currentTargetLang = readReplyLang(), not readTargetLang()).
    // Picker freshness is handled separately in showLangPicker /
    // showTonePicker / showSourceLangPicker.

    // Source chip: show "Auto" or language name
    val chipLabels = getEffectiveLangLabels()
    panel.sourceLangChip?.apply {
        visibility = View.VISIBLE
        text = if (currentSourceLang == "auto") "Auto"
               else (chipLabels[currentSourceLang] ?: currentSourceLang.uppercase())
    }

    // Target chip
    panel.langChip?.apply {
        visibility = View.VISIBLE
        text = chipLabels[currentTargetLang] ?: currentTargetLang.uppercase()
    }

    // Settings icon (formerly tone chip): always visible. The icon alone
    // carries the affordance — the actual tone shows up inside the
    // settings sheet, so we don't need a per-state label here.
    panel.toneChip?.visibility = View.VISIBLE
}

internal fun BubbleService.updateModeTabs(accent: Int, mutedCol: Int) {
    val style = BubbleStyle.of(this)
    val dp = style.dp
    val subduedBg = Color.parseColor(if (style.isDark) "#2A2A40" else "#F0EFFF")
    for ((mode, tab) in panel.modeButtons) {
        val isActive = mode == currentMode
        val fg = if (isActive) Color.WHITE else accent
        tab.container.background = GradientDrawable().apply {
            if (isActive) {
                // Active tab uses the brand gradient (#6366F1 → #A855F7)
                // so the popup matches the in-app FeatureButtons primary.
                colors = intArrayOf(Palette.ACCENT, Palette.ACCENT_END)
                orientation = GradientDrawable.Orientation.TL_BR
            } else {
                setColor(subduedBg)
            }
            cornerRadius = 14 * dp
        }
        tab.label.setTextColor(fg)
        tab.icon.setColorFilter(fg)
    }
}

// buildPanelLayoutParams moved to ResultPanelExtensions.kt

internal fun BubbleService.hideResultPanel() {
    isTranslating = false
    // Reset resize state so the next panel starts at default geometry
    // — otherwise a previous "drag to expand" or fullscreen toggle
    // would leak into an unrelated translation.
    panel.heightPx = 0
    panel.fullscreen = false
    panel.fullscreenBtn = null
    panel.contentScroll = null
    panel.sourceExpanded = false
    panel.sourceToggle = null
    removeResultPanel()
    setState(STATE_IDLE)
    // Result panel just closed — settle the bubble back into its
    // half-hidden idle posture against the screen edge.
    scheduleBubbleHalfHide(resources.displayMetrics.density)
}
