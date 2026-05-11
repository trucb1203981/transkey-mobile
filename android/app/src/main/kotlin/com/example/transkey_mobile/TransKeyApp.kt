package com.example.transkey_mobile

import io.flutter.app.FlutterApplication
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.embedding.engine.dart.DartExecutor

class TransKeyApp : FlutterApplication() {

    companion object {
        const val ENGINE_ID = "transkey_engine"
        var engine: FlutterEngine? = null
            private set
    }

    override fun onCreate() {
        super.onCreate()

        // Pre-warm a FlutterEngine so BubbleService can communicate with it
        val flutterEngine = FlutterEngine(this)
        flutterEngine.dartExecutor.executeDartEntrypoint(
            DartExecutor.DartEntrypoint.createDefault(),
        )
        FlutterEngineCache.getInstance().put(ENGINE_ID, flutterEngine)
        engine = flutterEngine
    }
}
