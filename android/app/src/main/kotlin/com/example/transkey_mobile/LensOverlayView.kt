package com.example.transkey_mobile

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
    private val items: List<Item>,
    private val onDismissOutsideTap: () -> Unit,
) : View(context) {

    data class Item(val original: String, val translation: String, val bounds: Rect)

    private val whitePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.WHITE
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

    // Per-item "show original" toggle. When true for a given index, that
    // block draws the screenshot crop instead of the white-on-translation.
    private val showOriginal = BooleanArray(items.size)

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

    private val srcDrawDest = RectF()  // reused per draw call

    init {
        setBackgroundColor(Color.parseColor("#CC000000"))
        isClickable = true
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

            if (showOriginal[i]) {
                // Leave the original screenshot visible; just outline so
                // the user knows this block is interactive.
                canvas.drawRect(origRect, borderPaint)
                continue
            }

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
            // Cap at MAX_EXPAND_FACTOR so a tiny "OK" badge can't blow up
            // into a card-sized overlay.
            val maxAllowedH = min(
                (origBlockH * MAX_EXPAND_FACTOR).toInt(),
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
            // location stays even when the box grows).
            canvas.drawRect(drawRect, whitePaint)
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
            .setMaxLines(8)
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
        if (event.action != MotionEvent.ACTION_UP) return true
        val x = event.x
        val y = event.y

        // Translate touch point back into bitmap coords using same scale
        // factors as onDraw.
        val viewW = width.toFloat()
        val viewH = height.toFloat()
        val bmpW = screenshot.width.toFloat()
        val bmpH = screenshot.height.toFloat()
        val scale = min(viewW / bmpW, viewH / bmpH)
        val drawW = bmpW * scale
        val drawH = bmpH * scale
        val offsetX = (viewW - drawW) / 2f
        val offsetY = (viewH - drawH) / 2f

        // Iterate top-down so a block whose expanded rect overlaps a
        // smaller neighbour below still claims its own taps first.
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
                showOriginal[i] = !showOriginal[i]
                // Force rebuild so the toggle's hidden translation doesn't
                // sit stale in cache when user flips back.
                if (!showOriginal[i]) layoutCache[i] = null
                invalidate()
                return true
            }
        }
        // Tap outside any block → dismiss.
        onDismissOutsideTap()
        return true
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
