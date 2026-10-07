package com.mconnect.mconnect

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import android.provider.DocumentsContract
import android.webkit.MimeTypeMap
import androidx.documentfile.provider.DocumentFile
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * Storage Access Framework access to a user-chosen download folder.
 *
 * Why this exists at all: `file_picker` cannot give us a usable custom folder.
 * For `type=dir` its Android side maps a SAF tree to a *synthetic file system
 * path* (`FileUtils.kt` volumeId → `/storage/...`) and hands Dart a plain
 * string, so the app ends up writing to a path scoped storage refuses (EACCES),
 * and the persistable grant it needs is never taken. The only way to get a real
 * tree URI is to run `ACTION_OPEN_DOCUMENT_TREE` ourselves and call
 * `takePersistableUriPermission`, which is what this controller does.
 *
 * The channel (`com.mconnect.mconnect/saf_tree`) exposes:
 * * `pickDirectory` → `{uri, name, canRead, canWrite}` (or null when cancelled);
 * * `isGranted(uri)` → bool, against `persistedUriPermissions`;
 * * `release(uri)` → bool, drops the persisted grant;
 * * `copyToTree(uri, relativePath, fileName, sourcePath)` → `{bytes, uri, displayName}`,
 *   streamed in 64 KiB chunks and **size-verified**;
 * * `openTree(uri)` → opens the folder in a file manager (the path-based
 *   `FileOpener.openFolder` cannot open a `content://` tree).
 *
 * Every error is reported with a stable code so Dart can classify it
 * (`PERMISSION_LOST` is the one that must not fail silently).
 */
class SafDocumentTreeController(private val activity: Activity) {

    companion object {
        const val CHANNEL = "com.mconnect.mconnect/saf_tree"
        const val PICK_REQUEST_CODE = 4109

        private const val CHUNK_BYTES = 64 * 1024
    }

    private var channel: MethodChannel? = null
    private var pendingPick: MethodChannel.Result? = null

    fun attach(messenger: BinaryMessenger) {
        val methodChannel = MethodChannel(messenger, CHANNEL)
        methodChannel.setMethodCallHandler { call, result -> handle(call, result) }
        channel = methodChannel
    }

    fun dispose() {
        channel?.setMethodCallHandler(null)
        channel = null
        pendingPick = null
    }

