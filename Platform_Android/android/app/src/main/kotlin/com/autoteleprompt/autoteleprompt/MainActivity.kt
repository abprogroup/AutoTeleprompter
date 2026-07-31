package com.autoteleprompter.autoteleprompter

import android.app.Activity
import android.content.ContentValues
import android.content.ContentUris
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.provider.DocumentsContract
import android.provider.MediaStore
import android.provider.OpenableColumns
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import androidx.core.content.FileProvider
import java.io.File
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
    private val androidFilesChannel = "autoteleprompter/android_files"
    private val sttChannel = "autoteleprompter/stt"
    private val exportFolderRequestCode = 41013
    private val exportFileRequestCode = 41014
    private var pendingExportFolderResult: MethodChannel.Result? = null
    private var pendingExportFileResult: MethodChannel.Result? = null
    private val appExportRelativePath = "${Environment.DIRECTORY_DOCUMENTS}/AutoTeleprompter/"

    private var sttMethodChannel: MethodChannel? = null
    private var speechRecognizer: SpeechRecognizer? = null
    private var sttLocale: String? = null
    private var sttLanguageRetried = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        sttMethodChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            sttChannel
        ).also { channel ->
            channel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "isAvailable" -> handleSttIsAvailable(result)
                    "start" -> handleSttStart(call.argument<String>("locale"), result)
                    "stop" -> handleSttStop(result)
                    else -> result.notImplemented()
                }
            }
        }

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
                "createExportFile" -> {
                    val displayName = call.argument<String>("displayName")
                    val mimeType = call.argument<String>("mimeType")
                    if (displayName.isNullOrBlank() || mimeType.isNullOrBlank()) {
                        result.success(null)
                        return@setMethodCallHandler
                    }
                    if (pendingExportFileResult != null) {
                        result.error(
                            "export_file_pending",
                            "An export file picker is already open.",
                            null
                        )
                        return@setMethodCallHandler
                    }
                    try {
                        pendingExportFileResult = result
                        val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                            addCategory(Intent.CATEGORY_OPENABLE)
                            type = mimeType
                            putExtra(Intent.EXTRA_TITLE, displayName)
                            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                            addFlags(Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
                            addFlags(Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
                        }
                        startActivityForResult(intent, exportFileRequestCode)
                    } catch (e: Exception) {
                        pendingExportFileResult = null
                        result.error("export_file_picker_failed", e.message, null)
                    }
                }
                "listDefaultExportFolder" -> {
                    try {
                        result.success(listMediaStoreExportFolder())
                    } catch (_: Exception) {
                        result.success(emptyList<Map<String, String>>())
                    }
                }
                "createDefaultExportDocument" -> {
                    val displayName = call.argument<String>("displayName")
                    val mimeType = call.argument<String>("mimeType")
                    if (displayName.isNullOrBlank() || mimeType.isNullOrBlank()) {
                        result.success(null)
                        return@setMethodCallHandler
                    }
                    try {
                        val values = ContentValues().apply {
                            put(MediaStore.MediaColumns.DISPLAY_NAME, displayName)
                            put(MediaStore.MediaColumns.MIME_TYPE, mimeType)
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                                put(MediaStore.MediaColumns.RELATIVE_PATH, appExportRelativePath)
                                put(MediaStore.MediaColumns.IS_PENDING, 1)
                            }
                        }
                        val created = contentResolver.insert(mediaStoreFilesUri(), values)
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
                        try {
                            val deleted = contentResolver.delete(Uri.parse(uriValue), null, null)
                            result.success(deleted > 0)
                        } catch (_: Exception) {
                            result.success(false)
                        }
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
                                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                                    try {
                                        val values = ContentValues().apply {
                                            put(MediaStore.MediaColumns.IS_PENDING, 0)
                                        }
                                        contentResolver.update(Uri.parse(uriValue), values, null, null)
                                    } catch (_: Exception) {
                                        // Non-MediaStore providers do not support IS_PENDING.
                                    }
                                }
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
                "installApk" -> {
                    val path = call.argument<String>("path")
                    if (path.isNullOrBlank()) {
                        result.success(false)
                        return@setMethodCallHandler
                    }
                    try {
                        val apkFile = File(path)
                        if (!apkFile.exists()) {
                            result.success(false)
                            return@setMethodCallHandler
                        }
                        val apkUri = FileProvider.getUriForFile(
                            this,
                            "$packageName.fileprovider",
                            apkFile
                        )
                        val intent = Intent(Intent.ACTION_VIEW).apply {
                            setDataAndType(apkUri, "application/vnd.android.package-archive")
                            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        }
                        startActivity(intent)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("install_apk_failed", e.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    // On-device speech recognition (API 31+). Some OEMs (ColorOS/MIUI/OneUI)
    // restrict Google's speech-recognition-hosting app to foreground-only
    // microphone access, which makes the standard speech_to_text plugin fail
    // with error_permission even though this app's own RECORD_AUDIO grant is
    // fine. SpeechRecognizer.createOnDeviceSpeechRecognizer() runs recognition
    // in-process using this app's own permission, bypassing that restriction.
    private fun handleSttIsAvailable(result: MethodChannel.Result) {
        val apiLevel = Build.VERSION.SDK_INT
        if (apiLevel < Build.VERSION_CODES.S) {
            result.success(mapOf("available" to false, "onDevice" to false, "apiLevel" to apiLevel))
            return
        }
        val onDevice = try {
            SpeechRecognizer.isOnDeviceRecognitionAvailable(this)
        } catch (_: Throwable) {
            false
        }
        result.success(mapOf("available" to onDevice, "onDevice" to onDevice, "apiLevel" to apiLevel))
    }

    private fun handleSttStart(locale: String?, result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) {
            result.success(
                mapOf(
                    "success" to false,
                    "message" to "On-device speech recognition requires Android 12+"
                )
            )
            return
        }
        sttLocale = locale
        sttLanguageRetried = false
        Handler(Looper.getMainLooper()).post {
            try {
                destroySpeechRecognizer()
                val recognizer = SpeechRecognizer.createOnDeviceSpeechRecognizer(this)
                speechRecognizer = recognizer
                recognizer.setRecognitionListener(createSttRecognitionListener())
                recognizer.startListening(buildSttRecognizerIntent(locale))
                result.success(mapOf("success" to true))
            } catch (e: Exception) {
                speechRecognizer = null
                result.success(
                    mapOf(
                        "success" to false,
                        "message" to (e.message ?: "Native STT failed to start")
                    )
                )
            }
        }
    }

    private fun handleSttStop(result: MethodChannel.Result) {
        Handler(Looper.getMainLooper()).post {
            destroySpeechRecognizer()
            result.success(null)
        }
    }

    private fun buildSttRecognizerIntent(locale: String?): Intent {
        return Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
            putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
            putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true)
            putExtra(RecognizerIntent.EXTRA_PREFER_OFFLINE, true)
            putExtra(RecognizerIntent.EXTRA_CALLING_PACKAGE, packageName)
            if (!locale.isNullOrBlank()) {
                putExtra(RecognizerIntent.EXTRA_LANGUAGE, locale.replace('_', '-'))
            }
        }
    }

    private fun destroySpeechRecognizer() {
        try {
            speechRecognizer?.stopListening()
            speechRecognizer?.destroy()
        } catch (_: Exception) {
            // Recognizer may already be in a torn-down state; nothing to do.
        }
        speechRecognizer = null
    }

    private fun restartSttListening(recognizer: SpeechRecognizer) {
        Handler(Looper.getMainLooper()).postDelayed({
            val current = speechRecognizer
            if (current == null || current !== recognizer) return@postDelayed
            try {
                recognizer.startListening(buildSttRecognizerIntent(sttLocale))
            } catch (_: Exception) {
                // If the recognizer is unusable, the next explicit start() call
                // from Dart will recreate it.
            }
        }, 150)
    }

    private fun emitSttResult(bundle: Bundle?, isFinal: Boolean) {
        val matches = bundle?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
        val words = matches?.firstOrNull()
        if (!words.isNullOrEmpty()) {
            sttMethodChannel?.invokeMethod("onResult", mapOf("words" to words, "isFinal" to isFinal))
        }
    }

    private fun sttErrorName(error: Int): String {
        // The numeric code is always appended so an unmapped/unexpected value
        // is still exactly identifiable from the in-app debug log alone,
        // without needing adb. Named cases cover every SpeechRecognizer
        // ERROR_* constant available at compileSdk 34 (API 21-34).
        val name = when (error) {
            SpeechRecognizer.ERROR_NETWORK_TIMEOUT -> "error_network_timeout"
            SpeechRecognizer.ERROR_NETWORK -> "error_network"
            SpeechRecognizer.ERROR_AUDIO -> "error_audio"
            SpeechRecognizer.ERROR_SERVER -> "error_server"
            SpeechRecognizer.ERROR_CLIENT -> "error_client"
            SpeechRecognizer.ERROR_SPEECH_TIMEOUT -> "error_speech_timeout"
            SpeechRecognizer.ERROR_NO_MATCH -> "error_no_match"
            SpeechRecognizer.ERROR_RECOGNIZER_BUSY -> "error_recognizer_busy"
            SpeechRecognizer.ERROR_INSUFFICIENT_PERMISSIONS -> "error_insufficient_permissions"
            SpeechRecognizer.ERROR_TOO_MANY_REQUESTS -> "error_too_many_requests"
            SpeechRecognizer.ERROR_SERVER_DISCONNECTED -> "error_server_disconnected"
            SpeechRecognizer.ERROR_LANGUAGE_NOT_SUPPORTED -> "error_language_not_supported"
            SpeechRecognizer.ERROR_LANGUAGE_UNAVAILABLE -> "error_language_unavailable"
            else -> "error_unknown"
        }
        return "$name($error)"
    }

    private fun createSttRecognitionListener(): RecognitionListener {
        return object : RecognitionListener {
            override fun onReadyForSpeech(params: Bundle?) {
                sttMethodChannel?.invokeMethod("onStatus", "listening")
            }

            override fun onBeginningOfSpeech() {}

            override fun onRmsChanged(rmsdB: Float) {}

            override fun onBufferReceived(buffer: ByteArray?) {}

            override fun onEndOfSpeech() {}

            override fun onError(error: Int) {
                val recognizer = speechRecognizer
                // Silence/no-speech timeouts and transient recognizer/network
                // hiccups are expected during normal pauses in dictation — the
                // speech_to_text plugin handles these the same way, by quietly
                // restarting rather than surfacing them as user-facing errors.
                val recoverable = error == SpeechRecognizer.ERROR_NO_MATCH ||
                    error == SpeechRecognizer.ERROR_SPEECH_TIMEOUT ||
                    error == SpeechRecognizer.ERROR_RECOGNIZER_BUSY ||
                    error == SpeechRecognizer.ERROR_NETWORK ||
                    error == SpeechRecognizer.ERROR_NETWORK_TIMEOUT ||
                    error == SpeechRecognizer.ERROR_SERVER
                if (recoverable && recognizer != null) {
                    restartSttListening(recognizer)
                    return
                }
                // The requested language's on-device model may be missing even
                // though a different one (e.g. the device's own default locale)
                // is installed. Try once with no explicit locale before giving
                // up - mirrors SpeechService's own language-retry behavior.
                val languageIssue = error == SpeechRecognizer.ERROR_LANGUAGE_NOT_SUPPORTED ||
                    error == SpeechRecognizer.ERROR_LANGUAGE_UNAVAILABLE
                if (languageIssue && recognizer != null && !sttLanguageRetried) {
                    sttLanguageRetried = true
                    try {
                        recognizer.startListening(buildSttRecognizerIntent(null))
                        return
                    } catch (_: Exception) {
                        // Fall through to normal fatal reporting below.
                    }
                }
                sttMethodChannel?.invokeMethod("onError", sttErrorName(error))
                sttMethodChannel?.invokeMethod("onStatus", "error")
                destroySpeechRecognizer()
            }

            override fun onResults(results: Bundle?) {
                emitSttResult(results, isFinal = true)
                val recognizer = speechRecognizer
                if (recognizer != null) restartSttListening(recognizer)
            }

            override fun onPartialResults(partialResults: Bundle?) {
                emitSttResult(partialResults, isFinal = false)
            }

            override fun onEvent(eventType: Int, params: Bundle?) {}
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode == exportFileRequestCode) {
            val pending = pendingExportFileResult
            pendingExportFileResult = null
            if (pending == null) {
                super.onActivityResult(requestCode, resultCode, data)
                return
            }
            if (resultCode != Activity.RESULT_OK || data?.data == null) {
                pending.success(null)
                return
            }

            val fileUri = data.data!!
            val requestedFlags =
                Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION
            val grantedFlags = data.flags and requestedFlags
            try {
                contentResolver.takePersistableUriPermission(
                    fileUri,
                    if (grantedFlags != 0) grantedFlags else requestedFlags
                )
            } catch (_: Exception) {
                // Some document providers grant a one-shot write URI only. The
                // immediate save can still proceed, but future Replace may need
                // the provider to grant persistent access.
            }
            pending.success(fileUri.toString())
            return
        }

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

    private fun mediaStoreFilesUri(): Uri {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            MediaStore.Files.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
        } else {
            MediaStore.Files.getContentUri("external")
        }
    }

    private fun listMediaStoreExportFolder(): List<Map<String, String>> {
        val projection = arrayOf(
            MediaStore.MediaColumns._ID,
            MediaStore.MediaColumns.DISPLAY_NAME,
            MediaStore.MediaColumns.MIME_TYPE
        )
        val entries = mutableListOf<Map<String, String>>()
        val selection: String?
        val args: Array<String>?
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            selection = "${MediaStore.MediaColumns.RELATIVE_PATH} = ?"
            args = arrayOf(appExportRelativePath)
        } else {
            selection = null
            args = null
        }

        contentResolver.query(
            mediaStoreFilesUri(),
            projection,
            selection,
            args,
            "${MediaStore.MediaColumns.DATE_MODIFIED} DESC"
        ).use { cursor ->
            if (cursor == null) return entries
            val idIndex = cursor.getColumnIndex(MediaStore.MediaColumns._ID)
            val nameIndex = cursor.getColumnIndex(MediaStore.MediaColumns.DISPLAY_NAME)
            val mimeIndex = cursor.getColumnIndex(MediaStore.MediaColumns.MIME_TYPE)
            while (cursor.moveToNext()) {
                if (idIndex < 0 || nameIndex < 0) continue
                val displayName = cursor.getString(nameIndex) ?: continue
                val id = cursor.getLong(idIndex)
                val uri = ContentUris.withAppendedId(mediaStoreFilesUri(), id)
                entries.add(
                    mapOf(
                        "displayName" to displayName,
                        "uri" to uri.toString(),
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
