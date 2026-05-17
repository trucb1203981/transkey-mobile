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
        Log.d(TAG, "idle release: no capture in ${IDLE_RELEASE_MS}ms, dropping projection")
        stopProjectionAndSelf()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        startForegroundCompat()
        when (intent?.action) {
            ACTION_CAPTURE -> startCapture()
            ACTION_STOP_PROJECTION -> stopProjectionAndSelf()
            else -> stopProjectionAndSelf()
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
            // Any new capture cancels the pending idle-release; we'll
            // re-arm it after the capture completes.
            handler.removeCallbacks(idleReleaseRunnable)
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
     * [IDLE_RELEASE_MS], in which case we drop the projection entirely.
     */
    private fun armIdleRelease() {
        handler.removeCallbacks(idleReleaseRunnable)
        handler.postDelayed(idleReleaseRunnable, IDLE_RELEASE_MS)
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
        return if (rowPadding == 0) padded
        else Bitmap.createBitmap(padded, 0, 0, width, height)
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
                OcrHelper.recognizeBlocks(
                    bitmap,
                    hintLang = ScreenCaptureManager.languageHint,
                ) { blocks ->
                    handler.post {
                        if (blocks.isNullOrEmpty()) {
                            // Recycle the bitmap ourselves since the overlay
                            // path won't be invoked to consume it.
                            if (!bitmap.isRecycled) bitmap.recycle()
                            deliverEmptyToBubble()
                        } else {
                            // Hand off the bitmap + blocks; the overlay
                            // owns them now and will recycle when it dismisses.
                            ScreenCaptureManager.screenshot = bitmap
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

    companion object {
        private const val TAG = "TransKeyOCR"
        const val ACTION_CAPTURE = "transkey.screen.CAPTURE"
        const val ACTION_STOP_PROJECTION = "transkey.screen.STOP_PROJECTION"
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
         * Auto-release the MediaProjection when no capture happens for this
         * long. The grant-reuse optimisation is great for back-to-back
         * scans, but holding the VirtualDisplay live forever means the
         * GPU keeps mirroring the screen at 60 fps the entire time the
         * bubble is on — which heats the device noticeably during a
         * regular browsing session. 3 minutes covers the realistic
         * "scan → read translation → scan next thing" pace (60 s was
         * too tight; users reading a longer Lens result kept hitting
         * a re-consent prompt on their next scan). The cost: a scan
         * after a quiet 3 minutes triggers the consent dialog again.
         */
        private const val IDLE_RELEASE_MS = 180_000L

        /**
         * True while this service holds a live MediaProjection grant.
         * BubbleService reads this to decide whether the next scan needs
         * a fresh consent prompt (false) or can fire ACTION_CAPTURE
         * directly (true). Volatile so writes from the service thread are
         * visible to the bubble's main-thread reads.
         */
        @Volatile var isProjectionActive: Boolean = false
            private set
    }
}
