package app.transkey.mobile

import android.content.Intent
import android.graphics.Bitmap

/**
 * In-memory shuttle for the MediaProjection token + capture artifacts
 * between [ScreenCapturePermissionActivity] (which requests the token from
 * the user), [ScreenCaptureService] (which grabs the frame and OCRs), and
 * [BubbleService] (which renders the Lens overlay).
 *
 * Deliberately NOT persistent — MediaProjection grants are single-session
 * by design and the bitmap is large enough that we want it GC'd as soon as
 * the overlay closes. [clearAll] is called when the overlay dismisses.
 */
object ScreenCaptureManager {

    /** Two output modes: legacy "Scan → Input picker" vs Lens overlay. */
    enum class Flow { LENS, TEXT_INTO_INPUT }

    // ── Projection token (set by permission activity, consumed by service) ──
    @Volatile var resultCode: Int = 0
    @Volatile var resultIntent: Intent? = null

    // ── Capture settings (set by BubbleService before the activity launch) ──
    /** ISO-639-1 lang hint so OcrHelper can pick the right CJK recognizer. */
    @Volatile var languageHint: String? = null

    /** Translate mode to apply after OCR — only meaningful for TEXT_INTO_INPUT. */
    @Volatile var pendingMode: String = "translate"

    /** Translate target lang for batch — only meaningful for LENS. */
    @Volatile var targetLang: String = "en"

    /** Which downstream UI handles the result. */
    @Volatile var flow: Flow = Flow.TEXT_INTO_INPUT

    /**
     * When true, ScreenCaptureService skips immediate OCR and hands the raw
     * bitmap back to BubbleService so the user can rubber-band a region.
     * OCR then runs on the cropped sub-bitmap, with block bounds offset
     * back into full-screen coords before the Lens overlay renders.
     */
    @Volatile var regionMode: Boolean = false

    // ── Capture results (set by service, consumed by BubbleService) ──
    @Volatile var screenshot: Bitmap? = null
    @Volatile var blocks: List<OcrHelper.Block> = emptyList()

    fun clearToken() {
        resultCode = 0
        resultIntent = null
    }

    /** Drop the bitmap so it doesn't linger after the overlay dismisses. */
    fun clearAll() {
        clearToken()
        screenshot?.let { if (!it.isRecycled) it.recycle() }
        screenshot = null
        blocks = emptyList()
        languageHint = null
        regionMode = false
    }

    /**
     * Hand the current screenshot to a caller that will own its lifecycle
     * (e.g. the Lens "reopen last result" cache) WITHOUT recycling it. The
     * manager forgets the reference so a subsequent [clearAll] won't double
     * -free it. Caller MUST recycle the returned bitmap when done.
     */
    fun detachScreenshot(): Bitmap? {
        val b = screenshot
        screenshot = null
        return b
    }
}
