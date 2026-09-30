package com.mconnect.mconnect

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.content.pm.ApplicationInfo
import android.content.res.Configuration
import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.provider.Settings
import android.text.Spannable
import android.text.SpannableString
import android.text.Spanned
import android.text.TextUtils
import android.text.style.ForegroundColorSpan
import android.util.Log
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.ViewConfiguration
import android.view.WindowManager
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.TextView
import io.flutter.plugin.common.MethodChannel
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.roundToInt

/**
 * System overlay that mirrors the current lyric line, modeled after the
 * NetEase Cloud Music desktop lyrics:
 *
 * - full screen width (MATCH_PARENT, so it stays centered across rotations)
 *   and draggable on the vertical axis only
 * - two lyric lines at once: the line being sung plus the next one
 * - the already-sung prefix of the current line is revealed by clipping a
 *   second, highlight-colored copy of the line stacked over the base one. A
 *   paint shader cannot be used for this: a TextView that also carries a
 *   shadow layer renders its glyphs with the solid color only, which made the
 *   sweep invisible.
 * - tapping the lyrics hides/shows the control row
 * - locking freezes the position AND makes the whole window click-through, so
 *   touches land on whatever is underneath; it is unlocked from the app
 * - the settings button opens a row with color swatches (highlight color) and
 *   font size buttons
 *
 * The Dart side owns persistence; this class owns the live window state
 * (position, controls visibility, play state) for as long as the overlay
 * exists. Updates arrive about five times per second while playing, so every
 * applier below is idempotent: it only touches a view when its value actually
 * changed. Anything else would re-layout the marquee on every progress tick.
 */
