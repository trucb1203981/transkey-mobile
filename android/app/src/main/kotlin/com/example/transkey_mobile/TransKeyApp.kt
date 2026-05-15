package com.example.transkey_mobile

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

                    val intent = Intent(this, BubbleService::class.java).apply {
                        action = BubbleService.ACTION_SHOW_RESULT
                        putExtra(BubbleService.EXTRA_TRANSLATION, translation)
                        putExtra(BubbleService.EXTRA_ROMANIZATION, romanization)
                        putExtra(BubbleService.EXTRA_DETECTED_LANG, detectedLang)
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
