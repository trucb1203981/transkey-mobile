package app.transkey.mobile

import android.content.Intent
import android.os.Build
import android.provider.Settings
import io.flutter.app.FlutterApplication
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel

/**
 * Fraud warning delivered alongside a translation. Absent (null) when the
 * message is safe — the server drops level "none". [reason] is a
 * target-language explanation, only on paid plans.
 */
data class ScamInfo(val level: String, val type: String?, val reason: String?) {
    val isHigh: Boolean get() = level == "high"

    companion object {
        /** Build from the flattened channel/intent fields; null unless level is low/high. */
        fun of(level: String?, type: String?, reason: String?): ScamInfo? {
            if (level != "low" && level != "high") return null
            return ScamInfo(
                level = level,
                type = type?.takeIf { it.isNotBlank() },
                reason = reason?.takeIf { it.isNotBlank() },
            )
        }
    }
}

class TransKeyApp : FlutterApplication() {

    companion object {
        const val ENGINE_ID = "transkey_engine"
        var engine: FlutterEngine? = null
            private set

        // translateText resolves asynchronously via `deliverResult` keyed by
        // requestId. The bubble path forwards results to BubbleService; the
        // keyboard (TransKeyIME) instead registers a one-shot listener here so
        // a result for its requestId lands back on the strip rather than the
        // overlay. Lookups are by registry membership, so the two surfaces
        // never cross even if their requestId numbers were to overlap.
        private val imeResultListeners =
            java.util.concurrent.ConcurrentHashMap<Long, (translation: String?, error: String?, errorCode: String?, scam: ScamInfo?) -> Unit>()

        fun registerImeResult(
            reqId: Long,
            cb: (translation: String?, error: String?, errorCode: String?, scam: ScamInfo?) -> Unit,
        ) {
            imeResultListeners[reqId] = cb
        }

        fun cancelImeResult(reqId: Long) {
            imeResultListeners.remove(reqId)
        }

        /**
         * Notify the keyboard listener for [reqId] and return true if this was
         * an IME-originated request; return false if it belongs to the bubble.
         * Called from BOTH deliverResult handlers (TransKeyApp's and the one
         * MainActivity installs over it on the shared engine), so the result
         * lands on the keyboard whichever handler currently owns the channel.
         * [errorCode] is the machine-readable code (e.g. "quota_exceeded") the
         * IME branches on; null for success/generic failures. [scam] carries a
         * fraud warning for a received message (null = safe).
         */
        fun dispatchImeResult(
            reqId: Long,
            translation: String?,
            error: String?,
            errorCode: String?,
            scam: ScamInfo?,
        ): Boolean {
            val cb = imeResultListeners.remove(reqId) ?: return false
            cb(translation, error, errorCode, scam)
            return true
        }
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
                    val errorCode = args?.get("errorCode") as? String
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
                    val scam = ScamInfo.of(
                        args?.get("scamLevel") as? String,
                        args?.get("scamType") as? String,
                        args?.get("scamReason") as? String,
                    )

                    // Keyboard-originated request? Hand the result to its
                    // listener instead of waking BubbleService/the overlay.
                    if (!dispatchImeResult(reqId, translation, error, errorCode, scam)) {
                        val intent = Intent(this, BubbleService::class.java).apply {
                            action = BubbleService.ACTION_SHOW_RESULT
                            putExtra(BubbleService.EXTRA_TRANSLATION, translation)
                            putExtra(BubbleService.EXTRA_ROMANIZATION, romanization)
                            putExtra(BubbleService.EXTRA_DETECTED_LANG, detectedLang)
                            putExtra(BubbleService.EXTRA_SUGGESTION_SOURCES, sources)
                            putExtra(BubbleService.EXTRA_SUGGESTION_TARGETS, targets)
                            putExtra(BubbleService.EXTRA_SCAM_LEVEL, scam?.level)
                            putExtra(BubbleService.EXTRA_SCAM_TYPE, scam?.type)
                            putExtra(BubbleService.EXTRA_SCAM_REASON, scam?.reason)
                            putExtra(BubbleService.EXTRA_ERROR, error)
                            putExtra(BubbleService.EXTRA_REQUEST_ID, reqId)
                        }
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            startForegroundService(intent)
                        } else {
                            startService(intent)
                        }
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
