package com.mconnect.mconnect

import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import android.os.StrictMode
import android.webkit.MimeTypeMap
import androidx.core.content.FileProvider
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : AudioServiceActivity() {
    private val fileOpenerChannel = "com.mconnect.mconnect/file_opener"
    private val floatingLyricsChannel = "com.mconnect.mconnect/floating_lyrics"
    private val playbackKeepAliveChannel = "com.mconnect.mconnect/playback_keep_alive"
    private var floatingLyricsController: FloatingLyricsController? = null
    private var playbackKeepAliveController: PlaybackKeepAliveController? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, fileOpenerChannel)
            .setMethodCallHandler { call, result ->
                val path = call.arguments as? String
                when (call.method) {
                    "openFile" -> openFile(path, result)
                    "openFolder" -> openFolder(path, result)
                    else -> result.notImplemented()
                }
            }

        playbackKeepAliveController = PlaybackKeepAliveController(applicationContext)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, playbackKeepAliveChannel)
            .setMethodCallHandler { call, result ->
                val controller = playbackKeepAliveController
                    ?: PlaybackKeepAliveController(applicationContext).also {
                        playbackKeepAliveController = it
                    }
                when (call.method) {
                    "setPlaying" -> controller.setPlaying(call.arguments, result)
                    else -> result.notImplemented()
                }
            }

        floatingLyricsController = FloatingLyricsController(this)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, floatingLyricsChannel)
            .setMethodCallHandler { call, result ->
                val controller = floatingLyricsController
                    ?: FloatingLyricsController(this).also {
                        floatingLyricsController = it
                    }
                when (call.method) {
                    "canDrawOverlays" -> result.success(controller.canDrawOverlays())
                    "openOverlaySettings" -> controller.openOverlaySettings(result)
                    "show" -> controller.show(call.arguments, result)
                    "update" -> controller.update(call.arguments, result)
                    "hide" -> controller.hide(result)
                    else -> result.notImplemented()
                }
            }
    }

    override fun onDestroy() {
        floatingLyricsController?.dispose()
        floatingLyricsController = null
        playbackKeepAliveController?.release()
        playbackKeepAliveController = null
        super.onDestroy()
    }

    private fun openFile(path: String?, result: MethodChannel.Result) {
        val file = resolveExistingPath(path, result) ?: return
        try {
            val uri = contentUriFor(file)
            val mimeType = MimeTypeMap.getSingleton()
                .getMimeTypeFromExtension(file.extension.lowercase())
                ?: "*/*"
            val intent = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri, mimeType)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
            startActivity(Intent.createChooser(intent, "Open file"))
            result.success(true)
        } catch (e: ActivityNotFoundException) {
            result.error("OPEN_FAILED", "No app can open this file", null)
        } catch (e: Exception) {
            result.error("OPEN_FAILED", e.message, null)
        }
    }

    private fun openFolder(path: String?, result: MethodChannel.Result) {
        val folder = resolveExistingPath(path, result) ?: return
        if (!folder.isDirectory) {
            result.error("INVALID_PATH", "Path is not a folder", null)
            return
        }

        try {
            val uri = contentUriFor(folder)
            val intents = listOf(
                Intent(Intent.ACTION_VIEW).apply {
                    setDataAndType(uri, "resource/folder")
                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                },
                Intent(Intent.ACTION_VIEW).apply {
                    setDataAndType(uri, "vnd.android.document/directory")
                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                },
                Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                },
            )

            val intent = intents.firstOrNull {
                it.resolveActivity(packageManager) != null
            } ?: intents.last()

            startActivity(Intent.createChooser(intent, "Open folder"))
            result.success(true)
        } catch (e: ActivityNotFoundException) {
            try {
                val previousPolicy = StrictMode.getVmPolicy()
                StrictMode.setVmPolicy(StrictMode.VmPolicy.Builder().build())
                val fallback = Intent(Intent.ACTION_VIEW).apply {
                    setDataAndType(Uri.fromFile(folder), "resource/folder")
                }
                startActivity(Intent.createChooser(fallback, "Open folder"))
                StrictMode.setVmPolicy(previousPolicy)
                result.success(true)
            } catch (fallbackError: Exception) {
                result.error("OPEN_FAILED", "No app can open this folder", null)
            }
        } catch (e: Exception) {
            result.error("OPEN_FAILED", e.message, null)
        }
    }

    private fun resolveExistingPath(path: String?, result: MethodChannel.Result): File? {
        if (path.isNullOrBlank()) {
            result.error("INVALID_PATH", "Path is empty", null)
            return null
        }
        val file = File(path)
        if (!file.exists()) {
            result.error("INVALID_PATH", "Path does not exist", null)
            return null
        }
        return file
    }

    private fun contentUriFor(file: File): Uri {
        return FileProvider.getUriForFile(
            this,
            "${applicationContext.packageName}.fileprovider",
            file,
        )
    }
}
