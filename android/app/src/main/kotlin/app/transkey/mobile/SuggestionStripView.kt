package app.transkey.mobile

import android.content.Context
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RectF
import android.util.AttributeSet
import android.view.MotionEvent
import android.view.View

/**
 * Gboard-style suggestion strip.
 *   left:   apps / grid icon
 *   middle: up to three word suggestions (best first); tap one to apply
 *   right:  mic icon
 * When there are no suggestions it shows faint slot dividers (idle look).
 */
class SuggestionStripView : View {

    constructor(context: Context, attrs: AttributeSet?) : super(context, attrs)
    constructor(context: Context, attrs: AttributeSet?, defStyle: Int) :
        super(context, attrs, defStyle)

    var onMicTap: (() -> Unit)? = null
    var onGridTap: (() -> Unit)? = null
    var onSuggestionTap: ((String) -> Unit)? = null
    // Tap the ▼ chevron at the right of the candidate row to open the full
    // candidate grid (CJK: see every pinyin/kanji candidate, not just the few
    // that fit on the strip).
    var onExpandTap: (() -> Unit)? = null
    // Action chips shown in the idle middle zone (no word suggestions): the
    // index of the tapped chip is reported back (0 = first chip, ...).
    var onActionTap: ((Int) -> Unit)? = null
    // Compact language pill (e.g. "VI→EN") at the left of the action chips;
    // tap opens the language picker. Empty label hides it.
    var onLangTap: (() -> Unit)? = null
    private var langLabel: String = ""
    private var langPillRight = 0f

    // Undo chip at the right of the action chips: revert the last whole-field
    // replace (translate / refine / reply). Shown only when undoVisible.
    var onUndoTap: (() -> Unit)? = null
    private var undoVisible = false
    private var undoZoneLeft = Float.MAX_VALUE

    /** Show/hide the undo chip next to the action chips. */
    fun setUndoVisible(on: Boolean) {
        if (on != undoVisible) {
            undoVisible = on
            invalidate()
        }
    }

    // Mic active state: while dictation is live the mic icon turns red (filled
    // red circle + white mic) so the user can see voice is on.
    private var micListening = false

    fun setMicListening(on: Boolean) {
        if (on != micListening) {
            micListening = on
            invalidate()
        }
    }

    // Premium top accent bar: a thin brand-gradient line on the panel's top edge,
    // shown only for paid accounts (toggled by TransKeyIME.applyPremiumChrome).
    // Drawn here (clipped to the panel's rounded top corners) so it follows the
    // corner radius instead of overflowing like a flat background layer would.
    private var showTopBar = false

    fun setTopBar(on: Boolean) {
        if (on != showTopBar) {
            showTopBar = on
            invalidate()
        }
    }

    fun setLang(label: String) {
        if (label != langLabel) {
            langLabel = label
            invalidate()
        }
    }

    private var suggestions: List<String> = emptyList()
    // Highlighted slot (Japanese kanji conversion: the candidate currently in
    // the composing text). -1 = none; index 0 keeps its always-best style.
    private var selectedSuggestion: Int = -1
    // Feature chips (e.g. "Dịch" / "Trau chuốt") drawn when there are no word
    // suggestions to show. Word suggestions take priority while typing.
    private var actions: List<String> = emptyList()
    // While a chip's request is in flight the strip shows a status label and
    // ignores middle-zone taps so the user can't fire a second request.
    private var processing: Boolean = false
    private var processingLabel: String = ""

    // CJK candidate mode: when set, the strip prefixes each candidate with a
    // 1-based index (Chinese) and shows a ▼ chevron to open the full grid.
    private var numbered = false
    private var expandable = false

    fun setSuggestions(list: List<String>, selected: Int = -1) {
        if (list != suggestions || selected != selectedSuggestion || expandable) {
            suggestions = list
            selectedSuggestion = selected
            expandable = false
            numbered = false
            invalidate()
        }
    }

    /** CJK candidate bar: like [setSuggestions] but with optional 1-based index
     *  labels ([withNumbers], Chinese) and a ▼ expand-all chevron. */
    fun setCandidates(list: List<String>, selected: Int, withNumbers: Boolean) {
        if (list != suggestions || selected != selectedSuggestion ||
            withNumbers != numbered || !expandable
        ) {
            suggestions = list
            selectedSuggestion = selected
            numbered = withNumbers
            expandable = true
            invalidate()
        }
    }

