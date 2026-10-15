package com.example.epub_reader

import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : AudioServiceActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        QuickListen.attach(this, flutterEngine)
        // Swiped away, or the phone restarted before the receiver ran.
        QuickListen.restore(this)
    }
}