class FloatingLyricsController(
    private val activity: Activity,
    private val channel: MethodChannel,
) {
    private val windowManager =
        activity.getSystemService(Context.WINDOW_SERVICE) as WindowManager
    private var overlayView: FrameLayout? = null
    private var layoutParams: WindowManager.LayoutParams? = null
    private var lyricText: TextView? = null
    private var nextText: TextView? = null
    private var translationText: TextView? = null
    private var controlRow: LinearLayout? = null
    private var settingsRow: LinearLayout? = null
    private var lockButton: ImageView? = null
    private var closeButton: ImageView? = null
    private var previousButton: ImageView? = null
    private var playPauseButton: ImageView? = null
    private var nextButton: ImageView? = null
    private var settingsButton: ImageView? = null
    private var colorDots: List<TextView> = emptyList()
    private var sizeButtons: List<TextView> = emptyList()

    // Live window state.
    private var isLocked = false
    private var controlsVisible = true
    private var settingsVisible = false
    private var isPlaying = false
    private var hasSong = false
    private var textColor = Color.WHITE
    private var highlightColor = Color.rgb(255, 212, 74)
    private var fontSize = 23f
    private var shadowOpacity = 0.78
    private var backgroundColor = Color.TRANSPARENT
    private var lastReportedPosition = Int.MIN_VALUE

    // Snapshots of what has already been pushed into the views.
    private var appliedLyricText: String? = null
    private var appliedNextText: String? = null
    private var appliedTranslation: String? = null
    private var appliedProgress = -1.0
    private var appliedSpanWhole = -1
    private var appliedSpanStep = -1
    private var appliedFontSize = -1f
    private var appliedShadowOpacity = -1.0
    private var appliedBaseColor = Int.MIN_VALUE
    private var appliedDotColor = Int.MIN_VALUE
    private var appliedBackgroundColor = Int.MIN_VALUE
    private var appliedPlaying: Boolean? = null
    private var appliedHasSong: Boolean? = null
    private var appliedLocked: Boolean? = null

    // Played-progress animation. Dart re-anchors every ~200ms; these frames fill
    // the gaps so the color boundary sweeps continuously.
    private val frameHandler = Handler(Looper.getMainLooper())
    private var frameRunnable: Runnable? = null
    private var frameScheduled = false
    private var anchorProgress = 0.0
    private var anchorRatePerMs = 0.0
    private var anchorUptime = 0L

    private val isDebuggable: Boolean
        get() = (activity.applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE) != 0
    private var lastDebugLogAt = 0L

    // Values the user just changed from the overlay itself. Dart round-trips
    // them, but a progress update can arrive first with the previous value, so
    // the local choice wins until Dart echoes it back (or the deadline passes).
    private var pendingFontSize: Float? = null
    private var pendingFontSizeUntil = 0L
    private var pendingHighlightColor: Int? = null
    private var pendingHighlightColorUntil = 0L

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

    /**
     * A rotation re-measures the full width window on its own (MATCH_PARENT),
     * so only the vertical offset has to be pulled back into the new screen.
     */
    fun onConfigurationChanged(@Suppress("UNUSED_PARAMETER") config: Configuration? = null) {
        val params = layoutParams ?: return
        val view = overlayView ?: return
        params.y = clampY(params.y)
        try {
            windowManager.updateViewLayout(view, params)
        } catch (_: Exception) {
        }
    }

    private fun createOverlay(data: Map<*, *>) {
        val params = WindowManager.LayoutParams(
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.WRAP_CONTENT,
            overlayWindowType(),
            windowFlags(isLocked),
            PixelFormat.TRANSLUCENT,
        ).apply {
            gravity = Gravity.TOP or Gravity.START
            x = 0
            y = clampY(number(data["positionY"], DEFAULT_POSITION_Y).toInt())
        }

        val root = FrameLayout(activity).apply {
            setBackgroundColor(Color.TRANSPARENT)
            setPadding(dp(12), dp(6), dp(12), dp(6))
        }

        val column = LinearLayout(activity).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER_HORIZONTAL
            setBackgroundColor(Color.TRANSPARENT)
        }

        val lyricsBlock = FrameLayout(activity).apply {
            setBackgroundColor(Color.TRANSPARENT)
        }
        val lyricsColumn = LinearLayout(activity).apply {
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
        nextText = TextView(activity).apply {
            gravity = Gravity.CENTER
            includeFontPadding = false
            minHeight = dp(26)
            configureMarquee()
        }
        translationText = TextView(activity).apply {
            gravity = Gravity.CENTER
            includeFontPadding = false
            minHeight = dp(20)
            configureMarquee()
        }
        lyricsColumn.addView(
            lyricText,
            LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT,
            ),
        )
        lyricsColumn.addView(
            nextText,
            LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT,
            ).apply {
                topMargin = 2
            },
        )
        lyricsColumn.addView(
            translationText,
            LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT,
            ).apply {
                topMargin = 2
            },
        )
        lyricsBlock.addView(
            lyricsColumn,
            FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.WRAP_CONTENT,
                Gravity.CENTER,
            ),
        )

        val close = iconButton(R.drawable.fl_ic_close, "关闭悬浮歌词") {
            closeOverlay()
        }
        closeButton = close
        lyricsBlock.addView(
            close,
            FrameLayout.LayoutParams(dp(32), dp(32), Gravity.TOP or Gravity.END),
        )

        controlRow = buildControlRow()
        settingsRow = buildSettingsRow().apply { visibility = View.GONE }

        column.addView(
            lyricsBlock,
            LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT,
            ),
        )
        column.addView(
            controlRow,
            LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                dp(CONTROL_ROW_HEIGHT_DP),
            ),
        )
        column.addView(
            settingsRow,
            LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                dp(CONTROL_ROW_HEIGHT_DP),
            ),
        )

        root.addView(
            column,
            FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.WRAP_CONTENT,
                Gravity.CENTER,
            ),
        )

        installDragHandler(root)
        root.addOnLayoutChangeListener { view, left, top, right, bottom, _, _, _, _ ->
            if (bottom - top <= 0 || right - left <= 0) return@addOnLayoutChangeListener
            val active = layoutParams ?: return@addOnLayoutChangeListener
            val clamped = clampY(active.y)
            if (clamped != active.y) {
                active.y = clamped
                try {
                    windowManager.updateViewLayout(view, active)
                } catch (_: Exception) {
                }
            }
            // The color spans are derived from the text layout, so re-apply them
            // whenever that layout changes.
            applyProgressSpans(appliedProgress.coerceAtLeast(0.0))
            updateFrameLoop()
        }

        windowManager.addView(root, params)
        overlayView = root
        layoutParams = params
    }

    private fun buildControlRow(): LinearLayout {
        val row = LinearLayout(activity).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setBackgroundColor(Color.TRANSPARENT)
        }

        val lock = iconButton(R.drawable.fl_ic_unlock, "锁定悬浮歌词") { toggleLock() }
        lockButton = lock
        val previous = iconButton(R.drawable.fl_ic_prev, "上一首") {
            requestControl(CONTROL_PREVIOUS)
        }
        previousButton = previous
        val playPause = iconButton(R.drawable.fl_ic_play, "播放或暂停") {
            requestControl(CONTROL_PLAY_PAUSE)
        }
        playPauseButton = playPause
        val next = iconButton(R.drawable.fl_ic_next, "下一首") {
            requestControl(CONTROL_NEXT)
        }
        nextButton = next
        val settings = iconButton(R.drawable.fl_ic_settings, "歌词设置") {
            toggleSettings()
        }
        settingsButton = settings

        row.addView(lock, iconLayoutParams())
        row.addView(spacer(), spacerLayoutParams())
        row.addView(previous, iconLayoutParams())
        row.addView(playPause, iconLayoutParams())
        row.addView(next, iconLayoutParams())
        row.addView(spacer(), spacerLayoutParams())
        row.addView(settings, iconLayoutParams())
        return row
    }

    private fun buildSettingsRow(): LinearLayout {
        val row = LinearLayout(activity).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setBackgroundColor(Color.TRANSPARENT)
        }
        // The swatches pick the already-played highlight color; the base color
        // is configured from the app settings page.
        colorDots = PRESET_COLORS.map { preset -> colorDot(preset) }
        for (dot in colorDots) {
            row.addView(dot, dotLayoutParams())
        }
        row.addView(spacer(), spacerLayoutParams())
        val plus = textButton("T+") { adjustFontSize(FONT_STEP) }
        val minus = textButton("T-") { adjustFontSize(-FONT_STEP) }
        sizeButtons = listOf(plus, minus)
        row.addView(plus, textButtonLayoutParams())
        row.addView(minus, textButtonLayoutParams())
        return row
    }

    private fun spacer(): View {
        return View(activity).apply { setBackgroundColor(Color.TRANSPARENT) }
    }

    private fun spacerLayoutParams(): LinearLayout.LayoutParams {
        return LinearLayout.LayoutParams(0, 1, 1f)
    }

    private fun iconLayoutParams(): LinearLayout.LayoutParams {
        return LinearLayout.LayoutParams(dp(42), dp(42)).apply {
            marginStart = dp(2)
            marginEnd = dp(2)
        }
    }

    private fun dotLayoutParams(): LinearLayout.LayoutParams {
        return LinearLayout.LayoutParams(dp(30), dp(30)).apply {
            marginStart = dp(4)
            marginEnd = dp(4)
        }
    }

    private fun textButtonLayoutParams(): LinearLayout.LayoutParams {
        return LinearLayout.LayoutParams(dp(40), dp(34)).apply {
            marginStart = dp(2)
            marginEnd = dp(2)
        }
    }

    private fun iconButton(
        resId: Int,
        description: String,
        onClick: () -> Unit,
    ): ImageView {
        return ImageView(activity).apply {
            setImageResource(resId)
            setColorFilter(Color.WHITE)
            contentDescription = description
            scaleType = ImageView.ScaleType.FIT_CENTER
            val padding = dp(9)
            setPadding(padding, padding, padding, padding)
            isClickable = true
            isFocusable = false
            setOnClickListener { onClick() }
        }
    }

    private fun textButton(label: String, onClick: () -> Unit): TextView {
        return TextView(activity).apply {
            text = label
            textSize = 16f
            typeface = Typeface.DEFAULT_BOLD
            gravity = Gravity.CENTER
            setTextColor(Color.WHITE)
            setShadowLayer(4f, 0f, 1f, Color.argb(180, 0, 0, 0))
            isClickable = true
            isFocusable = false
            setOnClickListener { onClick() }
        }
    }

    private fun colorDot(color: Int): TextView {
        return TextView(activity).apply {
            gravity = Gravity.CENTER
            textSize = 13f
            typeface = Typeface.DEFAULT_BOLD
            setTextColor(Color.WHITE)
            background = GradientDrawable().apply {
                shape = GradientDrawable.OVAL
                setColor(color)
                setStroke(dp(1), Color.argb(110, 255, 255, 255))
            }
            isClickable = true
            isFocusable = false
            tag = color
            setOnClickListener { selectHighlightColor(color) }
        }
    }

    private fun installDragHandler(root: View) {
        val touchSlop = ViewConfiguration.get(activity).scaledTouchSlop
        var startY = 0
        var startRawY = 0f
        var moved = false

        root.setOnTouchListener { _, event ->
            val params = layoutParams ?: return@setOnTouchListener false
            if (isLocked) return@setOnTouchListener false
            when (event.actionMasked) {
                MotionEvent.ACTION_DOWN -> {
                    startY = params.y
                    startRawY = event.rawY
                    moved = false
                    true
                }
                MotionEvent.ACTION_MOVE -> {
                    val dy = event.rawY - startRawY
                    if (abs(dy) > touchSlop) {
                        moved = true
                    }
                    if (moved) {
                        // Vertical only: the window spans the full width, so the
                        // horizontal offset stays pinned at 0.
                        params.y = clampY(startY + dy.toInt())
                        overlayView?.let { windowManager.updateViewLayout(it, params) }
                    }
                    true
                }
                MotionEvent.ACTION_UP -> {
                    if (moved) {
                        notifyPositionChanged(params.y)
                    } else {
                        toggleControls()
                    }
                    true
                }
                MotionEvent.ACTION_CANCEL -> {
                    moved = false
                    true
                }
                else -> false
            }
        }
    }

    private fun toggleControls() {
        if (isLocked) return
        controlsVisible = !controlsVisible
        if (!controlsVisible) {
            settingsVisible = false
        }
        applyControlsVisibility()
        clampPosition()
    }

    private fun toggleSettings() {
        if (isLocked) return
        settingsVisible = !settingsVisible
        if (settingsVisible) {
            controlsVisible = true
        }
        applyControlsVisibility()
        clampPosition()
    }

    private fun toggleLock() {
        isLocked = !isLocked
        if (isLocked) {
            controlsVisible = false
            settingsVisible = false
        } else {
            controlsVisible = true
        }
        applyLockUi(isLocked)
        notifyLockChanged()
    }

    private fun closeOverlay() {
        removeOverlay()
        notifyClosedByUser()
    }

    private fun selectHighlightColor(color: Int) {
        if (highlightColor == color) return
        highlightColor = color
        pendingHighlightColor = color
        pendingHighlightColorUntil = SystemClock.uptimeMillis() + PENDING_CHANGE_MS
        // The highlight color lives in the spans; re-apply them now.
        appliedSpanWhole = -1
        appliedSpanStep = -1
        applyProgressSpans(appliedProgress.coerceAtLeast(0.0))
        updateDotSelection()
        notifyStyleChanged()
    }

    private fun adjustFontSize(delta: Float) {
        val next = (fontSize + delta).coerceIn(MIN_FONT_SIZE, MAX_FONT_SIZE)
        if (next == fontSize) return
        fontSize = next
        pendingFontSize = next
        pendingFontSizeUntil = SystemClock.uptimeMillis() + PENDING_CHANGE_MS
        applyTextSize()
        notifyStyleChanged()
        clampPosition()
    }

    private fun requestControl(action: String) {
        invoke("controlRequested", mapOf("action" to action))
    }

    private fun applyData(data: Map<*, *>) {
        applyBaseStyle(
            color = intColor(data["textColor"], textColor),
            highlight = resolvePendingHighlightColor(
                intColor(data["highlightColor"], highlightColor),
            ),
            size = resolvePendingFontSize(
                number(data["fontSize"], fontSize.toDouble())
                    .toFloat()
                    .coerceIn(MIN_FONT_SIZE, MAX_FONT_SIZE),
            ),
            shadow = number(data["shadowOpacity"], shadowOpacity).coerceIn(0.0, 1.0),
            background = intColor(data["backgroundColor"], backgroundColor),
        )
        applyTexts(
            text = string(data["text"]),
            next = string(data["nextText"]),
            translation = string(data["translation"]),
        )
        applyPlayedProgress(
            number(data["highlightProgress"], appliedProgress),
            number(data["highlightRate"], anchorRatePerMs),
        )
        applyPlaybackUi(
            playing = bool(data["isPlaying"], isPlaying),
            song = bool(data["hasSong"], hasSong),
        )
        applyLockUi(bool(data["isLocked"], isLocked))
        clampPosition()
    }

    private fun resolvePendingFontSize(incoming: Float): Float {
        val pending = pendingFontSize ?: return incoming
        if (incoming == pending || SystemClock.uptimeMillis() > pendingFontSizeUntil) {
            pendingFontSize = null
            return incoming
        }
        return pending
    }

    private fun resolvePendingHighlightColor(incoming: Int): Int {
        val pending = pendingHighlightColor ?: return incoming
        if (incoming == pending ||
            SystemClock.uptimeMillis() > pendingHighlightColorUntil
        ) {
            pendingHighlightColor = null
            return incoming
        }
        return pending
    }

    private fun applyBaseStyle(
        color: Int,
        highlight: Int,
        size: Float,
        shadow: Double,
        background: Int,
    ) {
        val baseChanged = appliedBaseColor != color
        val dotChanged = appliedDotColor != highlight
        val sizeChanged = size != fontSize
        val shadowChanged = shadow != shadowOpacity
        textColor = color
        highlightColor = highlight
        fontSize = size
        shadowOpacity = shadow

        if (background != appliedBackgroundColor) {
            appliedBackgroundColor = background
            backgroundColor = background
            overlayView?.setBackgroundColor(background)
        }
        if (sizeChanged || shadowChanged) {
            applyTextSize()
        }
        if (baseChanged) {
            appliedBaseColor = color
            lyricText?.setTextColor(color)
            nextText?.setTextColor(withAlpha(color, NEXT_LINE_ALPHA))
            translationText?.setTextColor(withAlpha(color, TRANSLATION_ALPHA))
        }
        if (dotChanged) {
            appliedDotColor = highlight
            updateDotSelection()
        }
        if (baseChanged || dotChanged) {
            // Both colors live in the spans, so re-apply them at the current
            // progress instead of waiting for the next anchor.
            appliedSpanWhole = -1
            appliedSpanStep = -1
            applyProgressSpans(appliedProgress.coerceAtLeast(0.0))
        }
    }

    private fun applyTextSize() {
        if (appliedFontSize == fontSize && appliedShadowOpacity == shadowOpacity) return
        appliedFontSize = fontSize
        appliedShadowOpacity = shadowOpacity
        lyricText?.apply {
            textSize = fontSize
            setShadowLayer(
                7f,
                0f,
                2f,
                Color.argb((shadowOpacity * 255).toInt(), 0, 0, 0),
            )
        }
        nextText?.apply {
            textSize = fontSize * NEXT_LINE_FONT_SCALE
            setShadowLayer(
                6f,
                0f,
                2f,
                Color.argb((shadowOpacity * 230).toInt(), 0, 0, 0),
            )
        }
        translationText?.apply {
            textSize = (fontSize * TRANSLATION_FONT_SCALE).coerceAtLeast(11f)
            setShadowLayer(
                5f,
                0f,
                1f,
                Color.argb((shadowOpacity * 220).toInt(), 0, 0, 0),
            )
        }
    }

    private fun applyTexts(text: String, next: String, translation: String) {
        if (appliedLyricText != text) {
            appliedLyricText = text
            // The line changed: the new one starts unplayed, so drop the color
            // spans until the next progress anchor.
            appliedProgress = 0.0
            appliedSpanWhole = -1
            appliedSpanStep = -1
            lyricText?.apply {
                setTextIfChanged(text)
                isSelected = text.isNotBlank()
            }
        }
        if (appliedNextText != next) {
            appliedNextText = next
            nextText?.apply {
                setTextIfChanged(next)
                isSelected = next.isNotBlank()
                visibility = if (next.isBlank()) View.GONE else View.VISIBLE
            }
        }
        if (appliedTranslation != translation) {
            appliedTranslation = translation
            translationText?.apply {
                setTextIfChanged(translation)
                isSelected = translation.isNotBlank()
                visibility = if (translation.isBlank()) View.GONE else View.VISIBLE
            }
        }
    }

    /**
     * Positions the played-progress coloring of the current line.
     *
     * Dart re-anchors this every ~200ms with a continuous 0..1 progress plus a
     * progress-per-millisecond rate; the frame loop below fills the gaps so the
     * boundary advances smoothly instead of stepping once per update.
     */
    private fun applyPlayedProgress(progress: Double, rate: Double) {
        anchorProgress = progress.coerceIn(0.0, 1.0)
        anchorRatePerMs = if (rate.isFinite()) rate.coerceAtLeast(0.0) else 0.0
        anchorUptime = SystemClock.uptimeMillis()
        applyProgressSpans(anchorProgress)
        updateFrameLoop()
    }

    private fun updateFrameLoop() {
        if (frameRunnable == null) {
            frameRunnable = Runnable { runFrame() }
        }
        val visible = overlayView?.isShown == true
        val progressAnimating = anchorRatePerMs > 0.0 && anchorProgress < 1.0
        if (progressAnimating && isPlaying && visible && !frameScheduled) {
            frameScheduled = true
            frameHandler.postDelayed(frameRunnable!!, FRAME_INTERVAL_MS)
        } else if (!progressAnimating || !isPlaying || !visible) {
            stopFrameLoop()
        }
    }

    private fun stopFrameLoop() {
        val runnable = frameRunnable
        if (runnable != null) {
            frameHandler.removeCallbacks(runnable)
        }
        frameScheduled = false
    }

    private fun runFrame() {
        frameScheduled = false
        if (!isPlaying || overlayView?.isShown != true) return
        val elapsed = SystemClock.uptimeMillis() - anchorUptime
        val progress = (anchorProgress + anchorRatePerMs * elapsed).coerceIn(0.0, 1.0)
        applyProgressSpans(progress)
        if (progress < 1.0 && anchorRatePerMs > 0.0) {
            frameScheduled = true
            frameHandler.postDelayed(frameRunnable!!, FRAME_INTERVAL_MS)
        }
    }

    /**
     * Colors the already-sung part of the current line.
     *
     * The highlight is a property of the TEXT itself (a color span on the same
     * TextView that draws the line), deliberately not a second clipped view:
     * that extra layer needed its visibility, clip and scroll offset kept in
     * sync every frame, and whenever that soft state went stale the whole line
     * rendered blank until a layout pass "fixed" it. Spans cannot detach from
     * the glyphs, so a marquee-scrolling long line keeps its colors glued.
     *
     * The character at the boundary is painted with a color blended from the
     * base to the highlight color, which keeps the sweep from looking like a
     * hard per-character hop.
     */
    private fun applyProgressSpans(progress: Double) {
        val view = lyricText ?: return
        appliedProgress = progress.coerceIn(0.0, 1.0)
        val spannable = view.text as? Spannable ?: return
        val total = spannable.length
        if (total <= 0) return

        val scaled = appliedProgress * total
        val whole = scaled.toInt().coerceIn(0, total)
        val fraction = (scaled - whole).coerceIn(0.0, 1.0)
        // Quantize the blend so we do not rewrite spans at frame rate.
        val step = if (whole >= total) {
            BLEND_STEPS
        } else {
            (fraction * BLEND_STEPS).toInt().coerceIn(0, BLEND_STEPS)
        }
        if (whole == appliedSpanWhole && step == appliedSpanStep) return
        appliedSpanWhole = whole
        appliedSpanStep = step

        for (span in spannable.getSpans(0, total, ForegroundColorSpan::class.java)) {
            spannable.removeSpan(span)
        }
        if (whole > 0) {
            spannable.setSpan(
                ForegroundColorSpan(highlightColor),
                0,
                whole,
                Spanned.SPAN_EXCLUSIVE_EXCLUSIVE,
            )
        }
        if (whole < total && step > 0) {
            val blend = blendColor(
                textColor,
                highlightColor,
                step.toFloat() / BLEND_STEPS,
            )
            spannable.setSpan(
                ForegroundColorSpan(blend),
                whole,
                whole + 1,
                Spanned.SPAN_EXCLUSIVE_EXCLUSIVE,
            )
        }
        view.invalidate()
        debugLog(whole, step, total)
    }

    private fun blendColor(from: Int, to: Int, ratio: Float): Int {
        val r = ratio.coerceIn(0f, 1f)
        fun mix(a: Int, b: Int): Int =
            (a + ((b - a) * r)).toInt().coerceIn(0, 255)
        return Color.argb(
            mix(Color.alpha(from), Color.alpha(to)),
            mix(Color.red(from), Color.red(to)),
            mix(Color.green(from), Color.green(to)),
            mix(Color.blue(from), Color.blue(to)),
        )
    }

    private fun debugLog(whole: Int, step: Int, total: Int) {
        if (!isDebuggable) return
        val now = SystemClock.uptimeMillis()
        if (now - lastDebugLogAt < 1000L) return
        lastDebugLogAt = now
        Log.d(
            TAG,
            "len=" + total +
                " whole=" + whole +
                " step=" + step + "/" + BLEND_STEPS +
                " progress=" + "%.3f".format(appliedProgress) +
                " rate=" + "%.6f".format(anchorRatePerMs),
        )
    }

    private fun applyPlaybackUi(playing: Boolean, song: Boolean) {
        if (appliedPlaying == playing && appliedHasSong == song) return
        appliedPlaying = playing
        appliedHasSong = song
        isPlaying = playing
        hasSong = song
        playPauseButton?.setImageResource(
            if (playing) R.drawable.fl_ic_pause else R.drawable.fl_ic_play,
        )
        applyControlsVisibility()
        // Pausing must freeze the sweep immediately.
        updateFrameLoop()
    }

    private fun applyLockUi(locked: Boolean) {
        if (appliedLocked == locked) return
        appliedLocked = locked
        isLocked = locked
        lockButton?.setImageResource(
            if (locked) R.drawable.fl_ic_lock else R.drawable.fl_ic_unlock,
        )
        applyWindowFlags()
        applyControlsVisibility()
    }

    /** Locked windows become fully click-through: touches reach what is below. */
    private fun applyWindowFlags() {
        val params = layoutParams ?: return
        val view = overlayView ?: return
        val flags = windowFlags(isLocked)
        if (params.flags == flags) return
        params.flags = flags
        try {
            windowManager.updateViewLayout(view, params)
        } catch (_: Exception) {
        }
    }

    private fun applyControlsVisibility() {
        val rowVisible = isLocked || controlsVisible
        controlRow?.visibility = if (rowVisible) View.VISIBLE else View.GONE
        lockButton?.visibility = View.VISIBLE
        closeButton?.visibility = if (!isLocked && controlsVisible) View.VISIBLE else View.GONE
        settingsButton?.visibility = if (!isLocked && controlsVisible) View.VISIBLE else View.GONE
        settingsRow?.visibility =
            if (!isLocked && controlsVisible && settingsVisible) View.VISIBLE else View.GONE
        val transport = if (!isLocked && hasSong) View.VISIBLE else View.GONE
        previousButton?.visibility = transport
        playPauseButton?.visibility = transport
        nextButton?.visibility = transport
        applyButtonAlpha()
    }

    private fun applyButtonAlpha() {
        lockButton?.alpha = if (isLocked) LOCKED_LOCK_ALPHA else BUTTON_ALPHA
        closeButton?.alpha = BUTTON_ALPHA
        previousButton?.alpha = BUTTON_ALPHA
        playPauseButton?.alpha = BUTTON_ALPHA
        nextButton?.alpha = BUTTON_ALPHA
        settingsButton?.alpha = BUTTON_ALPHA
        for (dot in colorDots) {
            dot.alpha = BUTTON_ALPHA
        }
        for (button in sizeButtons) {
            button.alpha = BUTTON_ALPHA
        }
    }

    private fun updateDotSelection() {
        for (dot in colorDots) {
            val preset = dot.tag as? Int
            val selected = preset != null && preset == highlightColor
            val label = if (selected) "✓" else ""
            if (dot.text?.toString() != label) {
                dot.text = label
            }
        }
    }

    private fun clampPosition() {
        val params = layoutParams ?: return
        val clamped = clampY(params.y)
        if (clamped == params.y) return
        params.y = clamped
        overlayView?.let {
            try {
                windowManager.updateViewLayout(it, params)
            } catch (_: Exception) {
            }
        }
    }

    private fun clampY(value: Int): Int {
        return value.coerceIn(0, maxY())
    }

    private fun maxY(): Int {
        val height = overlayView?.height?.takeIf { it > 0 } ?: estimatedContentHeightPx()
        return max(0, screenHeightPx() - height)
    }

    private fun estimatedContentHeightPx(): Int {
        val lyrics = dp((fontSize * 2.6f).roundToInt() + 30)
        val controls = if (controlsVisible) dp(CONTROL_ROW_HEIGHT_DP) else 0
        val settings = if (controlsVisible && settingsVisible) dp(CONTROL_ROW_HEIGHT_DP) else 0
        return dp(12) + lyrics + controls + settings
    }

    private fun screenHeightPx(): Int = activity.resources.displayMetrics.heightPixels

    private fun windowFlags(locked: Boolean): Int {
        var flags = WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
            WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL or
            WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS
        if (locked) {
            flags = flags or WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE
        }
        return flags
    }

    private fun overlayWindowType(): Int {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        } else {
            @Suppress("DEPRECATION")
            WindowManager.LayoutParams.TYPE_PHONE
        }
    }

    private fun removeOverlay() {
        stopFrameLoop()
        overlayView?.let {
            try {
                windowManager.removeView(it)
            } catch (_: Exception) {
            }
        }
        overlayView = null
        layoutParams = null
        lyricText = null
        nextText = null
        translationText = null
        controlRow = null
        settingsRow = null
        lockButton = null
        closeButton = null
        previousButton = null
        playPauseButton = null
        nextButton = null
        settingsButton = null
        colorDots = emptyList()
        sizeButtons = emptyList()
        isLocked = false
        controlsVisible = true
        settingsVisible = false
        appliedLyricText = null
        appliedNextText = null
        appliedTranslation = null
        appliedProgress = -1.0
        appliedSpanWhole = -1
        appliedSpanStep = -1
        anchorProgress = 0.0
        anchorRatePerMs = 0.0
        anchorUptime = 0L
        appliedFontSize = -1f
        appliedShadowOpacity = -1.0
        appliedBaseColor = Int.MIN_VALUE
        appliedDotColor = Int.MIN_VALUE
        appliedBackgroundColor = Int.MIN_VALUE
        appliedPlaying = null
        appliedHasSong = null
        appliedLocked = null
        pendingFontSize = null
        pendingHighlightColor = null
        lastReportedPosition = Int.MIN_VALUE
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
            // Must be SPANNABLE: with the default BufferType.NORMAL, TextView
            // copies the CharSequence through TextUtils.stringOrSpannedString()
            // into an immutable SpannedString, which silently drops every span
            // (that is what killed the played-progress highlight).
            setText(SpannableString(value), TextView.BufferType.SPANNABLE)
        }
    }

    private fun notifyClosedByUser() {
        invoke("closedByUser", null)
    }

    private fun notifyLockChanged() {
        invoke("lockChanged", isLocked)
    }

    private fun notifyStyleChanged() {
        invoke(
            "styleChanged",
            mapOf(
                "highlightColor" to (highlightColor.toLong() and 0xFFFFFFFFL),
                "fontSize" to fontSize.toDouble(),
            ),
        )
    }

    private fun notifyPositionChanged(position: Int) {
        if (position == lastReportedPosition) return
        lastReportedPosition = position
        invoke("positionChanged", position.toDouble())
    }

    private fun invoke(method: String, arguments: Any?) {
        try {
            channel.invokeMethod(method, arguments)
        } catch (_: Exception) {
        }
    }

    private fun withAlpha(color: Int, factor: Float): Int {
        val alpha = (Color.alpha(color) * factor).roundToInt().coerceIn(0, 255)
        return (color and 0x00FFFFFF) or (alpha shl 24)
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

    private companion object {
        const val MIN_FONT_SIZE = 14f
        const val MAX_FONT_SIZE = 48f
        const val FONT_STEP = 2f
        const val DEFAULT_POSITION_Y = 160.0
        const val CONTROL_ROW_HEIGHT_DP = 44
        const val BUTTON_ALPHA = 0.5f
        const val LOCKED_LOCK_ALPHA = 0.2f
        const val NEXT_LINE_FONT_SCALE = 0.92f
        const val NEXT_LINE_ALPHA = 0.7f
        const val TRANSLATION_FONT_SCALE = 0.62f
        const val TRANSLATION_ALPHA = 0.55f
        const val FRAME_INTERVAL_MS = 16L
        const val TAG = "FloatingLyrics"
        /** Steps the boundary character blends from base to highlight color. */
        const val BLEND_STEPS = 24
        const val CONTROL_PREVIOUS = "previous"
        const val CONTROL_PLAY_PAUSE = "playPause"
        const val CONTROL_NEXT = "next"
        const val PENDING_CHANGE_MS = 1500L
        val PRESET_COLORS = intArrayOf(
            0xFFFE4C4C.toInt(),
            0xFF4AA8FF.toInt(),
            0xFF4CD964.toInt(),
            0xFFFFB22C.toInt(),
            0xFFB06CFF.toInt(),
        )
    }
}
