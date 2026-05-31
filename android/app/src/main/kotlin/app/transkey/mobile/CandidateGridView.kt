package app.transkey.mobile

import android.content.Context
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.RectF
import android.view.MotionEvent
import android.view.View
import android.view.ViewConfiguration
import kotlin.math.abs
import kotlin.math.max

/**
 * Full candidate grid shown in place of the keyboard when the user taps the ▼
 * chevron on the suggestion strip. Lists every CJK candidate (pinyin->hanzi or
 * kana->kanji) as tappable chips wrapped across rows, with vertical scroll if
 * they overflow. A ▲ header collapses back to the keyboard. Mirrors the
 * self-drawn, dependency-free approach of [EmojiPanelView].
 */
class CandidateGridView(context: Context) : View(context) {

    var onPick: ((String) -> Unit)? = null
    var onCollapse: (() -> Unit)? = null

    private var candidates: List<String> = emptyList()
    private var numbered = false
    private var panelHeight = 0

    private var scrollY = 0f
    private var maxScroll = 0f

    private val d = resources.displayMetrics.density
    private fun dp(v: Float) = v * d
    private fun sp(v: Float) = v * resources.displayMetrics.scaledDensity

    private val headerH get() = dp(40f)
    private val rowH get() = dp(50f)
    private val padH get() = dp(8f)
    private val gap get() = dp(8f)

    private val bg = Paint().apply { color = 0xFF0B1020.toInt() }
    private val chipFill = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = 0x14FFFFFF; style = Paint.Style.FILL
    }
    private val chipText = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = 0xFFECECF1.toInt(); textAlign = Paint.Align.LEFT; textSize = sp(18f)
    }
    private val numText = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = 0xFF7E828C.toInt(); textAlign = Paint.Align.LEFT; textSize = sp(11f)
    }
    private val headerText = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = 0xFF9AA0AE.toInt(); textAlign = Paint.Align.LEFT
        textSize = sp(13f); isFakeBoldText = true
    }
    private val chevron = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = 0xFFC4C7CE.toInt(); style = Paint.Style.STROKE; strokeWidth = dp(2f)
        strokeCap = Paint.Cap.ROUND; strokeJoin = Paint.Join.ROUND
    }
    private val headerLine = Paint().apply { color = 0x1AFFFFFF }
    private val rectF = RectF()

    // Laid-out chips for hit-testing, in content coordinates (header offset
    // included; the canvas is translated by -scrollY when drawing).
    private data class Chip(
        val left: Float, val top: Float, val right: Float, val bottom: Float,
        val word: String, val index: Int,
    )
    private val chips = ArrayList<Chip>()

    private val touchSlop = ViewConfiguration.get(context).scaledTouchSlop

    init { isClickable = true }

    fun setNumbered(on: Boolean) { numbered = on }

    fun setCandidates(list: List<String>) {
        candidates = list
        scrollY = 0f
        layoutChips()
        invalidate()
    }

    fun setPanelHeight(h: Int) {
        panelHeight = max(h, 1)
        requestLayout()
        layoutChips()
        invalidate()
    }

    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        setMeasuredDimension(MeasureSpec.getSize(widthMeasureSpec), panelHeight)
    }

    override fun onSizeChanged(w: Int, h: Int, oldw: Int, oldh: Int) {
        layoutChips()
    }

    /** Wrap candidates into rows of chips; compute the scrollable content height. */
    private fun layoutChips() {
        chips.clear()
        val w = width.toFloat()
        if (w <= 0f) return
        var x = padH
        var y = headerH + padH
        for ((i, word) in candidates.withIndex()) {
            val numW = if (numbered && i < 9) dp(12f) else 0f
            val chipW = numW + chipText.measureText(word) + dp(24f)
            if (x + chipW > w - padH && x > padH) { // wrap to the next row
                x = padH
                y += rowH
            }
            chips.add(Chip(x, y, x + chipW, y + rowH - gap, word, i))
            x += chipW + gap
        }
        val contentBottom = (chips.lastOrNull()?.bottom ?: headerH) + padH
        maxScroll = max(0f, contentBottom - panelHeight)
    }

    override fun onDraw(c: Canvas) {
        c.drawRect(0f, 0f, width.toFloat(), height.toFloat(), bg)
        // Header: label + ▲ collapse on the right.
        val baseH = headerH / 2f - (headerText.descent() + headerText.ascent()) / 2f
        c.drawText("中文 / 候補", padH, baseH, headerText)
        drawCollapse(c, width - dp(26f), headerH / 2f)
        c.drawLine(0f, headerH, width.toFloat(), headerH, headerLine)
        // Chips, scrolled and clipped below the header.
        c.save()
        c.clipRect(0f, headerH, width.toFloat(), height.toFloat())
        c.translate(0f, -scrollY)
        for (chip in chips) {
            rectF.set(chip.left, chip.top, chip.right, chip.bottom)
            c.drawRoundRect(rectF, dp(8f), dp(8f), chipFill)
            val base = (chip.top + chip.bottom) / 2f - (chipText.descent() + chipText.ascent()) / 2f
            var tx = chip.left + dp(12f)
            if (numbered && chip.index < 9) {
                c.drawText("${chip.index + 1}", chip.left + dp(5f), chip.top + dp(15f), numText)
                tx = chip.left + dp(14f)
            }
            c.drawText(chip.word, tx, base, chipText)
        }
        c.restore()
    }

    /** ▲ up-chevron = "collapse" (back to the keyboard). */
    private fun drawCollapse(c: Canvas, cx: Float, cy: Float) {
        val w = dp(7f)
        val h = dp(5f)
        c.drawLine(cx - w, cy + h / 2, cx, cy - h / 2, chevron)
        c.drawLine(cx, cy - h / 2, cx + w, cy + h / 2, chevron)
    }

    private var downY = 0f
    private var scrolled = false

    override fun onTouchEvent(e: MotionEvent): Boolean {
        when (e.action) {
            MotionEvent.ACTION_DOWN -> { downY = e.y; scrolled = false }
            MotionEvent.ACTION_MOVE -> {
                if (!scrolled && abs(e.y - downY) > touchSlop) scrolled = true
                if (scrolled && maxScroll > 0f) {
                    scrollY = (scrollY - (e.y - downY)).coerceIn(0f, maxScroll)
                    downY = e.y
                    invalidate()
                }
            }
            MotionEvent.ACTION_UP -> {
                if (scrolled) return true
                if (e.y < headerH) { onCollapse?.invoke(); return true }
                val cy = e.y + scrollY // screen -> content coordinates
                for (chip in chips) {
                    if (e.x >= chip.left && e.x <= chip.right && cy >= chip.top && cy <= chip.bottom) {
                        onPick?.invoke(chip.word)
                        return true
                    }
                }
            }
            MotionEvent.ACTION_CANCEL -> { scrolled = false }
        }
        return true
    }
}
