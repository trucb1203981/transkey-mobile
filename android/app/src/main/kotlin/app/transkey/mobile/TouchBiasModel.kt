package app.transkey.mobile

import kotlin.math.abs

/** Pure touch correction shared by the Android keyboard and JVM bias tests. */
internal object TouchBiasModel {
    data class Point(val x: Float, val y: Float)

    /**
     * Apply the measured two-thumb QWERTY correction. Non-QWERTY layouts use
     * raw coordinates because their geometry and gestures need their own data.
     *
     * [letterTop] is where the LETTER rows start (px from the top of the
     * keyboard). Depth is measured from there, not from the top of the view, so
     * a layout that stacks an extra non-letter row above the letters - the VNI
     * digits row - keeps the calibration that was measured on plain QWERTY
     * instead of diluting it across a taller keyboard. 0 (plain QWERTY, where
     * the letters ARE the first row) reproduces the original formula exactly.
     * Anything above the letter area clamps to the strongest (top) bias, which
     * is what the longest thumb reach deserves.
     */
    fun correct(
        rawX: Float,
        rawY: Float,
        width: Float,
        height: Float,
        qwertyProfile: Boolean,
        biasTop: Float,
        biasBottom: Float,
        leftThumbHome: Float,
        rightThumbHome: Float,
        thumbSplit: Float,
        reachGain: Float,
        letterTop: Float = 0f,
    ): Point {
        if (!qwertyProfile || width <= 0f || height <= 0f) return Point(rawX, rawY)
        val top = letterTop.coerceIn(0f, height)
        val span = height - top
        if (span <= 0f) return Point(rawX, rawY)
        val depth = ((rawY - top) / span).coerceIn(0f, 1f)
        val rowBias = biasTop + (biasBottom - biasTop) * depth
        val home = if (rawX < thumbSplit * width) leftThumbHome * width else rightThumbHome * width
        val reach = abs(rawX - home) / width
        return Point(rawX, rawY - rowBias * (1f + reachGain * reach))
    }

    /** Grow both outer letter keys symmetrically into their inner neighbours. */
    fun growLetterEdges(
        index: Int,
        size: Int,
        left: Float,
        right: Float,
        grow: Float,
        firstIsLetter: Boolean,
        lastIsLetter: Boolean,
    ): Pair<Float, Float> {
        var adjustedLeft = left
        var adjustedRight = right
        if (firstIsLetter) {
            if (index == 0) adjustedRight += grow
            if (index == 1) adjustedLeft += grow
        }
        if (lastIsLetter) {
            if (index == size - 2) adjustedRight -= grow
            if (index == size - 1) adjustedLeft -= grow
        }
        return adjustedLeft to adjustedRight
    }
}
