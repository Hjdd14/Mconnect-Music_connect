package com.mconnect.mconnect

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.graphics.BitmapFactory
import android.net.Uri
import android.view.KeyEvent
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider

/**
 * 桌面小组件的原生渲染（RemoteViews 路线，不是 Glance）。
 *
 * 选 RemoteViews 的理由见 docs/v1.5-w2w3-implementation-specs.md §B.5：Glance 需要在
 * 这个 Flutter 工程里再开一套 Compose 工具链（buildFeatures.compose + glance-appwidget
 * + 与 Kotlin 2.2.20 的编译器对齐），第一版不值得；RemoteViews 只需要这一个类。
 *
 * ## 状态从哪来（进程被杀 / App 从未启动都成立）
 * Dart 侧调 `HomeWidget.saveWidgetData(...)` 写共享存储（Android 上是 SharedPreferences），
 * 框架把**同一份** SharedPreferences 作为 [widgetData] 传进来，渲染**完全不依赖 Flutter 进程**。
 * 反过来也意味着：首次把组件拖到桌面时 App 可能从没跑过 → 每个取值都必须有兜底。
 * 二进制（封面）不走 SharedPreferences：Dart 侧用 `saveFile` 落盘后把**绝对路径**存进
 * `coverPath`，这里用 BitmapFactory.decodeFile 读。
 *
 * ## 三个按钮为什么走 ACTION_MEDIA_BUTTON，而不是 HomeWidgetBackgroundIntent
 * 规格 §B.2 原本写的是"按钮 → HomeWidgetBackgroundIntent（后台 isolate 跑 Dart）"。
 * 实施时核对了 audio_service 的源码，发现更稳的路径：
 *
 *     public class MediaButtonReceiver extends androidx.media.session.MediaButtonReceiver
 *
 * 也就是说本 App 的 manifest 里已经声明了一个标准的媒体键接收器
 * （`com.ryanheise.audioservice.MediaButtonReceiver` + `android.intent.action.MEDIA_BUTTON`），
 * 它会把事件派发给当前活跃的 MediaSessionCompat —— 也就是正在播放的那个前台服务。
 * 于是"播放/暂停、上一首、下一首"用一次**显式组件的广播**就能驱动既有会话：
 *   * 不依赖 Flutter 进程、不依赖后台 isolate（HomeWidgetBackgroundReceiver 在本 App
 *     的架构里无法直接控制 audio_service 的 handler，因为它活在另一个 isolate）；
 *   * 只用 framework 类（Intent / KeyEvent / PendingIntent），**不需要**新增
 *     build.gradle 依赖、也不需要 androidx.media 的 buildMediaButtonPendingIntent；
 *   * 组件名是显式的，绕开了 Android 8+ 对**隐式**广播的限制。
 *
 * 兜底（如果真机上媒体键没驱动起会话）：把 [mediaButton] 换成
 * `HomeWidgetBackgroundIntent.getBroadcast(context, uri)`，并在 manifest 里加回
 * `<receiver android:name="es.antonborri.home_widget.HomeWidgetBackgroundReceiver">`
 * 与 `es.antonborri.home_widget.action.BACKGROUND` 过滤器，Dart 侧再调
 * `WidgetBridgeDebug.registerBackgroundFallback()`。这三处一起换，不要只换一半。
 *
 * ⚠️【需真机/Android Studio 验证】：RemoteViews 膨胀结果、深色桌面可读性、按钮是否真的
 * 驱动起播放会话、点击是否落在正确页面 —— 都无法在本仓库的自动化测试里验证（没有
 * Android 运行时）。自动化能覆盖的只有 Dart 侧的 URI 解析与状态映射。
 */
