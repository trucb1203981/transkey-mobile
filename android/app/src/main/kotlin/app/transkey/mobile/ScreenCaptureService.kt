package app.transkey.mobile

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.graphics.Bitmap
import android.graphics.PixelFormat
import android.hardware.display.DisplayManager
import android.hardware.display.VirtualDisplay
import android.media.ImageReader
import android.media.projection.MediaProjection
import android.media.projection.MediaProjectionManager
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.util.Log
import android.view.WindowManager

/**
 * Foreground service that owns the user's MediaProjection grant.
 *
 * Earlier versions tore the projection down after every scan, which meant
 * Android re-prompted "Start recording?" on every Lens tap — annoying for
 * users doing several scans in a row. We now keep [mediaProjection] alive
 * across captures so consent is asked once per bubble session: only the
 * per-frame VirtualDisplay + ImageReader are recreated each time. The
 * projection is released when:
 *  - User closes the bubble (`stopBubble` → ACTION_STOP_PROJECTION)
 *  - System revokes the grant (callback `onStop` from MediaProjection)
 *  - Service is killed by the OS (`onDestroy`)
 *
 * The system "casting" indicator stays visible while the projection is
 * alive — a deliberate privacy cue so the user knows TransKey still has
 * screen-capture access.
 *
 * Android 14+ requires the mediaProjection foregroundServiceType to be
 * declared in the manifest AND attached at startForeground() time;
 * otherwise `MediaProjectionManager.getMediaProjection` returns a token
 * that throws SecurityException as soon as we try to create a VirtualDisplay.
 */
class ScreenCaptureService : Service() {

    /** Long-lived across scans. Released only on explicit STOP or system revoke. */
    private var mediaProjection: MediaProjection? = null

    /** Per-capture — recreated each ACTION_CAPTURE. */
    private var virtualDisplay: VirtualDisplay? = null
    private var imageReader: ImageReader? = null

    private val handler = Handler(Looper.getMainLooper())

    /** Set true while a single frame capture is in flight, cleared after delivery. */
    @Volatile private var captured = false

    /**
     * True when the in-flight capture is REUSING an already-granted
     * projection (vs the first capture right after a fresh consent). Drives
     * [captureTimeoutRunnable]'s recovery branch: a reuse that yields no
     * frame means a single-app grant whose target app is no longer
     * foreground (the user switched apps and pressed capture), so we
     * re-open consent for the new app instead of just failing. A first
     * capture that times out keeps the old "deliver empty + stop" behaviour.
     */
    @Volatile private var reuseCapture = false

    /**
     * Pending auto-release: tears down the projection if the user doesn't
     * trigger another capture within [IDLE_RELEASE_MS]. Without this the
     * VirtualDisplay keeps mirroring the screen every refresh — the
     * device gets noticeably warm during long browsing sessions because
     * the GPU is composing two surfaces (the real display + our virtual
     * one) at 60 fps even when no one is asking us to translate. The
     * trade-off is that the NEXT scan after a quiet minute pops the
     * consent dialog again.
     */
    private val idleReleaseRunnable = Runnable {
        Log.d(TAG, "idle release: capture window expired, dropping projection")
        stopProjectionAndSelf()
    }

    /**
     * Android 14+ single-app MediaProjection guard.
     *
     * When the user picks "This app only" at consent (the default for some
     * OEMs on Android 14+), the projection captures frames ONLY while the
     * granted task is in the foreground. Switch to another app and press
     * capture → the VirtualDisplay stops receiving frames → our ImageReader
     * listener never fires → `captured` is open but nothing arrives → the
     * bubble (set to GONE by [BubbleService.hideOverlaysForCapture]) is
     * never restored.
     *
     * This runnable is armed after every `captured = false` and cancelled
     * inside the listener as soon as ANY frame is delivered. "No frame" is
     * exactly the "user granted app A but is now capturing app B" signal —
     * and because we only judge it at capture time (overlays already
     * hidden), our own Lens overlay occluding the source can never trigger
     * a false re-consent. Recovery depends on which capture timed out:
     *  - REUSE capture ([reuseCapture] true): the cached single-app grant
     *    can't serve the new foreground app → re-open consent so the user
     *    grants the app they're actually on. A full-screen grant always
     *    yields a frame, so it never lands here. See [reopenConsent] for the
     *    two constraints (crash-free + MIUI background-launch grace).
     *  - FIRST capture (fresh grant): keep the old behaviour — deliver
     *    empty (restores the bubble) and stop; re-prompting would risk a
     *    consent loop on a grant the user just made.
     */
    private val captureTimeoutRunnable = Runnable {
        captured = true   // close the gate
        if (reuseCapture) {
            Log.w(TAG, "reuse capture got no frame — single-app grant bound to a " +
                "different app than the current foreground; re-opening consent")
            reopenConsent()
        } else {
            Log.w(TAG, "first capture timed out — no frame; restoring bubble")
            deliverEmptyToBubble()
            stopProjectionAndSelf()
        }
    }

    // ──────────────────────────────────────────────────────────────────
    // Live video-subtitle mode (continuous capture).
    //
    // Deliberately kept on its OWN VirtualDisplay + ImageReader, separate
    // from the single-shot Lens pipeline above, so none of the delicate
    // one-shot gate / timeout / MIUI-reuse logic is touched. The two modes
    // never run at once (both need the single-session MediaProjection),
    // so sharing [mediaProjection] is safe.
    // ──────────────────────────────────────────────────────────────────
    @Volatile private var subtitleMode = false
    private var subVirtualDisplay: VirtualDisplay? = null
    private var subImageReader: ImageReader? = null
    private var subWidth = 0
    private var subHeight = 0
    private var subtitleOverlay: SubtitleOverlay? = null

    /** aHash of the last OCR band, so unchanged frames skip OCR entirely. */
    private var lastBandHash: Long = 0L

    /** Last OCR'd caption text, so a still-showing line isn't re-translated. */
    private var lastOcrText: String? = null

