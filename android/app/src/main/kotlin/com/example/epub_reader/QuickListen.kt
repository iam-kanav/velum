package com.example.epub_reader

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import com.ryanheise.audioservice.AudioServicePlugin
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * "Listen to clipboard": a notification that stays in the shade. Tapping it
 * opens [QuickListenActivity], which reads the clipboard and hands the text
 * to the app (lib/features/notes/data/clipboard_listen.dart) to save as a
 * note and read aloud.
 */
object QuickListen {
    private const val CHANNEL = "velum/quick_listen"
    private const val NOTIFICATION_CHANNEL_ID = "com.velum.reader.quick_listen"
    private const val NOTIFICATION_ID = 7301
    private const val PREFS = "velum_quick_listen"
    private const val KEY_ENABLED = "enabled"

    private var engine: FlutterEngine? = null
    private var channel: MethodChannel? = null

    /** Copied text waiting for the app to pick it up. */
    private var pendingText: String? = null

    /** Runs once the app has started reading [pendingText] (or gave up). */
    private var onDone: (() -> Unit)? = null

    fun attach(context: Context, flutterEngine: FlutterEngine) {
        if (engine === flutterEngine) return
        val app = context.applicationContext
        engine = flutterEngine
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "takePending" -> {
                        result.success(pendingText)
                        pendingText = null
                    }
                    "done" -> {
                        onDone?.invoke()
                        onDone = null
                        result.success(null)
                    }
                    "isEnabled" -> result.success(isEnabled(app))
                    "setEnabled" -> {
                        setEnabled(app, call.arguments as Boolean)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }

    /**
     * Read [text] aloud. Starts the app in the background if it isn't
     * running: it shares the engine audio_service keeps for the activity.
     */
    fun listen(context: Context, text: String, done: () -> Unit) {
        attach(context, AudioServicePlugin.getFlutterEngine(context.applicationContext))
        pendingText = text
        onDone = done
        // A running app picks it up now; a starting one asks once it's ready.
        channel?.invokeMethod("pending", null)
    }

    private fun prefs(context: Context) =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    fun isEnabled(context: Context) = prefs(context).getBoolean(KEY_ENABLED, false)

    fun setEnabled(context: Context, enabled: Boolean) {
        prefs(context).edit().putBoolean(KEY_ENABLED, enabled).apply()
        if (enabled) {
            showNotification(context)
        } else {
            context.getSystemService(NotificationManager::class.java).cancel(NOTIFICATION_ID)
        }
    }

    /** Put the notification back if it's turned on. */
    fun restore(context: Context) {
        if (isEnabled(context)) showNotification(context)
    }

    private fun showNotification(context: Context) {
        val manager = context.getSystemService(NotificationManager::class.java)
        val tap = PendingIntent.getActivity(
            context,
            0,
            Intent(context, QuickListenActivity::class.java)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_NO_ANIMATION),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            manager.createNotificationChannel(
                NotificationChannel(
                    NOTIFICATION_CHANNEL_ID,
                    "Listen to clipboard",
                    NotificationManager.IMPORTANCE_LOW,
                ).apply {
                    description = "Tap to read what you last copied aloud"
                    setShowBadge(false)
                },
            )
            Notification.Builder(context, NOTIFICATION_CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(context).setPriority(Notification.PRIORITY_LOW)
        }
        val notification = builder
            .setSmallIcon(R.drawable.ic_quick_listen)
            .setColor(0xFF5B3DE3.toInt())
            .setContentTitle("Listen to clipboard")
            .setContentText("Tap to read what you last copied aloud")
            .setContentIntent(tap)
            .setOngoing(true)
            .setShowWhen(false)
            .build()
        manager.notify(NOTIFICATION_ID, notification)
    }
}
