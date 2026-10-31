package com.teamagent5.marieum

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var liveTranscriber: LiveTranscriber? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        liveTranscriber = LiveTranscriber(
            this,
            MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "marieum/live_transcriber"),
        )
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        liveTranscriber?.dispose()
        liveTranscriber = null
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
