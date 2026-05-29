package app.transkey.mobile

import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.util.TypedValue
import android.content.Intent
import android.os.SystemClock
import android.view.Gravity
import android.view.MotionEvent
import android.view.ViewConfiguration
import android.view.WindowManager
import android.widget.FrameLayout
import android.widget.TextView
import app.transkey.mobile.BubbleService.Companion.BUBBLE_SIZE_DP
import app.transkey.mobile.BubbleService.Companion.CLOSE_ZONE_BOTTOM_MARGIN_DP
import app.transkey.mobile.BubbleService.Companion.CLOSE_ZONE_HIT_RADIUS_DP
import app.transkey.mobile.BubbleService.Companion.CLOSE_ZONE_SIZE_DP

/**
 * Bubble touch handling and the drag-to-close target. Extracted from
 * [BubbleService] so the service class itself stays focused on lifecycle
 * and intent routing rather than gesture math.
 *
 * The drag-state fields (`initialX`, `initialY`, `initialTouchX`,
 * `initialTouchY`, `isDragging`, `isOverCloseZone`, `closeZoneView`,
 * `closeZoneIcon`) live on the service so onBubbleTapped + onDestroy
 * can still observe / reset them.
 */
internal fun BubbleService.handleBubbleTouch(event: MotionEvent, dp: Float): Boolean {
    val params = bubbleView?.layoutParams as? WindowManager.LayoutParams ?: return false

    when (event.action) {
        MotionEvent.ACTION_DOWN -> {
            // Nudge the bubble fully into view before reading initialX —
            // when idle it sits half-hidden against the edge (Messenger
            // chat-head style); the touch should restore full visibility
            // first so a drag from this point doesn't yank the bubble
            // through a discontinuous jump.
            snapBubbleToEdge(dp, halfHidden = false)
            initialX = params.x
            initialY = params.y
            initialTouchX = event.rawX
            initialTouchY = event.rawY
            isDragging = false
            isOverCloseZone = false
            longPressFired = false
            handler.postDelayed(longPressRunnable, ViewConfiguration.getLongPressTimeout().toLong())
            return true
        }
        MotionEvent.ACTION_MOVE -> {
            val dx = event.rawX - initialTouchX
            val dy = event.rawY - initialTouchY
            if (!isDragging && dx * dx + dy * dy > 25 * dp * dp) {
                isDragging = true
                handler.removeCallbacks(longPressRunnable)
                showCloseZone(dp)
            }
            params.x = initialX + dx.toInt()
            params.y = initialY + dy.toInt()
            windowManager?.updateViewLayout(bubbleView!!, params)
            if (isDragging) {
                val bubbleSize = (BUBBLE_SIZE_DP * dp).toInt()
                val bubbleCenterX = params.x + bubbleSize / 2
                val bubbleCenterY = params.y + bubbleSize / 2
                val over = isBubbleOverCloseZone(bubbleCenterX, bubbleCenterY, dp)
                if (over != isOverCloseZone) {
                    isOverCloseZone = over
                    updateCloseZoneVisual(over)
                }
            }
            return true
        }
        MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
            handler.removeCallbacks(longPressRunnable)
            if (isDragging) {
                hideCloseZone()
                if (isOverCloseZone) {
                    isOverCloseZone = false
                    stopBubble()
                    return true
                }
                // Snap to the closest edge first (Y stays in-bounds),
                // then ride the half-hide animation so the bubble settles
                // peeking out — Messenger chat-head behavior.
                val sw = resources.displayMetrics.widthPixels
                val sh = resources.displayMetrics.heightPixels
                val centerX = params.x + (BUBBLE_SIZE_DP * dp / 2).toInt()
                params.x = if (centerX < sw / 2) 0 else sw - (BUBBLE_SIZE_DP * dp).toInt()
                params.y = params.y.coerceIn(0, sh - (BUBBLE_SIZE_DP * dp).toInt())
                windowManager?.updateViewLayout(bubbleView!!, params)
                scheduleBubbleHalfHide(dp)
            } else if (event.action == MotionEvent.ACTION_UP && !longPressFired) {
                onBubbleTapped()
            }
            return true
        }
    }
    return false
}

