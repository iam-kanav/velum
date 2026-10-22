package com.example.epub_reader

import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : AudioServiceActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        QuickListen.attach(this, flutterEngine)
        // Swiped away, or the phone restarted before the receiver ran.
        QuickListen.restore(this)

        // Links in books open in the browser (reader_screen.dart).
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "velum/links")
            .setMethodCallHandler { call, result ->
                if (call.method != "open") return@setMethodCallHandler result.notImplemented()
                val url = call.argument<String>("url")
                try {
                    startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)))
                    result.success(true)
                } catch (e: ActivityNotFoundException) {
                    result.success(false)
                }
            }
    }
}
