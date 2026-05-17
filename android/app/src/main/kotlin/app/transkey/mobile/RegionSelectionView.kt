package app.transkey.mobile

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Path
import android.graphics.Path.Direction
import android.graphics.Rect
import android.graphics.RectF
import android.graphics.drawable.GradientDrawable
import android.util.TypedValue
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.TextView
import kotlin.math.max
import kotlin.math.min

/**
 * Rubber-band region selector for the Lens flow. Renders the captured
 * screenshot full-screen, dims everything outside the user's drag
 * rectangle, and exposes Confirm / Cancel buttons after release.
 *
 * Coordinates handed back via [onConfirm] are in the SOURCE BITMAP
 * coordinate space (not view pixels), so BubbleService can crop the
 * bitmap directly without re-applying any scale factor.
 */
@SuppressLint("ViewConstructor")
class RegionSelectionView(
    context: Context,
    private val bitmap: Bitmap,
    private val onConfirm: (Rect) -> Unit,
    private val onCancel: () -> Unit,
) : FrameLayout(context) {

    /** Current selection in VIEW coords (not bitmap coords). */
    private val selectionView = RectF()
    private var hasSelection = false
    private var anchorX = 0f
    private var anchorY = 0f

    // Once a rectangle has been drawn, subsequent touches can resize from
    // a corner, move the whole rect, or — outside the rect — start fresh.
    private enum class DragMode { NONE, NEW, MOVE, RESIZE_TL, RESIZE_TR, RESIZE_BL, RESIZE_BR }
    private var dragMode = DragMode.NONE
    private var dragStartX = 0f
    private var dragStartY = 0f
    private val dragStartRect = RectF()

    // ── Paints ──
    private val dimPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.parseColor("#99000000")
        style = Paint.Style.FILL
    }
    private val borderPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.parseColor("#6C63FF")
        style = Paint.Style.STROKE
        strokeWidth = context.resources.displayMetrics.density * 2f
    }
    private val handlePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.parseColor("#6C63FF")
        style = Paint.Style.FILL
    }

    // Bitmap-to-view scale (set in onSizeChanged). Selection rect in view
    // coords must be divided by this to recover bitmap coords on confirm.
    private var bitmapScale: Float = 1f
    private var bitmapOffsetX: Float = 0f
    private var bitmapOffsetY: Float = 0f

    private val drawingPath = Path()
    private val viewBounds = RectF()

    // Cached layout for the bitmap destination rect to avoid allocating
    // every frame.
    private val bitmapDest = RectF()

    // ── Floating UI: hint + Cancel/Confirm pill buttons ──
    private val hintView: TextView
    private val actionRow: LinearLayout
    private val confirmButton: TextView

    init {
        setBackgroundColor(Color.TRANSPARENT)
        isClickable = true
        setWillNotDraw(false)

        val dp = context.resources.displayMetrics.density
        val accent = Color.parseColor("#6C63FF")

        hintView = TextView(context).apply {
            text = context.getString(R.string.bubble_lens_region_hint)
            setTextColor(Color.WHITE)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 14f)
            setShadowLayer(4f * dp, 0f, dp, Color.BLACK)
            setPadding((16 * dp).toInt(), (10 * dp).toInt(), (16 * dp).toInt(), (10 * dp).toInt())
            background = GradientDrawable().apply {
                setColor(Color.parseColor("#AA1E1E30"))
                cornerRadius = 12 * dp
            }
            gravity = Gravity.CENTER
        }
        addView(hintView, LayoutParams(
            LayoutParams.WRAP_CONTENT,
            LayoutParams.WRAP_CONTENT,
            Gravity.TOP or Gravity.CENTER_HORIZONTAL,
        ).apply { topMargin = (48 * dp).toInt() })

        actionRow = LinearLayout(context).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER
            visibility = GONE
        }
        actionRow.addView(TextView(context).apply {
            text = context.getString(R.string.bubble_cancel)
            setTextColor(Color.WHITE)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 14f)
            typeface = android.graphics.Typeface.DEFAULT_BOLD
            setPadding((20 * dp).toInt(), (12 * dp).toInt(), (20 * dp).toInt(), (12 * dp).toInt())
            background = GradientDrawable().apply {
                setColor(Color.parseColor("#AA1E1E30"))
                cornerRadius = 14 * dp
            }
            isClickable = true
            isFocusable = true
            setOnClickListener { onCancel() }
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.WRAP_CONTENT,
                LinearLayout.LayoutParams.WRAP_CONTENT,
            ).apply { marginEnd = (10 * dp).toInt() }
        })
        confirmButton = TextView(context).apply {
            text = context.getString(R.string.bubble_lens_region_confirm)
            setTextColor(Color.WHITE)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 14f)
            typeface = android.graphics.Typeface.DEFAULT_BOLD
            setPadding((20 * dp).toInt(), (12 * dp).toInt(), (20 * dp).toInt(), (12 * dp).toInt())
            background = GradientDrawable().apply {
                setColor(accent)
                cornerRadius = 14 * dp
            }
            isClickable = true
            isFocusable = true
            setOnClickListener {
                val rect = currentBitmapRect() ?: return@setOnClickListener
                onConfirm(rect)
            }
        }
        actionRow.addView(confirmButton)
        addView(actionRow, LayoutParams(
            LayoutParams.WRAP_CONTENT,
            LayoutParams.WRAP_CONTENT,
            Gravity.BOTTOM or Gravity.CENTER_HORIZONTAL,
        ).apply { bottomMargin = (48 * dp).toInt() })
    }

    override fun onSizeChanged(w: Int, h: Int, oldw: Int, oldh: Int) {
        super.onSizeChanged(w, h, oldw, oldh)
        recomputeBitmapDest(w.toFloat(), h.toFloat())
    }

    private fun recomputeBitmapDest(viewW: Float, viewH: Float) {
        val bmpW = bitmap.width.toFloat()
        val bmpH = bitmap.height.toFloat()
        val scale = min(viewW / bmpW, viewH / bmpH)
        bitmapScale = scale
        val drawW = bmpW * scale
        val drawH = bmpH * scale
        bitmapOffsetX = (viewW - drawW) / 2f
        bitmapOffsetY = (viewH - drawH) / 2f
        bitmapDest.set(
            bitmapOffsetX, bitmapOffsetY,
            bitmapOffsetX + drawW, bitmapOffsetY + drawH,
        )
    }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        viewBounds.set(0f, 0f, width.toFloat(), height.toFloat())

        // 1) Screenshot full-size as background
        canvas.drawBitmap(bitmap, null, bitmapDest, null)

        if (!hasSelection && dragMode == DragMode.NONE) {
            // No selection yet — dim the whole screen uniformly so the
            // user knows they're in selection mode.
            canvas.drawRect(viewBounds, dimPaint)
            return
        }

        // 2) Dim outside the selection rectangle by drawing the dim layer
        // through an inverse path (EVEN_ODD fill rule cuts the rect out).
        drawingPath.reset()
        drawingPath.fillType = Path.FillType.EVEN_ODD
        drawingPath.addRect(viewBounds, Direction.CW)
        drawingPath.addRect(selectionView, Direction.CW)
        canvas.drawPath(drawingPath, dimPaint)

        // 3) Selection border + 4 corner handles
        canvas.drawRect(selectionView, borderPaint)
        val handleR = context.resources.displayMetrics.density * 6f
        canvas.drawCircle(selectionView.left, selectionView.top, handleR, handlePaint)
        canvas.drawCircle(selectionView.right, selectionView.top, handleR, handlePaint)
        canvas.drawCircle(selectionView.left, selectionView.bottom, handleR, handlePaint)
        canvas.drawCircle(selectionView.right, selectionView.bottom, handleR, handlePaint)
    }

    override fun onTouchEvent(event: MotionEvent): Boolean {
        when (event.action) {
            MotionEvent.ACTION_DOWN -> {
                if (isPointInChildButton(event.x, event.y)) return false
                dragStartX = event.x
                dragStartY = event.y
                dragStartRect.set(selectionView)
                dragMode = pickDragMode(event.x, event.y)

                if (dragMode == DragMode.NEW) {
                    anchorX = event.x.coerceIn(bitmapDest.left, bitmapDest.right)
                    anchorY = event.y.coerceIn(bitmapDest.top, bitmapDest.bottom)
                    selectionView.set(anchorX, anchorY, anchorX, anchorY)
                    hasSelection = false
                    hintView.visibility = VISIBLE
                }
                // Hide actions during any active drag — they re-appear on UP.
                actionRow.visibility = GONE
                invalidate()
                return true
            }
            MotionEvent.ACTION_MOVE -> {
                if (dragMode == DragMode.NONE) return false
                val cx = event.x.coerceIn(bitmapDest.left, bitmapDest.right)
                val cy = event.y.coerceIn(bitmapDest.top, bitmapDest.bottom)
                applyDragUpdate(cx, cy)
                invalidate()
                return true
            }
            MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                if (dragMode == DragMode.NONE) return false
                dragMode = DragMode.NONE
                normalizeRect()
                val minSizeDp = context.resources.displayMetrics.density * 24f
                hasSelection = selectionView.width() > minSizeDp &&
                    selectionView.height() > minSizeDp
                if (hasSelection) {
                    hintView.visibility = GONE
                    actionRow.visibility = VISIBLE
                } else {
                    // Treat tiny drags as no-selection — keep instruction
                    // visible and stay in pre-selection state.
                    selectionView.set(0f, 0f, 0f, 0f)
                    actionRow.visibility = GONE
                    hintView.visibility = VISIBLE
                }
                invalidate()
                return true
            }
        }
        return false
    }

    private fun pickDragMode(x: Float, y: Float): DragMode {
        if (!hasSelection) return DragMode.NEW
        // 28dp hit radius around each corner — generous enough for fat
        // fingers, small enough to leave the rect interior addressable.
        val hit = context.resources.displayMetrics.density * 28f
        return when {
            nearPoint(x, y, selectionView.left, selectionView.top, hit) -> DragMode.RESIZE_TL
            nearPoint(x, y, selectionView.right, selectionView.top, hit) -> DragMode.RESIZE_TR
            nearPoint(x, y, selectionView.left, selectionView.bottom, hit) -> DragMode.RESIZE_BL
            nearPoint(x, y, selectionView.right, selectionView.bottom, hit) -> DragMode.RESIZE_BR
            selectionView.contains(x, y) -> DragMode.MOVE
            else -> DragMode.NEW
        }
    }

    private fun applyDragUpdate(cx: Float, cy: Float) {
        when (dragMode) {
            DragMode.NEW -> selectionView.set(
                min(anchorX, cx), min(anchorY, cy),
                max(anchorX, cx), max(anchorY, cy),
            )
            DragMode.RESIZE_TL -> selectionView.set(
                cx, cy, dragStartRect.right, dragStartRect.bottom,
            )
            DragMode.RESIZE_TR -> selectionView.set(
                dragStartRect.left, cy, cx, dragStartRect.bottom,
            )
            DragMode.RESIZE_BL -> selectionView.set(
                cx, dragStartRect.top, dragStartRect.right, cy,
            )
            DragMode.RESIZE_BR -> selectionView.set(
                dragStartRect.left, dragStartRect.top, cx, cy,
            )
            DragMode.MOVE -> {
                val w = dragStartRect.width()
                val h = dragStartRect.height()
                val rawLeft = dragStartRect.left + (cx - dragStartX)
                val rawTop  = dragStartRect.top  + (cy - dragStartY)
                val left = rawLeft.coerceIn(bitmapDest.left, bitmapDest.right - w)
                val top  = rawTop.coerceIn(bitmapDest.top,  bitmapDest.bottom - h)
                selectionView.set(left, top, left + w, top + h)
            }
            DragMode.NONE -> Unit
        }
    }

    private fun nearPoint(x: Float, y: Float, px: Float, py: Float, radius: Float): Boolean {
        val dx = x - px; val dy = y - py
        return dx * dx + dy * dy <= radius * radius
    }

    private fun normalizeRect() {
        // Resize drags can flip the rectangle when the user crosses past
        // the opposite edge — restore left ≤ right and top ≤ bottom.
        if (selectionView.left > selectionView.right) {
            val tmp = selectionView.left
            selectionView.left = selectionView.right
            selectionView.right = tmp
        }
        if (selectionView.top > selectionView.bottom) {
            val tmp = selectionView.top
            selectionView.top = selectionView.bottom
            selectionView.bottom = tmp
        }
    }

    private fun isPointInChildButton(x: Float, y: Float): Boolean {
        // Buttons are inside actionRow; if the row's hidden, nothing to check.
        if (actionRow.visibility != VISIBLE) return false
        val xy = IntArray(2)
        val selfXY = IntArray(2)
        getLocationOnScreen(selfXY)
        for (i in 0 until actionRow.childCount) {
            val btn = actionRow.getChildAt(i)
            btn.getLocationOnScreen(xy)
            val left = xy[0] - selfXY[0].toFloat()
            val top = xy[1] - selfXY[1].toFloat()
            if (x in left..left + btn.width && y in top..top + btn.height) return true
        }
        return false
    }

    /**
     * Translate the on-screen selection rectangle back into bitmap pixel
     * coordinates, clamping to the bitmap edges. Returns null if there is
     * no meaningful selection yet.
     */
    private fun currentBitmapRect(): Rect? {
        if (!hasSelection || selectionView.isEmpty) return null
        val left = ((selectionView.left - bitmapOffsetX) / bitmapScale).toInt()
        val top = ((selectionView.top - bitmapOffsetY) / bitmapScale).toInt()
        val right = ((selectionView.right - bitmapOffsetX) / bitmapScale).toInt()
        val bottom = ((selectionView.bottom - bitmapOffsetY) / bitmapScale).toInt()
        val clamped = Rect(
            left.coerceIn(0, bitmap.width),
            top.coerceIn(0, bitmap.height),
            right.coerceIn(0, bitmap.width),
            bottom.coerceIn(0, bitmap.height),
        )
        return if (clamped.width() > 0 && clamped.height() > 0) clamped else null
    }
}
