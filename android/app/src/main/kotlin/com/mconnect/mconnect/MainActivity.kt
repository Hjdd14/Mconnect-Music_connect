package com.mconnect.mconnect

import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import android.os.StrictMode
import android.webkit.MimeTypeMap
import androidx.core.content.FileProvider
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import com.ryanheise.audioservice.AudioServiceActivity
import java.io.File

class MainActivity : AudioServiceActivity() {
    private val fileOpenerChannel = "com.mconnect.mconnect/file_opener"
    private val floatingLyricsChannel = "com.mconnect.mconnect/floating_lyrics"
    private var floatingLyricsController: FloatingLyricsController? = null

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
        val floatingLyricsMethodChannel =
            MethodChannel(flutterEngine.dartExecutor.binaryMessenger, floatingLyricsChannel)
        floatingLyricsController = FloatingLyricsController(this, floatingLyricsMethodChannel)
        floatingLyricsMethodChannel.setMethodCallHandler { call, result ->
                val controller = floatingLyricsController ?: FloatingLyricsController(
                    this,
                    floatingLyricsMethodChannel,
                ).also {
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
            startActivity(Intent.createChooser(intent, "打开文件"))
            result.success(true)
        } catch (e: ActivityNotFoundException) {
            result.error("OPEN_FAILED", "没有可用的应用打开该文件", null)
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

            startActivity(Intent.createChooser(intent, "打开文件夹"))
            result.success(true)
        } catch (e: ActivityNotFoundException) {
            // Some file managers only accept file:// for folder navigation. Keep it
            // as a fallback after the FileProvider attempts above.
            try {
                val previousPolicy = StrictMode.getVmPolicy()
                StrictMode.setVmPolicy(StrictMode.VmPolicy.Builder().build())
                val fallback = Intent(Intent.ACTION_VIEW).apply {
                    setDataAndType(Uri.fromFile(folder), "resource/folder")
                }
                startActivity(Intent.createChooser(fallback, "打开文件夹"))
                StrictMode.setVmPolicy(previousPolicy)
                result.success(true)
            } catch (fallbackError: Exception) {
                result.error("OPEN_FAILED", "没有可用的应用打开该文件夹", null)
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
