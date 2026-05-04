package com.autoteleprompter.autoteleprompter

import android.app.Activity
import android.content.ContentValues
import android.content.ContentUris
import android.content.Intent
import android.net.Uri
import android.provider.DocumentsContract
import android.provider.MediaStore
import android.provider.OpenableColumns
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
    private val androidFilesChannel = "autoteleprompter/android_files"
    private val exportFolderRequestCode = 41013
    private var pendingExportFolderResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            androidFilesChannel
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "pickExportFolder" -> {
                    if (pendingExportFolderResult != null) {
                        result.error(
                            "export_folder_pending",
                            "An export folder picker is already open.",
                            null
                        )
                        return@setMethodCallHandler
                    }
                    try {
                        pendingExportFolderResult = result
                        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
                            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                            addFlags(Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
                            addFlags(Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
                            addFlags(Intent.FLAG_GRANT_PREFIX_URI_PERMISSION)
                        }
                        startActivityForResult(intent, exportFolderRequestCode)
                    } catch (e: Exception) {
                        pendingExportFolderResult = null
                        result.error("export_folder_picker_failed", e.message, null)
                    }
                }
                "hasPersistedExportFolder" -> {
                    val treeUriValue = call.argument<String>("treeUri")
                    if (treeUriValue.isNullOrBlank()) {
                        result.success(false)
                        return@setMethodCallHandler
                    }
                    result.success(hasPersistedTreePermission(Uri.parse(treeUriValue)))
                }
                "listExportFolder" -> {
                    val treeUriValue = call.argument<String>("treeUri")
                    if (treeUriValue.isNullOrBlank()) {
                        result.success(emptyList<Map<String, String>>())
                        return@setMethodCallHandler
                    }
                    try {
                        result.success(listTreeChildren(Uri.parse(treeUriValue)))
                    } catch (_: Exception) {
                        result.success(emptyList<Map<String, String>>())
                    }
                }
                "createExportDocument" -> {
                    val treeUriValue = call.argument<String>("treeUri")
                    val displayName = call.argument<String>("displayName")
                    val mimeType = call.argument<String>("mimeType")
                    if (
                        treeUriValue.isNullOrBlank() ||
                        displayName.isNullOrBlank() ||
                        mimeType.isNullOrBlank()
                    ) {
                        result.success(null)
                        return@setMethodCallHandler
                    }
                    try {
                        val treeUri = Uri.parse(treeUriValue)
                        val parentUri = DocumentsContract.buildDocumentUriUsingTree(
                            treeUri,
                            DocumentsContract.getTreeDocumentId(treeUri)
                        )
                        val created = DocumentsContract.createDocument(
                            contentResolver,
                            parentUri,
                            mimeType,
                            displayName
                        )
                        result.success(created?.toString())
                    } catch (_: Exception) {
                        result.success(null)
                    }
                }
                "deleteDocument" -> {
                    val uriValue = call.argument<String>("uri")
                    if (uriValue.isNullOrBlank()) {
                        result.success(false)
                        return@setMethodCallHandler
                    }
                    try {
                        result.success(
                            DocumentsContract.deleteDocument(
                                contentResolver,
                                Uri.parse(uriValue)
                            )
                        )
                    } catch (_: Exception) {
                        result.success(false)
                    }
                }
                "writeBytesToUri" -> {
                    val uriValue = call.argument<String>("uri")
                    val bytes = call.argument<ByteArray>("bytes")
                    if (uriValue.isNullOrBlank() || bytes == null) {
                        result.success(false)
                        return@setMethodCallHandler
                    }
                    try {
                        contentResolver.openOutputStream(Uri.parse(uriValue), "wt").use { stream ->
                            if (stream == null) {
                                result.success(false)
                            } else {
                                stream.write(bytes)
                                stream.flush()
                                result.success(true)
                            }
                        }
                    } catch (_: Exception) {
                        result.success(false)
                    }
                }
                "renameDocument" -> {
                    val uriValue = call.argument<String>("uri")
                    val displayName = call.argument<String>("displayName")
                    if (uriValue.isNullOrBlank() || displayName.isNullOrBlank()) {
                        result.success(null)
                        return@setMethodCallHandler
                    }
                    val uri = Uri.parse(uriValue)
                    try {
                        val renamed = DocumentsContract.renameDocument(
                            contentResolver,
                            uri,
                            displayName
                        )
                        if (renamed != null) {
                            result.success(renamed.toString())
                            return@setMethodCallHandler
                        }
                    } catch (_: Exception) {
                        // Some providers return MediaStore URIs from ACTION_CREATE_DOCUMENT.
                        // DocumentsContract cannot rename those, but DISPLAY_NAME update can.
                    }
                    try {
                        val values = ContentValues().apply {
                            put(MediaStore.MediaColumns.DISPLAY_NAME, displayName)
                        }
                        val updated = contentResolver.update(uri, values, null, null)
                        result.success(if (updated > 0) uri.toString() else null)
                    } catch (_: Exception) {
                        result.success(null)
                    }
                }
                "displayNameForUri" -> {
                    val uriValue = call.argument<String>("uri")
                    if (uriValue.isNullOrBlank()) {
                        result.success(null)
                        return@setMethodCallHandler
                    }
                    try {
                        contentResolver.query(
                            Uri.parse(uriValue),
                            arrayOf(OpenableColumns.DISPLAY_NAME),
                            null,
                            null,
                            null
                        ).use { cursor ->
                            if (cursor != null && cursor.moveToFirst()) {
                                val index = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                                result.success(if (index >= 0) cursor.getString(index) else null)
                            } else {
                                result.success(null)
                            }
                        }
                    } catch (_: Exception) {
                        result.success(null)
                    }
                }
                "findDocumentsByDisplayBase" -> {
                    val baseName = call.argument<String>("baseName")?.trim().orEmpty()
                    val format = call.argument<String>("format")?.trim()?.lowercase().orEmpty()
                    if (baseName.isBlank() || format.isBlank()) {
                        result.success(emptyList<Map<String, String>>())
                        return@setMethodCallHandler
                    }
                    try {
                        val collection = MediaStore.Files.getContentUri("external")
                        val projection = arrayOf(
                            MediaStore.MediaColumns._ID,
                            MediaStore.MediaColumns.DISPLAY_NAME
                        )
                        val candidates = mutableListOf<Map<String, String>>()
                        val safeBase = Regex("[/\\\\:*?\"<>|]").replace(baseName, "_")
                            .replace(
                                Regex("""\.(txt|pdf|docx|rtf|doc|pages|md)$""", RegexOption.IGNORE_CASE),
                                ""
                            )
                            .trim()
                        val escapedBase = Regex.escape(safeBase)
                        val escapedExt = Regex.escape(format)
                        val namePattern = Regex(
                            """^$escapedBase(?: \(\d+\))?\.$escapedExt$|^$escapedBase\.$escapedExt \(\d+\)$""",
                            RegexOption.IGNORE_CASE
                        )

                        contentResolver.query(
                            collection,
                            projection,
                            "${MediaStore.MediaColumns.DISPLAY_NAME} LIKE ?",
                            arrayOf("$safeBase%"),
                            "${MediaStore.MediaColumns.DATE_MODIFIED} DESC"
                        ).use { cursor ->
                            if (cursor != null) {
                                val idIndex = cursor.getColumnIndex(MediaStore.MediaColumns._ID)
                                val nameIndex = cursor.getColumnIndex(MediaStore.MediaColumns.DISPLAY_NAME)
                                while (cursor.moveToNext()) {
                                    if (idIndex < 0 || nameIndex < 0) continue
                                    val displayName = cursor.getString(nameIndex) ?: continue
                                    if (!namePattern.matches(displayName.trim())) continue
                                    val id = cursor.getLong(idIndex)
                                    val uri = ContentUris.withAppendedId(collection, id).toString()
                                    candidates.add(mapOf("displayName" to displayName, "uri" to uri))
                                }
                            }
                        }
                        result.success(candidates)
                    } catch (_: Exception) {
                        result.success(emptyList<Map<String, String>>())
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode == exportFolderRequestCode) {
            val pending = pendingExportFolderResult
            pendingExportFolderResult = null
            if (pending == null) {
                super.onActivityResult(requestCode, resultCode, data)
                return
            }
            if (resultCode != Activity.RESULT_OK || data?.data == null) {
                pending.success(null)
                return
            }

            val treeUri = data.data!!
            val requestedFlags =
                Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION
            val grantedFlags = data.flags and requestedFlags
            try {
                contentResolver.takePersistableUriPermission(
                    treeUri,
                    if (grantedFlags != 0) grantedFlags else requestedFlags
                )
                pending.success(treeUri.toString())
            } catch (e: Exception) {
                pending.error("export_folder_permission_failed", e.message, null)
            }
            return
        }
        super.onActivityResult(requestCode, resultCode, data)
    }

    private fun hasPersistedTreePermission(treeUri: Uri): Boolean {
        return contentResolver.persistedUriPermissions.any { permission ->
            permission.uri == treeUri &&
                permission.isReadPermission &&
                permission.isWritePermission
        }
    }

    private fun listTreeChildren(treeUri: Uri): List<Map<String, String>> {
        val childrenUri = DocumentsContract.buildChildDocumentsUriUsingTree(
            treeUri,
            DocumentsContract.getTreeDocumentId(treeUri)
        )
        val projection = arrayOf(
            DocumentsContract.Document.COLUMN_DOCUMENT_ID,
            DocumentsContract.Document.COLUMN_DISPLAY_NAME,
            DocumentsContract.Document.COLUMN_MIME_TYPE
        )
        val entries = mutableListOf<Map<String, String>>()
        contentResolver.query(childrenUri, projection, null, null, null).use { cursor ->
            if (cursor == null) return entries
            val idIndex = cursor.getColumnIndex(DocumentsContract.Document.COLUMN_DOCUMENT_ID)
            val nameIndex = cursor.getColumnIndex(DocumentsContract.Document.COLUMN_DISPLAY_NAME)
            val mimeIndex = cursor.getColumnIndex(DocumentsContract.Document.COLUMN_MIME_TYPE)
            while (cursor.moveToNext()) {
                if (idIndex < 0 || nameIndex < 0) continue
                val documentId = cursor.getString(idIndex) ?: continue
                val displayName = cursor.getString(nameIndex) ?: continue
                val documentUri = DocumentsContract.buildDocumentUriUsingTree(
                    treeUri,
                    documentId
                )
                entries.add(
                    mapOf(
                        "displayName" to displayName,
                        "uri" to documentUri.toString(),
                        "mimeType" to if (mimeIndex >= 0) {
                            cursor.getString(mimeIndex) ?: ""
                        } else {
                            ""
                        }
                    )
                )
            }
        }
        return entries
    }
}
