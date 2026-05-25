package app.transkey.mobile

import android.content.Intent
import android.os.Build
import android.provider.Settings
import io.flutter.app.FlutterApplication
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel

class TransKeyApp : FlutterApplication() {

    companion object {
        const val ENGINE_ID = "transkey_engine"
        var engine: FlutterEngine? = null
            private set
    }

    override fun onCreate() {
        super.onCreate()

        // Pre-warm a FlutterEngine so BubbleService/ShareActivity can talk to it
        val flutterEngine = FlutterEngine(this)
        flutterEngine.dartExecutor.executeDartEntrypoint(
            DartExecutor.DartEntrypoint.createDefault(),
        )
        FlutterEngineCache.getInstance().put(ENGINE_ID, flutterEngine)
        engine = flutterEngine

        // Listen for translation results coming back from Flutter and
        // forward them to BubbleService via Intent so the overlay updates.
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            BubbleService.METHOD_CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "deliverResult" -> {
                    val args = call.arguments as? Map<*, *>
                    val translation = args?.get("translation") as? String
                    val romanization = args?.get("romanization") as? String
                    val detectedLang = args?.get("detectedLang") as? String
                    val error = args?.get("error") as? String
                    val reqId = (args?.get("requestId") as? Number)?.toLong() ?: -1L
                    // Bilingual suggestions arrive as two parallel arrays —
                    // sources are the reply text to send back to the
                    // conversation partner (their language), targets are the
                    // same idea in the user's language so they understand
                    // what they'd be sending. Preserve indexing including
                    // empty strings — BubbleService pairs them by position.
                    val sources = (args?.get("suggestionSources") as? List<*>)
                        ?.map { (it as? String).orEmpty() }
                        ?.toTypedArray()
                    val targets = (args?.get("suggestionTargets") as? List<*>)
                        ?.map { (it as? String).orEmpty() }
                        ?.toTypedArray()

                    val intent = Intent(this, BubbleService::class.java).apply {
                        action = BubbleService.ACTION_SHOW_RESULT
                        putExtra(BubbleService.EXTRA_TRANSLATION, translation)
                        putExtra(BubbleService.EXTRA_ROMANIZATION, romanization)
                        putExtra(BubbleService.EXTRA_DETECTED_LANG, detectedLang)
                        putExtra(BubbleService.EXTRA_SUGGESTION_SOURCES, sources)
                        putExtra(BubbleService.EXTRA_SUGGESTION_TARGETS, targets)
                        putExtra(BubbleService.EXTRA_ERROR, error)
                        putExtra(BubbleService.EXTRA_REQUEST_ID, reqId)
                    }
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        startForegroundService(intent)
                    } else {
                        startService(intent)
                    }
                    result.success(null)
                }
                "deliverLensChunk" -> {
                    // Progressive Lens translate: Flutter pushes one chunk
                    // of translations at a time as each /translate-batch
                    // call completes. We forward to BubbleService via
                    // Intent so the LensOverlayView patches chips in place.
                    val args = call.arguments as? Map<*, *>
                    val startIdx = (args?.get("startIdx") as? Number)?.toInt() ?: -1
                    val translations = (args?.get("translations") as? List<*>)
                        ?.map { (it as? String).orEmpty() }
                        ?.toTypedArray()
                    if (startIdx >= 0 && translations != null) {
                        val intent = Intent(this, BubbleService::class.java).apply {
                            action = BubbleService.ACTION_DELIVER_LENS_CHUNK
                            putExtra(BubbleService.EXTRA_LENS_CHUNK_START, startIdx)
                            putExtra(BubbleService.EXTRA_LENS_CHUNK_TRANSLATIONS, translations)
                        }
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            startForegroundService(intent)
                        } else {
                            startService(intent)
                        }
                    }
                    result.success(null)
                }
                "deliverLensMismatch" -> {
                    val args = call.arguments as? Map<*, *>
                    val detected = args?.get("detected") as? String
                    if (!detected.isNullOrBlank()) {
                        val intent = Intent(this, BubbleService::class.java).apply {
                            action = BubbleService.ACTION_DELIVER_LENS_MISMATCH
                            putExtra(BubbleService.EXTRA_LENS_MISMATCH_DETECTED, detected)
                        }
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            startForegroundService(intent)
                        } else {
                            startService(intent)
                        }
                    }
                    result.success(null)
                }
                // Query/control methods the Dart side hits during the pre-warm
                // window: this engine runs main() at Application.onCreate, so
                // BubbleManager._seedInitialState + tryAutoStart call these
                // BEFORE MainActivity.configureFlutterEngine swaps in the full
                // handler. Without these branches they'd return notImplemented
                // -> MissingPluginException on the Dart side (and auto-resume
                // would silently break). Bodies mirror MainActivity's and only
                // use the Application context (pref read / overlay grant /
                // startService), so no Activity is required.
                "isRunning" -> {
                    val prefs = getSharedPreferences("FlutterSharedPreferences", MODE_PRIVATE)
                    val flagOn = prefs.getBoolean("flutter.tk_bubble_active", false)
                    val hasOverlay = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                        Settings.canDrawOverlays(this)
                    } else true
                    // Liveness-gated — see MainActivity.isRunning.
                    result.success(BubbleService.isAlive && flagOn && hasOverlay)
                }
                "checkPermission" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                        result.success(Settings.canDrawOverlays(this))
                    } else {
                        result.success(true)
                    }
                }
                "startBubble" -> {
                    startService(
                        Intent(this, BubbleService::class.java).apply {
                            action = BubbleService.ACTION_START
                        },
                    )
                    result.success(null)
                }
                "stopBubble" -> {
                    startService(
                        Intent(this, BubbleService::class.java).apply {
                            action = BubbleService.ACTION_STOP
                        },
                    )
                    result.success(null)
                }
                "setBubbleState" -> {
                    val state = call.arguments as? String ?: BubbleService.STATE_IDLE
                    startService(
                        Intent(this, BubbleService::class.java).apply {
                            action = BubbleService.ACTION_SET_STATE
                            putExtra(BubbleService.EXTRA_STATE, state)
                        },
                    )
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }
}
