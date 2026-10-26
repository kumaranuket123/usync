package com.crn.usync

import android.app.NotificationChannel
import android.app.NotificationManager
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterFragmentActivity

class MainActivity : FlutterFragmentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        createSilentChannel()
    }

    /// Location alerts use this channel: low importance means no sound and no
    /// heads-up popup. The id must match the one in the send-push Edge Function.
    private fun createSilentChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val channel = NotificationChannel(
            "usync_silent",
            "Location alerts",
            NotificationManager.IMPORTANCE_LOW,
        ).apply {
            description = "Quiet alerts when your partner checks your location"
            setSound(null, null)
            enableVibration(false)
        }
        getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
    }
}
