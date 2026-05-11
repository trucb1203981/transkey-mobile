package com.example.transkey_mobile

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private val shareChannel = "transkey/share"
    private val bubbleChannel = "transkey/bubble"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Share intent channel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, shareChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getSharedText" -> {
                        val text = intent?.getStringExtra(Intent.EXTRA_TEXT)
                            ?: intent?.getCharSequenceExtra(Intent.EXTRA_PROCESS_TEXT)?.toString()
                        result.success(text)
                    }
                    else -> result.notImplemented()
                }
            }

        // Bubble control channel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, bubbleChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "checkPermission" -> {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                            result.success(Settings.canDrawOverlays(this))
                        } else {
                            result.success(true)
                        }
                    }
                    "requestPermission" -> {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                            if (!Settings.canDrawOverlays(this)) {
                                val i = Intent(
                                    Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                                    Uri.parse("package:$packageName"),
                                )
                                startActivity(i)
                            }
                            result.success(Settings.canDrawOverlays(this))
                        } else {
                            result.success(true)
                        }
                    }
                    "startBubble" -> {
                        val i = Intent(this, BubbleService::class.java).apply {
                            action = BubbleService.ACTION_START
                        }
                        startService(i)
                        result.success(null)
                    }
                    "stopBubble" -> {
                        val i = Intent(this, BubbleService::class.java).apply {
                            action = BubbleService.ACTION_STOP
                        }
                        startService(i)
                        result.success(null)
                    }
                    "setBubbleState" -> {
                        val state = call.arguments as? String ?: BubbleService.STATE_IDLE
                        val i = Intent(this, BubbleService::class.java).apply {
                            action = BubbleService.ACTION_SET_STATE
                            putExtra(BubbleService.EXTRA_STATE, state)
                        }
                        startService(i)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }

        // Check if launched from share intent
        handleIncomingIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleIncomingIntent(intent)
    }

    private fun handleIncomingIntent(intent: Intent?) {
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
            TransKeyApp.engine?.let { engine ->
                MethodChannel(engine.dartExecutor.binaryMessenger, shareChannel)
                    .invokeMethod("onSharedText", sharedText)
            }
        }
    }
}
