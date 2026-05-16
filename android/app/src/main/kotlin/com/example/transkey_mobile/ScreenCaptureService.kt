package com.example.transkey_mobile

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
        // mirroring the screen. Re-arm `captured = false` and the existing
        // listener will pick up the next frame the system pushes through
        // — typically within one display refresh (~16 ms).
        //
        // Why we DON'T tear down VirtualDisplay between scans: on Android
        // 14+ the MediaProjection grant is invalidated as soon as its
        // last VirtualDisplay is released. We'd then need a fresh
        // "Start recording?" prompt for every scan, which defeats the
        // whole point of caching the grant.
        if (mediaProjection != null && imageReader != null && virtualDisplay != null) {
            captured = false
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
        captured = false

        val metrics = resources.displayMetrics
        val width = metrics.widthPixels
        val height = metrics.heightPixels
        val density = metrics.densityDpi

        val reader = ImageReader.newInstance(width, height, PixelFormat.RGBA_8888, 2)
        imageReader = reader
        reader.setOnImageAvailableListener({ r ->
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
                image.close()
            }
            // Pipeline stays alive — next scan will set captured=false and
            // this same listener will pick up the next available frame.

            if (bitmap == null) {
                deliverEmptyToBubble()
                return@setOnImageAvailableListener
            }
            runOcr(bitmap)
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
        }
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
        // Region mode: defer OCR to BubbleService so the user can crop the
        // captured frame first. We hand over the raw bitmap and let the
        // overlay run OCR on the sub-image after the rubber-band release.
        if (ScreenCaptureManager.flow == ScreenCaptureManager.Flow.LENS &&
            ScreenCaptureManager.regionMode) {
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
            .setSmallIcon(R.mipmap.ic_launcher)
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
