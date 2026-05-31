package com.mconnect.mconnect

import android.content.Context
import android.os.PowerManager
import io.flutter.plugin.common.MethodChannel

class PlaybackKeepAliveController(context: Context) {
    private val powerManager =
        context.applicationContext.getSystemService(Context.POWER_SERVICE) as PowerManager
    private val wakeLock = powerManager
        .newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "Mconnect:PlaybackKeepAlive")
        .apply { setReferenceCounted(false) }

    fun setPlaying(arguments: Any?, result: MethodChannel.Result) {
        val playing = arguments as? Boolean
        if (playing == null) {
            result.error("INVALID_ARGUMENT", "Expected a boolean playing state", null)
            return
        }

        try {
            if (playing) {
                if (!wakeLock.isHeld) {
                    wakeLock.acquire()
                }
            } else {
                release()
            }
            result.success(null)
        } catch (error: Exception) {
            result.error("WAKE_LOCK_FAILED", error.message, null)
        }
    }

    fun release() {
        if (wakeLock.isHeld) {
            wakeLock.release()
        }
    }
}
