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
import android.util.SparseBooleanArray
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

    // Liquid Glass key caps - violet-tinted (was a flat Gboard-gray clone),
    // tuned to sit ~18 luma above the Glass.PANEL_DARK (#14121F) panel behind
    // them so caps stay clearly separated from the inter-key gaps.
    private val colLetter = 0xFF262435.toInt()
    private val colLetterPressed = 0xFF3A3654.toInt()
    private val colAction = 0xFF2E2C48.toInt()
    private val colActionPressed = 0xFF46427A.toInt()
    private val colText = 0xFFF3F2FF.toInt()
    private val colHint = 0xFF9A97B5.toInt()
    private val colSpace = 0xFFC9C6DE.toInt()

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

    /**
     * QWERTY-profile calibration, also used by the VNI layout (same letter
     * rows, one digit row on top). Complex, RTL and flick layouts stay neutral.
     */
    var useQwertyTouchBias = false

    /**
     * Top of the letter rows per keyboard (px), the origin the thumb bias is
     * measured from. Cached alongside the touch rects because a layout with an
     * extra row above the letters (VNI digits) would otherwise report every
     * letter row as sitting deeper than it does on plain QWERTY.
     */
    private val letterTops = IdentityHashMap<Keyboard, Float>()

    // Custom multi-touch dispatch. Each finger tracks the key under it
    // (updated as it slides), and commits on lift - so a fast typist who lands
    // a hair off and rolls onto the key gets the key they settled on, like
    // Gboard. Repeatable keys (backspace) fire on hold.
    private var actionListener: OnKeyboardActionListener? = null
    private val pointerKeys = SparseArray<Keyboard.Key>()
    /**
     * Pointers whose character was already emitted by the roll-over commit in
     * [pointerDown] (or by a held repeat), so their lift must not emit it again.
     */
    private val consumedPointers = SparseBooleanArray()
    private var repeatKey: Keyboard.Key? = null
    /**
     * The finger that owns the running key-repeat. Repeat MUST be cancelled by
     * owner, not by "is the current key still the repeat key": sliding off
     * backspace onto a letter changed the pointer's key, so the lift no longer
     * matched [repeatKey] and left the repeat runnable posted - backspace then
     * kept deleting after the finger was gone.
     */
    private var repeatPointerId = -1
    /**
     * Bumped by [cancelAllGestures]. A commit made from inside [pointerDown]
     * can re-enter the IME and tear the gesture state down underneath us, so
     * anything that resumes after such a commit must check this first.
     */
    private var gestureGen = 0
    private var repeated = false
    /** Repeats emitted for the current hold, used to accelerate a long hold. */
    private var repeatTicks = 0
    private val repeatRunnable = object : Runnable {
        override fun run() {
            val k = repeatKey ?: return
            actionListener?.onKey(k.codes.firstOrNull() ?: 0, k.codes)
            repeated = true
            repeatTicks++
            // Hold-to-delete accelerates, like the system keyboards: a steady
            // 100 ms is right for trimming a word but far too slow to clear a
            // sentence, and speeding up beats the old flat 55 ms, which
            // overshot on a short hold.
            postDelayed(
                this,
                if (repeatTicks >= REPEAT_ACCEL_AFTER) REPEAT_INTERVAL_FAST else REPEAT_INTERVAL,
            )
        }
    }

    /**
     * Emit the character still held under any other finger. Called when a new
     * finger lands so overlapping presses ("roll-over") come out in the order
     * they were PRESSED. Only plain character keys chord this way - space,
     * enter and the function keys keep their press-and-lift semantics, and a
     * finger mid-flick / mid-accent / mid-space-swipe is left alone.
     */
    private fun commitHeldChars() {
        // Snapshot the ids first: `onKey` runs the IME's commit path, which can
        // reach `onFinishInput` (the host moves focus on commit) -> our own
        // `cancelAllGestures()` -> `pointerKeys.clear()`. Indexing a SparseArray
        // whose size shrank mid-loop throws on API 30+ and kills the IME.
        val ids = IntArray(pointerKeys.size()) { pointerKeys.keyAt(it) }
        for (id in ids) {
            if (consumedPointers.get(id)) continue
            if (id == accentPointerId || id == spacePointerId) continue
            if (flickStates.get(id) != null) continue
            val k = pointerKeys.get(id) ?: continue
            if (k === repeatKey) continue
            val code = k.codes.firstOrNull() ?: 0
            if (!isCharCode(code)) continue
            if (id == longPressId) {
                removeCallbacks(longPressRunnable)
                longPressId = -1
            }
            consumedPointers.put(id, true)
            actionListener?.onKey(code, k.codes)
        }
    }

    /** A printable character key: not space, not one of the function keys. */
    private fun isCharCode(code: Int) = code > 0 && code != TransKeyIME.KEYCODE_SPACE

    /** End the running key-repeat, whoever owned it. */
    private fun stopRepeat() {
        removeCallbacks(repeatRunnable)
        repeatKey = null
        repeatPointerId = -1
        repeatTicks = 0
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
    /**
     * Flick gesture state, tracked PER FINGER: Japanese flick typing is a
     * two-thumb input method, and a single shared slot let the second thumb
     * overwrite the first one's key/direction (the first flick then fell through
     * to the plain-key path and emitted the wrong kana).
     */
    private class FlickState(
        val key: Keyboard.Key,
        val downX: Float,
        val downY: Float,
        val labels: Array<String>,
    ) {
        var dir = 0
    }
    private val flickStates = SparseArray<FlickState>()
    /**
     * Long-press accent popup (European Latin modes). [accentProvider] returns the
     * popup labels [base, accent…, number?] for (keyCode, shifted), or null for a
     * normal long-press. On lift the selected label is committed via [onAccent].
     */
    var accentProvider: ((Int, Boolean) -> Array<String>?)? = null
    var onAccent: ((String) -> Unit)? = null
    private var accentPointerId = -1
    private var accentKey: Keyboard.Key? = null
    private var accentLabels: Array<String>? = null
    private var accentIndex = 0
    private var longPressId = -1
    private var longPressFired = false
    private val longPressRunnable = Runnable {
        val k = pointerKeys.get(longPressId) ?: return@Runnable
        val code = k.codes.firstOrNull() ?: 0
        // Accent popup (European Latin modes) wins over the normal long-press.
        // The finger stays down: MOVE slides the selection, lift commits it.
        val labels = accentProvider?.invoke(code, keyboard?.isShifted == true)
        if (labels != null && labels.size > 1) {
            accentPointerId = longPressId
            accentKey = k
            accentLabels = labels
            accentIndex = 0
            longPressFired = true
            invalidate()
            return@Runnable
        }
        if (onLongPress?.invoke(code) == true) {
            longPressFired = true
            k.pressed = false
            pointerKeys.remove(longPressId) // lift won't re-emit the key
            invalidate()
        }
    }

    // Keyed by the key's lowercase char CODE, not by Char: a Map<Char, _>
    // lookup boxes the key on every hint draw, i.e. once per top-row key per
    // frame, and the strip redraws on every press.
    private val numberHints = SparseArray<String>().apply {
        put('q'.code, "1"); put('w'.code, "2"); put('e'.code, "3")
        put('r'.code, "4"); put('t'.code, "5"); put('y'.code, "6")
        put('u'.code, "7"); put('i'.code, "8"); put('o'.code, "9")
        put('p'.code, "0")
    }

    /**
     * Shifted labels, cached. `label.uppercase()` allocated a fresh String for
     * every letter key on every frame, and a drag repaints continuously.
     */
    private val upperLabels = HashMap<String, String>()

    private val actionCodes = setOf(
        TransKeyIME.KEYCODE_SHIFT, TransKeyIME.KEYCODE_DELETE,
        TransKeyIME.KEYCODE_ENTER, TransKeyIME.KEYCODE_SYMBOLS,
        TransKeyIME.KEYCODE_EMOJI, TransKeyIME.KEYCODE_LANG_GLOBE,
        TransKeyIME.KEYCODE_KANA_TOGGLE,
    )

    companion object {
        // Hold-to-repeat, matched to the iOS keyboard so backspace feels the
        // same on both platforms: pause, then a steady rate, then accelerate.
        // The first press already fired on touch-down, so this delay only gates
        // the SECOND delete.
        private const val REPEAT_DELAY = 500L
        private const val REPEAT_INTERVAL = 100L
        private const val REPEAT_INTERVAL_FAST = 45L
        private const val REPEAT_ACCEL_AFTER = 12
        // 300 ms was short enough that merely pausing a thumb on the top letter
        // row committed the key's corner digit instead of the letter. 500 ms is
        // the iOS long-press timing and roughly the platform default.
        private const val LONGPRESS_DELAY = 500L
        // Flick cell offsets by direction (center, left, up, right, down).
        // Hoisted out of the draw loop: rebuilding them per frame allocated an
        // array plus 5 boxed Pairs on every drag frame.
        private val FLICK_COL_OFF = intArrayOf(0, -1, 0, 1, 0)
        private val FLICK_ROW_OFF = intArrayOf(0, 0, -1, 0, 1)
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

    // How far outside the view a touch may stray and still hit-test to a key.
    // Past this the gesture counts as "dragged off to cancel".
    private val OFF_KEYBOARD_SLOP = dp(28f)
    private val flickBgPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.FILL }
    private val flickTextPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        textAlign = Paint.Align.CENTER; textSize = sp(20f)
    }
    private val colFlickCell = 0xFF2E2C48.toInt() // matches colAction, glass-tinted
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

    override fun onSizeChanged(w: Int, h: Int, oldw: Int, oldh: Int) {
        super.onSizeChanged(w, h, oldw, oldh)
        if (w != oldw) keyboard?.let {
            tiled.remove(it)
            tileTouchTargets(it)
        }
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
        val viewW = width.takeIf { it > 0 }?.toFloat()
            ?: measuredWidth.takeIf { it > 0 }?.toFloat()
            ?: resources.displayMetrics.widthPixels.toFloat()
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
                var tRight = if (ki == row.size - 1) viewW else (ox[ki] + ow[ki] + ox[ki + 1]) / 2f
                val firstIsLetter = (row[0].codes.firstOrNull() ?: 0) in 'a'.code..'z'.code
                val lastIsLetter = (row.last().codes.firstOrNull() ?: 0) in 'a'.code..'z'.code
                val adjusted = TouchBiasModel.growLetterEdges(
                    ki, row.size, tLeft, tRight, EDGE_GROW, firstIsLetter, lastIsLetter,
                )
                tLeft = adjusted.first
                tRight = adjusted.second
                touchRects[key] = RectF(tLeft, tTop, tRight, tBottom)
            }
        }
        letterTops[kb] = kb.keys
            .filter { (it.codes.firstOrNull() ?: 0) in 'a'.code..'z'.code }
            .minOfOrNull { touchRects[it]?.top ?: 0f } ?: 0f
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
                    val fs = flickStates.get(id)
                    if (fs != null) {
                        val dir = flickDirection(px - fs.downX, event.getY(p) - fs.downY)
                        if (dir != fs.dir) { fs.dir = dir; invalidate() }
                        continue
                    }
                    // Accent popup drag: slide horizontally to pick a variant.
                    if (id == accentPointerId) {
                        val idx = accentIndexFor(px)
                        if (idx != accentIndex) { accentIndex = idx; invalidate() }
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
                    // A finger holding a repeatable key (backspace) does not
                    // retarget: it keeps deleting until it lifts, like the
                    // system keyboards. Letting it adopt the key underneath
                    // both ended the repeat early and typed a stray character.
                    if (id == repeatPointerId) continue
                    val k = keyAt(px, event.getY(p))
                    if (k !== pointerKeys.get(id)) setPointerKey(id, k)
                }
            }
            MotionEvent.ACTION_UP, MotionEvent.ACTION_POINTER_UP ->
                pointerUp(event.getPointerId(event.actionIndex))
            MotionEvent.ACTION_CANCEL -> cancelAllGestures()
        }
        return true
    }

    private fun pointerDown(id: Int, x: Float, y: Float) {
        val k = keyAt(x, y) ?: return
        // Roll-over commit, like Gboard and the iOS keyboard: a character used
        // to be emitted only on LIFT, so output order followed the order the
        // fingers were RAISED, not the order they landed - a fast typist who
        // pressed 'a' then 'b' but released 'b' first got "ba". Chord the
        // still-held character out now, before the new finger is registered.
        //
        // That commit re-enters the IME, and in a field that closes after one
        // character it can reach onFinishInput -> cancelAllGestures(). Snapshot
        // the gesture generation so we do NOT re-register this pointer on top
        // of a cleanup that just happened - it would survive into the next
        // input session and type a stray character there.
        val gen = gestureGen
        commitHeldChars()
        if (gen != gestureGen) return
        setPointerKey(id, k)
        val code = k.codes.firstOrNull() ?: 0
        actionListener?.onPress(code) // haptic + click on touch
        // Japanese flick key: track the drag direction ourselves and emit a
        // flick on lift. Skip space-swipe / repeat / long-press for these.
        val labels = flickProvider?.invoke(code)
        if (labels != null) {
            flickStates.put(id, FlickState(k, x, y, labels))
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
            // A second finger landing on delete must not stack a second
            // runnable on top of the first, which doubled the delete rate.
            if (repeatPointerId != -1) stopRepeat()
            repeatKey = k
            // Act on touch DOWN (backspace deletes immediately, like iOS and the
            // system keyboards). It used to fire only on lift or after the
            // REPEAT_DELAY, so a quick tap felt like the key was dead. `repeated`
            // is set now so the lift does not delete a second time.
            actionListener?.onKey(code, k.codes)
            repeated = true
            repeatTicks = 0
            repeatPointerId = id
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
        // Sliding onto a different key cancels this finger's long-press. The
        // timer resolved against whatever key the finger had moved TO, so
        // sliding across the top row and pausing popped a digit from a key the
        // user never pressed. Jitter inside one key never reaches here - the
        // caller only calls us when the key actually changed - so this doubles
        // as the movement slop.
        if (id == longPressId) {
            removeCallbacks(longPressRunnable)
            longPressId = -1
        }
        // Same for the key-repeat: sliding off backspace ends the repeat, it
        // does not hand it to the key underneath.
        if (id == repeatPointerId) stopRepeat()
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
        // An accent finger lifts: commit the selected variant, type no base key.
        if (id == accentPointerId) {
            val sel = accentLabels?.getOrNull(accentIndex)
            val k = accentKey
            val code = k?.codes?.firstOrNull() ?: 0
            k?.pressed = false
            pointerKeys.remove(id)
            consumedPointers.delete(id)
            clearAccent()
            if (!sel.isNullOrEmpty()) onAccent?.invoke(sel)
            actionListener?.onRelease(code)
            invalidate()
            return
        }
        // A flick finger lifts: emit the chosen direction's kana, type no key.
        val fs = flickStates.get(id)
        if (fs != null) {
            val code = fs.key.codes.firstOrNull() ?: 0
            fs.key.pressed = false
            pointerKeys.remove(id)
            consumedPointers.delete(id)
            flickStates.remove(id)
            if (code != 0) {
                onFlick?.invoke(code, fs.dir)
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
                consumedPointers.delete(id)
                invalidate()
                return
            }
        }
        val k = pointerKeys.get(id)
        val alreadyEmitted = consumedPointers.get(id)
        pointerKeys.remove(id)
        consumedPointers.delete(id)
        if (k != null) {
            k.pressed = false
            val code = k.codes.firstOrNull() ?: 0
            // Commit on lift (the settled key). Skip when this finger's key was
            // already emitted - either by the roll-over commit in [pointerDown]
            // or by a held repeat.
            if (!alreadyEmitted && !(k === repeatKey && repeated)) {
                actionListener?.onKey(code, k.codes)
            }
            actionListener?.onRelease(code)
        }
        // Cancel by OWNER, not by "the key under this finger is still the
        // repeat key" - a finger that slid off backspace no longer matches it
        // and used to leave the repeat running after the lift.
        if (id == repeatPointerId) stopRepeat()
        invalidate()
    }

    /**
     * Drop every in-flight gesture and pressed state. Called on ACTION_CANCEL
     * and from the IME when the keyboard window goes away (app switch, IME
     * switch, field closed) - without that lifecycle call a held backspace kept
     * its repeat runnable posted and a popup could stay stuck on screen.
     */
    fun cancelAllGestures() {
        gestureGen++
        stopRepeat()
        removeCallbacks(longPressRunnable)
        repeated = false
        longPressId = -1
        longPressFired = false
        spacePointerId = -1
        spaceSwiping = false
        flickStates.clear()
        clearAccent()
        for (i in 0 until pointerKeys.size()) pointerKeys.valueAt(i)?.pressed = false
        pointerKeys.clear()
        consumedPointers.clear()
        invalidate()
    }

    private fun clearAccent() {
        accentPointerId = -1; accentKey = null; accentLabels = null; accentIndex = 0
    }

    /**
     * Accent popup geometry: [startX, top, cellW, cellH]. A horizontal row of
     * `labels.size` cells, key-width each, centred over the key and clamped into
     * the view; placed above the key, or below it when the key is in the top row.
     */
    private fun accentGeom(): FloatArray? {
        val key = accentKey ?: return null
        val labels = accentLabels ?: return null
        val r = visualRects[key] ?: return null
        val cellW = r.width(); val cellH = r.height()
        val total = labels.size * cellW
        val startX = (r.centerX() - total / 2f).coerceIn(0f, (width - total).coerceAtLeast(0f))
        var top = r.top - cellH - dp(6f)
        if (top < 0f) top = r.bottom + dp(6f) // top row: drop the popup below
        return floatArrayOf(startX, top, cellW, cellH)
    }

    /** Map a horizontal touch position to the accent cell index. */
    private fun accentIndexFor(px: Float): Int {
        val n = accentLabels?.size ?: return accentIndex
        val g = accentGeom() ?: return accentIndex
        return (((px - g[0]) / g[2]).toInt()).coerceIn(0, n - 1)
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

        // A finger dragged well clear of the keyboard is a CANCEL gesture, not
        // a key. The nearest-center fallback at the end never returns null, so
        // sliding a finger off the side or up into the text field and lifting
        // still typed the closest edge key. The margin is generous enough that
        // the fallback still rescues the legitimate near-edge cases (the
        // upward thumb bias can push a top-row touch above every rect).
        val vw = width.toFloat()
        val vh = height.toFloat()
        if (rawX < -OFF_KEYBOARD_SLOP || rawX > vw + OFF_KEYBOARD_SLOP ||
            rawY < -OFF_KEYBOARD_SLOP || rawY > vh + OFF_KEYBOARD_SLOP
        ) {
            return null
        }

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
        val corrected = TouchBiasModel.correct(
            rawX, rawY, w, h, useQwertyTouchBias,
            biasTop, biasBottom, leftThumbHome, rightThumbHome, thumbSplit, REACH_GAIN,
            letterTop = letterTops[kb] ?: 0f,
        )
        val x = corrected.x
        val y = corrected.y
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
                        val text = if (shifted && letter) upperOf(raw) else raw
                        // Single glyphs (letters, digits, single symbols) use the
                        // full label size for Gboard-level readability; only the
                        // multi-char toggles (=\<, ?123, ABC) shrink to fit.
                        val p = if (text.length == 1) labelPaint else symbolPaint
                        canvas.drawText(text, cx, baseline(cy, p), p)
                    }
                    numberHints.get(code.toChar().lowercaseChar().code)?.let { hint ->
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
        drawAccentPreview(canvas)
    }

    /**
     * While an accent key is held, show its variants in a row above (or below, for
     * the top key row) the key and highlight the one the current slide would commit.
     */
    private fun drawAccentPreview(canvas: Canvas) {
        val labels = accentLabels ?: return
        val g = accentGeom() ?: return
        val startX = g[0]; val top = g[1]; val cellW = g[2]; val cellH = g[3]
        for (i in labels.indices) {
            val left = startX + i * cellW
            rectF.set(left + dp(1f), top + dp(1f), left + cellW - dp(1f), top + cellH - dp(1f))
            flickBgPaint.color = if (i == accentIndex) colFlickActive else colFlickCell
            canvas.drawRoundRect(rectF, radius, radius, flickBgPaint)
            flickTextPaint.color = colText
            canvas.drawText(labels[i], left + cellW / 2f, baseline(top + cellH / 2f, flickTextPaint), flickTextPaint)
        }
    }

    /**
     * While a flick key is held, show its 5 kana in a plus around the key and
     * highlight the one the current drag would commit. Clamped into the view so
     * the top row's "up" cell and the edge columns aren't cut off.
     */
    private fun drawFlickPreview(canvas: Canvas) {
        for (i in 0 until flickStates.size()) drawOneFlick(canvas, flickStates.valueAt(i))
    }

    private fun drawOneFlick(canvas: Canvas, fs: FlickState) {
        val key = fs.key
        val labels = fs.labels
        val r = visualRects[key] ?: return
        val cw = r.width(); val ch = r.height()
        // Center the plus on the key, then clamp so all 5 cells stay on-screen.
        var cx = r.centerX()
        var cy = r.centerY()
        cx = cx.coerceIn(1.5f * cw, width - 1.5f * cw)
        val hh = if (layoutHeight > 0) layoutHeight.toFloat() else height.toFloat()
        cy = cy.coerceIn(1.5f * ch, hh - 1.5f * ch)
        for (i in 0..4) {
            val label = labels.getOrNull(i) ?: continue
            if (label.isEmpty()) continue
            val ox = cx + FLICK_COL_OFF[i] * cw
            val oy = cy + FLICK_ROW_OFF[i] * ch
            rectF.set(ox - cw / 2 + dp(1f), oy - ch / 2 + dp(1f), ox + cw / 2 - dp(1f), oy + ch / 2 - dp(1f))
            flickBgPaint.color = if (i == fs.dir) colFlickActive else colFlickCell
            canvas.drawRoundRect(rectF, radius, radius, flickBgPaint)
            flickTextPaint.color = colText
            canvas.drawText(label, ox, baseline(oy, flickTextPaint), flickTextPaint)
        }
    }

    private fun baseline(cy: Float, p: Paint) = cy - (p.descent() + p.ascent()) / 2f

    /** Cached uppercase of a key label - see [upperLabels]. */
    private fun upperOf(raw: String): String =
        upperLabels.getOrPut(raw) { raw.uppercase() }

    override fun onDetachedFromWindow() {
        // The keyboard window can go away mid-gesture (app switch, IME switch,
        // the field closing). Without this a held backspace kept its repeat
        // runnable posted against a detached view.
        cancelAllGestures()
        super.onDetachedFromWindow()
    }

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
