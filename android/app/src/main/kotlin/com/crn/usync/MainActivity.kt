package com.crn.usync

import android.app.NotificationChannel
import android.app.NotificationManager
import android.os.Build
import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {
    /// The private chat is open: screenshots, screen recording and the app-switcher preview
    /// stay blocked for as long as it is, including across pause and resume.
    private var secureScreen = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "usync/secure_screen")
            .setMethodCallHandler { call, result ->
                if (call.method == "set") {
                    secureScreen = call.arguments as? Boolean ?: false
                    if (secureScreen) {
                        window.setFlags(WindowManager.LayoutParams.FLAG_SECURE, WindowManager.LayoutParams.FLAG_SECURE)
                    } else {
                        window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                    }
                    result.success(null)
                } else {
                    result.notImplemented()
                }
            }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        createSilentChannel()
    }

    // With the app lock on, the app-switcher preview is blank. FLAG_SECURE is only set
    // while the activity is paused, so screenshots work normally in the app and the
    // notification shade (which does not pause it) leaves the app untouched.
    override fun onPause() {
        super.onPause()
        // Flutter's SharedPreferences plugin stores values under the "flutter." prefix.
        val prefs = getSharedPreferences("FlutterSharedPreferences", MODE_PRIVATE)
        if (prefs.getBoolean("flutter.app_lock", true)) {
            window.setFlags(WindowManager.LayoutParams.FLAG_SECURE, WindowManager.LayoutParams.FLAG_SECURE)
        }
    }

    override fun onResume() {
        super.onResume()
        if (!secureScreen) window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
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
