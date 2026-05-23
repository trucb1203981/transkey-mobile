package app.transkey.mobile

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Rect
import android.graphics.RectF
import android.text.Layout
import android.text.StaticLayout
import android.text.TextPaint
import android.util.TypedValue
import android.view.GestureDetector
import android.view.MotionEvent
import android.view.View
import kotlin.math.max
import kotlin.math.min

/**
 * Google-Lens-style translation overlay. Renders the captured screenshot
 * full-screen, then for every recognised text block paints a white
 * rectangle over the original text and draws the translated text on top,
 * auto-fitted to the same bounding box.
 *
 * Two visual states per block:
 *   - default: translation visible, original hidden
 *   - tapped:  translation hidden, original screenshot visible (for the
 *              tapped block only — others stay translated). Tap again to
 *              flip back.
 *
 * Tap outside any block → caller dismisses via the supplied callback.
 */
@SuppressLint("ViewConstructor")
class LensOverlayView(
    context: Context,
    private val screenshot: Bitmap,
    initialItems: List<Item>,
    private val onDismissOutsideTap: () -> Unit,
    /// Long-press on a block opens the "What is this?" explain sheet for
    /// that block's original (source) text. Caller is responsible for
    /// dismissing the overlay + bringing the Flutter activity foreground.
    /// Null skips the long-press feature entirely.
    private val onLongPressBlock: ((String) -> Unit)? = null,
    /// Single tap on a block opens a readable popup with the FULL
    /// translation + original text. In-place chips stay size-bounded for a
    /// clean overlay, but long CJK→Latin translations that don't fit the
    /// chip are never lost — the user taps to read the whole thing.
    private val onBlockTap: ((original: String, translation: String) -> Unit)? = null,
) : View(context) {

    data class Item(val original: String, val translation: String, val bounds: Rect)

    /// Mutable so chunks can patch translations in place as they arrive
    /// from the server (progressive emit). Bounds + count never change
    /// after construction — only [Item.translation] gets swapped.
    private val items: MutableList<Item> = initialItems.toMutableList()

    /// Bridges Android's long-press recognizer to [onLongPressBlock]. We
    /// keep the existing onTouchEvent (single-tap toggle) intact and just
    /// forward events to the gesture detector for the long-press signal.
    private val gestureDetector = GestureDetector(
        context,
        object : GestureDetector.SimpleOnGestureListener() {
            override fun onLongPress(event: MotionEvent) {
                val callback = onLongPressBlock ?: return
                val idx = findItemIndexAt(event.x, event.y)
                if (idx < 0) return
                callback(items[idx].original)
            }
        },
    )

    private val whitePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.WHITE
        style = Paint.Style.FILL
    }
    // Background for chips still waiting on their translation. Amber tint
    // tells the user "this one is in flight" so the source-text placeholder
    // doesn't look like a translation failure.
    private val pendingPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.parseColor("#FFF3CD")
        style = Paint.Style.FILL
    }
    private val borderPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.parseColor("#33000000")
        style = Paint.Style.STROKE
        strokeWidth = context.resources.displayMetrics.density * 0.5f
    }
    private val textPaint = TextPaint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.parseColor("#1A1A2E")
        textAlign = Paint.Align.LEFT
    }
    // "Đang dịch X/Y" progress pill — painted at the top of the overlay
    // while any chunk is still in flight; dropped once every slot has
    // been processed.
    private val progressBgPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.parseColor("#E61A1A2E")
        style = Paint.Style.FILL
    }
    private val progressTextPaint = TextPaint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.WHITE
        textAlign = Paint.Align.CENTER
        textSize = context.resources.displayMetrics.density * 13f
    }

    // Per-item "translation arrived from the server" flag. Starts false
    // (every chip begins as a placeholder showing its source text). Set
    // true by [applyTranslations] for every slot the server has spoken
    // for — independent of whether the answer differs from the original
    // (a no-op answer for a slot with garbage OCR still counts as
    // processed so we don't keep painting it amber forever).
    private val processed = BooleanArray(items.size)
    private var processedCount: Int = 0

    // Source-mismatch banner. Set via [showSourceMismatch] when the
    // server reports the pinned source language disagrees with the
    // detected script. Tapping it re-runs the translation with the
    // detected language. [mismatchBannerRect] is the last-painted hit
    // box, recomputed every frame the banner is visible.
    private var mismatchLabel: String? = null
    private var onMismatchTap: (() -> Unit)? = null
    private val mismatchBannerRect = RectF()
    private val mismatchBgPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.parseColor("#F0B45309")
        style = Paint.Style.FILL
    }
    private val mismatchTextPaint = TextPaint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.WHITE
        textAlign = Paint.Align.CENTER
        textSize = context.resources.displayMetrics.density * 13f
    }

    // Cached StaticLayouts indexed by item position — built lazily inside
    // onDraw, invalidated whenever the toggle flips.
    private val layoutCache = arrayOfNulls<StaticLayout>(items.size)
    private val sizeCache = FloatArray(items.size)  // text size used per item

    /**
     * Vertically-grown rect for items where the translation doesn't fit
     * inside the original OCR box at a readable text size. Indexed same as
     * [items]; null means "use original bounds".
     *
     * Translations from CJK → Latin commonly take 2-3x the original height
     * because Japanese/Chinese pack ~4-6 chars per word while Vietnamese
     * spells those out into multiple Latin words. Shrinking to fit was
     * making text unreadable (sub-9sp clipped at MIN_SP) and the
     * single-line ellipsis hid most of the translation. Growing downward
     * preserves the original anchor point (top-left of the OCR block) so
     * the visual association with the source text stays intact while the
     * full translation is actually visible.
     */
    private val expandedRect = arrayOfNulls<RectF>(items.size)

    /**
     * Per-item bitmap-space upper bound on how tall the expanded white
     * card may grow before it would crash into the next OCR block in the
     * same column. Computed once in [computeExpansionLimits] and reused
     * every frame; cleared when the toggle invalidates the cache.
     *
     * The expand-downward behaviour without this limit was painting CJK→
     * Latin translations on top of the NEXT message's translation, so
     * users saw two stacked lens cards in the same screen region (the
     * lower one's text peeked out from under the upper one's bottom edge).
     */
    private val maxExpandPxBmp = IntArray(items.size)

    private val srcDrawDest = RectF()  // reused per draw call

    init {
        setBackgroundColor(Color.parseColor("#CC000000"))
        isClickable = true
        computeExpansionLimits()
    }

    /**
     * Progressive emit hook: replace the translations for the slice
     * `[startIdx, startIdx + newTranslations.size)` in place. Bounds /
     * count don't change, so [computeExpansionLimits] stays valid; only
     * the layout caches for the patched slots are invalidated so the
     * next [onDraw] re-measures and re-paints them with the real text.
     *
     * MUST be called on the UI thread (the View owns the caches).
     */
    fun applyTranslations(startIdx: Int, newTranslations: List<String>) {
        if (startIdx < 0 || startIdx >= items.size) return
        val end = min(startIdx + newTranslations.size, items.size)
        var dirty = false
        for (i in startIdx until end) {
            if (!processed[i]) {
                processed[i] = true
                processedCount++
                // Background tint changes even if the text doesn't, so we
                // need a redraw for the colour swap alone.
                dirty = true
            }
            val incoming = newTranslations[i - startIdx]
            if (incoming.isBlank()) continue
            val current = items[i]
            if (current.translation == incoming) continue
            items[i] = current.copy(translation = incoming)
            // Drop layout caches for THIS index so onDraw rebuilds with
            // the new translation text; expandedRect needs to be re-fit
            // for the new content length too.
            layoutCache[i] = null
            sizeCache[i] = 0f
            expandedRect[i] = null
            dirty = true
        }
        if (dirty) invalidate()
    }

    /**
     * Show the tappable "Detected X — switch?" banner. [onTap] re-runs the
     * translation with the detected language (wired by BubbleService).
     */
    fun showSourceMismatch(label: String, onTap: () -> Unit) {
        mismatchLabel = label
        onMismatchTap = onTap
        invalidate()
    }

    /**
     * Reset every chip back to the pending (amber) state and drop the
     * mismatch banner — used right before a re-translate so the user sees
     * the chips re-process under the new source language.
     */
    fun resetForRetranslate() {
        for (i in processed.indices) processed[i] = false
        processedCount = 0
        mismatchLabel = null
        onMismatchTap = null
        invalidate()
    }

    /** Current items (with whatever translations have landed) — used to
     *  snapshot a finished scan into the "reopen last result" cache. */
    fun snapshotItems(): List<Item> = items.toList()

    /** The screenshot this overlay paints over — exposed so the reopen
     *  cache can take ownership of the SAME bitmap on dismiss. */
    val bitmap: Bitmap get() = screenshot

    /** Mark every chip as already-translated (white, no progress pill) —
     *  used when restoring a cached scan whose translations are final. */
    fun markAllProcessed() {
        for (i in processed.indices) processed[i] = true
        processedCount = items.size
        invalidate()
    }

    /**
     * For every block, find the nearest block immediately below that
     * shares any horizontal extent (i.e., is in the same column), then
     * record `nextBelow.top - thisBlock.top` as the cap on how tall this
     * block's expanded card may grow. Blocks with no neighbour below in
     * their column fall back to MAX_EXPAND_FACTOR × original height.
     *
     * All work is in bitmap-pixel coordinates; the per-frame onDraw scales
     * it together with everything else.
     */
    private fun computeExpansionLimits() {
        for (i in items.indices) {
            val a = items[i].bounds
            var nearestTop = Int.MAX_VALUE
            for (j in items.indices) {
                if (j == i) continue
                val b = items[j].bounds
                // Same column? Require any horizontal overlap.
                val horizontallyOverlaps = a.left < b.right && b.left < a.right
                if (!horizontallyOverlaps) continue
                // Strictly below the start of A so we don't constrain
                // against A's own bounds or against a sibling that starts
                // higher.
                if (b.top <= a.top) continue
                if (b.top < nearestTop) nearestTop = b.top
            }
            val origH = a.height()
            val cap = if (nearestTop != Int.MAX_VALUE) {
                // Leave the smaller of "until next block" or
                // "MAX_EXPAND_FACTOR × original height". The latter keeps
                // a tiny chip from blowing up just because the next block
                // happens to be far below.
                min(nearestTop - a.top, (origH * MAX_EXPAND_FACTOR).toInt())
            } else {
                (origH * MAX_EXPAND_FACTOR).toInt()
            }
            maxExpandPxBmp[i] = max(origH, cap)
        }
    }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        // Scale screenshot to fit view width. We capture at screen
        // resolution so 1:1 most of the time, but be defensive in case the
        // system padded the buffer or the user rotated mid-capture.
        val viewW = width.toFloat()
        val viewH = height.toFloat()
        val bmpW = screenshot.width.toFloat()
        val bmpH = screenshot.height.toFloat()
        val scale = min(viewW / bmpW, viewH / bmpH)
        val drawW = bmpW * scale
        val drawH = bmpH * scale
        val offsetX = (viewW - drawW) / 2f
        val offsetY = (viewH - drawH) / 2f

        // Base layer: full screenshot, slightly dimmed by the view's own
        // semi-transparent background painted underneath.
        srcDrawDest.set(offsetX, offsetY, offsetX + drawW, offsetY + drawH)
        canvas.drawBitmap(screenshot, null, srcDrawDest, null)

        // Per-block overlay
        for (i in items.indices) {
            val item = items[i]
            val left = offsetX + item.bounds.left * scale
            val top = offsetY + item.bounds.top * scale
            val right = offsetX + item.bounds.right * scale
            val bottom = offsetY + item.bounds.bottom * scale
            val origRect = RectF(left, top, right, bottom)

            val blockW = ((right - left) - PADDING_PX * 2f).toInt()
            val origBlockH = ((bottom - top) - PADDING_PX * 2f).toInt()
            if (blockW <= 0 || origBlockH <= 0) {
                // Tiny block — cover the original and bail (nothing to render).
                canvas.drawRect(origRect, whitePaint)
                canvas.drawRect(origRect, borderPaint)
                continue
            }

            // Build layout at the "ideal" size for the original box, then
            // grow the rect downward if the translation needs more room.
            // Cap by (a) MAX_EXPAND_FACTOR via the precomputed neighbour-
            // aware bound — which already stops the card from crashing
            // into the next block in the same column — and (b) the screen
            // bottom so we never grow past the visible area.
            val maxAllowedFromNeighbour = (maxExpandPxBmp[i] * scale - PADDING_PX * 2f).toInt()
            val maxAllowedH = min(
                maxAllowedFromNeighbour.coerceAtLeast(origBlockH),
                (viewH - top - PADDING_PX * 2f).toInt().coerceAtLeast(origBlockH),
            )
            val layout = buildLayout(i, item.translation, blockW, origBlockH, maxAllowedH)
            val finalBlockH = max(origBlockH, layout.height)
            val finalBottom = top + PADDING_PX * 2f + finalBlockH
            val drawRect = if (finalBlockH > origBlockH) {
                RectF(left, top, right, finalBottom)
            } else {
                origRect
            }
            expandedRect[i] = drawRect

            // Cover original, then draw translation top-aligned (preserve
            // the anchor at top-left so the visual link to the source
            // location stays even when the box grows). Untranslated chips
            // use an amber tint so the user can tell at a glance that
            // those slots are still in flight.
            val bgPaint = if (processed[i]) whitePaint else pendingPaint
            canvas.drawRect(drawRect, bgPaint)
            canvas.drawRect(drawRect, borderPaint)
            val drawY = if (finalBlockH > origBlockH) {
                top + PADDING_PX
            } else {
                top + PADDING_PX + max(0f, ((origBlockH - layout.height) / 2f))
            }
            canvas.save()
            canvas.translate(left + PADDING_PX, drawY)
            layout.draw(canvas)
            canvas.restore()
        }

        drawProgressPill(canvas, viewW)
        drawMismatchBanner(canvas, viewW)
    }

    /**
     * Tappable amber banner under the progress pill warning that the
     * pinned source language likely doesn't match the on-screen script.
     */
    private fun drawMismatchBanner(canvas: Canvas, viewW: Float) {
        val label = mismatchLabel ?: run {
            mismatchBannerRect.setEmpty()
            return
        }
        val density = resources.displayMetrics.density
        val padH = 16f * density
        val padV = 10f * density
        val textW = mismatchTextPaint.measureText(label)
        val fm = mismatchTextPaint.fontMetrics
        val textH = -fm.ascent + fm.descent
        val bannerW = min(textW + padH * 2, viewW - 24f * density)
        val bannerH = textH + padV * 2
        // Stack below the progress pill when it's showing; otherwise sit
        // at the same top margin.
        val topMargin = (if (processedCount < items.size) 60f else 14f) * density
        val left = (viewW - bannerW) / 2f
        val top = topMargin
        val radius = 10f * density
        mismatchBannerRect.set(left, top, left + bannerW, top + bannerH)
        canvas.drawRoundRect(mismatchBannerRect, radius, radius, mismatchBgPaint)
        canvas.drawText(label, viewW / 2f, top + padV - fm.ascent, mismatchTextPaint)
    }

    /**
     * Floating "Đang dịch X/Y" pill at the top of the overlay while any
     * slot is still un-processed. Once every slot has been spoken for by
     * the server, the pill is dropped from the next frame.
     *
     * Localised label is fetched lazily from the host context so this
     * View doesn't have to know which string resources exist.
     */
    private fun drawProgressPill(canvas: Canvas, viewW: Float) {
        if (processedCount >= items.size) return
        val density = resources.displayMetrics.density
        val label = context.getString(
            R.string.lens_progress_translating,
            processedCount,
            items.size,
        )
        val padH = 14f * density
        val padV = 8f * density
        val textW = progressTextPaint.measureText(label)
        val textH = -progressTextPaint.fontMetrics.ascent + progressTextPaint.fontMetrics.descent
        val pillW = textW + padH * 2
        val pillH = textH + padV * 2
        val topMargin = 14f * density
        val left = (viewW - pillW) / 2f
        val top = topMargin
        val radius = pillH / 2f
        canvas.drawRoundRect(left, top, left + pillW, top + pillH, radius, radius, progressBgPaint)
        canvas.drawText(
            label,
            viewW / 2f,
            top + padV - progressTextPaint.fontMetrics.ascent,
            progressTextPaint,
        )
    }

    /**
     * Build (or reuse) a StaticLayout that fits the given [width]. Uses
     * the original box height [origHeight] as the target text size, but
     * allows the layout to grow up to [maxAllowedHeight] before falling
     * back to text shrinking — keeps text readable when the translation
     * is significantly longer than the source (typical CJK → Latin).
     */
    private fun buildLayout(
        idx: Int,
        text: String,
        width: Int,
        origHeight: Int,
        maxAllowedHeight: Int,
    ): StaticLayout {
        layoutCache[idx]?.let { cached ->
            if (cached.width == width) return cached
        }
        val density = resources.displayMetrics.density
        var sizePx = sizeCache[idx].takeIf { it > 0f } ?: heuristicStartSizePx(origHeight)

        var layout = makeLayout(text, sizePx, width)
        // Shrink only when even the max-allowed (expanded) height can't
        // contain the layout. This means translations that just spill
        // slightly past the original box stay at full size and we expand
        // the rect downward; only truly oversize translations get shrunk.
        val minPx = MIN_SP * density
        while (layout.height > maxAllowedHeight && sizePx > minPx) {
            sizePx = max(minPx, sizePx * 0.9f)
            layout = makeLayout(text, sizePx, width)
        }
        sizeCache[idx] = sizePx
        layoutCache[idx] = layout
        return layout
    }

    private fun makeLayout(text: String, sizePx: Float, width: Int): StaticLayout {
        textPaint.textSize = sizePx
        return StaticLayout.Builder.obtain(text, 0, text.length, textPaint, width)
            .setAlignment(Layout.Alignment.ALIGN_NORMAL)
            .setLineSpacing(0f, 1f)
            .setIncludePad(false)
            .setEllipsize(android.text.TextUtils.TruncateAt.END)
            // Medium blocks fit in-place; anything longer is still fully
            // readable via the tap-to-expand popup, so the cap only guards
            // against one giant block dominating the overlay.
            .setMaxLines(15)
            .build()
    }

    /**
     * Starting text size. Earlier versions scaled by box height
     * (`boxHeight * 0.55`) which gave a 9–18sp spread depending on the
     * original OCR block — multi-line paragraph blocks ended up at 18sp,
     * tight single-line chips at 9sp, and reading several chunks of
     * translation on the same screen felt like a ransom note. ML Kit
     * boxes don't expose line height directly, so we anchor at a fixed
     * readable size and let the shrink loop in [buildLayout] knock it
     * down only when the box is genuinely tight.
     */
    private fun heuristicStartSizePx(@Suppress("UNUSED_PARAMETER") boxHeight: Int): Float {
        return TypedValue.applyDimension(
            TypedValue.COMPLEX_UNIT_SP, DEFAULT_SP, resources.displayMetrics,
        )
    }

    override fun onTouchEvent(event: MotionEvent): Boolean {
        // Forward EVERY event to the gesture detector — it needs the full
        // DOWN→MOVE→UP stream to recognize a long-press. We then keep the
        // existing tap behaviour by acting only on ACTION_UP below.
        gestureDetector.onTouchEvent(event)
        if (event.action != MotionEvent.ACTION_UP) return true
        // Mismatch banner tap takes priority — it sits above the chips and
        // re-runs translation with the detected language.
        if (mismatchLabel != null && !mismatchBannerRect.isEmpty &&
            event.x in mismatchBannerRect.left..mismatchBannerRect.right &&
            event.y in mismatchBannerRect.top..mismatchBannerRect.bottom
        ) {
            onMismatchTap?.invoke()
            return true
        }
        val idx = findItemIndexAt(event.x, event.y)
        if (idx >= 0) {
            // Tap a chip → open the full-translation popup so long results
            // truncated in-place are still fully readable.
            onBlockTap?.invoke(items[idx].original, items[idx].translation)
            return true
        }
        // Tap outside any block → dismiss.
        onDismissOutsideTap()
        return true
    }

    /// Find the item whose visible rect contains [x, y] (in view coords).
    /// Iterates top-down so a block whose expanded rect overlaps a smaller
    /// neighbour below still claims its own taps first.
    private fun findItemIndexAt(x: Float, y: Float): Int {
        val viewW = width.toFloat()
        val viewH = height.toFloat()
        val bmpW = screenshot.width.toFloat()
        val bmpH = screenshot.height.toFloat()
        val scale = min(viewW / bmpW, viewH / bmpH)
        val drawW = bmpW * scale
        val drawH = bmpH * scale
        val offsetX = (viewW - drawW) / 2f
        val offsetY = (viewH - drawH) / 2f

        for (i in items.indices) {
            // Prefer the expanded rect (matches the visible white card);
            // fall back to original OCR bounds before first paint.
            val rect = expandedRect[i] ?: RectF(
                offsetX + items[i].bounds.left * scale,
                offsetY + items[i].bounds.top * scale,
                offsetX + items[i].bounds.right * scale,
                offsetY + items[i].bounds.bottom * scale,
            )
            if (x in rect.left..rect.right && y in rect.top..rect.bottom) {
                return i
            }
        }
        return -1
    }

    companion object {
        private const val PADDING_PX = 4f
        private const val MIN_SP = 9
        /**
         * Uniform starting font size for all blocks. Matches typical mobile
         * body text — readable on a phone at arm's length without making
         * any single block look like a heading.
         */
        private const val DEFAULT_SP = 13f
        /**
         * How much taller the lens box may grow vs. the original OCR
         * bounds before we start shrinking text. 3x covers most CJK →
         * Latin expansions without letting a single-word badge balloon
         * into a card-sized chunk of the screen.
         */
        private const val MAX_EXPAND_FACTOR = 3f
    }
}
