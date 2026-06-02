package app.transkey.mobile

import android.content.Context
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RectF
import android.inputmethodservice.Keyboard
import android.inputmethodservice.KeyboardView
import android.util.AttributeSet
import android.util.SparseArray
import android.view.MotionEvent
import java.util.Collections
import java.util.IdentityHashMap

/**
 * Gboard-styled keyboard renderer with its own layout + touch handling.
 *
 * The deprecated AOSP [KeyboardView] could only paint one key colour, drew no
 * number hints, and - worst - kept fighting us on touch: its nearest-key grid
 * returned nothing for some in-bounds points, and [Keyboard.resize] re-laid the
 * keys out (with gaps) right after we adjusted them, reviving ~28% of dead
 * "gap" area. So we own everything that matters:
 *
 *  - [tileTouchTargets] computes, ONCE per keyboard, a [visualRects] cap (the
 *    centered Gboard-look rectangle) and a [touchRects] hit box that tiles the
 *    whole keyboard with no gaps. Both are stored in maps and used for drawing
 *    and hit-testing, so KeyboardView/resize mutating key.x can't break us.
 *  - [onDraw] paints the caps (letter vs tinted function colour, number hints,
 *    Gboard line icons, off-white text) from [visualRects].
 *  - [onTouchEvent] hit-tests against [touchRects] and dispatches press / key /
 *    repeat itself, so every tap - edges and the space bar included - lands.
 *
 * Colours were pixel-sampled from Gboard on the device (Material You dark).
 */
class GboardKeyboardView : KeyboardView {

    constructor(context: Context, attrs: AttributeSet?) : super(context, attrs)
    constructor(context: Context, attrs: AttributeSet?, defStyle: Int) :
        super(context, attrs, defStyle)

    private val d = resources.displayMetrics.density
    private fun dp(v: Float) = v * d
    private fun sp(v: Float) = v * resources.displayMetrics.scaledDensity

    private val radius = dp(6f)
    // Bigger caps / smaller visual gap (the layout's ~11px) for fast-typing
    // accuracy; touch tiling already fills the gaps anyway.
    private val insetX = 0f
    private val iconSize = dp(10.5f)
    private val hintDx = dp(8f)   // number hint nearer the top-RIGHT corner
    private val hintDy = dp(12f)  // (was 12/15, sat too close to the letter)

    private val colLetter = 0xFF38393F.toInt()
    private val colLetterPressed = 0xFF5A5B62.toInt()
    private val colAction = 0xFF404659.toInt()
    private val colActionPressed = 0xFF5C6286.toInt()
    private val colText = 0xFFE2E2E9.toInt()
    private val colHint = 0xFF9AA0A6.toInt()
    private val colSpace = 0xFFBFC2C9.toInt()

