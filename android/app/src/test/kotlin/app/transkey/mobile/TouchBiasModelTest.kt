package app.transkey.mobile

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class TouchBiasModelTest {
    @Test fun nonQwertyLayoutsStayNeutral() {
        val point = correct(x = 173f, y = 211f, qwerty = false)
        assertEquals(173f, point.x, 0f)
        assertEquals(211f, point.y, 0f)
    }

    @Test fun qwertyCorrectionScalesAcrossWidths() {
        val phone = correct(x = 90f, y = 210f, width = 360f, height = 240f)
        val tablet = correct(x = 180f, y = 420f, width = 720f, height = 480f,
            biasTop = 12.4f, biasBottom = 1.4f)
        assertEquals(phone.y * 2f, tablet.y, 0.001f)
    }

    @Test fun qwertyCorrectionNeverChangesHorizontalCoordinate() {
        for (x in 0..360 step 12) {
            val point = correct(x = x.toFloat(), y = 120f)
            assertEquals(x.toFloat(), point.x, 0f)
        }
    }

    @Test fun outerLetterGrowthIsLeftRightSymmetric() {
        val first = TouchBiasModel.growLetterEdges(0, 10, 0f, 50f, 7f, true, true)
        val second = TouchBiasModel.growLetterEdges(1, 10, 50f, 100f, 7f, true, true)
        val penultimate = TouchBiasModel.growLetterEdges(8, 10, 400f, 450f, 7f, true, true)
        val last = TouchBiasModel.growLetterEdges(9, 10, 450f, 500f, 7f, true, true)
        assertEquals(first.second - 50f, 450f - last.first, 0f)
        assertEquals(second.first - 50f, 450f - penultimate.second, 0f)
        assertEquals(first.second, second.first, 0f)
        assertEquals(penultimate.second, last.first, 0f)
    }

    @Test fun everySupportedSizeProducesFiniteInBoundsCorrection() {
        for (width in listOf(320f, 360f, 412f, 600f)) {
            val height = width * 0.67f
            for (x in 0..20) for (y in 0..20) {
                val point = correct(x * width / 20f, y * height / 20f,
                    width = width, height = height)
                assertTrue(point.x.isFinite() && point.y.isFinite())
                assertTrue(point.y <= y * height / 20f)
            }
        }
    }

    // ---- VNI: a digit row above the letters must not dilute the calibration

    @Test fun anExtraTopRowKeepsTheLetterRowCorrection() {
        // Same letter area (200px tall) in both: plain QWERTY starts it at 0,
        // VNI pushes it down by a 40px digit row. A tap the same distance INTO
        // the letters must be corrected by exactly the same amount.
        val plainQwerty = correct(x = 90f, y = 60f, height = 200f)
        val vni = correct(x = 90f, y = 100f, height = 240f, letterTop = 40f)
        assertEquals(60f - plainQwerty.y, 100f - vni.y, 0.001f)
    }

    @Test fun rowsAboveTheLetterAreaClampToTheStrongestBias() {
        val digitRow = correct(x = 90f, y = 10f, height = 240f, letterTop = 40f)
        val topLetterRow = correct(x = 90f, y = 40f, height = 240f, letterTop = 40f)
        assertEquals(10f - digitRow.y, 40f - topLetterRow.y, 0.001f)
    }

    @Test fun aZeroLetterTopReproducesTheOriginalFormula() {
        for (y in 0..240 step 20) {
            val implicit = correct(x = 90f, y = y.toFloat())
            val explicit = correct(x = 90f, y = y.toFloat(), letterTop = 0f)
            assertEquals(implicit.y, explicit.y, 0f)
        }
    }

    private fun correct(
        x: Float,
        y: Float,
        width: Float = 360f,
        height: Float = 240f,
        qwerty: Boolean = true,
        biasTop: Float = 6.2f,
        biasBottom: Float = 0.7f,
        letterTop: Float = 0f,
    ) = TouchBiasModel.correct(
        x, y, width, height, qwerty, biasTop, biasBottom,
        leftThumbHome = 0.22f,
        rightThumbHome = 0.73f,
        thumbSplit = 0.62f,
        reachGain = 0.6f,
        letterTop = letterTop,
    )
}
