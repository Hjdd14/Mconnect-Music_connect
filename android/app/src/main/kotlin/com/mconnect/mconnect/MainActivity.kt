package com.mconnect.mconnect

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
import android.content.res.Configuration
import android.media.MediaMetadataRetriever
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
    private var pendingKnownIndex: Map<String, LongArray> = emptyMap()

    // Custom download folder (SAF). Kept in its own controller/file so this
    // shared activity only carries the wiring: see SafDocumentTreeController.
    private var safDocumentTreeController: SafDocumentTreeController? = null

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
                    "pickAndScanDirectory" ->
                        pickAndScanLocalMusicDirectory(call.arguments, result)
                    "rescanDirectory" -> rescanLocalMusicDirectory(call.arguments, result)
                    else -> result.notImplemented()
                }
            }

        // SAF document tree (`com.mconnect.mconnect/saf_tree`): the custom
        // download folder picker / writer. Additive — the local-music channel
        // above keeps its own handler.
        safDocumentTreeController = SafDocumentTreeController(this).also {
            it.attach(flutterEngine.dartExecutor.binaryMessenger)
        }

        playbackKeepAliveController = PlaybackKeepAliveController(applicationContext)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, playbackKeepAliveChannel)            .setMethodCallHandler { call, result ->
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
        safDocumentTreeController?.dispose()
        safDocumentTreeController = null
        super.onDestroy()
    }

    override fun onConfigurationChanged(newConfig: Configuration) {
        super.onConfigurationChanged(newConfig)
        // The floating lyrics window spans the full screen width, so a rotation
        // has to re-measure it and pull it back into the visible area.
        floatingLyricsController?.onConfigurationChanged(newConfig)
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        // The SAF download-folder picker owns its own request code
        // (SafDocumentTreeController.PICK_REQUEST_CODE), so it is asked first
        // and simply reports whether it handled the result.
        if (safDocumentTreeController?.onActivityResult(requestCode, resultCode, data) == true) {
            return
        }
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
                    val scanResult = scanDocumentTree(uri, pendingKnownIndex)
                    pendingKnownIndex = emptyMap()
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

    private fun pickAndScanLocalMusicDirectory(
        arguments: Any?,
        result: MethodChannel.Result,
    ) {
        if (pendingLocalMusicResult != null) {
            result.error("PICKER_BUSY", "A local music picker is already open", null)
            return
        }
        pendingKnownIndex = parseKnownIndex((arguments as? Map<*, *>)?.get("known"))
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

    /**
     * Rescans a tree the user already granted (`takePersistableUriPermission` at
     * [onActivityResult]) without showing the picker again. Until now the URI
     * was never stored, so that persistent grant was wasted (H-16).
     */
    private fun rescanLocalMusicDirectory(arguments: Any?, result: MethodChannel.Result) {
        val args = arguments as? Map<*, *>
        val uriString = args?.get("uri") as? String
        if (uriString.isNullOrBlank()) {
            result.error("INVALID_URI", "No persisted tree uri", null)
            return
        }
        val uri = Uri.parse(uriString)
        val known = parseKnownIndex(args?.get("known"))
        Thread {
            try {
                val scanResult = scanDocumentTree(uri, known)
                runOnUiThread { result.success(scanResult) }
            } catch (e: Exception) {
                runOnUiThread {
                    result.error("SCAN_FAILED", e.message ?: "Local music scan failed", null)
                }
            }
        }.start()
    }

    /** Decodes the `{uri: [mtime, size]}` index Dart sends for incremental scans. */
    private fun parseKnownIndex(raw: Any?): Map<String, LongArray> {
        val map = raw as? Map<*, *> ?: return emptyMap()
        val index = HashMap<String, LongArray>(map.size)
        for ((key, value) in map) {
            val path = key as? String ?: continue
            val pair = value as? List<*> ?: continue
            if (pair.size < 2) continue
            val mtime = (pair[0] as? Number)?.toLong() ?: continue
            val size = (pair[1] as? Number)?.toLong() ?: continue
            index[path] = longArrayOf(mtime, size)
        }
        return index
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

    /**
     * Scans a SAF tree.
     *
     * [known] is the `(mtime, size)` index Dart already persisted, keyed by the
     * document URI: an unchanged document skips [MediaMetadataRetriever], which
     * is the expensive part of an Android scan (H-16: the page used to walk and
     * re-read everything on every visit).
     */
    private fun scanDocumentTree(uri: Uri, known: Map<String, LongArray>): Map<String, Any?> {
        val root = DocumentFile.fromTreeUri(this, uri)
            ?: return mapOf(
                "selectedDirectory" to uri.toString(),
                "treeUri" to uri.toString(),
                "songs" to emptyList<Map<String, Any?>>(),
                "skippedFiles" to listOf(uri.toString()),
            )
        val audioDocuments = mutableListOf<LocalAudioDocument>()
        val lyricsByKey = mutableMapOf<String, MutableList<LyricDocument>>()
        val skippedFiles = mutableListOf<String>()
        collectLocalMusicDocuments(
            root,
            audioDocuments,
            lyricsByKey,
            skippedFiles,
            known,
            root.uri.toString(),
        )
        audioDocuments.sortBy { (it.title ?: it.name).lowercase() }
        val songs = audioDocuments.map { document ->
            mapOf(
                "path" to document.uri.toString(),
                "mtime" to document.mtime,
                "size" to document.size,
                "changed" to document.changed,
                "title" to document.title,
                "artist" to document.artist,
                "album" to document.album,
                "durationMs" to document.durationMs,
                "trackNumber" to document.trackNumber,
                "coverPath" to document.coverPath,
                "lyrics" to lyricsByKey[document.baseNameKey].orEmpty()
                    .sortedByDescending { lyricPreference[it.extension] ?: 0 }
                    .map {
                        mapOf("extension" to it.extension, "content" to it.content)
                    },
            )
        }
        return mapOf(
            "selectedDirectory" to (root.name ?: uri.toString()),
            "treeUri" to uri.toString(),
            "songs" to songs,
            "skippedFiles" to skippedFiles,
        )
    }

    private fun collectLocalMusicDocuments(
        directory: DocumentFile,
        audioDocuments: MutableList<LocalAudioDocument>,
        lyricsByKey: MutableMap<String, MutableList<LyricDocument>>,
        skippedFiles: MutableList<String>,
        known: Map<String, LongArray>,
        directoryKey: String,
    ) {
        for (document in directory.listFiles()) {
            if (document.isDirectory) {
                collectLocalMusicDocuments(
                    document,
                    audioDocuments,
                    lyricsByKey,
                    skippedFiles,
                    known,
                    document.uri.toString(),
                )
                continue
            }
            if (!document.isFile) continue
            val name = document.name ?: continue
            val extension = extensionOf(name)
            val baseName = baseNameOf(name)
            if (supportedAudioExtensions.contains(extension)) {
                val uriKey = document.uri.toString()
                val mtime = document.lastModified()
                val size = document.length()
                val previous = known[uriKey]
                val changed =
                    previous == null || previous[0] != mtime || previous[1] != size
                val audio = LocalAudioDocument(
                    uri = document.uri,
                    baseName = baseName,
                    baseNameKey = "$directoryKey|${baseName.lowercase()}",
                    name = name,
                    mtime = mtime,
                    size = size,
                    changed = changed,
                )
                if (changed) {
                    readAudioMetadata(document, audio)
                }
                audioDocuments.add(audio)
            } else if (supportedLyricsExtensions.contains(extension)) {
                // Keyed by the containing directory *and* the base name: the old
                // code keyed only on the lower-cased base name, so `A/01.mp3`
                // and `B/01.mp3` shared whichever lyric file was walked last
                // (H-16 "歌词串词").
                val key = "$directoryKey|${baseName.lowercase()}"
                val lyrics = readTextDocument(document, skippedFiles)
                if (!lyrics.isNullOrBlank()) {
                    lyricsByKey.getOrPut(key) { mutableListOf() }
                        .add(LyricDocument(extension, lyrics))
                }
            }
        }
    }

    /**
     * Reads tags with [MediaMetadataRetriever] and caches the embedded cover
     * inside the app cache directory (the Dart side cannot open a `content://`
     * URI, and the fallback — the file name — is what the app used to show).
     */
    private fun readAudioMetadata(document: DocumentFile, audio: LocalAudioDocument) {
        val retriever = MediaMetadataRetriever()
        try {
            retriever.setDataSource(this, document.uri)
            audio.title = retriever
                .extractMetadata(MediaMetadataRetriever.METADATA_KEY_TITLE)
                ?.trim()
                ?.takeIf { it.isNotEmpty() }
            audio.artist = retriever
                .extractMetadata(MediaMetadataRetriever.METADATA_KEY_ARTIST)
                ?.trim()
                ?.takeIf { it.isNotEmpty() }
            audio.album = retriever
                .extractMetadata(MediaMetadataRetriever.METADATA_KEY_ALBUM)
                ?.trim()
                ?.takeIf { it.isNotEmpty() }
            audio.durationMs = retriever
                .extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)
                ?.toLongOrNull() ?: 0L
            audio.trackNumber = retriever
                .extractMetadata(MediaMetadataRetriever.METADATA_KEY_CD_TRACK_NUMBER)
                ?.substringBefore('/')
                ?.trim()
                ?.toIntOrNull()
            audio.coverPath = writeEmbeddedCover(retriever, document)
        } catch (_: Exception) {
            // Unsupported container or revoked permission: the Dart side keeps
            // the track and falls back to the file name.
        } finally {
            try {
                retriever.release()
            } catch (_: Exception) {
                // Nothing to release.
            }
        }
    }

    private fun writeEmbeddedCover(
        retriever: MediaMetadataRetriever,
        document: DocumentFile,
    ): String? {
        return try {
            val bytes = retriever.embeddedPicture ?: return null
            if (bytes.isEmpty()) return null
            val directory = File(cacheDir, "local_covers")
            if (!directory.exists()) {
                directory.mkdirs()
            }
            val name = Integer.toHexString(document.uri.toString().hashCode()) + ".img"
            val file = File(directory, name)
            if (!file.exists() || file.length() != bytes.size.toLong()) {
                file.writeBytes(bytes)
            }
            file.absolutePath
        } catch (_: Exception) {
            null
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

    private data class LyricDocument(
        val extension: String,
        val content: String,
    )

    private data class LocalAudioDocument(
        val uri: Uri,
        val baseName: String,
        val baseNameKey: String,
        val name: String,
        val mtime: Long,
        val size: Long,
        val changed: Boolean,
        var title: String? = null,
        var artist: String? = null,
        var album: String? = null,
        var durationMs: Long = 0L,
        var trackNumber: Int? = null,
        var coverPath: String? = null,
    )

    companion object {
        /**
         * Highest preference first; Dart falls back to the next entry when a
         * payload cannot be decoded (e.g. an undecryptable KRC).
         */
        private val lyricPreference = mapOf(
            ".lrc" to 4,
            ".krc" to 3,
            ".qrc" to 2,
            ".txt" to 1,
        )

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
        private val supportedLyricsExtensions = lyricPreference.keys
    }
}
