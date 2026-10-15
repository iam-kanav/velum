package com.example.epub_reader

import android.app.Activity
import android.content.ClipboardManager
import android.graphics.Color
import android.graphics.drawable.GradientDrawable
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.util.TypedValue
import android.view.Gravity
import android.view.ViewGroup
import android.view.WindowManager
import android.widget.LinearLayout
import android.widget.ProgressBar
import android.widget.TextView
import android.widget.Toast

/**
 * A small pill at the bottom of the screen, shown while a tap on the
 * "Listen to clipboard" notification is handled. Android only lets the app
 * in front read the clipboard, so this window takes focus, reads it, and
 * closes once reading aloud has started. Touches elsewhere go to the app
 * behind it.
 */
class QuickListenActivity : Activity() {
    private val handler = Handler(Looper.getMainLooper())
    private var handled = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(pill())
        window.setLayout(ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT)
        window.setGravity(Gravity.BOTTOM or Gravity.CENTER_HORIZONTAL)
        window.attributes = window.attributes.apply { y = dp(96) }
        window.addFlags(WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL)
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (!hasFocus || handled) return
        handled = true

        val text = readClipboard()
        if (text.isNullOrBlank()) {
            Toast.makeText(this, "Nothing copied to read aloud", Toast.LENGTH_SHORT).show()
            finish()
            return
        }
        // Stay until reading has started: the app counts as in front while
        // this is up, which Android needs to let playback start.
        QuickListen.listen(this, text) { finish() }
        handler.postDelayed({ finish() }, 10_000)
    }

    private fun readClipboard(): String? {
        val clip = getSystemService(ClipboardManager::class.java).primaryClip ?: return null
        if (clip.itemCount == 0) return null
        return clip.getItemAt(0).coerceToText(this)?.toString()
    }

    override fun finish() {
        super.finish()
        @Suppress("DEPRECATION")
        overridePendingTransition(0, 0)
    }

    override fun onDestroy() {
        handler.removeCallbacksAndMessages(null)
        super.onDestroy()
    }

    private fun dp(value: Int) = TypedValue.applyDimension(
        TypedValue.COMPLEX_UNIT_DIP, value.toFloat(), resources.displayMetrics,
    ).toInt()

    private fun pill() = LinearLayout(this).apply {
        orientation = LinearLayout.HORIZONTAL
        gravity = Gravity.CENTER_VERTICAL
        setPadding(dp(18), dp(12), dp(20), dp(12))
        background = GradientDrawable().apply {
            cornerRadius = dp(24).toFloat()
            setColor(0xF0222222.toInt())
        }
        addView(ProgressBar(context).apply {
            isIndeterminate = true
            indeterminateTintList = android.content.res.ColorStateList.valueOf(Color.WHITE)
        }, LinearLayout.LayoutParams(dp(18), dp(18)))
        addView(TextView(context).apply {
            text = "Reading clipboard aloud…"
            setTextColor(Color.WHITE)
            textSize = 14f
            setPadding(dp(12), 0, 0, 0)
        })
    }
}
