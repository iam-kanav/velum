package com.example.epub_reader

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/** Brings the "Listen to clipboard" notification back after a restart or update. */
class QuickListenRestoreReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            Intent.ACTION_BOOT_COMPLETED,
            Intent.ACTION_MY_PACKAGE_REPLACED -> QuickListen.restore(context)
        }
    }
}