class MconnectWidgetProvider : HomeWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        appWidgetIds.forEach { widgetId ->
            val views = RemoteViews(context.packageName, R.layout.mconnect_widget).apply {
                // 1) 整块点击 → 打开 App（落在播放页；Dart 侧按 URI 决定）
                setOnClickPendingIntent(
                    R.id.mconnect_widget_container,
                    HomeWidgetLaunchIntent.getActivity(
                        context,
                        MainActivity::class.java,
                        Uri.parse(OPEN_URI),
                    ),
                )

                // 2) 文案：没有数据时用**资源兜底**，绝不留空字符串
                val title = widgetData.getString(KEY_TITLE, null)
                val artist = widgetData.getString(KEY_ARTIST, null)
                val hasSong = widgetData.getBoolean(KEY_HAS_SONG, false)
                val showSong = hasSong && !title.isNullOrBlank()

                setTextViewText(
                    R.id.mconnect_widget_title,
                    if (showSong) title!! else context.getString(R.string.mconnect_widget_idle),
                )
                setTextViewText(
                    R.id.mconnect_widget_artist,
                    if (showSong && !artist.isNullOrBlank()) {
                        artist
                    } else {
                        context.getString(R.string.mconnect_widget_open_hint)
                    },
                )

                // 3) 封面：只有拿到本地文件路径时才显示；拿不到就把 ImageView 藏掉
                //    （网络封面需要先落盘 —— 见 WidgetBridge 的注释，留作后续）
                val cover = widgetData.getString(KEY_COVER_PATH, null)
                    ?.takeIf { it.isNotBlank() }
                    ?.let { runCatching { BitmapFactory.decodeFile(it) }.getOrNull() }
                if (cover != null) {
                    setImageViewBitmap(R.id.mconnect_widget_cover, cover)
                    setViewVisibility(R.id.mconnect_widget_cover, View.VISIBLE)
                } else {
                    setViewVisibility(R.id.mconnect_widget_cover, View.GONE)
                }

                // 4) 播放/暂停图标跟随状态
                val playing = widgetData.getBoolean(KEY_IS_PLAYING, false)
                setImageViewResource(
                    R.id.mconnect_widget_play_pause,
                    if (playing) android.R.drawable.ic_media_pause
                    else android.R.drawable.ic_media_play,
                )

                // 5) 三个按钮 → 媒体键广播（驱动既有播放会话，不必打开 App）
                setOnClickPendingIntent(
                    R.id.mconnect_widget_previous,
                    mediaButton(context, widgetId, R.id.mconnect_widget_previous, KeyEvent.KEYCODE_MEDIA_PREVIOUS),
                )
                setOnClickPendingIntent(
                    R.id.mconnect_widget_play_pause,
                    mediaButton(context, widgetId, R.id.mconnect_widget_play_pause, KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE),
                )
                setOnClickPendingIntent(
                    R.id.mconnect_widget_next,
                    mediaButton(context, widgetId, R.id.mconnect_widget_next, KeyEvent.KEYCODE_MEDIA_NEXT),
                )
            }

            appWidgetManager.updateAppWidget(widgetId, views)
        }
    }

    /**
     * 一个"按下媒体键"的显式广播 PendingIntent。
     *
     * 触发链：桌面点击 → ACTION_MEDIA_BUTTON（显式组件）→
     * `com.ryanheise.audioservice.MediaButtonReceiver`
     * （`extends androidx.media.session.MediaButtonReceiver`）→ 活跃 MediaSessionCompat
     * → audio_service 的 AudioHandler.play/pause/skipToNext… → 我们的 Dart 播放器。
     *
     * requestCode 用 `widgetId * 10 + viewId` 而不是常量：桌面可以放多个小组件实例，
     * 不同实例的 PendingIntent 必须不同（否则 FLAG_UPDATE_CURRENT 会让它们互相覆盖）。
     * FLAG_IMMUTABLE 是 Android 12+ 的硬要求（可变 PendingIntent 必须显式声明）。
     */
    private fun mediaButton(
        context: Context,
        widgetId: Int,
        viewId: Int,
        keyCode: Int,
    ): PendingIntent {
        val intent = Intent(Intent.ACTION_MEDIA_BUTTON).apply {
            // 显式组件：只发给本 App 已声明的那个接收器，避免隐式广播限制与误投递
            component = android.content.ComponentName(
                context.packageName,
                "com.ryanheise.audioservice.MediaButtonReceiver",
            )
            // 只带 ACTION_DOWN：MediaSessionCompat 对媒体键就是在 DOWN 上派发的
            // （androidx 的 buildMediaButtonPendingIntent 也是这么造的）
            putExtra(Intent.EXTRA_KEY_EVENT, KeyEvent(KeyEvent.ACTION_DOWN, keyCode))
        }
        return PendingIntent.getBroadcast(
            context,
            widgetId * 10 + viewId,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    companion object {
        /**
         * 与 Dart 侧 `WidgetDataKeys` 的字面量**必须一致**（两边都有注释互相指向）。
         */
        private const val KEY_TITLE = "title"
        private const val KEY_ARTIST = "artist"
        private const val KEY_IS_PLAYING = "isPlaying"
        private const val KEY_HAS_SONG = "hasSong"
        private const val KEY_COVER_PATH = "coverPath"

        /**
         * 与 Dart 侧 `WidgetActions` 的 URI 约定一致。用 `mconnect://widget/...`：
         * `app_links` 只监听 `ACTION_VIEW`，而这里走
         * `es.antonborri.home_widget.action.LAUNCH`，两条通道不会互相触发
         * （也就不会"点一次跳两次"）。
         */
        private const val OPEN_URI = "mconnect://widget/open"
    }
}
