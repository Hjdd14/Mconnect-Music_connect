package com.mconnect.mconnect

import android.content.Context
import android.net.wifi.WifiManager
import android.os.PowerManager
import io.flutter.plugin.common.MethodChannel

class PlaybackKeepAliveController(context: Context) {
    private val appContext = context.applicationContext
    private val powerManager =
        appContext.getSystemService(Context.POWER_SERVICE) as PowerManager
    private val wifiManager =
        appContext.getSystemService(Context.WIFI_SERVICE) as? WifiManager
    private val wakeLock = powerManager
        .newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "Mconnect:PlaybackKeepAlive")
        .apply { setReferenceCounted(false) }
    private val wifiLock = wifiManager
        ?.createWifiLock(WifiManager.WIFI_MODE_FULL_HIGH_PERF, "Mconnect:PlaybackWifiKeepAlive")
        ?.apply { setReferenceCounted(false) }

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
                if (wifiLock != null && !wifiLock.isHeld) {
                    wifiLock.acquire()
                }
            } else {
                release()
            }
            result.success(lockState())
        } catch (error: Exception) {
            result.error("PLAYBACK_KEEP_ALIVE_FAILED", error.message, lockState())
        }
    }

    fun release() {
        if (wakeLock.isHeld) {
            wakeLock.release()
        }
        if (wifiLock?.isHeld == true) {
            wifiLock.release()
        }
    }

    private fun lockState(): Map<String, Boolean> {
        return mapOf(
            "wakeLockHeld" to wakeLock.isHeld,
            "wifiLockHeld" to (wifiLock?.isHeld == true),
        )
    }
}