    /** True when the user left source = "auto"; we detect it from the captions. */
    private var autoSource = false

    /** Resolved source language (fixed pick, or auto-detected). Empty until known. */
    private var resolvedSource = ""

    /** Lazily-created on-device language identifier (auto-source mode only). */
    private var langIdentifier: com.google.mlkit.nl.languageid.LanguageIdentifier? = null

    /** LRU cache OCR text → translation; a caption shown for 2-4 s spans many
     *  frames, and repeats across a video, so caching avoids re-translating. */
    private val translationCache = object : LinkedHashMap<String, String>(64, 0.75f, true) {
        override fun removeEldestEntry(eldest: MutableMap.MutableEntry<String, String>?): Boolean =
            size > TRANSLATION_CACHE_MAX
    }

    private val subtitleTick = Runnable { grabSubtitleFrame() }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        startForegroundCompat()
        when (intent?.action) {
            ACTION_CAPTURE -> startCapture()
            ACTION_START_SUBTITLE -> startSubtitle()
            ACTION_STOP_SUBTITLE -> stopSubtitle()
            // The notification's Stop action is shared: route it to whichever
            // mode is live so one button always tears the right thing down.
            ACTION_STOP_PROJECTION -> if (subtitleMode) stopSubtitle() else stopProjectionAndSelf()
            else -> if (subtitleMode) stopSubtitle() else stopProjectionAndSelf()
        }
        return START_NOT_STICKY
    }

    private fun startForegroundCompat() {
        val notification = buildNotification()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            // API 34+: must pass type matching the manifest declaration.
            startForeground(
                NOTIFICATION_ID, notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION,
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    private fun startCapture() {
        // Reuse path: pipeline (VirtualDisplay + ImageReader) is already
        // mirroring the screen. We DON'T just flip `captured = false`
        // immediately because the bubble's `WindowManager.removeView`
        // call (from the caller) is async — the next frame the system
        // pushes through VirtualDisplay can still contain the bubble for
        // up to 1-2 display refreshes after the view was "removed".
        // Wait CAPTURE_SETTLE_MS, drain stale buffered frames, THEN arm
        // the gate so the captured frame is guaranteed to be post-bubble-hide.
        //
        // Why we DON'T tear down VirtualDisplay between scans: on Android
        // 14+ the MediaProjection grant is invalidated as soon as its
        // last VirtualDisplay is released. We'd then need a fresh
        // "Start recording?" prompt for every scan, which defeats the
        // whole point of caching the grant.
        if (mediaProjection != null && imageReader != null && virtualDisplay != null) {
            captured = true  // close the gate so stale frames get dropped
            // This capture reuses an existing grant: a no-frame timeout here
            // means the (single-app) grant's target app is no longer
            // foreground → re-open consent rather than fail. See
            // captureTimeoutRunnable.
            reuseCapture = true
            // Any new capture cancels the pending idle-release; we'll
            // re-arm it after the capture completes.
            handler.removeCallbacks(idleReleaseRunnable)
            // Also cancel any prior capture timeout — we're starting fresh.
            handler.removeCallbacks(captureTimeoutRunnable)
            handler.postDelayed({
                // Drain any frames buffered during the settle window so
                // acquireLatestImage doesn't hand us a bubble-visible frame.
                try {
                    while (true) {
                        val img = imageReader?.acquireLatestImage() ?: break
                        img.close()
                    }
                } catch (_: Exception) {}
                captured = false
                // Arm the no-frame timeout. Android 14+ single-app
                // projection stops pushing frames when the granted task
                // is backgrounded; without this fallback the bubble
                // stays GONE forever waiting for an image that won't
                // come. A same-app reuse frame arrives in well under
                // REUSE_TIMEOUT_MS, so the only thing that trips this is a
                // genuine "capturing a different app" case.
                handler.postDelayed(captureTimeoutRunnable, REUSE_TIMEOUT_MS)
            }, CAPTURE_SETTLE_MS)
            return
        }

        // First capture of the session: acquire the token from the activity
        // result the user just approved.
        val resultCode = ScreenCaptureManager.resultCode
        val resultIntent = ScreenCaptureManager.resultIntent
        if (resultIntent == null) {
            Log.w(TAG, "startCapture: no projection token")
            deliverEmptyToBubble()
            stopProjectionAndSelf()
            return
        }
        val mpm = getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
        val projection = try {
            mpm.getMediaProjection(resultCode, resultIntent)
        } catch (error: Exception) {
            Log.w(TAG, "getMediaProjection failed: ${error.message}")
            null
        }
        if (projection == null) {
            deliverEmptyToBubble()
            stopProjectionAndSelf()
            return
        }
        mediaProjection = projection
        isProjectionActive = true

        // Register callback BEFORE createVirtualDisplay — Android 14 throws
        // otherwise. If the user revokes the grant from system UI, drop
        // our flag so the next scan re-prompts.
        projection.registerCallback(object : MediaProjection.Callback() {
            override fun onStop() {
                Log.d(TAG, "MediaProjection revoked by system / user")
                handler.post {
                    isProjectionActive = false
                    teardownCapturePipeline()
                    mediaProjection = null
                    ScreenCaptureManager.clearToken()
                    stopForeground(STOP_FOREGROUND_REMOVE)
                    stopSelf()
                }
            }
        }, handler)

        // Brief delay so the system permission dialog has time to dismiss
        // before the next frame is captured — otherwise the dialog itself
        // ends up in the screenshot on some OEMs. Only needed the FIRST
        // time when projection was just granted.
        handler.postDelayed({ setupPipeline(projection) }, 300)
    }

    /**
     * Wire VirtualDisplay → ImageReader exactly once per session. The
     * listener stays armed for the whole session and uses [captured] as
     * a gate: when false it grabs the next frame and processes it; when
     * true it drains incoming frames so ImageReader's small buffer
     * doesn't back up.
     */
    private fun setupPipeline(projection: MediaProjection) {
        // Start with the gate CLOSED. VirtualDisplay begins mirroring the
        // screen the instant it's created, and the consent dialog's
        // dismiss animation can still be in-flight at that point — without
        // a second settle window the first captured frame ends up showing
        // a partially-redrawn screen (status bar in transition, missing
        // app chrome) instead of the stable source-app frame the user
        // expected. We re-open the gate after FIRST_CAPTURE_ARM_MS, with
        // a drain to discard any stale frames the listener buffered.
        captured = true

        // Use the FULL physical display bounds (incl. system bars). The
        // app-context resources.displayMetrics on some devices/orientations
        // returns the in-app available area, which excludes status / nav
        // bars — that caused the captured bitmap to be smaller than the
        // actual screen, so the LensOverlayView showed a letterboxed mini
        // version of the source app instead of full-screen translation.
        val (width, height, density) = readDisplaySize()

        val reader = ImageReader.newInstance(width, height, PixelFormat.RGBA_8888, 2)
        imageReader = reader
        reader.setOnImageAvailableListener({ r ->
            // A frame arrived — clear the "no frame" timeout regardless of
            // whether we'll use it. Even drop-frames-during-settle count
            // as "projection IS pushing", so the Android 14+ single-app
            // freeze didn't happen.
            handler.removeCallbacks(captureTimeoutRunnable)
            // Defensive: the whole listener is wrapped because system-level
            // events outside our control (screen recorder taking the
            // projection, OEM "you weren't using this so we killed it"
            // throttling on MIUI/OneUI, low-memory teardown) can invalidate
            // `r` or its backing surface between when this callback was
            // queued and when it actually runs. Throwing out of an
            // ImageReader callback crashes the foreground service.
            try {
                if (captured) {
                    // Not in capture mode — drop the frame so the buffer
                    // can recycle for the next one.
                    r.acquireLatestImage()?.close()
                    return@setOnImageAvailableListener
                }
                val image = r.acquireLatestImage() ?: return@setOnImageAvailableListener
                captured = true
                val bitmap = try {
                    imageToBitmap(image, width, height)
                } catch (error: Exception) {
                    Log.w(TAG, "imageToBitmap failed: ${error.message}")
                    null
                } finally {
                    try { image.close() } catch (_: Exception) {}
                }
                // Pipeline stays alive — next scan will set captured=false and
                // this same listener will pick up the next available frame.

                if (bitmap == null) {
                    deliverEmptyToBubble()
                    armIdleRelease()
                    return@setOnImageAvailableListener
                }
                runOcr(bitmap)
                // Schedule auto-release if no further scan within the
                // idle window — keeps "scan multiple things back to
                // back" cheap while preventing the VirtualDisplay from
                // sitting hot on the GPU through the rest of the day.
                armIdleRelease()
            } catch (error: Throwable) {
                // Throwable (not Exception) so we also catch OutOfMemoryError
                // from Bitmap.createBitmap — the screen-recorder scenario
                // doubles bitmap allocations because the system holds its
                // own copy of every captured frame too.
                Log.w(TAG, "capture listener failed: ${error.message}")
                captured = true
                handler.post { deliverEmptyToBubble() }
            }
        }, handler)

        try {
            virtualDisplay = projection.createVirtualDisplay(
                "TransKeyOCRCapture",
                width, height, density,
                DisplayManager.VIRTUAL_DISPLAY_FLAG_AUTO_MIRROR,
                reader.surface, null, handler,
            )
        } catch (error: Exception) {
            Log.w(TAG, "createVirtualDisplay failed: ${error.message}")
            deliverEmptyToBubble()
            teardownCapturePipeline()
            return
        }

        // Pipeline is live and mirroring; drop frames the listener
        // collects during the settle window, then drain + arm so we
        // capture a stable frame instead of a consent-dialog-dismiss
        // transition.
        handler.postDelayed({
            try {
                while (true) {
                    val img = imageReader?.acquireLatestImage() ?: break
                    img.close()
                }
            } catch (_: Exception) {}
            captured = false
            // This is the FIRST capture on a fresh grant — a timeout here
            // must NOT loop back into consent (the user just granted), so
            // mark it non-reuse: captureTimeoutRunnable will deliver empty
            // and stop instead of re-prompting.
            reuseCapture = false
            // Arm the no-frame timeout. Even on first capture (fresh
            // consent grant) the Android 14+ single-app projection can
            // refuse to push frames if the user picked the wrong app at
            // consent — give up after CAPTURE_TIMEOUT_MS and restore.
            handler.postDelayed(captureTimeoutRunnable, CAPTURE_TIMEOUT_MS)
        }, FIRST_CAPTURE_ARM_MS)
    }

    /**
     * Returns (widthPx, heightPx, densityDpi) for the full physical display
     * — equivalent to what MediaProjection actually mirrors. On API 30+
     * we read `maximumWindowMetrics.bounds`; older releases fall back to
     * Display.getRealMetrics, which is the documented way to get the
     * physical size including any system insets.
     */
    private fun readDisplaySize(): Triple<Int, Int, Int> {
        val wm = getSystemService(Context.WINDOW_SERVICE) as WindowManager
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            val bounds = wm.maximumWindowMetrics.bounds
            Triple(bounds.width(), bounds.height(), resources.displayMetrics.densityDpi)
        } else {
            @Suppress("DEPRECATION")
            val display = wm.defaultDisplay
            val real = android.util.DisplayMetrics()
            @Suppress("DEPRECATION")
            display.getRealMetrics(real)
            Triple(real.widthPixels, real.heightPixels, real.densityDpi)
        }
    }

    /**
     * Reset (or start) the idle-release timer. Call after every capture
     * completes — the timer fires only if no new capture comes in during
     * the user-configured window, in which case we drop the projection.
     *
     * Window comes from the Flutter setting `tk_capture_keepalive_s`
     * (seconds). 0 means "release immediately after each scan" — handled
     * by posting at delay 0, which fires on the next handler tick.
     */
    private fun armIdleRelease() {
        handler.removeCallbacks(idleReleaseRunnable)
        handler.postDelayed(idleReleaseRunnable, readIdleReleaseMs())
    }

    private fun readIdleReleaseMs(): Long {
        val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        // Flutter int-typed prefs land as Long under the hood; read defensively
        // so a corrupted/legacy value just falls back to the default.
        val seconds = try {
            prefs.getLong("flutter.tk_capture_keepalive_s", IDLE_RELEASE_DEFAULT_S)
        } catch (_: ClassCastException) {
            IDLE_RELEASE_DEFAULT_S
        }
        val clamped = seconds.coerceIn(0L, IDLE_RELEASE_MAX_S)
        return clamped * 1000L
    }

    /** Release VirtualDisplay + ImageReader. Called only on full session stop. */
    private fun teardownCapturePipeline() {
        try { virtualDisplay?.release() } catch (_: Exception) {}
        virtualDisplay = null
        try { imageReader?.close() } catch (_: Exception) {}
        imageReader = null
    }

    private fun imageToBitmap(image: android.media.Image, width: Int, height: Int): Bitmap {
        val plane = image.planes[0]
        val buffer = plane.buffer
        val pixelStride = plane.pixelStride
        val rowStride = plane.rowStride
        val rowPadding = rowStride - pixelStride * width
        // Allocate slightly wider bitmap to absorb row padding, then crop.
        val padded = Bitmap.createBitmap(
            width + rowPadding / pixelStride, height,
            Bitmap.Config.ARGB_8888,
        )
        padded.copyPixelsFromBuffer(buffer)
        if (rowPadding == 0) return padded
        val cropped = Bitmap.createBitmap(padded, 0, 0, width, height)
        padded.recycle()
        return cropped
    }

    /**
     * Height of the system status bar in pixels (top of screen).
     * Returns 0 when the resource is unavailable so callers can skip the crop.
     */
    private fun getStatusBarHeight(): Int {
        val resId = resources.getIdentifier("status_bar_height", "dimen", "android")
        return if (resId > 0) resources.getDimensionPixelSize(resId) else 0
    }

    /**
     * Height of the system navigation bar in pixels (bottom of screen).
     * On gesture-nav devices this is typically 20-40 dp (just the swipe
     * handle area). On 3-button-nav devices it is ~48-56 dp. Returns 0
     * on devices that report no nav bar (e.g. full-screen / no-bar mode).
     */
    private fun getNavBarHeight(): Int {
        val resId = resources.getIdentifier("navigation_bar_height", "dimen", "android")
        return if (resId > 0) resources.getDimensionPixelSize(resId) else 0
    }

    private fun runOcr(bitmap: Bitmap) {
        // Region mode: defer OCR to BubbleService regardless of downstream
        // flow. The user dragged the "Region select" entry to crop the
        // capture before OCR runs — running OCR here would OCR the WHOLE
        // screen and skip the rubber-band step entirely (the user reported
        // exactly this when picking Region → Summarize: the input picker
        // showed full-screen text before they could draw the box).
        if (ScreenCaptureManager.regionMode) {
            ScreenCaptureManager.screenshot = bitmap
            deliverRegionReadyToBubble()
            return
        }

        when (ScreenCaptureManager.flow) {
            ScreenCaptureManager.Flow.LENS -> {
                val hint = ScreenCaptureManager.languageHint

                // Crop system bars (status bar on top, navigation bar on bottom)
                // BEFORE OCR. These bars contain non-translatable UI elements:
                //   top:  network speed "KB/S", signal "ll", battery "74", time
                //   bottom: gesture handle area, back/home/recents buttons
                // ML Kit picks them up as OCR blocks, and since no model
                // translates them (translation == source), they trip the server's
                // script-leak quality gate — causing the sequential provider ladder
                // to run 60+ s on a screen that would otherwise finish in 5 s.
                // Cropping them out at the source eliminates all false-positive leaks.
                // Safety guard: only crop when the remaining content area is at
                // least 3× the combined bar height to avoid decimating the bitmap
                // in landscape or very small captures.
                val sbHeight = getStatusBarHeight()
                val navHeight = getNavBarHeight()
                val totalCrop = sbHeight + navHeight
                val ocrBitmap = if (totalCrop > 0 && bitmap.height > totalCrop * 3) {
                    val cropped = Bitmap.createBitmap(
                        bitmap, 0, sbHeight,
                        bitmap.width, bitmap.height - totalCrop,
                    )
                    // Original full-screen bitmap is no longer needed; recycle it
                    // so the large ARGB_8888 allocation is freed before OCR runs.
                    if (!bitmap.isRecycled) bitmap.recycle()
                    cropped
                } else bitmap

                // Parallel compression: when the source is pinned to a vision-
                // only script we already know the vision LLM path is likely.
                // Start JPEG compression on a background thread NOW, in
                // parallel with ML Kit OCR — by the time OCR finishes (~200ms)
                // the compression (~80ms) is already done. BubbleService picks
                // up the result via CompletableFuture.getNow() and skips the
                // inline compress. The future is cancelled in clearAll() if the
                // overlay is dismissed before it's consumed.
                // NOTE: blocksDominantlyLatin() may still route the call to the
                // batch path even when forceVision=true; in that case the future
                // completes but its result is simply never consumed (no waste —
                // the background thread has already returned by then).
                if (OcrHelper.needsVisionForSource(hint)) {
                    val future = java.util.concurrent.CompletableFuture<String?>()
                    ScreenCaptureManager.pendingVisionB64 = future
                    Thread {
                        try {
                            // Reuse BubbleService's compressBitmapToB64 logic
                            // inline here to avoid a cross-service dependency.
                            val maxEdge = 1600
                            val maxSide = maxOf(ocrBitmap.width, ocrBitmap.height)
                            val upload = if (maxSide > maxEdge) {
                                val scale = maxEdge.toFloat() / maxSide
                                android.graphics.Bitmap.createScaledBitmap(
                                    ocrBitmap,
                                    (ocrBitmap.width * scale).toInt().coerceAtLeast(1),
                                    (ocrBitmap.height * scale).toInt().coerceAtLeast(1),
                                    true,
                                )
                            } else ocrBitmap
                            val baos = java.io.ByteArrayOutputStream()
                            upload.compress(android.graphics.Bitmap.CompressFormat.JPEG, 85, baos)
                            if (upload !== ocrBitmap && !upload.isRecycled) upload.recycle()
                            future.complete(
                                android.util.Base64.encodeToString(
                                    baos.toByteArray(), android.util.Base64.NO_WRAP,
                                ),
                            )
                        } catch (e: Throwable) {
                            future.complete(null) // BubbleService falls back to inline compress
                        }
                    }.start()
                } else {
                    ScreenCaptureManager.pendingVisionB64 = null
                }
                OcrHelper.recognizeBlocks(
                    ocrBitmap,
                    hintLang = hint,
                ) { blocks ->
                    handler.post {
                        if (blocks.isNullOrEmpty()) {
                            // Recycle the bitmap ourselves since the overlay
                            // path won't be invoked to consume it.
                            if (!ocrBitmap.isRecycled) ocrBitmap.recycle()
                            deliverEmptyToBubble()
                        } else {
                            // Hand off the cropped bitmap + blocks; the overlay
                            // owns them now and will recycle when it dismisses.
                            // Using the cropped bitmap means the overlay renders
                            // starting from below the status bar — block
                            // coordinates are already relative to it, so no
                            // offset adjustment is needed.
                            ScreenCaptureManager.screenshot = ocrBitmap
                            ScreenCaptureManager.blocks = blocks
                            deliverLensReadyToBubble()
                        }
                    }
                }
            }
            ScreenCaptureManager.Flow.TEXT_INTO_INPUT -> {
                OcrHelper.recognize(
                    this,
                    bitmap,
                    hintLang = ScreenCaptureManager.languageHint,
                ) { text ->
                    handler.post {
                        if (!bitmap.isRecycled) bitmap.recycle()
                        deliverTextToBubble(text)
                    }
                }
            }
            ScreenCaptureManager.Flow.SUBTITLE -> {
                // Live subtitle runs its own continuous loop (grabSubtitleFrame),
                // never the single-shot runOcr path. Recycle defensively.
                if (!bitmap.isRecycled) bitmap.recycle()
            }
        }
    }

    private fun deliverRegionReadyToBubble() {
        val intent = Intent(this, BubbleService::class.java).apply {
            action = BubbleService.ACTION_DELIVER_REGION_READY
        }
        startBubbleService(intent)
    }

    private fun deliverTextToBubble(text: String?) {
        val intent = Intent(this, BubbleService::class.java).apply {
            action = BubbleService.ACTION_DELIVER_OCR
            putExtra(BubbleService.EXTRA_TEXT, text)
            putExtra(BubbleService.EXTRA_MODE, ScreenCaptureManager.pendingMode)
        }
        startBubbleService(intent)
    }

    private fun deliverLensReadyToBubble() {
        val intent = Intent(this, BubbleService::class.java).apply {
            action = BubbleService.ACTION_DELIVER_LENS
        }
        startBubbleService(intent)
    }

    private fun deliverEmptyToBubble() {
        val intent = Intent(this, BubbleService::class.java).apply {
            action = BubbleService.ACTION_DELIVER_OCR
            putExtra(BubbleService.EXTRA_TEXT, null as String?)
        }
        startBubbleService(intent)
    }

    private fun startBubbleService(intent: Intent) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(intent)
        } else {
            startService(intent)
        }
    }

    /**
     * Full teardown: release per-capture pipeline AND the MediaProjection,
     * then stop the foreground service entirely. Called when the user
     * closes the bubble, the system revokes the grant, or the OS kills us.
     */
    private fun stopProjectionAndSelf() {
        handler.removeCallbacks(idleReleaseRunnable)
        handler.removeCallbacks(captureTimeoutRunnable)
        teardownCapturePipeline()
        try { mediaProjection?.stop() } catch (_: Exception) {}
        mediaProjection = null
        isProjectionActive = false
        // Drop only the projection token — bitmap + blocks (if any) belong
        // to whatever overlay is currently showing them.
        ScreenCaptureManager.clearToken()
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    /**
     * The reused single-app grant couldn't capture the current foreground
     * app (the user switched apps and pressed capture). We cannot re-open
     * the system consent ourselves: MIUI aborts background activity starts
     * that aren't tied to a live user gesture, so launching the consent
     * activity from this timer is silently denied ("Abort background
     * activity starts"). Instead we fully release the stale projection (so a
     * later fresh consent won't hit SystemUI's reuse-branch crash) and hand
     * off to BubbleService, which restores the bubble and shows a tappable
     * "grant for this app" pill — the user's TAP then launches consent from
     * inside a gesture, which MIUI permits.
     *
     * [ScreenCaptureManager] still holds the flow / language hint / target
     * from [BubbleService.launchScanFlow], so the pill's re-scan resumes the
     * same action.
     */
    private fun reopenConsent() {
        handler.removeCallbacks(idleReleaseRunnable)
        handler.removeCallbacks(captureTimeoutRunnable)
        teardownCapturePipeline()
        try { mediaProjection?.stop() } catch (_: Exception) {}
        mediaProjection = null
        isProjectionActive = false
        ScreenCaptureManager.clearToken()
        startBubbleService(Intent(this, BubbleService::class.java).apply {
            action = BubbleService.ACTION_RECONSENT
        })
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    override fun onDestroy() {
        // Service can be killed by OS without ACTION_STOP — make sure the
        // global flag matches reality so the next bubble session triggers
        // a fresh consent prompt.
        isProjectionActive = false
        teardownCapturePipeline()
        try { mediaProjection?.stop() } catch (_: Exception) {}
        mediaProjection = null
        super.onDestroy()
    }

    // ── Notification ──

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID, "TransKey Screen Scan",
                NotificationManager.IMPORTANCE_LOW,
            ).apply {
                description = "Persistent notification while TransKey holds your screen-capture grant"
                setShowBadge(false)
            }
            getSystemService(NotificationManager::class.java)?.createNotificationChannel(channel)
        }
    }

    private fun buildNotification(): Notification {
        val launchIntent = PendingIntent.getActivity(
            this, 0,
            Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_IMMUTABLE,
        )
        // Tapping the notification's "Stop" action releases the projection.
        val stopIntent = PendingIntent.getService(
            this, 1,
            Intent(this, ScreenCaptureService::class.java).apply { action = ACTION_STOP_PROJECTION },
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION") Notification.Builder(this)
        }
        return builder
            .setContentTitle(getString(R.string.bubble_scan_notification_title))
            .setContentText(getString(R.string.bubble_scan_notification_body))
            // R.mipmap.ic_launcher is a colourful launcher icon — Android 11+
            // silently filters notifications whose small icon isn't a
            // tintable monochrome image, which made this FGS's persistent
            // notification invisible in the panel even though it WAS being
            // posted. Without it the user had no "casting" indicator and
            // no manual Stop entry point, so the only way out was waiting
            // for our code to release the projection. Use a system
            // monochrome drawable (same approach as BubbleService).
            .setSmallIcon(android.R.drawable.ic_menu_camera)
            .setContentIntent(launchIntent)
            .addAction(0, getString(R.string.bubble_scan_stop), stopIntent)
            .setOngoing(true)
            .build()
    }

    // ──────────────────────────────────────────────────────────────────
    // Live subtitle pipeline
    // ──────────────────────────────────────────────────────────────────

    /**
     * Enter continuous subtitle mode: acquire the projection (reusing the
     * token the permission activity just stashed), warm the on-device
     * translator, show the overlay bar, and start the capture tick loop.
     */
    private fun startSubtitle() {
        if (subtitleMode) return
        subtitleMode = true
        isSubtitleActive = true
        Log.d(TAG, "startSubtitle src=${ScreenCaptureManager.subtitleSource} tgt=${ScreenCaptureManager.subtitleTarget}")

        // Drop any stale single-shot Lens pipeline / projection so we don't
        // leak a VirtualDisplay or double-hold the grant.
        handler.removeCallbacks(idleReleaseRunnable)
        handler.removeCallbacks(captureTimeoutRunnable)
        teardownCapturePipeline()
        try { mediaProjection?.stop() } catch (_: Exception) {}
        mediaProjection = null

        subtitleOverlay = SubtitleOverlay(this).also { it.show() }

        // Resolve the source language. With a fixed pick we warm the model
        // now (first pair downloads ~30 MB; until ready, onSubtitleText shows
        // the original caption). With "auto" we defer until the first caption
        // lets us detect the language on-device.
        autoSource = ScreenCaptureManager.subtitleSource == "auto"
        resolvedSource = if (autoSource) "" else ScreenCaptureManager.subtitleSource
        if (!autoSource) {
            TranslateHelper.prepare(resolvedSource, ScreenCaptureManager.subtitleTarget) { ready ->
                if (!ready) handler.post {
                    subtitleOverlay?.setText(getString(R.string.subtitle_model_unavailable))
                }
            }
        }

        val resultIntent = ScreenCaptureManager.resultIntent
        if (resultIntent == null) {
            Log.w(TAG, "startSubtitle: no projection token")
            stopSubtitle()
            return
        }
        val mpm = getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
        val projection = try {
            mpm.getMediaProjection(ScreenCaptureManager.resultCode, resultIntent)
        } catch (error: Exception) {
            Log.w(TAG, "startSubtitle getMediaProjection failed: ${error.message}")
            null
        }
        if (projection == null) {
            stopSubtitle()
            return
        }
        mediaProjection = projection
        isProjectionActive = true
        projection.registerCallback(object : MediaProjection.Callback() {
            override fun onStop() {
                Log.d(TAG, "subtitle: MediaProjection revoked")
                handler.post { stopSubtitle() }
            }
        }, handler)

        // Let the consent dialog dismiss before the first frame.
        handler.postDelayed({ setupSubtitlePipeline(projection) }, 300)
    }

    private fun setupSubtitlePipeline(projection: MediaProjection) {
        if (!subtitleMode) return
        val (width, height, density) = readDisplaySize()
        subWidth = width
        subHeight = height
        val reader = ImageReader.newInstance(width, height, PixelFormat.RGBA_8888, 2)
        subImageReader = reader
        try {
            subVirtualDisplay = projection.createVirtualDisplay(
                "TransKeySubtitle",
                width, height, density,
                DisplayManager.VIRTUAL_DISPLAY_FLAG_AUTO_MIRROR,
                reader.surface, null, handler,
            )
        } catch (error: Exception) {
            Log.w(TAG, "subtitle createVirtualDisplay failed: ${error.message}")
            stopSubtitle()
            return
        }
        Log.d(TAG, "subtitle pipeline up ${width}x${height}, band=${bandFraction(KEY_BAND_TOP, OCR_BAND_TOP_DEFAULT)}..${bandFraction(KEY_BAND_BOTTOM, OCR_BAND_BOTTOM_DEFAULT)}")
        handler.postDelayed(subtitleTick, SUBTITLE_FIRST_DELAY_MS)
    }

    /**
     * One tick of the capture loop: grab the latest mirrored frame, hand it
     * to [processSubtitleBitmap], then re-arm. Runs at [SUBTITLE_INTERVAL_MS]
     * (~3 fps) — fast enough to feel live, slow enough to spare the battery.
     */
    private fun grabSubtitleFrame() {
        if (!subtitleMode) return
        try {
            val image = subImageReader?.acquireLatestImage()
            if (image != null) {
                val bitmap = try {
                    imageToBitmap(image, subWidth, subHeight)
                } catch (error: Exception) {
                    Log.w(TAG, "subtitle imageToBitmap failed: ${error.message}")
                    null
                } finally {
                    try { image.close() } catch (_: Exception) {}
                }
                if (bitmap != null) processSubtitleBitmap(bitmap)
            }
        } catch (error: Throwable) {
            Log.w(TAG, "subtitle grab failed: ${error.message}")
        }
        if (subtitleMode) handler.postDelayed(subtitleTick, SUBTITLE_INTERVAL_MS)
    }

    /**
     * Crop the caption band, skip it if unchanged since last frame, else OCR
     * it. The band sits ABOVE the overlay bar so we never read our own output.
     */
    private fun processSubtitleBitmap(full: Bitmap) {
        val top = (subHeight * bandFraction(KEY_BAND_TOP, OCR_BAND_TOP_DEFAULT)).toInt()
            .coerceIn(0, subHeight - 1)
        val bottom = (subHeight * bandFraction(KEY_BAND_BOTTOM, OCR_BAND_BOTTOM_DEFAULT)).toInt()
            .coerceIn(top + 1, subHeight)
        val band = try {
            Bitmap.createBitmap(full, 0, top, subWidth, bottom - top)
        } catch (error: Exception) {
            if (!full.isRecycled) full.recycle()
            return
        }
        if (!full.isRecycled) full.recycle()

        // Change detection: identical band (same caption still showing, or a
        // static scene) → skip the OCR + translate work entirely.
        val hash = aHash(band)
        if (lastBandHash != 0L && hammingDistance(hash, lastBandHash) <= HASH_HAMMING_THRESHOLD) {
            band.recycle()
            return
        }
        lastBandHash = hash

        OcrHelper.recognize(
            this,
            band,
            hintLang = ScreenCaptureManager.subtitleSource.takeIf { it != "auto" },
        ) { text ->
            handler.post {
                if (!band.isRecycled) band.recycle()
                if (subtitleMode) onSubtitleText(text)
            }
        }
    }

    private fun onSubtitleText(text: String?) {
        val clean = text?.replace('\n', ' ')?.trim()
        if (clean.isNullOrEmpty()) {
            subtitleOverlay?.clearText()
            lastOcrText = null
            return
        }
        // Same caption as last frame is still showing — nothing to do.
        if (clean == lastOcrText) return
        lastOcrText = clean

        // Auto-source: detect the caption language once, warm its model, and
        // show the original line in the meantime.
        if (autoSource && resolvedSource.isEmpty()) {
            detectSourceAndPrepare(clean)
            subtitleOverlay?.setText(clean)
            return
        }

        translationCache[clean]?.let {
            subtitleOverlay?.setText(it)
            return
        }

        TranslateHelper.translate(clean) { translated ->
            handler.post {
                // While translating, the caption may have changed; only show
                // this result if it still matches the current line.
                if (!subtitleMode || lastOcrText != clean) return@post
                if (translated != null) {
                    translationCache[clean] = translated
                    subtitleOverlay?.setText(translated)
                } else {
                    // Model not ready / unsupported pair: show the original so
                    // the user isn't left with a blank bar.
                    subtitleOverlay?.setText(clean)
                }
            }
        }
    }

    /**
     * Identify the caption language on-device and warm the translate model
     * for detected → target. Latches [resolvedSource] on the first confident
     * hit; a "und" / unsupported / same-as-target result is ignored so the
     * next caption retries.
     */
    private fun detectSourceAndPrepare(sample: String) {
        val identifier = langIdentifier
            ?: com.google.mlkit.nl.languageid.LanguageIdentification.getClient()
                .also { langIdentifier = it }
        identifier.identifyLanguage(sample)
            .addOnSuccessListener { code ->
                if (!subtitleMode || !autoSource || resolvedSource.isNotEmpty()) return@addOnSuccessListener
                val target = ScreenCaptureManager.subtitleTarget
                if (code == "und" || code == target || !TranslateHelper.isSupported(code)) {
                    return@addOnSuccessListener
                }
                resolvedSource = code
                Log.d(TAG, "subtitle auto-detected source=$code")
                TranslateHelper.prepare(code, target) { ready ->
                    if (!ready) handler.post {
                        subtitleOverlay?.setText(getString(R.string.subtitle_model_unavailable))
                    }
                }
            }
    }

    /** Exit subtitle mode, release everything, stop the service. */
    private fun stopSubtitle() {
        subtitleMode = false
        isSubtitleActive = false
        handler.removeCallbacks(subtitleTick)
        try { subVirtualDisplay?.release() } catch (_: Exception) {}
        subVirtualDisplay = null
        try { subImageReader?.close() } catch (_: Exception) {}
        subImageReader = null
        subtitleOverlay?.hide()
        subtitleOverlay = null
        TranslateHelper.close()
        try { langIdentifier?.close() } catch (_: Exception) {}
        langIdentifier = null
        autoSource = false
        resolvedSource = ""
        translationCache.clear()
        lastOcrText = null
        lastBandHash = 0L
        try { mediaProjection?.stop() } catch (_: Exception) {}
        mediaProjection = null
        isProjectionActive = false
        ScreenCaptureManager.clearToken()
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    /** Read a band fraction from Flutter prefs, clamped to a sane range. */
    private fun bandFraction(key: String, default: Float): Float {
        val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        val v = try {
            prefs.getFloat(key, default).let { if (it.isNaN()) default else it }
        } catch (_: ClassCastException) {
            default
        }
        return v.coerceIn(0.1f, 0.98f)
    }

    /**
     * 64-bit average hash of [bitmap]: downscale to 8x8 grayscale, set each
     * bit where the cell's luma exceeds the frame mean. Cheap and robust to
     * tiny noise — two frames of the same caption hash within a few bits.
     */
    private fun aHash(bitmap: Bitmap): Long {
        val small = Bitmap.createScaledBitmap(bitmap, 8, 8, true)
        val px = IntArray(64)
        small.getPixels(px, 0, 8, 0, 0, 8, 8)
        small.recycle()
        val luma = IntArray(64)
        var sum = 0L
        for (i in px.indices) {
            val p = px[i]
            val l = ((p shr 16 and 0xff) * 299 + (p shr 8 and 0xff) * 587 + (p and 0xff) * 114) / 1000
            luma[i] = l
            sum += l
        }
        val mean = sum / 64
        var bits = 0L
        for (i in 0 until 64) {
            if (luma[i] >= mean) bits = bits or (1L shl i)
        }
        return bits
    }

    private fun hammingDistance(a: Long, b: Long): Int = java.lang.Long.bitCount(a xor b)

    companion object {
        private const val TAG = "TransKeyOCR"
        const val ACTION_CAPTURE = "transkey.screen.CAPTURE"
        const val ACTION_STOP_PROJECTION = "transkey.screen.STOP_PROJECTION"
        const val ACTION_START_SUBTITLE = "transkey.screen.START_SUBTITLE"
        const val ACTION_STOP_SUBTITLE = "transkey.screen.STOP_SUBTITLE"

        // ── Live subtitle tuning ──
        /** Wait for the first mirrored frame after the consent dialog. */
        private const val SUBTITLE_FIRST_DELAY_MS = 700L
        /** Capture cadence (~3 fps): live enough, easy on the battery. */
        private const val SUBTITLE_INTERVAL_MS = 320L
        /** OCR band as a fraction of screen height. Defaults sit in the lower
         *  third where captions usually are, and STRICTLY ABOVE the overlay
         *  bar so we never OCR our own translation. Tunable via Flutter prefs
         *  [KEY_BAND_TOP]/[KEY_BAND_BOTTOM] without a rebuild. */
        private const val OCR_BAND_TOP_DEFAULT = 0.50f
        private const val OCR_BAND_BOTTOM_DEFAULT = 0.84f
        private const val KEY_BAND_TOP = "flutter.tk_subtitle_band_top"
        private const val KEY_BAND_BOTTOM = "flutter.tk_subtitle_band_bottom"
        /** Max aHash bit-difference still treated as "same band". */
        private const val HASH_HAMMING_THRESHOLD = 6
        private const val TRANSLATION_CACHE_MAX = 200
        private const val CHANNEL_ID = "transkey_screen_capture"
        private const val NOTIFICATION_ID = 1002

        /**
         * Settle delay (ms) between bubble removal and arming the capture
         * gate. WindowManager removal is async — the next 1-2 display
         * refreshes can still contain the bubble. 200 ms = ~12 frames at
         * 60 Hz, safely past any compositor lag without making the user
         * notice the wait.
         */
        private const val CAPTURE_SETTLE_MS = 200L

        /**
         * Settle delay (ms) on the FIRST capture, between VirtualDisplay
         * creation and arming the gate. Longer than the reuse path because
         * the consent dialog's dismiss animation is still in flight when
         * the projection token becomes valid, and the source app behind
         * it hasn't necessarily finished its redraw yet. 500 ms = ~30
         * frames, enough to outlast both the dialog exit transition and
         * any one-frame stutter from the system compositor switching back
         * to mirroring.
         */
        private const val FIRST_CAPTURE_ARM_MS = 500L

        /**
         * Maximum time we wait for an ImageReader frame after arming the
         * capture gate. On Android 14+ "single-app" MediaProjection, if
         * the user's granted task is no longer foreground the projection
         * stops pushing frames entirely — without this fallback the
         * bubble (set to GONE for capture) is never restored.
         *
         * 3000 ms is long enough that a fast scan still completes via the
         * real frame path (~50-300 ms typical) but short enough that the
         * user doesn't sit confused. On timeout we tear down the
         * projection and force a fresh consent on the next attempt.
         */
        private const val CAPTURE_TIMEOUT_MS = 3000L

        /**
         * No-frame timeout for the REUSE path (capturing on an
         * already-granted projection). A same-app reuse frame arrives within
         * ~1-2 display refreshes (the VirtualDisplay is already mirroring),
         * so 500 ms is a 10× safety margin yet trips quickly when a
         * single-app grant's target app is no longer foreground (user
         * switched apps and pressed capture). Kept SHORT on purpose: the
         * re-consent activity must launch inside MIUI's post-tap
         * background-activity grace window (~2 s), so detection can't dawdle.
         */
        private const val REUSE_TIMEOUT_MS = 500L

        /**
         * Default + max for the idle-release window. The actual window is
         * user-configurable via the Flutter setting `tk_capture_keepalive_s`
         * (capped to [0, IDLE_RELEASE_MAX_S]) and read each time we arm the
         * timer via [readIdleReleaseMs]. Default 180s = 3 min covers the
         * realistic "scan → read → scan next" pace; max 300s = 5 min is the
         * UX ceiling chosen so the casting indicator + GPU mirroring don't
         * sit hot indefinitely. Setting it to 0 means "release immediately
         * after each scan" — privacy/battery-conservative mode.
         */
        private const val IDLE_RELEASE_DEFAULT_S = 180L
        private const val IDLE_RELEASE_MAX_S = 300L

        /**
         * True while this service holds a live MediaProjection grant.
         * BubbleService reads this to decide whether the next scan needs
         * a fresh consent prompt (false) or can fire ACTION_CAPTURE
         * directly (true). Volatile so writes from the service thread are
         * visible to the bubble's main-thread reads.
         */
        @Volatile var isProjectionActive: Boolean = false
            private set

        /**
         * True while live subtitle mode is running. BubbleService reads this
         * so tapping the subtitle entry while it's active toggles it OFF.
         */
        @Volatile var isSubtitleActive: Boolean = false
            private set
    }
}