    /** Set the feature chips shown when the strip is otherwise idle. */
    fun setActions(list: List<String>) {
        if (list != actions) {
            actions = list
            invalidate()
        }
    }

    /** Toggle the "request in flight" status label + tap lock. */
    fun setProcessing(on: Boolean, label: String = "") {
        if (on == processing && label == processingLabel) return
        processing = on
        processingLabel = label
        invalidate()
    }

    private val d = resources.displayMetrics.density
    private fun dp(v: Float) = v * d
    private fun sp(v: Float) = v * resources.displayMetrics.scaledDensity

    private val colIcon = 0xFFC4C7CE.toInt()
    private val stroke = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = colIcon; style = Paint.Style.STROKE; strokeWidth = dp(2f)
        strokeCap = Paint.Cap.ROUND; strokeJoin = Paint.Join.ROUND
    }
    private val fill = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = colIcon; style = Paint.Style.FILL
    }
    private val divider = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = 0x1AFFFFFF; strokeWidth = dp(1f)
    }
    private val textBest = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = 0xFFECECF1.toInt(); textAlign = Paint.Align.CENTER; textSize = sp(16f)
        isFakeBoldText = true
    }
    private val textAlt = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = 0xFFB9BCC4.toInt(); textAlign = Paint.Align.CENTER; textSize = sp(16f)
    }
    // Feature chips (Dịch / Trau chuốt) use the home screen's brand gradient
    // (#6366F1 -> #A855F7, diagonal). The shader is rebuilt per chip from its
    // rect; the strip only repaints on state change, so this isn't a hot path.
    private val gradStart = 0xFF6366F1.toInt()
    private val gradEnd = 0xFFA855F7.toInt()
    private val chipGradient = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.FILL }
    // Premium top accent bar (paid): same brand gradient, clipped to the panel's
    // rounded top corners so it hugs the corner instead of overflowing.
    private val topBarPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.FILL }
    private val topBarPath = Path()
    private val textAction = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = 0xFFFFFFFF.toInt(); textAlign = Paint.Align.CENTER; textSize = sp(15f)
        isFakeBoldText = true
    }
    // Language pill: a bluish tint so it reads as a distinct control, not an
    // action chip.
    private val langPillFill = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = 0x2A8AB4F8; style = Paint.Style.FILL
    }
    // Undo chip: a solid red pill (NOT the brand gradient) so it clearly reads
    // as a "revert" control, distinct from the action chips.
    private val undoPillFill = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = 0xFFE5484D.toInt(); style = Paint.Style.FILL
    }
    // White arrow on the red undo pill. Reused for the mic icon while listening.
    private val undoStroke = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = 0xFFFFFFFF.toInt(); style = Paint.Style.STROKE; strokeWidth = dp(2f)
        strokeCap = Paint.Cap.ROUND; strokeJoin = Paint.Join.ROUND
    }
    // Red circle behind the mic icon while dictation is active.
    private val micRedFill = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = 0xFFE5484D.toInt(); style = Paint.Style.FILL
    }
    private val textLang = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = 0xFFCFE0FF.toInt(); textAlign = Paint.Align.CENTER; textSize = sp(13f)
        isFakeBoldText = true
    }
    // Small 1-based index drawn at each candidate's top-left (Chinese mode).
    private val textNum = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = 0xFF7E828C.toInt(); textAlign = Paint.Align.LEFT; textSize = sp(10f)
    }
    // ▼ expand-all chevron (own paint so the mic's gradient shader can't bleed).
    private val chevron = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = colIcon; style = Paint.Style.STROKE; strokeWidth = dp(2f)
        strokeCap = Paint.Cap.ROUND; strokeJoin = Paint.Join.ROUND
    }
    private val rectF = RectF()

    private val sideZone get() = dp(56f)
    private val expandZone get() = dp(40f)
    private val minSlot get() = dp(58f)
    private var expandLeft = 0f    // left edge of the ▼ zone (for hit-testing)
    private var visibleCount = 0   // candidates drawn on the strip (rest in grid)
    private var hasExpandZone = false

    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        setMeasuredDimension(MeasureSpec.getSize(widthMeasureSpec), dp(48f).toInt())
    }

    override fun onDraw(c: Canvas) {
        val cy = height / 2f
        if (showTopBar) drawTopBar(c)
        drawGrid(c, dp(30f), cy)
        drawMic(c, width - dp(30f), cy, dp(9.5f))

        val l = sideZone
        val r = width - sideZone

        // Priority: in-flight status > word suggestions > feature chips > idle.
        if (processing) {
            val base = cy - (textAlt.descent() + textAlt.ascent()) / 2f
            c.drawText(processingLabel, (l + r) / 2f, base, textAlt)
            return
        }
        val n = suggestions.size
        if (n == 0) {
            if (actions.isNotEmpty() || langLabel.isNotEmpty()) {
                drawActions(c, l, r, cy)
            } else {
                val slot = (r - l) / 3f
                c.drawLine(l + slot, cy - dp(10f), l + slot, cy + dp(10f), divider)
                c.drawLine(l + slot * 2, cy - dp(10f), l + slot * 2, cy + dp(10f), divider)
            }
            return
        }
        // Candidate row: reserve a ▼ zone on the right (only when there are more
        // candidates than fit) and cap how many render here; the rest live in the
        // expand-all grid.
        val maxNoExp = ((r - l) / minSlot).toInt().coerceAtLeast(1)
        hasExpandZone = expandable && n > maxNoExp
        val areaRight = if (hasExpandZone) r - expandZone else r
        expandLeft = areaRight
        val maxVis = ((areaRight - l) / minSlot).toInt().coerceAtLeast(1)
        val visible = if (n < maxVis) n else maxVis
        visibleCount = visible
        val slot = (areaRight - l) / visible
        val base = cy - (textBest.descent() + textBest.ascent()) / 2f
        // Highlight pill behind the selected candidate (JA conversion).
        if (selectedSuggestion in 0 until visible) {
            val pillH = dp(34f)
            val i = selectedSuggestion
            rectF.set(l + slot * i + dp(3f), cy - pillH / 2, l + slot * (i + 1) - dp(3f), cy + pillH / 2)
            chipGradient.shader = android.graphics.LinearGradient(
                rectF.left, rectF.top, rectF.right, rectF.bottom,
                gradStart, gradEnd, android.graphics.Shader.TileMode.CLAMP,
            )
            c.drawRoundRect(rectF, pillH / 2, pillH / 2, chipGradient)
            chipGradient.shader = null
        }
        for (i in 0 until visible) {
            val cx = l + slot * i + slot / 2f
            val p = when {
                i == selectedSuggestion -> textAction
                i == 0 -> textBest
                else -> textAlt
            }
            c.drawText(suggestions[i], cx, base, p)
            // 1-based index hint (Chinese): pick this candidate by long-pressing
            // the matching top-row key (q=1..o=9, p=10).
            if (numbered && i < 9 && i != selectedSuggestion) {
                c.drawText("${i + 1}", l + slot * i + dp(6f), cy - dp(8f), textNum)
            }
            if (i > 0 && i != selectedSuggestion && i - 1 != selectedSuggestion) {
                val x = l + slot * i
                c.drawLine(x, cy - dp(11f), x, cy + dp(11f), divider)
            }
        }
        if (hasExpandZone) drawExpandChevron(c, (areaRight + r) / 2f, cy)
    }

    /** ▼ down-chevron = "show all candidates" (opens the grid). */
    private fun drawExpandChevron(c: Canvas, cx: Float, cy: Float) {
        val w = dp(6f)
        val h = dp(4f)
        c.drawLine(cx - w, cy - h / 2, cx, cy + h / 2, chevron)
        c.drawLine(cx, cy + h / 2, cx + w, cy - h / 2, chevron)
    }

    /** Draw the optional language pill, then the feature chips in what's left. */
    private fun drawActions(c: Canvas, l: Float, r: Float, cy: Float) {
        val padH = dp(6f)
        val pillH = dp(34f)
        var start = l
        if (langLabel.isNotEmpty()) {
            val pillW = textLang.measureText(langLabel) + dp(24f)
            val left = start + padH
            val right = start + pillW - padH
            rectF.set(left, cy - pillH / 2, right, cy + pillH / 2)
            c.drawRoundRect(rectF, pillH / 2, pillH / 2, langPillFill)
            val base = cy - (textLang.descent() + textLang.ascent()) / 2f
            c.drawText(langLabel, (left + right) / 2f, base, textLang)
            langPillRight = start + pillW
            start += pillW
        } else {
            langPillRight = l
        }
        // Reserve a fixed zone on the right for the undo chip (next to the last
        // action chip), so the action chips shrink to fit instead of overlapping.
        var actionsRight = r
        if (undoVisible) {
            val undoW = dp(48f)
            undoZoneLeft = r - undoW
            actionsRight = undoZoneLeft
            val left = undoZoneLeft + padH
            val right = r - padH
            val top = cy - pillH / 2
            val bottom = cy + pillH / 2
            rectF.set(left, top, right, bottom)
            c.drawRoundRect(rectF, pillH / 2, pillH / 2, undoPillFill)
            drawUndoIcon(c, (left + right) / 2f, cy, dp(8f))
        } else {
            undoZoneLeft = Float.MAX_VALUE
        }
        if (actions.isEmpty()) return
        val slot = (actionsRight - start) / actions.size
        val base = cy - (textAction.descent() + textAction.ascent()) / 2f
        for (i in actions.indices) {
            val left = start + slot * i + padH
            val right = start + slot * (i + 1) - padH
            val top = cy - pillH / 2
            val bottom = cy + pillH / 2
            rectF.set(left, top, right, bottom)
            chipGradient.shader = android.graphics.LinearGradient(
                left, top, right, bottom, gradStart, gradEnd,
                android.graphics.Shader.TileMode.CLAMP,
            )
            c.drawRoundRect(rectF, pillH / 2, pillH / 2, chipGradient)
            c.drawText(actions[i], (left + right) / 2f, base, textAction)
        }
    }

    /** Counter-clockwise circular arrow = "undo". */
    private fun drawUndoIcon(c: Canvas, cx: Float, cy: Float, r: Float) {
        rectF.set(cx - r, cy - r, cx + r, cy + r)
        val start = 40f
        val sweep = -300f // counter-clockwise, leaving a gap for the arrowhead
        c.drawArc(rectF, start, sweep, false, undoStroke)
        // Arrowhead at the end of the sweep, barbs against the travel direction.
        val a = Math.toRadians((start + sweep).toDouble())
        val ex = (cx + r * Math.cos(a)).toFloat()
        val ey = (cy + r * Math.sin(a)).toFloat()
        val tx = Math.sin(a).toFloat()        // tangent for a CCW sweep
        val ty = (-Math.cos(a)).toFloat()
        val h = dp(5f)
        for (off in listOf(35.0, -35.0)) {
            val ca = Math.toRadians(off)
            val dx = (tx * Math.cos(ca) - ty * Math.sin(ca)).toFloat()
            val dy = (tx * Math.sin(ca) + ty * Math.cos(ca)).toFloat()
            c.drawLine(ex, ey, ex - dx * h, ey - dy * h, undoStroke)
        }
    }

    /**
     * Paid-only premium accent: a 3dp brand-gradient line on the panel's top
     * edge, clipped to a rounded-top rect whose radius matches the panel fill
     * (transkey_kb_panel_premium = 12dp) so the bar hugs the rounded corners
     * instead of overflowing past them.
     */
    private fun drawTopBar(c: Canvas) {
        val r = dp(12f)
        val barH = dp(3f)
        val w = width.toFloat()
        topBarPath.reset()
        topBarPath.addRoundRect(
            0f, 0f, w, r,
            floatArrayOf(r, r, r, r, 0f, 0f, 0f, 0f),
            Path.Direction.CW,
        )
        c.save()
        c.clipPath(topBarPath)
        topBarPaint.shader = android.graphics.LinearGradient(
            0f, 0f, w, 0f, gradStart, gradEnd, android.graphics.Shader.TileMode.CLAMP,
        )
        c.drawRect(0f, 0f, w, barH, topBarPaint)
        c.restore()
    }

    private fun drawGrid(c: Canvas, cx: Float, cy: Float) {
        val sq = dp(7f)
        val off = dp(5.5f)
        // Brand-gradient icon color (same #6366F1 -> #A855F7 as the chips), spanning
        // the 2x2 grid's bounding box so the four squares share one diagonal sweep.
        val ext = off + sq / 2
        fill.shader = android.graphics.LinearGradient(
            cx - ext, cy - ext, cx + ext, cy + ext, gradStart, gradEnd,
            android.graphics.Shader.TileMode.CLAMP,
        )
        for (dx in listOf(-off, off)) for (dy in listOf(-off, off)) {
            rectF.set(cx + dx - sq / 2, cy + dy - sq / 2, cx + dx + sq / 2, cy + dy + sq / 2)
            c.drawRoundRect(rectF, dp(2f), dp(2f), fill)
        }
    }

    private fun drawMic(c: Canvas, cx: Float, cy: Float, s: Float) {
        // Listening: red circle + white mic so voice-on is obvious. Idle: gray.
        val p = if (micListening) {
            c.drawCircle(cx, cy + s * 0.1f, s * 1.75f, micRedFill)
            undoStroke
        } else {
            // Idle mic: brand-gradient stroke (matches the grid icon + chips),
            // spanning the mic glyph's bounding box for a single diagonal sweep.
            stroke.shader = android.graphics.LinearGradient(
                cx - s * 0.8f, cy - s, cx + s * 0.8f, cy + s * 1.15f, gradStart, gradEnd,
                android.graphics.Shader.TileMode.CLAMP,
            )
            stroke
        }
        rectF.set(cx - s * 0.5f, cy - s, cx + s * 0.5f, cy + s * 0.2f)
        c.drawRoundRect(rectF, s * 0.5f, s * 0.5f, p)
        rectF.set(cx - s * 0.8f, cy - s * 0.45f, cx + s * 0.8f, cy + s * 0.7f)
        c.drawArc(rectF, 20f, 140f, false, p)
        c.drawLine(cx, cy + s * 0.7f, cx, cy + s * 1.15f, p)
        c.drawLine(cx - s * 0.5f, cy + s * 1.15f, cx + s * 0.5f, cy + s * 1.15f, p)
    }

    // Long-press the mic to open the voice-language picker (Gboard pattern).
    var onMicLongPress: (() -> Unit)? = null
    private var micLongPressFired = false
    private val micLongPressRunnable = Runnable {
        micLongPressFired = true
        onMicLongPress?.invoke()
    }

    override fun onTouchEvent(e: MotionEvent): Boolean {
        val x = e.x
        when (e.action) {
            MotionEvent.ACTION_DOWN -> {
                micLongPressFired = false
                if (x > width - sideZone && onMicLongPress != null) {
                    postDelayed(
                        micLongPressRunnable,
                        android.view.ViewConfiguration.getLongPressTimeout().toLong(),
                    )
                }
            }
            MotionEvent.ACTION_MOVE -> {
                if (x <= width - sideZone) removeCallbacks(micLongPressRunnable)
            }
            MotionEvent.ACTION_CANCEL -> removeCallbacks(micLongPressRunnable)
            MotionEvent.ACTION_UP -> {
                removeCallbacks(micLongPressRunnable)
                if (micLongPressFired) { micLongPressFired = false; return true }
                handleTap(x)
            }
        }
        return true
    }

    private fun handleTap(x: Float) {
        when {
            x < sideZone -> onGridTap?.invoke()
            x > width - sideZone -> onMicTap?.invoke()
            processing -> { /* locked while a request is in flight */ }
            suggestions.isNotEmpty() -> {
                if (hasExpandZone && x >= expandLeft) { onExpandTap?.invoke(); return }
                val l = sideZone
                val vis = visibleCount.coerceAtLeast(1)
                val slot = (expandLeft - l) / vis
                val i = ((x - l) / slot).toInt().coerceIn(0, vis - 1)
                onSuggestionTap?.invoke(suggestions.getOrElse(i) { suggestions.first() })
            }
            actions.isNotEmpty() || langLabel.isNotEmpty() -> {
                val l = sideZone
                val r = width - sideZone
                if (langLabel.isNotEmpty() && x < langPillRight) {
                    onLangTap?.invoke()
                } else if (undoVisible && x >= undoZoneLeft) {
                    onUndoTap?.invoke()
                } else if (actions.isNotEmpty()) {
                    val start = if (langLabel.isNotEmpty()) langPillRight else l
                    val actionsRight = if (undoVisible) undoZoneLeft else r
                    val slot = (actionsRight - start) / actions.size
                    val i = ((x - start) / slot).toInt().coerceIn(0, actions.size - 1)
                    onActionTap?.invoke(i)
                }
            }
        }
    }
}