    private fun handle(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "pickDirectory" -> pickDirectory(result)
            "isGranted" -> result.success(isGranted(call.argument<String>("uri")))
            "release" -> result.success(release(call.argument<String>("uri")))
            "copyToTree" -> copyToTree(call, result)
            "deleteDocument" -> deleteDocument(call, result)
            "openTree" -> openTree(call, result)
            else -> result.notImplemented()
        }
    }

    // --- picker -----------------------------------------------------------------

    private fun pickDirectory(result: MethodChannel.Result) {
        if (pendingPick != null) {
            result.error("PICKER_BUSY", "目录选择器已打开", null)
            return
        }
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            addFlags(Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
            addFlags(Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
            addFlags(Intent.FLAG_GRANT_PREFIX_URI_PERMISSION)
        }
        pendingPick = result
        try {
            activity.startActivityForResult(intent, PICK_REQUEST_CODE)
        } catch (e: Exception) {
            pendingPick = null
            result.error("PICKER_FAILED", e.message ?: "无法打开目录选择器", null)
        }
    }

    /**
     * Returns true when [requestCode] belonged to this controller, so
     * `MainActivity.onActivityResult` can tell its callers apart.
     */
    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != PICK_REQUEST_CODE) return false
        val result = pendingPick ?: return true
        pendingPick = null

        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            result.success(null)
            return true
        }

        // Write permission must be requested explicitly: the picker grants read
        // by default, and a read-only grant would let the user pick a folder we
        // then cannot write a download into.
        val takeFlags = (data.flags and
            (Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION)) or
            Intent.FLAG_GRANT_WRITE_URI_PERMISSION
        try {
            activity.contentResolver.takePersistableUriPermission(uri, takeFlags)
        } catch (e: Exception) {
            // Some providers (and some OEM file managers) grant only a transient
            // permission; the folder is still usable for this session, but it
            // must not be presented as permanently writable.
            result.error(
                "PERSIST_FAILED",
                "无法长期保留该目录的访问权限：${e.message ?: "未知原因"}",
                null,
            )
            return true
        }

        val document = DocumentFile.fromTreeUri(activity, uri)
        result.success(
            mapOf(
                "uri" to uri.toString(),
                "name" to (document?.name ?: uri.lastPathSegment ?: uri.toString()),
                "canRead" to (document?.canRead() ?: false),
                "canWrite" to (document?.canWrite() ?: false),
            ),
        )
        return true
    }

    // --- grants -----------------------------------------------------------------

    private fun isGranted(uriString: String?): Boolean {
        if (uriString.isNullOrBlank()) return false
        val uri = Uri.parse(uriString)
        return try {
            activity.contentResolver.persistedUriPermissions.any {
                it.uri.toString() == uri.toString() && it.isWritePermission
            }
        } catch (_: Exception) {
            false
        }
    }

    private fun release(uriString: String?): Boolean {
        if (uriString.isNullOrBlank()) return false
        return try {
            activity.contentResolver.releasePersistableUriPermission(
                Uri.parse(uriString),
                Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION,
            )
            true
        } catch (_: Exception) {
            false
        }
    }

    // --- copy -------------------------------------------------------------------

    private fun copyToTree(call: MethodCall, result: MethodChannel.Result) {
        val treeUri = call.argument<String>("uri")
        val sourcePath = call.argument<String>("sourcePath")
        val fileName = call.argument<String>("fileName")
        val relativePath = call.argument<String>("relativePath") ?: ""

        if (treeUri.isNullOrBlank() || sourcePath.isNullOrBlank() || fileName.isNullOrBlank()) {
            result.error("INVALID_ARGS", "copyToTree 缺少 uri/sourcePath/fileName", null)
            return
        }

        // The copy is up to a few dozen MB: never on the UI thread.
        Thread {
            try {
                val payload = copyIntoTree(treeUri, relativePath, fileName, sourcePath)
                activity.runOnUiThread { result.success(payload) }
            } catch (failure: SafFailure) {
                activity.runOnUiThread { result.error(failure.code, failure.message, null) }
            } catch (error: Exception) {
                activity.runOnUiThread {
                    result.error(
                        "COPY_FAILED",
                        error.message ?: "写入自定义目录失败",
                        null,
                    )
                }
            }
        }.start()
    }

    private fun copyIntoTree(
        treeUri: String,
        relativePath: String,
        fileName: String,
        sourcePath: String,
    ): Map<String, Any> {
        val uri = Uri.parse(treeUri)
        val root = DocumentFile.fromTreeUri(activity, uri)
            ?: throw SafFailure("TREE_UNAVAILABLE", "无法访问已保存的目录，请重新选择")
        if (!root.canWrite()) {
            throw SafFailure("PERMISSION_LOST", "自定义目录的写入权限已失效，请重新选择目录")
        }

        val source = File(sourcePath)
        if (!source.isFile) {
            throw SafFailure("SOURCE_MISSING", "临时文件不存在：$sourcePath")
        }

        val directory = ensureDirectory(root, relativePath)

        val existing = directory.findFile(fileName)
        if (existing != null) {
            if (existing.isDirectory) {
                throw SafFailure("NAME_CONFLICT", "目标位置已存在同名文件夹：$fileName")
            }
            // Replace, so a resumed download does not leave the old bytes behind.
            if (!existing.delete()) {
                throw SafFailure("DELETE_FAILED", "无法覆盖已存在的同名文件：$fileName")
            }
        }

        val target = directory.createFile(mimeTypeOf(fileName), fileName)
            ?: throw SafFailure("CREATE_FAILED", "无法在自定义目录创建文件：$fileName")

        try {
            val output = activity.contentResolver.openOutputStream(target.uri, "w")
                ?: throw SafFailure("OPEN_FAILED", "无法打开目标文件的写入流：$fileName")
            output.use { out ->
                source.inputStream().use { input ->
                    input.copyTo(out, CHUNK_BYTES)
                }
            }
        } catch (failure: SafFailure) {
            target.delete()
            throw failure
        } catch (error: Exception) {
            target.delete()
            throw SafFailure("WRITE_FAILED", error.message ?: "写入自定义目录失败")
        }

        val written = target.length()
        val expected = source.length()
        if (written != expected) {
            // A short write on a SAF provider usually means the provider stopped
            // accepting bytes (quota, revoked grant, full volume). Keeping the
            // half file would silently corrupt the library, so remove it.
            target.delete()
            throw SafFailure(
                "SIZE_MISMATCH",
                "写入自定义目录的字节数不符（期望 $expected，实际 $written）",
            )
        }

        return mapOf(
            "bytes" to written,
            "uri" to target.uri.toString(),
            "displayName" to (target.name ?: fileName),
        )
    }

    private fun ensureDirectory(root: DocumentFile, relativePath: String): DocumentFile {
        var current = root
        for (segment in relativePath.split('/')) {
            if (segment.isEmpty() || segment == ".") continue
            if (segment == "..") {
                throw SafFailure("INVALID_ARGS", "子目录路径不能包含 ..")
            }
            val existing = current.findFile(segment)
            current = when {
                existing == null ->
                    current.createDirectory(segment)
                        ?: throw SafFailure("CREATE_DIR_FAILED", "无法创建子目录：$segment")
                existing.isDirectory -> existing
                else -> throw SafFailure("NAME_CONFLICT", "已存在同名文件，无法创建子目录：$segment")
            }
        }
        return current
    }

    private fun mimeTypeOf(fileName: String): String {
        val extension = fileName.substringAfterLast('.', "").lowercase()
        if (extension.isEmpty()) return "application/octet-stream"
        return MimeTypeMap.getSingleton().getMimeTypeFromExtension(extension)
            ?: "application/octet-stream"
    }

    // --- delete -----------------------------------------------------------------

    /**
     * Deletes one document that [copyToTree] created.
     *
     * A SAF download is stored under a `content://` URI, so the Dart side cannot
     * delete it with `File(...)`: without this method "删除下载文件" would report
     * success (the path never "existed" as a file) and leave the song behind.
     */
    private fun deleteDocument(call: MethodCall, result: MethodChannel.Result) {
        val documentUri = call.argument<String>("uri")
        if (documentUri.isNullOrBlank()) {
            result.error("INVALID_ARGS", "deleteDocument 缺少 uri", null)
            return
        }
        Thread {
            try {
                val document = DocumentFile.fromSingleUri(activity, Uri.parse(documentUri))
                if (document == null || !document.exists()) {
                    // Already gone: deleting something that is not there is a
                    // success, exactly like `File.delete()` on a missing path.
                    activity.runOnUiThread { result.success(true) }
                    return@Thread
                }
                activity.runOnUiThread { result.success(document.delete()) }
            } catch (error: Exception) {
                activity.runOnUiThread {
                    result.error("DELETE_FAILED", error.message ?: "删除文件失败", null)
                }
            }
        }.start()
    }

    // --- open in a file manager -------------------------------------------------

    /**
     * Opens a SAF folder. `FileOpener.openFolder` cannot do this: it takes a
     * filesystem path and requires `File(path).exists()`, which is never true
     * for a `content://` tree.
     */
    private fun openTree(call: MethodCall, result: MethodChannel.Result) {
        val treeUri = call.argument<String>("uri")
        if (treeUri.isNullOrBlank()) {
            result.error("INVALID_ARGS", "openTree 缺少 uri", null)
            return
        }
        val uri = Uri.parse(treeUri)
        try {
            val documentUri = DocumentsContract.buildDocumentUriUsingTree(
                uri,
                DocumentsContract.getTreeDocumentId(uri),
            )
            val candidates = listOf(
                Intent(Intent.ACTION_VIEW).apply {
                    setDataAndType(documentUri, DocumentsContract.Document.MIME_TYPE_DIR)
                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                },
                Intent(Intent.ACTION_VIEW).apply {
                    setDataAndType(documentUri, "resource/folder")
                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                },
                Intent(Intent.ACTION_VIEW).apply {
                    setDataAndType(documentUri, "*/*")
                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                },
            )
            val intent = candidates.firstOrNull {
                it.resolveActivity(activity.packageManager) != null
            }
            if (intent == null) {
                // Reported instead of silently doing nothing: the UI must be able
                // to say "this device has no file manager that can open the folder".
                result.error("OPEN_FAILED", "没有应用可以打开该目录", null)
                return
            }
            activity.startActivity(intent)
            result.success(true)
        } catch (_: ActivityNotFoundException) {
            result.error("OPEN_FAILED", "没有应用可以打开该目录", null)
        } catch (e: Exception) {
            result.error("OPEN_FAILED", e.message ?: "打开目录失败", null)
        }
    }

    private class SafFailure(val code: String, message: String) : Exception(message)
}
