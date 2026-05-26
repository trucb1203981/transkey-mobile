package app.transkey.mobile

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Color
import android.graphics.Matrix
import android.graphics.Rect
import android.util.Log
import androidx.exifinterface.media.ExifInterface

/**
 * Estimate the background colour behind each OCR bounding box so the
 * translation overlay can paint a solid card matching the underlying
 * photo (instead of an opaque blue/black chip that visually replaces
 * the original layout).
 *
 * # Algorithm
 *
 * For every rect, sample a thin strip immediately OUTSIDE its bounding
 * box (top / bottom / left / right). These strips sit in the gutter
 * between text and surrounding background, so they mostly hit the
 * canvas behind the text rather than the glyphs themselves.
 *
 * Two robustness layers on top of the raw sampling:
 *
 *  1. **Skip-into-neighbour** - reject any sample pixel that falls
 *     INSIDE another rect from the same OCR pass. Dense text layouts
 *     (a menu with prices stacked tightly together) used to bleed each
 *     other's glyphs into the strip, so two cards 8 px apart would
 *     each pick the OTHER card's text colour as their "background"
 *     and render unreadable cards.
 *
 *  2. **Histogram bucket mode** instead of per-channel median. We
 *     quantise each pixel to a 5-bit-per-channel bucket (32^3 = 32k
 *     buckets) and pick the most-populated bucket. Mode handles
 *     textured backgrounds (a menu with pink flower decorations,
 *     a notebook with grid lines) much better than median: median
 *     mixes the two dominant colours channel-wise and yields a
 *     muddy in-between tint; mode picks the actual dominant tone.
 *
 * Pixels are read via [Bitmap.getPixels] one strip at a time. We do
 * NOT subsample - subsampling helped on 12 MP captures but cost
 * accuracy on the smaller strips at dense text. Total work is still
 * O(strip_pixels * rect_count); with strip=12 and ~30 rects, that's
 * a few thousand pixels per rect - well under 50 ms on mid-range
 * Android.
 */
object BgColorSampler {

    private const val TAG = "BgColorSampler"

    /** Rim thickness sampled just inside / just outside each bbox edge,
     *  in source-image pixels. Big enough to gather a stable histogram
     *  from the text-free margin around the glyphs, small enough not to
     *  reach into a neighbouring line on dense layouts. */
    private const val RIM_PX = 5

    /** Quantise colour buckets to 5 bits per channel = 32 levels each
     *  axis = 32k total buckets. Coarser would merge distinct tones
     *  (pure white vs cream); finer would split natural noise (camera
     *  shot noise on what's "really" one colour) into many buckets and
     *  give the mode no advantage over noise. 5 bits is the sweet spot
     *  on captured photos. */
    private const val QUANT_SHIFT = 3 // 8 - 5

    fun sample(imagePath: String, rects: List<Rect>): List<Int> {
        val bitmap: Bitmap? = decodeOriented(imagePath)
        if (bitmap == null) return List(rects.size) { Color.WHITE }
        val w = bitmap.width
        val h = bitmap.height
        val out = ArrayList<Int>(rects.size)
        for (i in rects.indices) {
            out.add(sampleOne(bitmap, rects, i, w, h))
        }
        bitmap.recycle()
        return out
    }

    /**
     * Decode the JPEG/PNG at [path] into an UPRIGHT bitmap that matches
     * the coordinate space ML Kit reported its bounding boxes in.
     *
     * [BitmapFactory.decodeFile] alone returns the raw pixel buffer and
     * IGNORES the JPEG EXIF orientation tag. Flutter's image codec (used
     * to derive the on-screen image size) and ML Kit's recogniser both
     * apply that tag, so a capture carrying an unbaked rotation would
     * leave the sampler reading from a transposed buffer - grabbing
     * colours from the wrong part of the photo entirely. We read the
     * tag with ExifInterface and rotate/flip to match.
     */
    private fun decodeOriented(path: String): Bitmap? {
        val raw = try {
            BitmapFactory.decodeFile(path, BitmapFactory.Options().apply {
                inMutable = false
            })
        } catch (e: Exception) {
            Log.w(TAG, "decode failed: ${e.message}")
            return null
        } ?: return null

        val orientation = try {
            ExifInterface(path).getAttributeInt(
                ExifInterface.TAG_ORIENTATION,
                ExifInterface.ORIENTATION_NORMAL,
            )
        } catch (e: Exception) {
            ExifInterface.ORIENTATION_NORMAL
        }

        val matrix = Matrix()
        when (orientation) {
            ExifInterface.ORIENTATION_ROTATE_90 -> matrix.postRotate(90f)
            ExifInterface.ORIENTATION_ROTATE_180 -> matrix.postRotate(180f)
            ExifInterface.ORIENTATION_ROTATE_270 -> matrix.postRotate(270f)
            ExifInterface.ORIENTATION_FLIP_HORIZONTAL -> matrix.preScale(-1f, 1f)
            ExifInterface.ORIENTATION_FLIP_VERTICAL -> matrix.preScale(1f, -1f)
            ExifInterface.ORIENTATION_TRANSPOSE -> {
                matrix.postRotate(90f); matrix.preScale(-1f, 1f)
            }
            ExifInterface.ORIENTATION_TRANSVERSE -> {
                matrix.postRotate(270f); matrix.preScale(-1f, 1f)
            }
            else -> return raw // ORIENTATION_NORMAL / undefined - already upright
        }

        return try {
            val rotated = Bitmap.createBitmap(
                raw, 0, 0, raw.width, raw.height, matrix, true,
            )
            if (rotated != raw) raw.recycle()
            rotated
        } catch (e: Exception) {
            Log.w(TAG, "orientation transform failed: ${e.message}")
            raw
        }
    }

