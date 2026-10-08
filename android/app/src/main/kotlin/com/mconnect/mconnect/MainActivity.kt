package com.mconnect.mconnect

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
import android.content.res.Configuration
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.os.StrictMode
import android.util.Log
import android.webkit.MimeTypeMap
import androidx.core.content.FileProvider
import androidx.documentfile.provider.DocumentFile
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.nio.ByteBuffer
import java.nio.charset.CharacterCodingException
import java.nio.charset.Charset
import java.nio.charset.CodingErrorAction
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.RejectedExecutionException

class MainActivity : AudioServiceActivity() {
    private val fileOpenerChannel = "com.mconnect.mconnect/file_opener"
    private val localMusicChannel = "com.mconnect.mconnect/local_music"
    private val floatingLyricsChannel = "com.mconnect.mconnect/floating_lyrics"
    private val playbackKeepAliveChannel = "com.mconnect.mconnect/playback_keep_alive"
    private val localMusicRequestCode = 4108
    private var floatingLyricsController: FloatingLyricsController? = null
    private var playbackKeepAliveController: PlaybackKeepAliveController? = null
    private var pendingLocalMusicResult: MethodChannel.Result? = null

    /** The `local_music` channel, kept so the media observer can push events back. */
    private var localMusicMethodChannel: MethodChannel? = null

    /** Watches `MediaStore` for library changes; created in `configureFlutterEngine`. */
    private var localMusicMediaObserver: LocalMusicMediaObserver? = null
    private var pendingKnownIndex: Map<String, LongArray> = emptyMap()

    /**
     * File/folder-open work (directory listing, `File.exists()`, three
     * `resolveActivity` IPCs) must not run on the platform main thread: on
     * Android that thread *is* the Flutter Dart isolate, so blocking it freezes
     * the UI and every pending Dart `await`.
     */
    private val fileIoExecutor: ExecutorService = Executors.newSingleThreadExecutor { runnable ->
        Thread(runnable, "mconnect-file-opener").apply { isDaemon = true }
    }

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

