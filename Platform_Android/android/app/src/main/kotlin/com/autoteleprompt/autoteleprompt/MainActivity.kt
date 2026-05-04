package com.autoteleprompter.autoteleprompter

import android.content.ContentValues
import android.net.Uri
import android.content.ContentUris
import android.provider.DocumentsContract
import android.provider.MediaStore
import android.provider.OpenableColumns
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
    private val androidFilesChannel = "autoteleprompter/android_files"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            androidFilesChannel
        ).setMethodCallHandler { call, result ->
            when (call.method) {
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
}