    /**
     * @param allRects every rect from the same OCR pass - used to skip
     *                 sample pixels that fall inside a NEIGHBOURING bbox
     *                 (which would contaminate the strip with the next
     *                 card's text).
     * @param selfIdx  index of the rect we're sampling for, so we don't
     *                 reject our own area.
     */
    private fun sampleOne(
        bitmap: Bitmap,
        allRects: List<Rect>,
        selfIdx: Int,
        w: Int,
        h: Int,
    ): Int {
        val r = allRects[selfIdx]
        val buckets = HashMap<Int, Int>(2048)

        fun bucketOf(p: Int): Int {
            val rr = ((p shr 16) and 0xff) shr QUANT_SHIFT
            val gg = ((p shr 8) and 0xff) shr QUANT_SHIFT
            val bb = (p and 0xff) shr QUANT_SHIFT
            // pack into single int — 5 bits per channel = 15 bits total
            return (rr shl 10) or (gg shl 5) or bb
        }

        fun pointInOtherRect(x: Int, y: Int): Boolean {
            for (j in allRects.indices) {
                if (j == selfIdx) continue
                val o = allRects[j]
                if (x >= o.left && x < o.right && y >= o.top && y < o.bottom) {
                    return true
                }
            }
            return false
        }

        fun addStrip(left: Int, top: Int, sw: Int, sh: Int) {
            if (sw <= 0 || sh <= 0) return
            val buf = IntArray(sw * sh)
            try {
                bitmap.getPixels(buf, 0, sw, left, top, sw, sh)
            } catch (e: Exception) {
                return
            }
            for (row in 0 until sh) {
                val py = top + row
                val rowStart = row * sw
                for (col in 0 until sw) {
                    val px = left + col
                    if (pointInOtherRect(px, py)) continue
                    val key = bucketOf(buf[rowStart + col])
                    buckets[key] = (buckets[key] ?: 0) + 1
                }
            }
        }

        val sLeft = r.left.coerceIn(0, w)
        val sRight = r.right.coerceIn(0, w)
        val sTop = r.top.coerceIn(0, h)
        val sBot = r.bottom.coerceIn(0, h)

        // # Sample the bbox INNER RIM, not the full interior
        //
        // First version sampled the full bbox interior. That mixed
        // text + anti-aliased halo + bg pixels into the histogram; for
        // white-text-on-red banners (Japanese menu titles) the
        // anti-aliasing alone spreads across enough buckets to defeat
        // the mode and the card ends up pale-pink instead of red.
        //
        // ML Kit's bbox geometry has a useful property: the TOP and
        // BOTTOM rows include 2-4 px above ascenders / below descenders
        // that are pure background; the LEFT and RIGHT columns
        // similarly include whatever inter-character / line-end space
        // the source kerning leaves. Sampling only those rims gives
        // an almost text-free view of the actual surface colour.
        //
        // We sample:
        //   - a RIM_PX strip just INSIDE each of the 4 edges
        //   - + RIM_PX just OUTSIDE each edge (handles tight bboxes
        //     that wrap a single glyph with no internal padding)
        // Pixels that fall into a NEIGHBOURING bbox are still skipped
        // so adjacent text can't leech into the histogram.
        val rim = RIM_PX
        // Inner top rim
        addStrip(sLeft, sTop, sRight - sLeft, (rim).coerceAtMost(sBot - sTop))
        // Inner bottom rim
        addStrip(sLeft, (sBot - rim).coerceAtLeast(sTop), sRight - sLeft, (rim).coerceAtMost(sBot - sTop))
        // Inner left rim
        addStrip(sLeft, sTop, (rim).coerceAtMost(sRight - sLeft), sBot - sTop)
        // Inner right rim
        addStrip((sRight - rim).coerceAtLeast(sLeft), sTop, (rim).coerceAtMost(sRight - sLeft), sBot - sTop)

        // Outer rims (paper / banner just beyond the bbox)
        val topTop = (r.top - rim).coerceIn(0, h)
        addStrip(sLeft, topTop, sRight - sLeft, sTop - topTop)
        val botBot = (r.bottom + rim).coerceIn(0, h)
        addStrip(sLeft, sBot, sRight - sLeft, botBot - sBot)
        val lLeft = (r.left - rim).coerceIn(0, w)
        addStrip(lLeft, sTop, sLeft - lLeft, sBot - sTop)
        val rRight = (r.right + rim).coerceIn(0, w)
        addStrip(sRight, sTop, rRight - sRight, sBot - sTop)

        if (buckets.isEmpty()) return Color.WHITE

        // Pick the most populated quantised bucket.
        var bestKey = -1
        var bestCount = 0
        for ((k, v) in buckets) {
            if (v > bestCount) {
                bestCount = v
                bestKey = k
            }
        }
        if (bestKey < 0) return Color.WHITE

        // Reconstruct an 8-bit colour from the 5-bit bucket center.
        // Centre = bucket * 8 + 4 (4 = half of 2^QUANT_SHIFT) so we don't
        // bias the recovered colour systematically towards black.
        val rOut = ((bestKey shr 10) and 0x1f) * 8 + 4
        val gOut = ((bestKey shr 5) and 0x1f) * 8 + 4
        val bOut = (bestKey and 0x1f) * 8 + 4
        return Color.argb(255, rOut.coerceAtMost(255), gOut.coerceAtMost(255), bOut.coerceAtMost(255))
    }
}
