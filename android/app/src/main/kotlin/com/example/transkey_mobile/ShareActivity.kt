package com.example.transkey_mobile

import android.content.Intent
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity

class ShareActivity : FlutterActivity() {

    companion object {
        const val CHANNEL = "transkey/share"
        private var pendingShare: String? = null
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        val sharedText = when (intent?.action) {
            Intent.ACTION_SEND -> {
                if (intent.type == "text/plain") {
                    intent.getStringExtra(Intent.EXTRA_TEXT)
                } else null
            }
            Intent.ACTION_PROCESS_TEXT -> {
                intent.getCharSequenceExtra(Intent.EXTRA_PROCESS_TEXT)?.toString()
            }
            else -> null
        }

        if (!sharedText.isNullOrBlank()) {
            pendingShare = sharedText
            trySendSharedText()
        } else {
            finish()
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
    }

    private fun trySendSharedText() {
        val text = pendingShare ?: return
        val eng = flutterEngine ?: return
        val messenger = eng.dartExecutor.binaryMessenger

        io.flutter.plugin.common.MethodChannel(messenger, CHANNEL)
            .invokeMethod("onSharedText", text)

        pendingShare = null

        android.os.Handler(android.os.Looper.getMainLooper()).postDelayed({
            finish()
        }, 500)
    }

    override fun onPause() {
        super.onPause()
        overridePendingTransition(0, 0)
    }
}
