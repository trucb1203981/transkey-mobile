package app.transkey.mobile

import android.content.Intent
import android.os.Build
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
                else -> result.notImplemented()
            }
        }
    }
}
