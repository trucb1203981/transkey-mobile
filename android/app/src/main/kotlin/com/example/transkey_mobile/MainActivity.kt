package com.example.transkey_mobile

import android.content.ComponentName
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import android.text.TextUtils
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
                    "isRunning" -> {
                        val prefs = getSharedPreferences("FlutterSharedPreferences", MODE_PRIVATE)
                        result.success(prefs.getBoolean("flutter.tk_bubble_active", false))
                    }
                    "checkAccessibility" -> {
                        result.success(isAccessibilityEnabled())
                    }
                    "requestAccessibility" -> {
                        startActivity(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS).apply {
                            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        })
                        result.success(null)
                    }
                    "androidSdkInt" -> {
                        // Used by the Flutter AccessibilitySetupScreen to
                        // decide whether to show the Android 13+ restricted-
                        // settings step. Returning Build.VERSION.SDK_INT
                        // avoids the screen having to pull device_info_plus
                        // just for one integer.
                        result.success(android.os.Build.VERSION.SDK_INT)
                    }
                    "openAppDetails" -> {
                        // Android 13+ "restricted settings" gate lives on
                        // the per-app details page. Onboarding routes here
                        // first so the user can unlock the Accessibility
                        // toggle before navigating to the Accessibility
                        // list. Bare Intent + package URI works on every
                        // OEM skin we've tested.
                        startActivity(
                            Intent(
                                Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                                android.net.Uri.parse("package:$packageName"),
                            ).apply { addFlags(Intent.FLAG_ACTIVITY_NEW_TASK) },
                        )
                        result.success(null)
                    }
                    "replaceFocusedText" -> {
                        val text = call.argument<String>("text") ?: ""
                        val svc = TransKeyAccessibilityService.instance
                        result.success(svc?.replaceFocusedText(text) ?: false)
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

    private var pendingSharedText: String? = null

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
            // Try sending via current activity's engine first
            val messenger = flutterEngine?.dartExecutor?.binaryMessenger
            if (messenger != null) {
                MethodChannel(messenger, shareChannel)
                    .invokeMethod("onSharedText", sharedText)
            } else {
                pendingSharedText = sharedText
            }
        }
    }

    // Flush any pending text once the engine is ready
    fun flushPendingText() {
        val text = pendingSharedText ?: return
        val messenger = flutterEngine?.dartExecutor?.binaryMessenger ?: return
        MethodChannel(messenger, shareChannel).invokeMethod("onSharedText", text)
        pendingSharedText = null
    }

    /**
     * True when our AccessibilityService is enabled in system settings AND
     * the service instance is connected. Both checks are needed: the system
     * setting can lag the actual binding state on cold start.
     */
    private fun isAccessibilityEnabled(): Boolean {
        val expected = ComponentName(this, TransKeyAccessibilityService::class.java)
            .flattenToString()
        val enabledServices = Settings.Secure.getString(
            contentResolver,
            Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES,
        ) ?: return false
        val splitter = TextUtils.SimpleStringSplitter(':')
        splitter.setString(enabledServices)
        while (splitter.hasNext()) {
            val component = ComponentName.unflattenFromString(splitter.next())
            if (component == ComponentName.unflattenFromString(expected)) return true
        }
        return false
    }
}
