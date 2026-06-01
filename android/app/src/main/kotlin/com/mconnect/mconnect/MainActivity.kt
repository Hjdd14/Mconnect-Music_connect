package com.mconnect.mconnect

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import android.os.StrictMode
import android.webkit.MimeTypeMap
import androidx.core.content.FileProvider
import androidx.documentfile.provider.DocumentFile
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : AudioServiceActivity() {
    private val fileOpenerChannel = "com.mconnect.mconnect/file_opener"
    private val localMusicChannel = "com.mconnect.mconnect/local_music"
    private val floatingLyricsChannel = "com.mconnect.mconnect/floating_lyrics"
    private val playbackKeepAliveChannel = "com.mconnect.mconnect/playback_keep_alive"
    private val localMusicRequestCode = 4108
    private var floatingLyricsController: FloatingLyricsController? = null
    private var playbackKeepAliveController: PlaybackKeepAliveController? = null
    private var pendingLocalMusicResult: MethodChannel.Result? = null

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

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, localMusicChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "pickAndScanDirectory" -> pickAndScanLocalMusicDirectory(result)
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

        val floatingLyricsMethodChannel =
            MethodChannel(flutterEngine.dartExecutor.binaryMessenger, floatingLyricsChannel)
        floatingLyricsController = FloatingLyricsController(this, floatingLyricsMethodChannel)
        floatingLyricsMethodChannel
            .setMethodCallHandler { call, result ->
                val controller = floatingLyricsController
                    ?: FloatingLyricsController(this, floatingLyricsMethodChannel).also {
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

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode == localMusicRequestCode) {
            val result = pendingLocalMusicResult ?: return
            pendingLocalMusicResult = null
            if (resultCode != Activity.RESULT_OK) {
                result.success(null)
                return
            }
            val uri = data?.data
            if (uri == null) {
                result.success(null)
                return
            }
            val flags = (data?.flags ?: 0) and
                (Intent.FLAG_GRANT_READ_URI_PERMISSION or
                    Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
            try {
                contentResolver.takePersistableUriPermission(uri, flags)
            } catch (_: Exception) {
                // Some providers grant only transient access. Scanning can still proceed.
            }
            Thread {
                try {
                    val scanResult = scanDocumentTree(uri)
                    runOnUiThread { result.success(scanResult) }
                } catch (e: Exception) {
                    runOnUiThread {
                        result.error("SCAN_FAILED", e.message ?: "Local music scan failed", null)
                    }
                }
            }.start()
            return
        }
        super.onActivityResult(requestCode, resultCode, data)
    }

    private fun pickAndScanLocalMusicDirectory(result: MethodChannel.Result) {
        if (pendingLocalMusicResult != null) {
            result.error("PICKER_BUSY", "A local music picker is already open", null)
            return
        }
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            addFlags(Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
            addFlags(Intent.FLAG_GRANT_PREFIX_URI_PERMISSION)
        }
        pendingLocalMusicResult = result
        try {
            startActivityForResult(intent, localMusicRequestCode)
        } catch (e: Exception) {
            pendingLocalMusicResult = null
            result.error("PICKER_FAILED", e.message ?: "Unable to open folder picker", null)
        }
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

    private fun scanDocumentTree(uri: Uri): Map<String, Any> {
        val root = DocumentFile.fromTreeUri(this, uri)
            ?: return mapOf(
                "selectedDirectory" to uri.toString(),
                "songs" to emptyList<Map<String, String>>(),
                "lyricsBySongId" to emptyMap<String, String>(),
                "skippedFiles" to listOf(uri.toString()),
            )
        val audioDocuments = mutableListOf<LocalAudioDocument>()
        val lyricsByBaseName = mutableMapOf<String, String>()
        val skippedFiles = mutableListOf<String>()
        collectLocalMusicDocuments(root, audioDocuments, lyricsByBaseName, skippedFiles)
        audioDocuments.sortBy { it.name.lowercase() }
        val songs = audioDocuments.map {
            mapOf("id" to it.uri.toString(), "name" to it.name)
        }
        val lyricsBySongId = audioDocuments.mapNotNull { document ->
            lyricsByBaseName[document.baseName]?.let { lyric ->
                document.uri.toString() to lyric
            }
        }.toMap()
        return mapOf(
            "selectedDirectory" to (root.name ?: uri.toString()),
            "songs" to songs,
            "lyricsBySongId" to lyricsBySongId,
            "skippedFiles" to skippedFiles,
        )
    }

    private fun collectLocalMusicDocuments(
        directory: DocumentFile,
        audioDocuments: MutableList<LocalAudioDocument>,
        lyricsByBaseName: MutableMap<String, String>,
        skippedFiles: MutableList<String>,
    ) {
        for (document in directory.listFiles()) {
            if (document.isDirectory) {
                collectLocalMusicDocuments(document, audioDocuments, lyricsByBaseName, skippedFiles)
                continue
            }
            if (!document.isFile) continue
            val name = document.name ?: continue
            val extension = extensionOf(name)
            val baseName = baseNameOf(name).lowercase()
            if (supportedAudioExtensions.contains(extension)) {
                audioDocuments.add(LocalAudioDocument(document.uri, baseName, baseNameOf(name)))
            } else if (supportedLyricsExtensions.contains(extension)) {
                val lyrics = readTextDocument(document, skippedFiles)
                if (!lyrics.isNullOrBlank()) {
                    lyricsByBaseName[baseName] = lyrics
                }
            }
        }
    }

    private fun readTextDocument(
        document: DocumentFile,
        skippedFiles: MutableList<String>,
    ): String? {
        return try {
            contentResolver.openInputStream(document.uri)?.bufferedReader()?.use {
                it.readText()
            }
        } catch (_: Exception) {
            skippedFiles.add(document.uri.toString())
            null
        }
    }

    private fun extensionOf(name: String): String {
        val dot = name.lastIndexOf('.')
        return if (dot >= 0) name.substring(dot).lowercase() else ""
    }

    private fun baseNameOf(name: String): String {
        val dot = name.lastIndexOf('.')
        return if (dot > 0) name.substring(0, dot) else name
    }

    private data class LocalAudioDocument(
        val uri: Uri,
        val baseName: String,
        val name: String,
    )

    companion object {
        private val supportedAudioExtensions = setOf(
            ".mp3",
            ".flac",
            ".wav",
            ".m4a",
            ".aac",
            ".ogg",
            ".opus",
            ".mp4",
            ".alac",
            ".aiff",
            ".aif",
        )
        private val supportedLyricsExtensions = setOf(".lrc", ".krc", ".qrc", ".txt")
    }
}
