package com.example.transkey_mobile

import android.annotation.SuppressLint
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.util.TypedValue
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.TextView

class BubbleService : Service() {

    companion object {
        const val CHANNEL_ID = "transkey_bubble"
        const val NOTIFICATION_ID = 1001
        const val ACTION_START = "transkey.bubble.START"
        const val ACTION_STOP = "transkey.bubble.STOP"
        const val ACTION_SET_STATE = "transkey.bubble.SET_STATE"
        const val EXTRA_STATE = "bubble_state"

        const val METHOD_CHANNEL = "transkey/bubble"

        // States
        const val STATE_IDLE = "idle"
        const val STATE_LOADING = "loading"
        const val STATE_RESULT = "result"
        const val STATE_ERROR = "error"

        private const val BUBBLE_SIZE_DP = 48
        private const val DISMISS_THRESHOLD_DP = 120
    }

    private var windowManager: WindowManager? = null
    private var bubbleView: View? = null
    private var bubbleIcon: ImageView? = null
    private var badgeText: TextView? = null
    private var loadingSpinner: View? = null
    private var dismissZone: View? = null
    private var currentState: String = STATE_IDLE

    private val handler = Handler(Looper.getMainLooper())
    private var loadingAngle = 0f
    private var loadingRunnable: Runnable? = null

