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
            val rectF = RectF(left, top, right, bottom)

            if (showOriginal[i]) {
                // Leave the original screenshot visible; just outline so
                // the user knows this block is interactive.
                canvas.drawRect(rectF, borderPaint)
                continue
            }

            // Cover original, then draw translation auto-fitted.
            canvas.drawRect(rectF, whitePaint)
            canvas.drawRect(rectF, borderPaint)

            val blockW = ((right - left) - PADDING_PX * 2f).toInt()
            val blockH = ((bottom - top) - PADDING_PX * 2f).toInt()
            if (blockW <= 0 || blockH <= 0) continue

            val layout = buildLayout(i, item.translation, blockW, blockH)
            val drawY = top + PADDING_PX + max(
                0f,
                ((blockH - layout.height) / 2f),
            )
            canvas.save()
            canvas.translate(left + PADDING_PX, drawY)
            layout.draw(canvas)
            canvas.restore()
        }
    }

    /**
     * Build (or reuse) a StaticLayout that fits both width AND height of
     * the box. Iteratively shrinks text size from a heuristic starting
     * point down to MIN_SP. Cached so re-layouts during invalidation
     * (toggle taps) don't repeat the size search.
     */
    private fun buildLayout(idx: Int, text: String, width: Int, maxHeight: Int): StaticLayout {
        layoutCache[idx]?.let { cached ->
            if (cached.width == width) return cached
        }
        val density = resources.displayMetrics.density
        var sizePx = sizeCache[idx].takeIf { it > 0f } ?: heuristicStartSizePx(maxHeight)

        var layout = makeLayout(text, sizePx, width)
        // Shrink until it fits height — capped at MIN_SP.
        val minPx = MIN_SP * density
        while (layout.height > maxHeight && sizePx > minPx) {
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

    /** Pick a starting text size proportional to the box height. */
    private fun heuristicStartSizePx(boxHeight: Int): Float {
        val density = resources.displayMetrics.density
        val maxSp = 18f
        val sp = min(maxSp, max(MIN_SP.toFloat(), (boxHeight / density) * 0.55f))
        return TypedValue.applyDimension(
            TypedValue.COMPLEX_UNIT_SP, sp, resources.displayMetrics,
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

        for (i in items.indices) {
            val item = items[i]
            val left = offsetX + item.bounds.left * scale
            val top = offsetY + item.bounds.top * scale
            val right = offsetX + item.bounds.right * scale
            val bottom = offsetY + item.bounds.bottom * scale
            if (x in left..right && y in top..bottom) {
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
    }
}