        // Stored rather than inlined: the media observer below pushes its
        // `mediaStoreChanged` event back to Dart over this same channel (a
        // `MethodChannel` is bidirectional).
        val localMusicMethodChannel =
            MethodChannel(flutterEngine.dartExecutor.binaryMessenger, localMusicChannel)
        this.localMusicMethodChannel = localMusicMethodChannel
        localMusicMethodChannel
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "pickAndScanDirectory" ->
                        pickAndScanLocalMusicDirectory(call.arguments, result)
                    "rescanDirectory" -> rescanLocalMusicDirectory(call.arguments, result)
                    else -> result.notImplemented()
                }
            }

        // Android reports media-store changes (a file was copied in, a track was
        // deleted); the observer de-bounces the burst and we forward one event.
        // Nothing is scanned here on purpose: Dart reacts by calling the same
        // stamped rescan as the manual refresh, so an unchanged folder still opens
        // no audio file.
        localMusicMediaObserver =
            LocalMusicMediaObserver(
                    applicationContext,
                    // Named on purpose: a trailing lambda would bind to the *last*
                    // parameter (`debounceMillis`), which is not a function type.
                    onChanged = {
                        localMusicMethodChannel.invokeMethod("mediaStoreChanged", null)
                    },
                )
                .also { it.start() }

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
        // A pending picker/scan must be answered: Dart is awaiting it, and after
        // onDestroy nothing else ever will — the caller would spin forever.
        pendingLocalMusicResult?.let { pending ->
            pendingLocalMusicResult = null
            pending.error("ACTIVITY_DESTROYED", "目录选择已中断，请重试", null)
        }
        pendingKnownIndex = emptyMap()
        // Stops the media-store observer before the engine goes away: leaving it
        // registered would keep a callback into a dead channel, and a pending
        // de-bounced event would fire into nothing.
        localMusicMediaObserver?.stop()
        localMusicMediaObserver = null
        localMusicMethodChannel = null
        floatingLyricsController?.dispose()
        floatingLyricsController = null
        playbackKeepAliveController?.release()
        playbackKeepAliveController = null
        safDocumentTreeController?.dispose()
        safDocumentTreeController = null
        // Let already-queued file/folder work finish; no new work can arrive
        // because the channel handlers are detached above.
        fileIoExecutor.shutdown()
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
            // No pending result means nothing is awaiting this callback (e.g. the
            // activity was recreated and `onDestroy` already failed the caller),
            // so there is no one to answer.
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
            Thread {
                try {
                    // A ContentResolver binder call: kept off the main thread so
                    // it cannot delay the frames the picker is returning to.
                    try {
                        contentResolver.takePersistableUriPermission(uri, flags)
                    } catch (_: Exception) {
                        // Some providers grant only transient access. Scanning
                        // can still proceed.
                    }
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
        // Path checks, `File.exists()` and the chooser are prepared off the main
        // thread; only `startActivity` and the channel result come back to it.
        runFileWork(result) {
            var intent: Intent? = null
            var failure: FileOpenFailure? = null
            try {
                val file = requireExistingPath(path)
                val uri = contentUriFor(file)
                val mimeType = MimeTypeMap.getSingleton()
                    .getMimeTypeFromExtension(file.extension.lowercase())
                    ?: "*/*"
                intent = Intent(Intent.ACTION_VIEW).apply {
                    setDataAndType(uri, mimeType)
                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                }
            } catch (openFailure: FileOpenFailure) {
                failure = openFailure
            } catch (e: Exception) {
                failure = FileOpenFailure("OPEN_FAILED", e.message ?: "No app can open this file")
            }

            runOnUiThread {
                val pendingFailure = failure
                if (pendingFailure != null) {
                    result.error(pendingFailure.code, pendingFailure.message, null)
                    return@runOnUiThread
                }
                val pendingIntent = intent ?: return@runOnUiThread
                try {
                    startActivity(Intent.createChooser(pendingIntent, "Open file"))
                    result.success(true)
                } catch (e: ActivityNotFoundException) {
                    result.error("OPEN_FAILED", "No app can open this file", null)
                } catch (e: Exception) {
                    result.error("OPEN_FAILED", e.message, null)
                }
            }
        }
    }

    private fun openFolder(path: String?, result: MethodChannel.Result) {
        runFileWork(result) {
            var intent: Intent? = null
            var folder: File? = null
            var failure: FileOpenFailure? = null
            try {
                val resolved = requireExistingPath(path)
                if (!resolved.isDirectory) {
                    throw FileOpenFailure("INVALID_PATH", "Path is not a folder")
                }
                folder = resolved
                val uri = contentUriFor(resolved)
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
                // Three PackageManager IPCs, none of which need the main thread.
                intent = intents.firstOrNull {
                    it.resolveActivity(packageManager) != null
                } ?: intents.last()
            } catch (openFailure: FileOpenFailure) {
                failure = openFailure
            } catch (e: Exception) {
                failure = FileOpenFailure("OPEN_FAILED", e.message ?: "No app can open this folder")
            }

            runOnUiThread {
                val pendingFailure = failure
                if (pendingFailure != null) {
                    result.error(pendingFailure.code, pendingFailure.message, null)
                    return@runOnUiThread
                }
                val pendingIntent = intent ?: return@runOnUiThread
                try {
                    startActivity(Intent.createChooser(pendingIntent, "Open folder"))
                    result.success(true)
                } catch (e: ActivityNotFoundException) {
                    val fallbackFolder = folder
                    if (fallbackFolder == null) {
                        result.error("OPEN_FAILED", "No app can open this folder", null)
                        return@runOnUiThread
                    }
                    try {
                        val previousPolicy = StrictMode.getVmPolicy()
                        StrictMode.setVmPolicy(StrictMode.VmPolicy.Builder().build())
                        val fallback = Intent(Intent.ACTION_VIEW).apply {
                            setDataAndType(Uri.fromFile(fallbackFolder), "resource/folder")
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
        }
    }

    /** Thrown by [requireExistingPath]; carries the channel error code. */
    private class FileOpenFailure(val code: String, message: String) : Exception(message)

    /**
     * Queues file/folder work, answering with an error when the executor is
     * already shut down (the activity is being destroyed) instead of leaving the
     * Dart caller awaiting a reply that can never come.
     */
    private fun runFileWork(result: MethodChannel.Result, work: () -> Unit) {
        try {
            fileIoExecutor.execute(work)
        } catch (_: RejectedExecutionException) {
            result.error("ACTIVITY_DESTROYED", "页面已关闭，请重试", null)
        }
    }

    private fun requireExistingPath(path: String?): File {
        if (path.isNullOrBlank()) {
            throw FileOpenFailure("INVALID_PATH", "Path is empty")
        }
        val file = File(path)
        if (!file.exists()) {
            throw FileOpenFailure("INVALID_PATH", "Path does not exist")
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
                "lyrics" to lyricCandidatesFor(document, lyricsByKey)
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
                val lyrics = readTextDocument(document, skippedFiles)
                if (!lyrics.isNullOrBlank()) {
                    // A `lyrics/` subdirectory belongs to the folder it sits in, so
                    // its sidecars are registered under the *parent's* key — that is
                    // how the audio file next to it finds them. The Dart walk does
                    // the same by offering `p.join(directory, 'lyrics', …)`.
                    val inLyricsSubdirectory =
                        directory.name?.equals("lyrics", ignoreCase = true) == true
                    val keyDirectory = if (inLyricsSubdirectory) {
                        directory.parentFile?.uri?.toString() ?: directoryKey
                    } else {
                        directoryKey
                    }
                    val rank = if (inLyricsSubdirectory) 1 else 0
                    lyricsByKey
                        .getOrPut("$keyDirectory|${baseName.lowercase()}") {
                            mutableListOf()
                        }
                        .add(LyricDocument(extension, lyrics, rank))

                    // The tagger shape: `周杰伦 - 稻香.lrc` also answers to `稻香`,
                    // which is what lets it be found beside `01. 稻香.flac`. It is
                    // stored under its *own* rank + 2, so an exactly named sidecar
                    // always wins when both exist.
                    val dash = baseName.lastIndexOf(" - ")
                    if (dash > 0 && dash + 3 < baseName.length) {
                        val tail = baseName.substring(dash + 3).trim()
                        if (tail.isNotEmpty()) {
                            lyricsByKey
                                .getOrPut("$keyDirectory|${tail.lowercase()}") {
                                    mutableListOf()
                                }
                                .add(LyricDocument(extension, lyrics, rank + 2))
                        }
                    }
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
            val bytes = contentResolver.openInputStream(document.uri)?.use {
                it.readBytes()
            } ?: return null
            decodeLyricsBytes(document.uri.toString(), bytes)
        } catch (_: Exception) {
            skippedFiles.add(document.uri.toString())
            null
        }
    }

    /**
     * Decodes a lyric file the user supplied themselves.
     *
     * Those are very often GBK/GB18030 rather than UTF-8: `bufferedReader()`
     * decoded them as UTF-8, threw, and the whole song silently showed
     * "暂无歌词" (the same class of bug as the Dart side, `local_lyrics_loader`).
     *
     * Order is fixed: UTF-8 BOM → strict UTF-8 → GB18030 → lenient UTF-8.
     * The strict UTF-8 step is what keeps correct files correct —
     * GB18030 happily "decodes" valid UTF-8 Chinese byte pairs into mojibake, so
     * trying it first would break files that were never broken.
     */
    private fun decodeLyricsBytes(uri: String, bytes: ByteArray): String {
        if (bytes.isEmpty()) return ""
        val hasUtf8Bom = bytes.size >= 3 &&
            bytes[0] == 0xEF.toByte() &&
            bytes[1] == 0xBB.toByte() &&
            bytes[2] == 0xBF.toByte()
        if (hasUtf8Bom) {
            return String(bytes, 3, bytes.size - 3, Charsets.UTF_8)
        }
        return try {
            decodeStrict(bytes, "UTF-8")
        } catch (_: CharacterCodingException) {
            try {
                val decoded = decodeStrict(bytes, "GB18030")
                Log.d(TAG, "lyrics decoded with GB18030 fallback: $uri")
                decoded
            } catch (_: CharacterCodingException) {
                // Neither encoding is valid: a lenient decode still beats
                // dropping the file, and the UI can show the replacement glyphs.
                String(bytes, Charsets.UTF_8)
            }
        }
    }

    private fun decodeStrict(bytes: ByteArray, charsetName: String): String {
        return Charset.forName(charsetName)
            .newDecoder()
            .onMalformedInput(CodingErrorAction.REPORT)
            .onUnmappableCharacter(CodingErrorAction.REPORT)
            .decode(ByteBuffer.wrap(bytes))
            .toString()
    }

    private fun extensionOf(name: String): String {
        val dot = name.lastIndexOf('.')
        return if (dot >= 0) name.substring(dot).lowercase() else ""
    }

    /**
     * The lyric candidates for one audio document, best first.
     *
     * Mirrors `_lyricCandidates` in `lib/features/local_music/data/local_music_repository.dart`
     * so both platforms rank the same way (`|` in the table is the key separator,
     * not a column):
     *
     * | candidate | Dart order | Kotlin rank |
     * |---|---|---|
     * | `<name>.lrc` beside the track | 1st | 0 |
     * | `lyrics/<name>.lrc` | 2nd | 1 |
     * | `歌手 - 歌名.lrc` (tail match) | after both | 2 |
     * | `lyrics/歌手 - 歌名.lrc` | after both | 3 |
     *
     * The tagger shapes are found by additionally looking up the audio name with
     * its leading track number removed (`01. 稻香` → `稻香`, `1-01 稻香` →
     * `稻香`). The exact key is always tried first, so an exactly named sidecar
     * cannot lose to a fuzzy one.
     */
    private fun lyricCandidatesFor(
        audio: LocalAudioDocument,
        lyricsByKey: Map<String, MutableList<LyricDocument>>,
    ): List<LyricDocument> {
        // `baseNameKey` is "<directoryKey>|<stem>"; an un-encoded URI cannot
        // contain `|`, so this split is exact.
        val directoryKey = audio.baseNameKey.substringBeforeLast('|')
        val keys = mutableListOf(audio.baseNameKey)
        for (stem in fuzzyStemsOf(audio.baseName)) {
            val key = "$directoryKey|${stem.lowercase()}"
            if (!keys.contains(key)) keys.add(key)
        }
        return keys
            .flatMap { lyricsByKey[it].orEmpty() }
            .distinct()
            .sortedWith(
                compareByDescending<LyricDocument> {
                    lyricPreference[it.extension] ?: 0
                }.thenBy { it.rank },
            )
    }

    /**
     * The stems an audio file name suggests besides its own, mirroring
     * `_fuzzyStemsFor` in the Dart walk: up to two leading track numbers
     * (`01. 稻香`, `1-01 稻香`, `[3] 稻香`) are stripped, and the part after the
     * last ` - ` is offered as well (`歌手 - 歌名` beside `歌名.flac`).
     */
    private fun fuzzyStemsOf(audioStem: String): List<String> {
        var stem = audioStem.trim()
        val leadingTrackNumber = Regex(
            "^\\s*(?:\\[\\d{1,3}\\]|\\d{1,3}\\s*[-._)]\\s*|\\d{1,3}\\s+)",
        )
        for (attempt in 0 until 2) {
            val stripped = stem.replaceFirst(leadingTrackNumber, "").trim()
            if (stripped == stem) break
            stem = stripped
        }
        if (stem.isEmpty()) return emptyList()
        val stems = mutableListOf(stem)
        val dash = stem.lastIndexOf(" - ")
        if (dash > 0 && dash + 3 < stem.length) {
            val tail = stem.substring(dash + 3).trim()
            if (tail.isNotEmpty() && tail != stem) stems.add(tail)
        }
        return stems
    }

    private fun baseNameOf(name: String): String {
        val dot = name.lastIndexOf('.')
        return if (dot > 0) name.substring(0, dot) else name
    }

    private data class LyricDocument(
        val extension: String,
        val content: String,
        /**
         * Preference *within* one track, mirroring the Dart rule in
         * `local_music_repository.dart`: `0` = a sidecar named after the audio file
         * in its own directory, `1` = the same name inside a `lyrics/`
         * subdirectory, `2`/`3` = the tagger shapes (`歌手 - 歌名.lrc` and its
         * `lyrics/` sibling). It only ever orders candidates for one track, so it
         * never competes with [lyricPreference] (the format order).
         */
        val rank: Int = 0,
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
        private const val TAG = "MconnectMainActivity"

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