    // Bubble position
    private var initialX = 0
    private var initialY = 0
    private var initialTouchX = 0f
    private var initialTouchY = 0f
    private var isDragging = false

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
        startForeground(NOTIFICATION_ID, buildNotification())
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> {
                stopBubble()
                return START_NOT_STICKY
            }
            ACTION_SET_STATE -> {
                val state = intent.getStringExtra(EXTRA_STATE) ?: return START_NOT_STICKY
                setState(state)
            }
            ACTION_START -> {
                showBubble()
            }
        }
        return START_STICKY
    }

    override fun onDestroy() {
        removeBubble()
        super.onDestroy()
    }

    // ── Notification ──

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "TransKey Bubble",
                NotificationManager.IMPORTANCE_LOW,
            ).apply {
                description = "Floating translation bubble"
                setShowBadge(false)
            }
            val nm = getSystemService(NotificationManager::class.java)
            nm.createNotificationChannel(channel)
        }
    }

    private fun buildNotification(): Notification {
        val intent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP
        }
        val pending = PendingIntent.getActivity(
            this, 0, intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
                .setContentTitle("TransKey Bubble")
                .setContentText("Floating translator active")
                .setSmallIcon(android.R.drawable.ic_dialog_info)
                .setContentIntent(pending)
                .setOngoing(true)
                .build()
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
                .setContentTitle("TransKey Bubble")
                .setContentText("Floating translator active")
                .setSmallIcon(android.R.drawable.ic_dialog_info)
                .setContentIntent(pending)
                .setOngoing(true)
                .build()
        }
    }

    // ── Bubble UI ──

    @SuppressLint("ClickableViewAccessibility")
    private fun showBubble() {
        if (bubbleView != null) return

        windowManager = getSystemService(WINDOW_SERVICE) as WindowManager
        val dp = resources.displayMetrics.density
        val bubbleSize = (BUBBLE_SIZE_DP * dp).toInt()

        // Main bubble container
        val container = FrameLayout(this).apply {
            layoutParams = FrameLayout.LayoutParams(bubbleSize, bubbleSize)
        }

        // Circle background
        val circleDrawable = GradientDrawable().apply {
            shape = GradientDrawable.OVAL
            setColor(Color.parseColor("#6C63FF"))
            setStroke(3, Color.WHITE)
        }

        // Icon
        bubbleIcon = ImageView(this).apply {
            setImageResource(android.R.drawable.ic_menu_crop) // translate icon substitute
            setColorFilter(Color.WHITE)
            setImageDrawable(getBubbleIconDrawable(STATE_IDLE))
            layoutParams = FrameLayout.LayoutParams(
                (24 * dp).toInt(), (24 * dp).toInt(),
                Gravity.CENTER,
            )
        }

        // Badge (for result/error)
        badgeText = TextView(this).apply {
            text = ""
            setTextColor(Color.WHITE)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 9f)
            typeface = android.graphics.Typeface.DEFAULT_BOLD
            gravity = Gravity.CENTER
            setBackgroundColor(Color.TRANSPARENT)
            visibility = View.GONE
            layoutParams = FrameLayout.LayoutParams(
                (16 * dp).toInt(), (16 * dp).toInt(),
                Gravity.END or Gravity.TOP,
            ).apply {
                setMargins(0, 0, (-4 * dp).toInt(), 0)
            }
        }

        // Loading spinner (rotating arc)
        loadingSpinner = View(this).apply {
            visibility = View.GONE
            layoutParams = FrameLayout.LayoutParams(
                (32 * dp).toInt(), (32 * dp).toInt(),
                Gravity.CENTER,
            )
        }

        container.addView(bubbleIcon)
        container.addView(badgeText)
        container.addView(loadingSpinner)
        container.background = circleDrawable

        // Dismiss zone (bottom trash area)
        dismissZone = View(this).apply {
            visibility = View.GONE
            background = GradientDrawable().apply {
                setColor(Color.parseColor("#40FF6B6B"))
                setCornerRadius(24 * dp)
            }
            layoutParams = FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                (80 * dp).toInt(),
                Gravity.BOTTOM,
            )
        }

        // Root layout
        val root = FrameLayout(this)
        root.addView(dismissZone, FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.MATCH_PARENT,
            (80 * dp).toInt(),
            Gravity.BOTTOM,
        ))

        bubbleView = container
        windowManager?.addView(container, buildLayoutParams())

        // Touch handling
        container.setOnTouchListener { _, event ->
            handleBubbleTouch(event, dp)
        }
    }

    private fun handleBubbleTouch(event: MotionEvent, dp: Float): Boolean {
        val params = bubbleView?.layoutParams as? WindowManager.LayoutParams ?: return false

        when (event.action) {
            MotionEvent.ACTION_DOWN -> {
                initialX = params.x
                initialY = params.y
                initialTouchX = event.rawX
                initialTouchY = event.rawY
                isDragging = false
                return true
            }
            MotionEvent.ACTION_MOVE -> {
                val dx = event.rawX - initialTouchX
                val dy = event.rawY - initialTouchY
                if (dx * dx + dy * dy > 25 * dp * dp) isDragging = true

                params.x = initialX + dx.toInt()
                params.y = initialY + dy.toInt()
                windowManager?.updateViewLayout(bubbleView!!, params)

                // Show dismiss zone when near bottom
                val screenHeight = resources.displayMetrics.heightPixels
                val dismissThreshold = (DISMISS_THRESHOLD_DP * dp).toInt()
                val nearBottom = params.y > screenHeight - dismissThreshold
                dismissZone?.visibility = if (nearBottom) View.VISIBLE else View.GONE

                return true
            }
            MotionEvent.ACTION_UP -> {
                if (isDragging) {
                    val screenHeight = resources.displayMetrics.heightPixels
                    val dismissThreshold = (DISMISS_THRESHOLD_DP * dp).toInt()

                    // Check if dropped in dismiss zone
                    if (params.y > screenHeight - dismissThreshold) {
                        stopBubble()
                        notifyFlutter("onDismissed")
                        return true
                    }

                    // Snap to nearest edge
                    val screenWidth = resources.displayMetrics.widthPixels
                    val centerX = params.x + (BUBBLE_SIZE_DP * dp / 2).toInt()
                    params.x = if (centerX < screenWidth / 2) 0 else screenWidth - (BUBBLE_SIZE_DP * dp).toInt()
                    params.y = params.y.coerceIn(0, screenHeight - (BUBBLE_SIZE_DP * dp).toInt())
                    windowManager?.updateViewLayout(bubbleView!!, params)
                } else {
                    // Tap — notify Flutter
                    notifyFlutter("onTapped")
                }

                dismissZone?.visibility = View.GONE
                return true
            }
        }
        return false
    }

    private fun buildLayoutParams(): WindowManager.LayoutParams {
        val dp = resources.displayMetrics.density
        val bubbleSize = (BUBBLE_SIZE_DP * dp).toInt()

        return WindowManager.LayoutParams(
            bubbleSize,
            bubbleSize,
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
                WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
            else
                @Suppress("DEPRECATION")
                WindowManager.LayoutParams.TYPE_PHONE,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE,
            PixelFormat.TRANSLUCENT,
        ).apply {
            gravity = Gravity.TOP or Gravity.START
            x = 0
            y = 300
        }
    }

    // ── State management ──

    fun setState(state: String) {
        currentState = state
        handler.post { updateBubbleVisuals() }
    }

    private fun updateBubbleVisuals() {
        val view = bubbleView ?: return
        val dp = resources.displayMetrics.density

        when (currentState) {
            STATE_IDLE -> {
                (view.background as? GradientDrawable)?.setColor(Color.parseColor("#6C63FF"))
                view.alpha = 0.6f
                badgeText?.visibility = View.GONE
                loadingSpinner?.visibility = View.GONE
                stopLoadingAnimation()
                bubbleIcon?.setImageDrawable(getBubbleIconDrawable(STATE_IDLE))
                bubbleIcon?.visibility = View.VISIBLE
            }
            STATE_LOADING -> {
                (view.background as? GradientDrawable)?.setColor(Color.parseColor("#6C63FF"))
                view.alpha = 1.0f
                badgeText?.visibility = View.GONE
                bubbleIcon?.visibility = View.GONE
                loadingSpinner?.visibility = View.VISIBLE
                startLoadingAnimation()
            }
            STATE_RESULT -> {
                (view.background as? GradientDrawable)?.setColor(Color.parseColor("#43E97B"))
                view.alpha = 1.0f
                bubbleIcon?.visibility = View.VISIBLE
                loadingSpinner?.visibility = View.GONE
                stopLoadingAnimation()
                bubbleIcon?.setImageDrawable(getBubbleIconDrawable(STATE_RESULT))
                badgeText?.apply {
                    text = "✓"
                    setTextColor(Color.WHITE)
                    background = GradientDrawable().apply {
                        shape = GradientDrawable.OVAL
                        setColor(Color.parseColor("#43E97B"))
                    }
                    visibility = View.VISIBLE
                }
            }
            STATE_ERROR -> {
                (view.background as? GradientDrawable)?.setColor(Color.parseColor("#FF6B6B"))
                view.alpha = 1.0f
                bubbleIcon?.visibility = View.VISIBLE
                loadingSpinner?.visibility = View.GONE
                stopLoadingAnimation()
                bubbleIcon?.setImageDrawable(getBubbleIconDrawable(STATE_ERROR))
                badgeText?.apply {
                    text = "!"
                    setTextColor(Color.WHITE)
                    background = GradientDrawable().apply {
                        shape = GradientDrawable.OVAL
                        setColor(Color.parseColor("#FF6B6B"))
                    }
                    visibility = View.VISIBLE
                }
            }
        }
    }

    private fun getBubbleIconDrawable(state: String): android.graphics.drawable.Drawable {
        // Use system drawables as placeholders
        return when (state) {
            STATE_RESULT -> {
                val drawable = GradientDrawable().apply {
                    shape = GradientDrawable.OVAL
                    setColor(Color.TRANSPARENT)
                    setStroke(3, Color.WHITE)
                }
                drawable
            }
            STATE_ERROR -> {
                val drawable = GradientDrawable().apply {
                    shape = GradientDrawable.OVAL
                    setColor(Color.TRANSPARENT)
                    setStroke(3, Color.WHITE)
                }
                drawable
            }
            else -> {
                val drawable = GradientDrawable().apply {
                    shape = GradientDrawable.OVAL
                    setColor(Color.TRANSPARENT)
                    setStroke(3, Color.WHITE)
                }
                drawable
            }
        }
    }

    private fun startLoadingAnimation() {
        stopLoadingAnimation()
        loadingRunnable = object : Runnable {
            override fun run() {
                loadingAngle = (loadingAngle + 10) % 360
                loadingSpinner?.rotation = loadingAngle
                loadingRunnable?.let { handler.postDelayed(it, 16) }
            }
        }
        loadingRunnable?.let { handler.post(it) }
    }

    private fun stopLoadingAnimation() {
        loadingRunnable?.let { handler.removeCallbacks(it) }
        loadingRunnable = null
    }

    // ── Flutter communication ──

    private fun notifyFlutter(method: String) {
        val eng = TransKeyApp.engine
        if (eng != null) {
            io.flutter.plugin.common.MethodChannel(
                eng.dartExecutor.binaryMessenger, METHOD_CHANNEL,
            ).invokeMethod(method, null)
        }
    }

    // ── Lifecycle ──

    fun stopBubble() {
        removeBubble()
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    private fun removeBubble() {
        stopLoadingAnimation()
        bubbleView?.let {
            try { windowManager?.removeView(it) } catch (_: Exception) {}
        }
        bubbleView = null
        bubbleIcon = null
        badgeText = null
        loadingSpinner = null
        dismissZone = null
    }
}
