package com.mconnect.mconnect

import android.content.Context
import android.database.ContentObserver
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore

/**
 * Watches the Android media store and reports "something changed" **once** per
 * burst.
 *
 * Why the de-bounce: copying a folder of music in, or a gallery scan, makes
 * MediaStore fire `onChange` hundreds of times — once per row. Forwarding each
 * one would make the Dart side rescan continuously while the user is still
 * copying, and a scan walks the whole tree even when the stamps make it cheap.
 * One event per idle gap is what "the library changed" actually means.
 *
 * Why this class does not scan anything: it deliberately carries no scanning
 * logic. It only says "the media store changed"; the Dart side reacts by calling
 * exactly the same rescan path as the manual refresh button, which reuses the
 * persisted `(mtime, size)` stamps and therefore opens no audio file at all when
 * nothing has changed. A second scanner here would be a second truth about what
 * is in the library.
 */
class LocalMusicMediaObserver(
    context: Context,
    private val onChanged: () -> Unit,
    private val debounceMillis: Long = DEFAULT_DEBOUNCE_MS,
) {
    private val appContext = context.applicationContext
    private val handler = Handler(Looper.getMainLooper())

    /** True while an event is already waiting out the de-bounce window. */
    private var pending = false
    private var registered = false

    private val flush = Runnable {
        pending = false
        onChanged()
    }

    private val observer = object : ContentObserver(handler) {
        override fun onChange(selfChange: Boolean) {
            schedule()
        }

        override fun onChange(selfChange: Boolean, uri: Uri?) {
            schedule()
        }
    }

    private fun schedule() {
        // Already waiting: this is the same burst, so it must not extend the
        // window (otherwise a long copy would starve the notification entirely)
        // and must not add a second event.
        if (pending) return
        pending = true
        handler.postDelayed(flush, debounceMillis)
    }

    /** Registers the observer. Idempotent, so a re-attach cannot double-register. */
    fun start() {
        if (registered) return
        appContext.contentResolver.registerContentObserver(
            MediaStore.Audio.Media.EXTERNAL_CONTENT_URI,
            /* notifyForDescendants = */ true,
            observer,
        )
        registered = true
    }

    /** Unregisters and drops a pending event; the Activity is going away. */
    fun stop() {
        if (!registered) return
        appContext.contentResolver.unregisterContentObserver(observer)
        handler.removeCallbacks(flush)
        pending = false
        registered = false
    }

    companion object {
        /**
         * Comfortably longer than the inter-row gap inside one MediaStore update,
         * and short enough that the user sees the library refresh right after they
         * finish copying files in.
         */
        const val DEFAULT_DEBOUNCE_MS = 1_500L
    }
}
