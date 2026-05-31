package com.mconnect.mconnect

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.graphics.Typeface
import android.net.Uri
import android.os.Build
import android.provider.Settings
import android.text.TextUtils
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.TextView
import io.flutter.plugin.common.MethodChannel
import kotlin.math.max

class FloatingLyricsController(
    private val activity: Activity,
    private val channel: MethodChannel,
) {
    private val windowManager =
        activity.getSystemService(Context.WINDOW_SERVICE) as WindowManager
    private var overlayView: FrameLayout? = null
    private var layoutParams: WindowManager.LayoutParams? = null
    private var lyricText: TextView? = null
    private var translationText: TextView? = null
    private var resizeHandle: TextView? = null
    private var lockButton: TextView? = null
    private var isLocked = false

    fun canDrawOverlays(): Boolean {
        return Build.VERSION.SDK_INT < Build.VERSION_CODES.M ||
            Settings.canDrawOverlays(activity)
    }

    fun openOverlaySettings(result: MethodChannel.Result) {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                val intent = Intent(
                    Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                    Uri.parse("package:${activity.packageName}"),
                )
                activity.startActivity(intent)
            }
            result.success(true)
        } catch (e: Exception) {
            result.error("OPEN_OVERLAY_SETTINGS_FAILED", e.message, null)
        }
    }

    fun show(arguments: Any?, result: MethodChannel.Result) {
        update(arguments, result, createIfMissing = true)
    }

    fun update(arguments: Any?, result: MethodChannel.Result) {
        update(arguments, result, createIfMissing = true)
    }

    private fun update(
        arguments: Any?,
        result: MethodChannel.Result,
        createIfMissing: Boolean,
    ) {
        if (!canDrawOverlays()) {
            result.error("OVERLAY_PERMISSION_DENIED", "Overlay permission is not granted", null)
            return
        }
        val data = arguments as? Map<*, *> ?: emptyMap<String, Any?>()
        try {
            if (overlayView == null && createIfMissing) {
                createOverlay(data)
            }
            applyData(data)
            result.success(true)
        } catch (e: Exception) {
            result.error("FLOATING_LYRICS_UPDATE_FAILED", e.message, null)
        }
    }

    fun hide(result: MethodChannel.Result) {
        try {
            removeOverlay()
            result.success(true)
        } catch (e: Exception) {
            result.error("FLOATING_LYRICS_HIDE_FAILED", e.message, null)
        }
    }

    fun dispose() {
        removeOverlay()
    }

    private fun createOverlay(data: Map<*, *>) {
        val width = (number(data["width"], 320.0) * activity.resources.displayMetrics.density)
            .toInt()
        val height = (number(data["height"], 92.0) * activity.resources.displayMetrics.density)
            .toInt()
        val type = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        } else {
            @Suppress("DEPRECATION")
            WindowManager.LayoutParams.TYPE_PHONE
        }
        val params = WindowManager.LayoutParams(
            width,
            height,
            type,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS,
            android.graphics.PixelFormat.TRANSLUCENT,
        ).apply {
            gravity = Gravity.TOP or Gravity.START
            x = 32
            y = 160
        }

        val root = FrameLayout(activity).apply {
            setBackgroundColor(Color.TRANSPARENT)
            setPadding(8, 6, 8, 6)
        }
        val column = LinearLayout(activity).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            setBackgroundColor(Color.TRANSPARENT)
        }
        lyricText = TextView(activity).apply {
            gravity = Gravity.CENTER
            typeface = Typeface.DEFAULT_BOLD
            includeFontPadding = false
            minHeight = dp(34)
            configureMarquee()
        }
        translationText = TextView(activity).apply {
            gravity = Gravity.CENTER
            includeFontPadding = false
            alpha = 0.82f
            minHeight = dp(22)
            configureMarquee()
        }
        column.addView(
            lyricText,
            LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT,
            ),
        )
        column.addView(
            translationText,
            LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT,
            ).apply {
                topMargin = 4
            },
        )
        root.addView(
            column,
            FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT,
                Gravity.CENTER,
            ),
        )

        val lockButton = controlButton("LOCK").apply {
            setOnClickListener {
                isLocked = !isLocked
                applyLockState()
                notifyLockChanged()
            }
        }
        this.lockButton = lockButton
        root.addView(
            lockButton,
            FrameLayout.LayoutParams(
                dp(50),
                dp(26),
                Gravity.TOP or Gravity.START,
            ),
        )

        val closeButton = controlButton("X").apply {
            textSize = 13f
            setOnClickListener {
                removeOverlay()
                notifyClosedByUser()
            }
        }
        root.addView(
            closeButton,
            FrameLayout.LayoutParams(
                dp(34),
                dp(26),
                Gravity.TOP or Gravity.END,
            ),
        )

        val resizeHandle = TextView(activity).apply {
            text = "//"
            textSize = 14f
            gravity = Gravity.CENTER
            setTextColor(Color.argb(170, 255, 255, 255))
            setShadowLayer(4f, 0f, 1f, Color.argb(190, 0, 0, 0))
        }
        this.resizeHandle = resizeHandle
        root.addView(
            resizeHandle,
            FrameLayout.LayoutParams(
                dp(28),
                dp(24),
                Gravity.BOTTOM or Gravity.END,
            ),
        )

        installDragHandler(root, resizeHandle)
        windowManager.addView(root, params)
        overlayView = root
        layoutParams = params
    }

    private fun installDragHandler(root: View, resizeHandle: View) {
        var startX = 0
        var startY = 0
        var startRawX = 0f
        var startRawY = 0f
        var startWidth = 0
        var startHeight = 0
        var resizing = false

        val listener = View.OnTouchListener { view, event ->
            val params = layoutParams ?: return@OnTouchListener false
            when (event.actionMasked) {
                MotionEvent.ACTION_DOWN -> {
                    if (isLocked) return@OnTouchListener false
                    startX = params.x
                    startY = params.y
                    startWidth = params.width
                    startHeight = params.height
                    startRawX = event.rawX
                    startRawY = event.rawY
                    resizing = view == resizeHandle
                    true
                }
                MotionEvent.ACTION_MOVE -> {
                    if (isLocked) return@OnTouchListener false
                    val dx = event.rawX - startRawX
                    val dy = event.rawY - startRawY
                    if (resizing) {
                        params.width = max(dp(180), startWidth + dx.toInt())
                        params.height = max(dp(56), startHeight + dy.toInt())
                    } else {
                        params.x = startX + dx.toInt()
                        params.y = startY + dy.toInt()
                    }
                    overlayView?.let { windowManager.updateViewLayout(it, params) }
                    true
                }
                else -> false
            }
        }
        root.setOnTouchListener(listener)
        resizeHandle.setOnTouchListener(listener)
    }

    private fun applyData(data: Map<*, *>) {
        val text = string(data["text"])
        val translation = string(data["translation"])
        val textColor = intColor(data["textColor"], Color.WHITE)
        val highlightColor = intColor(data["highlightColor"], Color.rgb(255, 212, 74))
        val fontSize = number(data["fontSize"], 23.0).toFloat()
        val shadowOpacity = number(data["shadowOpacity"], 0.78).coerceIn(0.0, 1.0)
        val backgroundColor = intColor(data["backgroundColor"], Color.TRANSPARENT)
        isLocked = bool(data["isLocked"], isLocked)

        overlayView?.setBackgroundColor(backgroundColor)
        lyricText?.apply {
            setTextIfChanged(text)
            textSize = fontSize
            isSelected = text.isNotBlank()
            setTextColor(if (text.isBlank()) Color.TRANSPARENT else textColor)
            setShadowLayer(
                7f,
                0f,
                2f,
                Color.argb((shadowOpacity * 255).toInt(), 0, 0, 0),
            )
        }
        translationText?.apply {
            setTextIfChanged(translation)
            visibility = if (translation.isBlank()) View.GONE else View.VISIBLE
            isSelected = translation.isNotBlank()
            textSize = (fontSize * 0.62f).coerceAtLeast(11f)
            setTextColor(textColor)
            setShadowLayer(
                5f,
                0f,
                1f,
                Color.argb((shadowOpacity * 220).toInt(), 0, 0, 0),
            )
        }
        // Keep highlightColor consumed by the channel contract. Native word-level
        // highlighting can use this value when per-word timing is pushed later.
        lyricText?.tag = highlightColor
        applyLockState()
    }

    private fun removeOverlay() {
        overlayView?.let {
            try {
                windowManager.removeView(it)
            } catch (_: Exception) {
            }
        }
        overlayView = null
        layoutParams = null
        lyricText = null
        translationText = null
        resizeHandle = null
        lockButton = null
        isLocked = false
    }

    private fun controlButton(label: String): TextView {
        return TextView(activity).apply {
            text = label
            textSize = 10f
            typeface = Typeface.DEFAULT_BOLD
            gravity = Gravity.CENTER
            setTextColor(Color.WHITE)
            setBackgroundColor(Color.argb(135, 0, 0, 0))
            isClickable = true
            isFocusable = false
        }
    }

    private fun TextView.configureMarquee() {
        maxLines = 1
        setSingleLine(true)
        setHorizontallyScrolling(true)
        ellipsize = TextUtils.TruncateAt.MARQUEE
        marqueeRepeatLimit = -1
        isFocusable = true
        isFocusableInTouchMode = true
        isSelected = true
    }

    private fun TextView.setTextIfChanged(value: String) {
        if (text?.toString() != value) {
            text = value
        }
    }

    private fun applyLockState() {
        lockButton?.text = if (isLocked) "MOVE" else "LOCK"
        resizeHandle?.visibility = if (isLocked) View.GONE else View.VISIBLE
    }

    private fun notifyClosedByUser() {
        try {
            channel.invokeMethod("closedByUser", null)
        } catch (_: Exception) {
        }
    }

    private fun notifyLockChanged() {
        try {
            channel.invokeMethod("lockChanged", isLocked)
        } catch (_: Exception) {
        }
    }

    private fun number(value: Any?, fallback: Double): Double {
        return when (value) {
            is Number -> value.toDouble()
            else -> fallback
        }
    }

    private fun string(value: Any?): String {
        return value as? String ?: ""
    }

    private fun bool(value: Any?, fallback: Boolean): Boolean {
        return value as? Boolean ?: fallback
    }

    private fun intColor(value: Any?, fallback: Int): Int {
        return when (value) {
            is Number -> value.toInt()
            else -> fallback
        }
    }

    private fun dp(value: Int): Int {
        return (value * activity.resources.displayMetrics.density).toInt()
    }
}
