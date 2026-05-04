package com.autoteleprompter.autoteleprompter

import android.net.Uri
import android.provider.DocumentsContract
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
                    try {
                        val renamed = DocumentsContract.renameDocument(
                            contentResolver,
                            Uri.parse(uriValue),
                            displayName
                        )
                        result.success(renamed?.toString())
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
                else -> result.notImplemented()
            }
        }
    }
}
