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
                // Web links only: the address comes from the book.
                val uri = call.argument<String>("url")?.let(Uri::parse)
                if (uri?.scheme?.lowercase() !in setOf("http", "https") ||
                    uri?.host.isNullOrEmpty()
                ) {
                    return@setMethodCallHandler result.success(false)
                }
                try {
                    startActivity(Intent(Intent.ACTION_VIEW, uri))
                    result.success(true)
                } catch (e: ActivityNotFoundException) {
                    result.success(false)
                }
            }
    }

    override fun onResume() {
        super.onResume()
        // Android 14+ lets the shortcut be swiped away while Velum is open.
        QuickListen.restore(this)
    }
}
