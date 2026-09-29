package com.example.sme_mobile

import android.media.AudioAttributes
import android.media.Ringtone
import android.media.RingtoneManager
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {
    private var activeNotificationRingtone: Ringtone? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.example.sme_mobile/notification_sound",
        ).setMethodCallHandler { call, result ->
            if (call.method != "play") {
                result.notImplemented()
                return@setMethodCallHandler
            }

            try {
                val notificationUri =
                    RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)
                        ?: throw IllegalStateException("No default notification sound is set")
                val ringtone = RingtoneManager.getRingtone(applicationContext, notificationUri)
                    ?: throw IllegalStateException("The default notification sound is unavailable")
                ringtone.audioAttributes = AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_NOTIFICATION)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                    .build()
                activeNotificationRingtone?.stop()
                activeNotificationRingtone = ringtone
                ringtone.play()
                result.success(null)
            } catch (error: RuntimeException) {
                result.error("NOTIFICATION_SOUND_FAILED", error.message, null)
            }
        }
    }

    override fun onDestroy() {
        activeNotificationRingtone?.stop()
        activeNotificationRingtone = null
        super.onDestroy()
    }
}