/// Snap the bubble flush against whichever screen edge it currently
/// sits closer to. When `halfHidden=true`, the bubble's x is pushed
/// further so only half of it remains visible — the Messenger
/// chat-head idle state. Always preserves Y (vertical position is
/// user-controlled).
internal fun BubbleService.snapBubbleToEdge(dp: Float, halfHidden: Boolean) {
    val view = bubbleView ?: return
    val params = view.layoutParams as? WindowManager.LayoutParams ?: return
    val sw = resources.displayMetrics.widthPixels
    val bubbleSize = (BUBBLE_SIZE_DP * dp).toInt()
    val centerX = params.x + bubbleSize / 2
    val onLeft = centerX < sw / 2
    val hiddenInset = bubbleSize / 2
    params.x = when {
        halfHidden && onLeft  -> -hiddenInset
        halfHidden && !onLeft -> sw - bubbleSize + hiddenInset
        onLeft                -> 0
        else                  -> sw - bubbleSize
    }
    // Slight alpha drop when peeking — closer to the Messenger idle
    // affordance and signals "tap to bring back" without being
    // distracting.
    view.alpha = if (halfHidden) 0.7f else 1.0f
    windowManager?.updateViewLayout(view, params)
}

/// Schedule the half-hide a short delay after the user has released
/// the bubble. The delay lets ripples / state changes settle and avoids
/// the bubble visually "fleeing" the touch the moment the finger leaves.
internal fun BubbleService.scheduleBubbleHalfHide(dp: Float) {
    cancelBubbleHalfHide()
    bubbleHalfHideRunnable = Runnable { snapBubbleToEdge(dp, halfHidden = true) }
    handler.postDelayed(bubbleHalfHideRunnable!!, 1200L)
}

/// Cancel any pending half-hide. Call when a popup (mode picker /
/// result panel) is about to open so the bubble doesn't slide off
/// the edge mid-interaction.
internal fun BubbleService.cancelBubbleHalfHide() {
    bubbleHalfHideRunnable?.let { handler.removeCallbacks(it) }
    bubbleHalfHideRunnable = null
}

internal fun BubbleService.showCloseZone(dp: Float) {
    if (closeZoneView != null) return
    ensureWindowManager()
    val size = (CLOSE_ZONE_SIZE_DP * dp).toInt()
    val container = FrameLayout(this).apply {
        layoutParams = FrameLayout.LayoutParams(size, size)
        background = GradientDrawable().apply {
            shape = GradientDrawable.OVAL
            setColor(Color.parseColor("#CC222230"))
        }
        alpha = 0f
        animate().alpha(1f).setDuration(150).start()
    }
    val icon = TextView(this).apply {
        text = "✕"
        setTextColor(Color.WHITE)
        setTextSize(TypedValue.COMPLEX_UNIT_SP, 24f)
        typeface = android.graphics.Typeface.DEFAULT_BOLD
        gravity = Gravity.CENTER
        layoutParams = FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.MATCH_PARENT,
            FrameLayout.LayoutParams.MATCH_PARENT,
        )
    }
    container.addView(icon)
    closeZoneIcon = icon
    closeZoneView = container

    val params = WindowManager.LayoutParams(
        size, size,
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        else @Suppress("DEPRECATION") WindowManager.LayoutParams.TYPE_PHONE,
        WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
            WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE,
        PixelFormat.TRANSLUCENT,
    ).apply {
        gravity = Gravity.BOTTOM or Gravity.CENTER_HORIZONTAL
        y = (CLOSE_ZONE_BOTTOM_MARGIN_DP * dp).toInt()
    }
    try { windowManager?.addView(container, params) } catch (_: Exception) {}
}

internal fun BubbleService.hideCloseZone() {
    closeZoneView?.let { v ->
        try { windowManager?.removeView(v) } catch (_: Exception) {}
    }
    closeZoneView = null
    closeZoneIcon = null
}

internal fun BubbleService.updateCloseZoneVisual(over: Boolean) {
    val container = closeZoneView ?: return
    val scale = if (over) 1.25f else 1.0f
    container.animate().scaleX(scale).scaleY(scale).setDuration(120).start()
    (container.background as? GradientDrawable)?.setColor(
        Color.parseColor(if (over) "#E63946" else "#CC222230"),
    )
}

internal fun BubbleService.isBubbleOverCloseZone(bubbleCenterX: Int, bubbleCenterY: Int, dp: Float): Boolean {
    val sw = resources.displayMetrics.widthPixels
    val sh = resources.displayMetrics.heightPixels
    val zoneSize = (CLOSE_ZONE_SIZE_DP * dp).toInt()
    val zoneCenterX = sw / 2
    val zoneCenterY = sh - (CLOSE_ZONE_BOTTOM_MARGIN_DP * dp).toInt() - zoneSize / 2
    val radius = (CLOSE_ZONE_HIT_RADIUS_DP * dp).toInt()
    val dx = bubbleCenterX - zoneCenterX
    val dy = bubbleCenterY - zoneCenterY
    return dx * dx + dy * dy <= radius * radius
}
