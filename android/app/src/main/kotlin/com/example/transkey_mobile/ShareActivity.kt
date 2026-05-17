package com.example.transkey_mobile

import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.util.Log
import android.widget.Toast

/**
 * Transparent activity that receives ACTION_SEND / ACTION_PROCESS_TEXT
 * from other apps. It reads the "transkey.mode" meta-data of the launched
 * alias to determine which action (translate/summarize/explain/refine),
 * then forwards to BubbleService which displays a floating overlay.
 *
 * For ACTION_READ_CLIPBOARD (sent from bubble mode picker), the activity must
 * gain real input focus before reading the clipboard — Android 10+ blocks
 * ClipboardManager.primaryClip for activities that don't have focus. The
 * window is transparent (see ShareActivityTheme) but NOT translucent, so it
 * still becomes a real focusable window.
 */
class ShareActivity : Activity() {

    private var pendingClipboardMode: String? = null
    private var clipboardForwarded = false
    private val handler = Handler(Looper.getMainLooper())
    private val fallbackRunnable = Runnable {
        val mode = pendingClipboardMode ?: return@Runnable
        Log.w(TAG, "Clipboard focus fallback fired after ${FOCUS_FALLBACK_MS}ms")
        forwardClipboardToService(mode)
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        handleIntent(intent)
    }

    override fun onNewIntent(intent: Intent?) {
        super.onNewIntent(intent)
        if (intent != null) {
            setIntent(intent)
            handleIntent(intent)
        }
    }

    override fun onResume() {
        super.onResume()
        // Belt-and-suspenders: onResume is when activity is fully foreground.
        // On some devices onWindowFocusChanged(true) only fires shortly after
        // onResume, but on others clipboard is already accessible here.
        val mode = pendingClipboardMode
        if (mode != null && hasWindowFocus()) {
            forwardClipboardToService(mode)
        }
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        val mode = pendingClipboardMode
        if (hasFocus && mode != null) {
            forwardClipboardToService(mode)
        }
    }

    override fun onDestroy() {
        handler.removeCallbacks(fallbackRunnable)
        super.onDestroy()
    }

    private fun handleIntent(intent: Intent?) {
        if (intent?.action == BubbleService.ACTION_READ_CLIPBOARD) {
            pendingClipboardMode = intent.getStringExtra(BubbleService.EXTRA_MODE)
                ?: BubbleService.MODE_TRANSLATE
            clipboardForwarded = false
            handler.removeCallbacks(fallbackRunnable)
            handler.postDelayed(fallbackRunnable, FOCUS_FALLBACK_MS)
            return
        }

        val text = extractText(intent)
        if (text.isNullOrBlank()) {
            finish()
            overridePendingTransition(0, 0)
            return
        }

        val mode = resolveMode()

        val hasOverlayPermission =
            Build.VERSION.SDK_INT < Build.VERSION_CODES.M || Settings.canDrawOverlays(this)

        if (hasOverlayPermission) {
            val svc = Intent(this, BubbleService::class.java).apply {
                action = BubbleService.ACTION_TRANSLATE
                putExtra(BubbleService.EXTRA_TEXT, text)
                putExtra(BubbleService.EXTRA_MODE, mode)
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                startForegroundService(svc)
            } else {
                startService(svc)
            }
        } else {
            Toast.makeText(
                this,
                "Enable 'Display over other apps' to get floating translations",
                Toast.LENGTH_LONG,
            ).show()
            val mainIntent = Intent(this, MainActivity::class.java).apply {
                action = Intent.ACTION_PROCESS_TEXT
                putExtra(Intent.EXTRA_PROCESS_TEXT, text)
                flags = Intent.FLAG_ACTIVITY_NEW_TASK
            }
            startActivity(mainIntent)
            val permIntent = Intent(
                Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                Uri.parse("package:$packageName"),
            ).apply { flags = Intent.FLAG_ACTIVITY_NEW_TASK }
            try { startActivity(permIntent) } catch (_: Exception) {}
        }

        finish()
        overridePendingTransition(0, 0)
    }

    private fun forwardClipboardToService(mode: String) {
        if (clipboardForwarded) return
        clipboardForwarded = true
        pendingClipboardMode = null
        handler.removeCallbacks(fallbackRunnable)

        val cm = getSystemService(CLIPBOARD_SERVICE) as android.content.ClipboardManager
        val text = cm.primaryClip?.takeIf { it.itemCount > 0 }
            ?.getItemAt(0)?.coerceToText(this)?.toString()?.trim()

        Log.d(TAG, "Clipboard read: focus=${hasWindowFocus()}, hasText=${!text.isNullOrBlank()}, len=${text?.length ?: 0}")

        val svc = Intent(this, BubbleService::class.java).apply {
            action = BubbleService.ACTION_TRANSLATE
            putExtra(BubbleService.EXTRA_MODE, mode)
        }
        if (!text.isNullOrBlank()) {
            svc.putExtra(BubbleService.EXTRA_TEXT, text)
        } else {
            // Differentiate the message based on whether Accessibility is
            // already on. The common confusing case is: user highlights
            // text (no copy), taps bubble, falls through to clipboard
            // (empty), and gets a "copy first" message — but with
            // Accessibility enabled they wouldn't need to copy at all.
            // Spelling that out cuts the support loop where users think
            // "select text → translate" should just work like in
            // Google Translate (which depends on the same permission).
            val errorMsg = if (TransKeyAccessibilityService.isAvailable()) {
                "No text in clipboard.\nCopy the selected text first, then tap the bubble."
            } else {
                "No text in clipboard.\n\nTip: Enable Accessibility for TransKey (Settings → Accessibility → TransKey) to translate highlighted text without copying first."
            }
            svc.putExtra(BubbleService.EXTRA_ERROR, errorMsg)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) startForegroundService(svc)
        else startService(svc)

        finish()
        overridePendingTransition(0, 0)
    }

    private fun extractText(intent: Intent?): String? = when (intent?.action) {
        Intent.ACTION_SEND -> {
            if (intent.type == "text/plain") intent.getStringExtra(Intent.EXTRA_TEXT) else null
        }
        Intent.ACTION_PROCESS_TEXT -> {
            intent.getCharSequenceExtra(Intent.EXTRA_PROCESS_TEXT)?.toString()
        }
        else -> null
    }

    /**
     * Reads the "transkey.mode" meta-data from the launched alias.
     * Each activity-alias in AndroidManifest declares a mode (translate /
     * summarize / explain / refine), so the same ShareActivity can be
     * reused by all four entries in the text selection menu.
     */
    private fun resolveMode(): String {
        val component = intent.component ?: return "translate"
        return try {
            val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                PackageManager.ComponentInfoFlags.of(PackageManager.GET_META_DATA.toLong())
            } else {
                @Suppress("DEPRECATION") null
            }
            val info = if (flags != null) {
                packageManager.getActivityInfo(component, flags)
            } else {
                @Suppress("DEPRECATION")
                packageManager.getActivityInfo(component, PackageManager.GET_META_DATA)
            }
            info.metaData?.getString("transkey.mode") ?: "translate"
        } catch (_: Exception) {
            "translate"
        }
    }

    companion object {
        private const val TAG = "ShareActivity"
        private const val FOCUS_FALLBACK_MS = 600L
    }
}