    private val capPaint = Paint(Paint.ANTI_ALIAS_FLAG)
    private val labelPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = colText; textAlign = Paint.Align.CENTER; textSize = sp(18f)
    }
    private val symbolPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = colText; textAlign = Paint.Align.CENTER; textSize = sp(15f)
    }
    private val spacePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = colSpace; textAlign = Paint.Align.CENTER; textSize = sp(13f)
    }
    private val hintPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = colHint; textAlign = Paint.Align.CENTER; textSize = sp(9.5f)
    }
    private val iconStroke = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = colText; style = Paint.Style.STROKE
        strokeWidth = dp(2f); strokeCap = Paint.Cap.ROUND; strokeJoin = Paint.Join.ROUND
    }
    private val iconFill = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = colText; style = Paint.Style.FILL
    }

    private val rectF = RectF()
    private val path = Path()

    // Our own layout, immune to KeyboardView/resize mutating key.x.
    private val visualRects = IdentityHashMap<Keyboard.Key, RectF>()
    private val touchRects = IdentityHashMap<Keyboard.Key, RectF>()
    private val tiled = Collections.newSetFromMap(IdentityHashMap<Keyboard, Boolean>())
    private var layoutHeight = 0

    // Custom multi-touch dispatch. Each finger tracks the key under it
    // (updated as it slides), and commits on lift - so a fast typist who lands
    // a hair off and rolls onto the key gets the key they settled on, like
    // Gboard. Repeatable keys (backspace) fire on hold.
    private var actionListener: OnKeyboardActionListener? = null
    private val pointerKeys = SparseArray<Keyboard.Key>()
    private var repeatKey: Keyboard.Key? = null
    private var repeated = false
    private val repeatRunnable = object : Runnable {
        override fun run() {
            val k = repeatKey ?: return
            actionListener?.onKey(k.codes.firstOrNull() ?: 0, k.codes)
            repeated = true
            postDelayed(this, REPEAT_INTERVAL)
        }
    }

    /**
     * Long-press hook (e.g. the comma key shows the emoji picker on hold).
     * Returns true if the hold was consumed, so the lift won't also emit the
     * normal key. Single-finger gesture; cancelled if the finger slides off.
     */
    var onLongPress: ((Int) -> Boolean)? = null
    /**
     * Space-bar swipe to move the caret: invoked with +1 (right) / -1 (left) once
     * per [CURSOR_STEP] of horizontal travel while a finger drags across space.
     */
    var onCursorMove: ((Int) -> Unit)? = null
    /** Caps-lock vs one-shot shift: draws the lock underline on the shift key. */
    var shiftLocked: Boolean = false
    /**
     * Japanese flick. [flickProvider] returns the 5 labels
     * [center, left, up, right, down] for a flickable key code (null = normal
     * key). When such a key lifts, [onFlick] is called with (code, direction)
     * 0=center,1=left,2=up,3=right,4=down INSTEAD of the usual onKey.
     */
    var flickProvider: ((Int) -> Array<String>?)? = null
    var onFlick: ((Int, Int) -> Unit)? = null
    private var flickPointerId = -1
    private var flickKey: Keyboard.Key? = null
    private var flickDownX = 0f
    private var flickDownY = 0f
    private var flickDir = 0
    private var flickLabels: Array<String>? = null
    private var longPressId = -1
    private var longPressFired = false
    private val longPressRunnable = Runnable {
        val k = pointerKeys.get(longPressId) ?: return@Runnable
        if (onLongPress?.invoke(k.codes.firstOrNull() ?: 0) == true) {
            longPressFired = true
            k.pressed = false
            pointerKeys.remove(longPressId) // lift won't re-emit the key
            invalidate()
        }
    }

    private val numberHints = mapOf(
        'q' to "1", 'w' to "2", 'e' to "3", 'r' to "4", 't' to "5",
        'y' to "6", 'u' to "7", 'i' to "8", 'o' to "9", 'p' to "0",
    )

    private val actionCodes = setOf(
        TransKeyIME.KEYCODE_SHIFT, TransKeyIME.KEYCODE_DELETE,
        TransKeyIME.KEYCODE_ENTER, TransKeyIME.KEYCODE_SYMBOLS,
        TransKeyIME.KEYCODE_EMOJI, TransKeyIME.KEYCODE_LANG_GLOBE,
        TransKeyIME.KEYCODE_KANA_TOGGLE,
    )

    companion object {
        private const val REPEAT_DELAY = 400L
        private const val REPEAT_INTERVAL = 55L
        private const val LONGPRESS_DELAY = 300L
    }

    // Right-shift of the leftmost letter column's touch boundary (px), to catch
    // the measured ~+23px overshoot when a thumb reaches q/a.
    private val EDGE_GROW = dp(7f) // ~19px on this 440dpi device

    // Upward touch bias (px), measured from real thumb-typing: the TOP letter
    // row undershoots most (thumb stretches up, pad lands ~18px low), the home
    // row ~12px, the bottom row ~0. So bias is STRONGER at the top and fades
    // downward. Measured on this device (~440dpi); dp-scaled for others.
    private val biasTop = dp(6.2f)    // ~17px on this 440dpi device (measured)
    private val biasBottom = dp(0.7f) // ~2px
    // How far above the space bar a tap still counts as space. Kept small so the
    // band only covers the GAP above space, stopping at the bottom edge of the
    // b/n keys - a larger value ate the lower part of b/n (taps fell into space).
    private val spaceReachUp = dp(5f)
    // Resting thumb home columns (fraction of width): left ~ s/d/z/x,
    // right ~ j/k/n/m. The left thumb is more mobile and reaches past centre
    // (to ~u/j/n), so the left/right split sits right of centre.
    private val leftThumbHome = 0.22f
    private val rightThumbHome = 0.73f
    private val thumbSplit = 0.62f
    private val REACH_GAIN = 0.6f // far keys undershoot a bit more (measured)

    // Space-bar swipe-to-move-caret state. Once a finger that landed on space
    // travels past SWIPE_SLOP horizontally, it stops being a space tap and emits
    // one caret move per CURSOR_STEP of further travel.
    private var spacePointerId = -1
    private var spaceDownX = 0f
    private var spaceSwiping = false
    private var cursorAnchorX = 0f
    private val SWIPE_SLOP = dp(12f)
    private val CURSOR_STEP = dp(11f)

    // JA flick: travel past this (px) from the down point picks a direction;
    // a shorter move stays on the center kana.
    private val FLICK_SLOP = dp(20f)
    private val flickBgPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.FILL }
    private val flickTextPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        textAlign = Paint.Align.CENTER; textSize = sp(20f)
    }
    private val colFlickCell = 0xFF2A2B31.toInt()
    private val colFlickActive = 0xFF6366F1.toInt() // brand indigo

    init { isPreviewEnabled = false }

    /** Fill the full parent width so edge taps reach us; height = our layout. */
    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        val kb = keyboard
        if (kb == null) {
            super.onMeasure(widthMeasureSpec, heightMeasureSpec)
            return
        }
        val h = if (layoutHeight > 0) layoutHeight else kb.height
        setMeasuredDimension(
            MeasureSpec.getSize(widthMeasureSpec),
            h + paddingTop + paddingBottom,
        )
    }

    override fun setKeyboard(keyboard: Keyboard?) {
        super.setKeyboard(keyboard)
        keyboard?.let {
            // Always track the bound keyboard's height: layouts can differ
            // (Thai = 5 rows, others = 4, symbols rescaled to match), so a
            // stale layoutHeight from a previous keyboard would size us wrong.
            layoutHeight = it.height
            tileTouchTargets(it)
        }
    }

    /**
     * Drop [kb]'s cached touch/visual layout so it is rebuilt on the next bind.
     * Call after externally changing its key geometry (e.g. a height rescale),
     * otherwise the stale cached rects/height are reused and the keyboard draws
     * at the wrong size (e.g. a symbols layer rescaled for Thai overflowing in a
     * 4-row language).
     */
    fun refreshLayout(kb: Keyboard?) { kb?.let { tiled.remove(it) } }

    override fun setOnKeyboardActionListener(listener: OnKeyboardActionListener?) {
        super.setOnKeyboardActionListener(listener)
        actionListener = listener
    }

    /**
     * Build our layout from the (already centered) key positions: a visual cap
     * per key, and a touch box that tiles the keyboard edge-to-edge (each gap
     * split at its midpoint; first/last key and top/bottom row reach the
     * keyboard edges). Stored in maps; key fields are left untouched.
     */
    private fun tileTouchTargets(kb: Keyboard) {
        if (!tiled.add(kb)) return
        val screenW = resources.displayMetrics.widthPixels.toFloat()
        val kbHeight = kb.height
        layoutHeight = kbHeight
        val rowsByY = kb.keys.groupBy { it.y }.toSortedMap()
        val ys = rowsByY.keys.toList()
        val rowTop = ys
        val rowHeight = ys.map { y -> rowsByY.getValue(y).maxOf { it.height } }
        rowsByY.values.forEachIndexed { ri, rowUnsorted ->
            val row = rowUnsorted.sortedBy { it.x }
            val ox = row.map { it.x }
            val ow = row.map { it.width }
            val visTop = rowTop[ri].toFloat()
            val visBottom = (rowTop[ri] + rowHeight[ri]).toFloat()
            val tTop = if (ri == 0) 0f else (rowTop[ri - 1] + rowHeight[ri - 1] + rowTop[ri]) / 2f
            val tBottom =
                if (ri == ys.size - 1) kbHeight.toFloat()
                else (rowTop[ri] + rowHeight[ri] + rowTop[ri + 1]) / 2f
            row.forEachIndexed { ki, key ->
                visualRects[key] = RectF(
                    ox[ki].toFloat(), visTop, (ox[ki] + ow[ki]).toFloat(), visBottom,
                )
                var tLeft = if (ki == 0) 0f else (ox[ki - 1] + ow[ki - 1] + ox[ki]) / 2f
                var tRight = if (ki == row.size - 1) screenW else (ox[ki] + ow[ki] + ox[ki + 1]) / 2f
                // Edge-key widening: a thumb reaching the leftmost letter column
                // (q, a) lands ~+23px right of centre (measured), so a fast tap
                // spills into the 2nd key. Grow the first letter column's right
                // boundary (and pull the 2nd key's left to match) so q/a keep
                // that overshoot. Only when col 0 is an actual letter (skips the
                // shift row), and only letter rows.
                val firstIsLetter = (row[0].codes.firstOrNull() ?: 0) in 'a'.code..'z'.code
                if (firstIsLetter) {
                    if (ki == 0) tRight += EDGE_GROW
                    if (ki == 1) tLeft += EDGE_GROW
                }
                touchRects[key] = RectF(tLeft, tTop, tRight, tBottom)
            }
        }
    }

    override fun onTouchEvent(event: MotionEvent): Boolean {
        when (event.actionMasked) {
            MotionEvent.ACTION_DOWN, MotionEvent.ACTION_POINTER_DOWN -> {
                val i = event.actionIndex
                pointerDown(event.getPointerId(i), event.getX(i), event.getY(i))
            }
            MotionEvent.ACTION_MOVE -> {
                for (p in 0 until event.pointerCount) {
                    val id = event.getPointerId(p)
                    val idx = event.findPointerIndex(id)
                    if (idx < 0) continue
                    val px = event.getX(idx)
                    // Flick drag: handle BEFORE the in-bounds guard - the finger
                    // slides across key boundaries but stays bound to its key.
                    if (id == flickPointerId) {
                        val dir = flickDirection(px - flickDownX, event.getY(p) - flickDownY)
                        if (dir != flickDir) { flickDir = dir; invalidate() }
                        continue
                    }
                    // Space-bar swipe: handle BEFORE the in-bounds guard, because
                    // once swiping we detach the pointer from any key.
                    if (id == spacePointerId) {
                        if (!spaceSwiping &&
                            kotlin.math.abs(px - spaceDownX) > SWIPE_SLOP
                        ) {
                            spaceSwiping = true
                            removeCallbacks(longPressRunnable)
                            removeCallbacks(repeatRunnable)
                            cursorAnchorX = px
                            setPointerKey(id, null) // no space will be typed on lift
                        }
                        if (spaceSwiping) {
                            while (px - cursorAnchorX >= CURSOR_STEP) {
                                onCursorMove?.invoke(1); cursorAnchorX += CURSOR_STEP
                            }
                            while (cursorAnchorX - px >= CURSOR_STEP) {
                                onCursorMove?.invoke(-1); cursorAnchorX -= CURSOR_STEP
                            }
                            continue
                        }
                    }
                    if (pointerKeys.indexOfKey(id) < 0) continue
                    val k = keyAt(px, event.getY(p))
                    if (k !== pointerKeys.get(id)) setPointerKey(id, k)
                }
            }
            MotionEvent.ACTION_UP, MotionEvent.ACTION_POINTER_UP ->
                pointerUp(event.getPointerId(event.actionIndex))
            MotionEvent.ACTION_CANCEL -> {
                removeCallbacks(repeatRunnable)
                removeCallbacks(longPressRunnable)
                repeatKey = null
                spacePointerId = -1
                spaceSwiping = false
                clearFlick()
                for (i in 0 until pointerKeys.size()) pointerKeys.valueAt(i)?.pressed = false
                pointerKeys.clear()
                invalidate()
            }
        }
        return true
    }

    private fun pointerDown(id: Int, x: Float, y: Float) {
        val k = keyAt(x, y) ?: return
        setPointerKey(id, k)
        val code = k.codes.firstOrNull() ?: 0
        actionListener?.onPress(code) // haptic on touch
        // Japanese flick key: track the drag direction ourselves and emit a
        // flick on lift. Skip space-swipe / repeat / long-press for these.
        val labels = flickProvider?.invoke(code)
        if (labels != null) {
            flickPointerId = id
            flickKey = k
            flickDownX = x; flickDownY = y
            flickDir = 0
            flickLabels = labels
            invalidate()
            return
        }
        // Track a finger that landed on space so a later horizontal drag becomes
        // a caret move instead of typing a space.
        if (k.codes.firstOrNull() == TransKeyIME.KEYCODE_SPACE) {
            spacePointerId = id
            spaceDownX = x
            spaceSwiping = false
        }
        if (k.repeatable) {
            repeatKey = k
            repeated = false
            postDelayed(repeatRunnable, REPEAT_DELAY)
        } else {
            // Arm the long-press hook (space -> language, comma -> emoji). Only
            // for non-repeatable keys; backspace etc. use the repeat path. Keys
            // with no long-press action just get onLongPress == false on fire.
            longPressId = id
            longPressFired = false
            removeCallbacks(longPressRunnable)
            postDelayed(longPressRunnable, LONGPRESS_DELAY)
        }
    }

    /** Move a pointer onto a new key, updating the pressed highlight. */
    private fun setPointerKey(id: Int, k: Keyboard.Key?) {
        pointerKeys.get(id)?.pressed = false
        if (k != null) {
            pointerKeys.put(id, k)
            k.pressed = true
        } else {
            pointerKeys.remove(id)
        }
        invalidate()
    }

    private fun pointerUp(id: Int) {
        // A flick finger lifts: emit the chosen direction's kana, type no key.
        if (id == flickPointerId) {
            val k = flickKey
            val code = k?.codes?.firstOrNull() ?: 0
            val dir = flickDir
            k?.pressed = false
            pointerKeys.remove(id)
            clearFlick()
            if (code != 0) {
                onFlick?.invoke(code, dir)
                actionListener?.onRelease(code)
            }
            invalidate()
            return
        }
        if (id == longPressId) removeCallbacks(longPressRunnable)
        // A space-swipe finger lifts: it already moved the caret, type no space.
        if (id == spacePointerId) {
            spacePointerId = -1
            if (spaceSwiping) {
                spaceSwiping = false
                pointerKeys.remove(id)
                invalidate()
                return
            }
        }
        val k = pointerKeys.get(id)
        pointerKeys.remove(id)
        if (k != null) {
            k.pressed = false
            val code = k.codes.firstOrNull() ?: 0
            // Commit on lift (the settled key). Skip if a held repeat already fired it.
            if (!(k === repeatKey && repeated)) actionListener?.onKey(code, k.codes)
            actionListener?.onRelease(code)
            if (k === repeatKey) {
                removeCallbacks(repeatRunnable)
                repeatKey = null
            }
        }
        invalidate()
    }

    private fun clearFlick() {
        flickPointerId = -1; flickKey = null; flickLabels = null; flickDir = 0
    }

    /** Flick direction from the drag delta: 0=center,1=left,2=up,3=right,4=down. */
    private fun flickDirection(dx: Float, dy: Float): Int {
        if (dx * dx + dy * dy < FLICK_SLOP * FLICK_SLOP) return 0
        return if (kotlin.math.abs(dx) > kotlin.math.abs(dy)) {
            if (dx < 0) 1 else 3
        } else {
            if (dy < 0) 2 else 4
        }
    }

    /**
     * The key under the touch, with a Gboard-style touch model. People aim for
     * a key but their finger pad contacts slightly BELOW the perceived point
     * (most of all in the thumb-driven bottom rows), so a tap that lands in the
     * gap between two rows was meant for the UPPER one. We bias the test point
     * upward before hit-testing, more strongly the lower on the keyboard the
     * touch is. Containment in the gap-free [touchRects] then resolves it;
     * nearest-center is the out-of-bounds fallback.
     */
    private fun keyAt(rawX: Float, rawY: Float): Keyboard.Key? {
        val kb = keyboard ?: return null

        // Space-bar high-tap catch (runs on RAW coords, before the upward bias).
        // The thumb rests ABOVE the space bar, so taps land in the gap just
        // above it - the opposite of the finger-lands-low bias used elsewhere.
        // Treat a band above space (within its x-range) as space, so "aim for
        // space, hit between b/n and space" gives space, not b/n.
        for (k in kb.keys) {
            if (k.codes.firstOrNull() == TransKeyIME.KEYCODE_SPACE) {
                val r = touchRects[k] ?: break
                if (rawX >= r.left && rawX < r.right &&
                    rawY >= r.top - spaceReachUp && rawY < r.bottom
                ) return k
                break
            }
        }

        // Thumb-arc upward bias. Two effects compound:
        //  - row depth: contact lands lower the further down the keyboard.
        //  - reach: a thumb extended FAR from its home column (left ~s/d/z/x,
        //    right ~j/k/n/m) undershoots more than one tapping near home.
        // So bias = rowBias * (1 + REACH_GAIN * distanceFromNearestThumbHome).
        val w = width.toFloat()
        val h = if (layoutHeight > 0) layoutHeight.toFloat() else height.toFloat()
        val frac = if (h > 0) (rawY / h).coerceIn(0f, 1f) else 0f
        val rowBias = biasTop + (biasBottom - biasTop) * frac
        // Assign the touch to a thumb. The LEFT thumb is more mobile and covers
        // past the centre (up to ~u/j/n), so the split sits right of centre, not
        // at the midpoint between the two home columns. Reach = distance from
        // that thumb's home; the farther the reach the more the pad undershoots,
        // so we bias upward proportionally (vertical only for now).
        val home = if (rawX < thumbSplit * w) leftThumbHome * w else rightThumbHome * w
        val homeDist = kotlin.math.abs(rawX - home) / w
        val y = rawY - rowBias * (1f + REACH_GAIN * homeDist)
        val x = rawX
        var nearest: Keyboard.Key? = null
        var best = Float.MAX_VALUE
        for (k in kb.keys) {
            val r = touchRects[k] ?: continue
            if (x >= r.left && x < r.right && y >= r.top && y < r.bottom) return k
            val dx = r.centerX() - x
            val dy = r.centerY() - y
            val dd = dx * dx + dy * dy
            if (dd < best) { best = dd; nearest = k }
        }
        return nearest
    }

    override fun onDraw(canvas: Canvas) {
        val kb = keyboard ?: return
        val shifted = kb.isShifted
        val s = iconSize
        for (key in kb.keys) {
            val v = visualRects[key] ?: continue
            val code = key.codes.firstOrNull() ?: 0
            val action = code in actionCodes
            capPaint.color = when {
                key.pressed && action -> colActionPressed
                key.pressed -> colLetterPressed
                action -> colAction
                else -> colLetter
            }
            rectF.set(v.left + insetX, v.top, v.right - insetX, v.bottom)
            canvas.drawRoundRect(rectF, radius, radius, capPaint)

            val cx = rectF.centerX()
            val cy = rectF.centerY()
            when (code) {
                TransKeyIME.KEYCODE_SHIFT -> drawShift(canvas, cx, cy, s, shifted)
                TransKeyIME.KEYCODE_DELETE -> drawBackspace(canvas, cx, cy, s)
                TransKeyIME.KEYCODE_ENTER -> drawEnter(canvas, cx, cy, s)
                TransKeyIME.KEYCODE_LANG_GLOBE -> drawGlobe(canvas, cx, cy, s)
                TransKeyIME.KEYCODE_EMOJI -> drawEmoji(canvas, cx, cy, s)
                TransKeyIME.KEYCODE_SPACE -> key.label?.let {
                    canvas.drawText(it.toString(), cx, baseline(cy, spacePaint), spacePaint)
                }
                else -> {
                    val raw = key.label?.toString()
                    if (!raw.isNullOrEmpty()) {
                        val letter = raw.length == 1 && raw[0].isLetter()
                        val text = if (shifted && letter) raw.uppercase() else raw
                        // Single glyphs (letters, digits, single symbols) use the
                        // full label size for Gboard-level readability; only the
                        // multi-char toggles (=\<, ?123, ABC) shrink to fit.
                        val p = if (text.length == 1) labelPaint else symbolPaint
                        canvas.drawText(text, cx, baseline(cy, p), p)
                    }
                    numberHints[code.toChar().lowercaseChar()]?.let { hint ->
                        canvas.drawText(hint, rectF.right - hintDx, rectF.top + hintDy, hintPaint)
                    }
                    // Only the bottom-row comma doubles as the emoji key (long-
                    // press to emoji), so draw the discoverability smiley there.
                    // A comma inside a letter row (e.g. the Thai shift layer) is a
                    // plain comma and must not show the smiley.
                    if (code == ','.code && (key.edgeFlags and Keyboard.EDGE_BOTTOM) != 0) {
                        drawEmoji(canvas, cx, rectF.top + dp(12f), dp(5f))
                    }
                }
            }
        }
        drawFlickPreview(canvas)
    }

    /**
     * While a flick key is held, show its 5 kana in a plus around the key and
     * highlight the one the current drag would commit. Clamped into the view so
     * the top row's "up" cell and the edge columns aren't cut off.
     */
    private fun drawFlickPreview(canvas: Canvas) {
        val key = flickKey ?: return
        val labels = flickLabels ?: return
        val r = visualRects[key] ?: return
        val cw = r.width(); val ch = r.height()
        // Center the plus on the key, then clamp so all 5 cells stay on-screen.
        var cx = r.centerX()
        var cy = r.centerY()
        cx = cx.coerceIn(1.5f * cw, width - 1.5f * cw)
        val hh = if (layoutHeight > 0) layoutHeight.toFloat() else height.toFloat()
        cy = cy.coerceIn(1.5f * ch, hh - 1.5f * ch)
        // dir -> (col offset, row offset): center,left,up,right,down
        val offs = arrayOf(
            0 to 0, -1 to 0, 0 to -1, 1 to 0, 0 to 1,
        )
        for (i in 0..4) {
            val label = labels.getOrNull(i) ?: continue
            if (label.isEmpty()) continue
            val ox = cx + offs[i].first * cw
            val oy = cy + offs[i].second * ch
            rectF.set(ox - cw / 2 + dp(1f), oy - ch / 2 + dp(1f), ox + cw / 2 - dp(1f), oy + ch / 2 - dp(1f))
            flickBgPaint.color = if (i == flickDir) colFlickActive else colFlickCell
            canvas.drawRoundRect(rectF, radius, radius, flickBgPaint)
            flickTextPaint.color = colText
            canvas.drawText(label, ox, baseline(oy, flickTextPaint), flickTextPaint)
        }
    }

    private fun baseline(cy: Float, p: Paint) = cy - (p.descent() + p.ascent()) / 2f

    // ---- Gboard-style line icons, drawn with canvas primitives ----

    private fun drawShift(c: Canvas, cx: Float, cy: Float, s: Float, on: Boolean) {
        path.reset()
        path.moveTo(cx, cy - s)
        path.lineTo(cx - s, cy - s * 0.05f)
        path.lineTo(cx - s * 0.45f, cy - s * 0.05f)
        path.lineTo(cx - s * 0.45f, cy + s * 0.85f)
        path.lineTo(cx + s * 0.45f, cy + s * 0.85f)
        path.lineTo(cx + s * 0.45f, cy - s * 0.05f)
        path.lineTo(cx + s, cy - s * 0.05f)
        path.close()
        c.drawPath(path, if (on) iconFill else iconStroke)
        // Caps-lock: underline bar beneath the arrow (one-shot shift has none).
        if (shiftLocked) {
            c.drawLine(cx - s * 0.55f, cy + s * 1.15f, cx + s * 0.55f, cy + s * 1.15f, iconStroke)
        }
    }

    private fun drawBackspace(c: Canvas, cx: Float, cy: Float, s: Float) {
        val w = s * 1.35f
        path.reset()
        path.moveTo(cx - w, cy)
        path.lineTo(cx - s * 0.35f, cy - s)
        path.lineTo(cx + w, cy - s)
        path.lineTo(cx + w, cy + s)
        path.lineTo(cx - s * 0.35f, cy + s)
        path.close()
        c.drawPath(path, iconStroke)
        val xc = cx + s * 0.45f
        val a = s * 0.4f
        c.drawLine(xc - a, cy - a, xc + a, cy + a, iconStroke)
        c.drawLine(xc + a, cy - a, xc - a, cy + a, iconStroke)
    }

    private fun drawEnter(c: Canvas, cx: Float, cy: Float, s: Float) {
        path.reset()
        path.moveTo(cx + s, cy - s)
        path.lineTo(cx + s, cy + s * 0.25f)
        path.lineTo(cx - s, cy + s * 0.25f)
        c.drawPath(path, iconStroke)
        c.drawLine(cx - s, cy + s * 0.25f, cx - s * 0.25f, cy - s * 0.45f, iconStroke)
        c.drawLine(cx - s, cy + s * 0.25f, cx - s * 0.25f, cy + s * 0.95f, iconStroke)
    }

    private fun drawGlobe(c: Canvas, cx: Float, cy: Float, s: Float) {
        c.drawCircle(cx, cy, s, iconStroke)
        rectF.set(cx - s * 0.45f, cy - s, cx + s * 0.45f, cy + s)
        c.drawOval(rectF, iconStroke)
        c.drawLine(cx - s, cy, cx + s, cy, iconStroke)
    }

    private fun drawEmoji(c: Canvas, cx: Float, cy: Float, s: Float) {
        c.drawCircle(cx, cy, s, iconStroke)
        c.drawCircle(cx - s * 0.38f, cy - s * 0.22f, dp(1.4f), iconFill)
        c.drawCircle(cx + s * 0.38f, cy - s * 0.22f, dp(1.4f), iconFill)
        rectF.set(cx - s * 0.5f, cy - s * 0.35f, cx + s * 0.5f, cy + s * 0.5f)
        c.drawArc(rectF, 20f, 140f, false, iconStroke)
    }
}
