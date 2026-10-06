package com.mconnect.mconnect

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Bundle

/**
 * Turns an inbound "share to Mconnect" into a deep link the Dart side can route.
 *
 * `app_links` only delivers `ACTION_VIEW`, so an `ACTION_SEND`
 * (`Intent.EXTRA_TEXT`, `text/plain`) has to be converted into the app's own
 * `mconnect://share?text=<urlencoded>` URI first — that is what
 * `ShareLinks.classify` / `unwrapBridgeText` on the Dart side unwraps and
 * re-parses (`InboundLinkHandler`).
 *
 * Deliberately a separate, UI-less activity rather than a hook in
 * `MainActivity`: the SEND intent arrives through its own manifest filter, and
 * MainActivity's `onActivityResult` (local music directory scan) must stay
 * untouched. `noHistory`/`excludeFromRecents` keep it out of the back stack and
 * the recents list, and the translucent theme means the user sees the share
 * sheet sliding into Mconnect rather than this activity.
 */
class ShareIntentHandler : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val sharedText = extractSharedText(intent)
        if (sharedText != null) {
            startActivity(
                Intent(this, MainActivity::class.java).apply {
                    action = Intent.ACTION_VIEW
                    data = Uri.parse(FORWARD_PREFIX + Uri.encode(sharedText))
                    // `singleTop` MainActivity: reuse the running task instead of
                    // stacking a second copy over the now-playing screen.
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                        Intent.FLAG_ACTIVITY_CLEAR_TOP or
                        Intent.FLAG_ACTIVITY_SINGLE_TOP
                }
            )
        }
        finish()
    }

    /** The shared text, or null when this is not a usable text share. */
    private fun extractSharedText(intent: Intent?): String? {
        if (intent == null || intent.action != Intent.ACTION_SEND) return null
        val type = intent.type ?: return null
        if (!type.startsWith("text/")) return null
        // Some apps put the payload in EXTRA_HTML_TEXT only; fall back to it so a
        // share is not silently dropped.
        val text = intent.getStringExtra(Intent.EXTRA_TEXT)
            ?: intent.getCharSequenceExtra(Intent.EXTRA_HTML_TEXT)?.toString()
        return text?.takeIf { it.isNotBlank() }
    }

    companion object {
        /** Must match `ShareLinks.bridgeLink` on the Dart side. */
        const val FORWARD_PREFIX = "mconnect://share?text="
    }
}
