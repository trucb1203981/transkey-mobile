package app.transkey.mobile

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private val shareChannel = "transkey/share"
    private val bubbleChannel = "transkey/bubble"
    private val bgSamplerChannel = "transkey/bg_sampler"
    private val imeChannel = "transkey/ime"

    /** Lazy worker for off-main-thread bitmap sampling. One thread is
     *  enough - sampler calls fire one per capture, never concurrently. */
    private val samplerThread by lazy {
        android.os.HandlerThread("bg-sampler").also { it.start() }
    }
    private val samplerHandler by lazy { android.os.Handler(samplerThread.looper) }

    override fun onDestroy() {
        super.onDestroy()
        samplerThread.quitSafely()
    }

    /**
     * Reuse the engine that [TransKeyApp] pre-warms in `onCreate`. Default
     * behaviour creates a SEPARATE engine for the Activity, which means
     * BubbleService (talking to the cached engine) and the UI (talking to
     * the fresh engine) live in two isolates with two Riverpod containers.
     * That breaks cross-process state updates: bubble writes a pref +
     * fires `invokeMethod("langChanged")` → only the cached-engine
     * provider invalidates → UI stays stale until app cold-restart.
     *
     * Sharing the engine collapses everything into one Dart isolate / one
     * provider container, so any push from BubbleService is immediately
     * visible in the UI.
     */
    override fun provideFlutterEngine(context: android.content.Context): FlutterEngine? {
        return FlutterEngineCache.getInstance().get(TransKeyApp.ENGINE_ID)
            ?: super.provideFlutterEngine(context)
    }

    /**
     * Guard against the "Play Store update while running" relaunch bug.
     *
     * When the app is updated in place and the user taps "Open" (or the
     * launcher icon) while the process is still alive, the system can route
     * the MAIN/LAUNCHER intent on top of the live process as a SECOND
     * MainActivity instead of resuming the existing task. Both instances
     * share the single process-global pre-warmed FlutterEngine
     * (TransKeyApp.ENGINE_ID), which can only render to one activity at a
     * time, so the redundant instance hangs forever on the LaunchTheme
     * splash ("treo ở logo") while the old task keeps running. The user only
     * recovers by killing every task to clear the process + engine cache.
     *
     * If this activity is NOT the task root and was started by a plain
     * MAIN/LAUNCHER intent, finish immediately so the existing task is
     * brought forward instead of stacking a dead duplicate. Pairs with
     * dropping taskAffinity="" on this activity in the manifest so the
     * launcher reuses the one true app task in the first place.
     */
    override fun onCreate(savedInstanceState: Bundle?) {
        if (!isTaskRoot &&
            intent.hasCategory(Intent.CATEGORY_LAUNCHER) &&
            Intent.ACTION_MAIN == intent.action
        ) {
            finish()
            return
        }
        super.onCreate(savedInstanceState)
    }

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
                        // The persisted flag is necessary but not sufficient:
                        // the user can revoke SYSTEM_ALERT_WINDOW from the
                        // notification's "App settings" link without ever
                        // going through stopBubble(), leaving the flag stuck
                        // at true while the bubble can no longer draw. Gate
                        // on the live overlay grant so isRunning reflects
                        // reality and the in-app Settings toggle converges.
                        val prefs = getSharedPreferences("FlutterSharedPreferences", MODE_PRIVATE)
                        val flagOn = prefs.getBoolean("flutter.tk_bubble_active", false)
                        val hasOverlay = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                            Settings.canDrawOverlays(this)
                        } else true
                        // Also require a live service: a hard kill (force-stop
                        // / OEM background killer) bypasses START_STICKY, so the
                        // flag can be stuck true while the service is dead.
                        // isAlive resets on process death → tryAutoStart can
                        // recover and the toggle won't lie.
                        result.success(BubbleService.isAlive && flagOn && hasOverlay)
                    }
                    "androidId" -> {
                        // SSAID — stable across app reinstalls (resets only on
                        // factory reset / a different signing key), no permission
                        // needed. Used as the device-id seed so reinstalling does
                        // NOT mint a new "device" and trip the per-account limit.
                        // Can be null / all-zeros on some custom ROMs; Dart side
                        // falls back to the Build.ID fingerprint then.
                        val ssaid = Settings.Secure.getString(
                            contentResolver,
                            Settings.Secure.ANDROID_ID,
                        )
                        result.success(ssaid)
                    }
                    // Forward to BubbleService via Intent — same body as the
                    // handler TransKeyApp.onCreate originally installed. We
                    // need it here too because MainActivity's
                    // setMethodCallHandler REPLACES TransKeyApp's (same
                    // channel, same engine after the engine-share fix), so
                    // without this case `result.notImplemented()` kills the
                    // entire bubble translateBatch / translateText pipeline
                    // whenever the user has the app foregrounded.
                    "deliverResult" -> {
                        val args = call.arguments as? Map<*, *>
                        val translation = args?.get("translation") as? String
                        val romanization = args?.get("romanization") as? String
                        val detectedLang = args?.get("detectedLang") as? String
                        val error = args?.get("error") as? String
                        val errorCode = args?.get("errorCode") as? String
                        val reqId = (args?.get("requestId") as? Number)?.toLong() ?: -1L
                        val sources = (args?.get("suggestionSources") as? List<*>)
                            ?.map { (it as? String).orEmpty() }
                            ?.toTypedArray()
                        val targets = (args?.get("suggestionTargets") as? List<*>)
                            ?.map { (it as? String).orEmpty() }
                            ?.toTypedArray()
                        // Keyboard-originated request routes back to the IME;
                        // otherwise forward to BubbleService/the overlay.
                        if (!TransKeyApp.dispatchImeResult(reqId, translation, error, errorCode)) {
                            val i = Intent(this, BubbleService::class.java).apply {
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
                                startForegroundService(i)
                            } else {
                                startService(i)
                            }
                        }
                        result.success(null)
                    }
                    // Same reason as deliverResult above — MainActivity's
                    // handler replaces TransKeyApp's on the shared engine,
                    // so the progressive-Lens path needs this case here too
                    // or chunks silently fail with MissingPluginException.
                    "deliverLensChunk" -> {
                        val args = call.arguments as? Map<*, *>
                        val startIdx = (args?.get("startIdx") as? Number)?.toInt() ?: -1
                        val translations = (args?.get("translations") as? List<*>)
                            ?.map { (it as? String).orEmpty() }
                            ?.toTypedArray()
                        if (startIdx >= 0 && translations != null) {
                            val i = Intent(this, BubbleService::class.java).apply {
                                action = BubbleService.ACTION_DELIVER_LENS_CHUNK
                                putExtra(BubbleService.EXTRA_LENS_CHUNK_START, startIdx)
                                putExtra(BubbleService.EXTRA_LENS_CHUNK_TRANSLATIONS, translations)
                            }
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                                startForegroundService(i)
                            } else {
                                startService(i)
                            }
                        }
                        result.success(null)
                    }
                    "deliverLensMismatch" -> {
                        val args = call.arguments as? Map<*, *>
                        val detected = args?.get("detected") as? String
                        if (!detected.isNullOrBlank()) {
                            val i = Intent(this, BubbleService::class.java).apply {
                                action = BubbleService.ACTION_DELIVER_LENS_MISMATCH
                                putExtra(BubbleService.EXTRA_LENS_MISMATCH_DETECTED, detected)
                            }
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                                startForegroundService(i)
                            } else {
                                startService(i)
                            }
                        }
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }

        // Background colour sampler — called by the camera overlay after
        // OCR returns block bounding boxes. Reads pixels from the capture
        // file on a worker thread so the UI thread isn't blocked while a
        // 12 MP JPG is decoded + scanned.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, bgSamplerChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "sample" -> {
                        val path = call.argument<String>("imagePath")
                        val rectsArg = call.argument<List<Map<String, Number>>>("rects")
                        if (path == null || rectsArg == null) {
                            result.error("ARG", "missing imagePath or rects", null)
                            return@setMethodCallHandler
                        }
                        val rects = rectsArg.map {
                            android.graphics.Rect(
                                (it["left"]?.toInt()) ?: 0,
                                (it["top"]?.toInt()) ?: 0,
                                (it["right"]?.toInt()) ?: 0,
                                (it["bottom"]?.toInt()) ?: 0,
                            )
                        }
                        samplerHandler.post {
                            val colors = BgColorSampler.sample(path, rects)
                            runOnUiThread { result.success(colors) }
                        }
                    }
                    else -> result.notImplemented()
                }
            }

        // TransKey IME channel - check enabled / selected state, open
        // system Settings to install the keyboard, and show the IME
        // picker so the user can switch the active keyboard mid-session.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, imeChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isEnabled" -> result.success(isImeEnabled())
                    "isSelected" -> result.success(isImeSelected())
                    "openImeSettings" -> {
                        startActivity(
                            Intent(Settings.ACTION_INPUT_METHOD_SETTINGS)
                                .apply { addFlags(Intent.FLAG_ACTIVITY_NEW_TASK) },
                        )
                        result.success(null)
                    }
                    "showImePicker" -> {
                        val imm = getSystemService(android.view.inputmethod.InputMethodManager::class.java)
                        imm?.showInputMethodPicker()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }

        // Check if launched from share intent
        handleIncomingIntent(intent)
    }

    private fun isImeEnabled(): Boolean {
        // MUST use InputMethodManager, NOT Settings.Secure
        // .ENABLED_INPUT_METHODS — that key throws SecurityException for
        // apps targeting SDK > 33 ("only readable to apps with
        // targetSdkVersion <= 33"). enabledInputMethodList is the public
        // API equivalent and needs no permission. InputMethodInfo.id is
        // the flattened ComponentName, so unflatten + compare normalises
        // the `pkg/.Class` shorthand vs `pkg/full.Class` forms.
        return try {
            val imm = getSystemService(
                android.view.inputmethod.InputMethodManager::class.java,
            ) ?: return false
            val target = android.content.ComponentName(this, TransKeyIME::class.java)
            imm.enabledInputMethodList.any {
                android.content.ComponentName.unflattenFromString(it.id) == target
            }
        } catch (e: Exception) {
            false
        }
    }

    private fun isImeSelected(): Boolean {
        // DEFAULT_INPUT_METHOD is still readable on current SDKs, but
        // wrap defensively in case a future restriction lands — falling
        // back to "not selected" just means the tile invites the user to
        // pick TransKey, which is harmless.
        return try {
            val selected = Settings.Secure.getString(
                contentResolver,
                Settings.Secure.DEFAULT_INPUT_METHOD,
            ) ?: return false
            val target = android.content.ComponentName(this, TransKeyIME::class.java)
            android.content.ComponentName.unflattenFromString(selected) == target
        } catch (e: Exception) {
            false
        }
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
}
