package app.transkey.mobile

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
import android.os.Build

/**
 * Foreground-service notification for [BubbleService]. Carried by every
 * bubble session — Android requires services that run with overlay
 * permission to be foreground services, and foreground services need an
 * ongoing notification. We also expose a "Turn off" action that posts
 * [BubbleService.ACTION_STOP] back to the service so the user can kill
 * the bubble from the shade without going through the app.
 *
 * Channel importance is LOW (no sound / no peek) — the notification is
 * mandatory infrastructure, not user-facing alerting.
 */
internal fun BubbleService.createBubbleNotificationChannel() {
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
        val channel = NotificationChannel(
            BubbleService.CHANNEL_ID, getString(R.string.bubble_notification_channel),
            NotificationManager.IMPORTANCE_LOW,
        ).apply {
            description = getString(R.string.bubble_notification_active)
            setShowBadge(false)
        }
        getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
    }
}

internal fun BubbleService.buildBubbleNotification(): Notification {
    val intent = Intent(this, MainActivity::class.java).apply {
        flags = Intent.FLAG_ACTIVITY_SINGLE_TOP
    }
    val pending = PendingIntent.getActivity(
        this, 0, intent,
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
    )

    // "Turn off" action — posts ACTION_STOP to the service itself.
    val stopIntent = Intent(this, BubbleService::class.java).apply {
        action = BubbleService.ACTION_STOP
    }
    val stopPending = PendingIntent.getService(
        this, 1, stopIntent,
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
    )

    val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
        Notification.Builder(this, BubbleService.CHANNEL_ID)
    else @Suppress("DEPRECATION") Notification.Builder(this)
    return builder
        .setContentTitle("TransKey")
        .setContentText(getString(R.string.bubble_notification_active))
        .setSmallIcon(android.R.drawable.ic_dialog_info)
        .setContentIntent(pending)
        .setOngoing(true)
        .addAction(
            android.R.drawable.ic_menu_close_clear_cancel,
            getString(R.string.bubble_notification_turn_off),
            stopPending,
        )
        .build()
}
