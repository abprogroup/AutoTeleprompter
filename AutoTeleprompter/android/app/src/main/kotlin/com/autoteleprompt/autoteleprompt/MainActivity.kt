package com.autoteleprompter.autoteleprompter

import android.content.ClipData
import android.content.ClipboardManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val clipboardChannel = "autoteleprompter/clipboard"
    private val systemChannel = "autoteleprompter/system"
    private val sttChannel = "autoteleprompter/stt"

    private var speechRecognizer: SpeechRecognizer? = null
    private var sttMethodChannel: MethodChannel? = null
    private var isListening = false
    private var currentLocale: String? = null
    private var usingOnDevice = false

    // Track fallback attempts to avoid infinite loops
    private var attemptStage = 0
    // 0 = on-device with locale (our mic, needs SODA pack)
    // 1 = on-device no locale (default language)
    // 2 = regular recognizer via TTS service (has lang packs)
    // 3 = regular recognizer default (works on most devices)
    // 4 = all failed

    companion object {
        private const val TAG = "NativeSTT"
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Clipboard channel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, clipboardChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "setHtml" -> {
                        val plain = call.argument<String>("plain") ?: ""
                        val html = call.argument<String>("html") ?: plain
                        try {
                            val cm = getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
                            val clip = ClipData.newHtmlText("AutoTeleprompter", plain, html)
                            cm.setPrimaryClip(clip)
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("CLIPBOARD_ERROR", e.message, null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }

        // System channel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, systemChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "openSpeechSettings" -> {
                        try {
                            val intents = listOf(
                                // Best: open offline speech recognition language download
                                Intent("com.google.android.speech.embedded.MANAGE_LANGUAGES"),
                                Intent().apply { action = "com.android.settings.TTS_SETTINGS" },
                                Intent(Settings.ACTION_INPUT_METHOD_SETTINGS),
                                Intent(Settings.ACTION_SETTINGS),
                            )
                            var opened = false
                            for (intent in intents) {
                                try {
                                    intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                                    if (intent.resolveActivity(packageManager) != null) {
                                        startActivity(intent)
                                        opened = true
                                        break
                                    }
                                } catch (_: Exception) { continue }
                            }
                            if (!opened) {
                                startActivity(Intent(Settings.ACTION_SETTINGS).apply {
                                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                                })
                            }
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("SETTINGS_ERROR", e.message, null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }

        // Native STT channel
        sttMethodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, sttChannel)
        sttMethodChannel!!.setMethodCallHandler { call, result ->
            when (call.method) {
                "isAvailable" -> {
                    val available = SpeechRecognizer.isRecognitionAvailable(this)
                    val onDevice = if (Build.VERSION.SDK_INT >= 31) {
                        SpeechRecognizer.isOnDeviceRecognitionAvailable(this)
                    } else false
                    result.success(mapOf(
                        "available" to available,
                        "onDevice" to onDevice,
                        "apiLevel" to Build.VERSION.SDK_INT
                    ))
                }
                "start" -> {
                    val locale = call.argument<String>("locale")
                    currentLocale = locale
                    attemptStage = 0
                    startWithFallback(result)
                }
                "stop" -> {
                    stopRecognition()
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }

    /// Start recognition with automatic fallback chain:
    /// Stage 0: on-device, WITH locale (our mic permission, needs SODA pack)
    /// Stage 1: on-device, NO locale (uses device default language pack)
    /// Stage 2: regular recognizer via TTS service component (has language packs)
    /// Stage 3: regular recognizer default (works on Samsung/Pixel/most devices)
    /// Stage 4: all failed — notify Dart
    private fun startWithFallback(result: MethodChannel.Result?) {
        try {
            stopRecognition()
            isListening = true

            when (attemptStage) {
                0 -> {
                    if (Build.VERSION.SDK_INT >= 31 &&
                        SpeechRecognizer.isOnDeviceRecognitionAvailable(this)) {
                        Log.i(TAG, "Stage 0: ON-DEVICE, locale=$currentLocale")
                        speechRecognizer = SpeechRecognizer.createOnDeviceSpeechRecognizer(this)
                        usingOnDevice = true
                        setupRecognitionListener()
                        speechRecognizer!!.startListening(buildRecognizerIntent(currentLocale, preferOffline = true))
                    } else {
                        // No on-device available, skip to regular recognizers
                        attemptStage = 2
                        startWithFallback(result)
                        return
                    }
                }
                1 -> {
                    // On-device with no locale defaults to English SODA.
                    // Only useful when the script language IS English —
                    // otherwise it produces gibberish and error 7 loops forever.
                    val isEnglish = currentLocale == null ||
                        currentLocale!!.startsWith("en", ignoreCase = true)
                    if (isEnglish && Build.VERSION.SDK_INT >= 31 &&
                        SpeechRecognizer.isOnDeviceRecognitionAvailable(this)) {
                        Log.i(TAG, "Stage 1: ON-DEVICE, no locale (device default)")
                        speechRecognizer = SpeechRecognizer.createOnDeviceSpeechRecognizer(this)
                        usingOnDevice = true
                        setupRecognitionListener()
                        speechRecognizer!!.startListening(buildRecognizerIntent(null, preferOffline = true))
                    } else {
                        Log.i(TAG, "Stage 1: SKIPPED (locale=$currentLocale is not English or no on-device)")
                        attemptStage = 2
                        startWithFallback(result)
                        return
                    }
                }
                2 -> {
                    // Try targeting the TTS recognition service directly —
                    // it has downloaded language packs and may have different
                    // mic permissions than the Google Search app
                    val ttsComponent = ComponentName(
                        "com.google.android.tts",
                        "com.google.android.apps.speech.tts.googletts.service.GoogleTTSRecognitionService"
                    )
                    Log.i(TAG, "Stage 2: TTS SERVICE recognizer, locale=$currentLocale")
                    speechRecognizer = SpeechRecognizer.createSpeechRecognizer(this, ttsComponent)
                    usingOnDevice = false
                    setupRecognitionListener()
                    speechRecognizer!!.startListening(buildRecognizerIntent(currentLocale))
                }
                3 -> {
                    Log.i(TAG, "Stage 3: REGULAR recognizer (default), locale=$currentLocale")
                    speechRecognizer = SpeechRecognizer.createSpeechRecognizer(this)
                    usingOnDevice = false
                    setupRecognitionListener()
                    speechRecognizer!!.startListening(buildRecognizerIntent(currentLocale))
                }
                else -> {
                    // All stages exhausted
                    Log.e(TAG, "All STT stages failed")
                    isListening = false
                    runOnUiThread {
                        sttMethodChannel?.invokeMethod("onError", "error_all_failed")
                        sttMethodChannel?.invokeMethod("onNeedLanguagePack", currentLocale ?: "en-US")
                    }
                    result?.success(mapOf("success" to false,
                        "message" to "Speech recognition not available. Please download the offline speech pack."))
                    return
                }
            }

            Log.i(TAG, "Started listening | stage=$attemptStage | onDevice=$usingOnDevice")
            result?.success(mapOf("success" to true, "onDevice" to usingOnDevice))
        } catch (e: Exception) {
            Log.e(TAG, "Start failed at stage $attemptStage", e)
            // Try next stage
            attemptStage++
            startWithFallback(result)
        }
    }

    private fun setupRecognitionListener() {
        speechRecognizer!!.setRecognitionListener(object : RecognitionListener {
            override fun onReadyForSpeech(params: Bundle?) {
                Log.i(TAG, "Ready for speech (stage=$attemptStage, onDevice=$usingOnDevice)")
                runOnUiThread {
                    sttMethodChannel?.invokeMethod("onStatus", "listening")
                }
            }

            override fun onBeginningOfSpeech() {}
            override fun onRmsChanged(rmsdB: Float) {}
            override fun onBufferReceived(buffer: ByteArray?) {}
            override fun onEndOfSpeech() {}

            override fun onError(error: Int) {
                Log.w(TAG, "Error $error at stage $attemptStage (onDevice=$usingOnDevice)")

                // Language unavailable/unsupported — try next fallback stage
                if (error == 13 || error == 12) {
                    attemptStage++
                    runOnUiThread {
                        try { speechRecognizer?.destroy() } catch (_: Exception) {}
                        startWithFallback(null)
                    }
                    return
                }

                // Mic permission denied (error 9) on regular recognizer —
                // this is the ColorOS issue. Try next stage before giving up.
                if (!usingOnDevice && error == SpeechRecognizer.ERROR_INSUFFICIENT_PERMISSIONS) {
                    Log.w(TAG, "Regular recognizer mic denied at stage $attemptStage — likely ColorOS restriction")
                    if (attemptStage < 3) {
                        attemptStage++
                        runOnUiThread {
                            try { speechRecognizer?.destroy() } catch (_: Exception) {}
                            startWithFallback(null)
                        }
                        return
                    }
                    // All regular stages failed with mic denied
                    isListening = false
                    runOnUiThread {
                        sttMethodChannel?.invokeMethod("onNeedLanguagePack", currentLocale ?: "en-US")
                    }
                    return
                }

                val errorMsg = when (error) {
                    SpeechRecognizer.ERROR_AUDIO -> "error_audio"
                    SpeechRecognizer.ERROR_CLIENT -> "error_client"
                    SpeechRecognizer.ERROR_INSUFFICIENT_PERMISSIONS -> "error_permission"
                    SpeechRecognizer.ERROR_NETWORK -> "error_network"
                    SpeechRecognizer.ERROR_NETWORK_TIMEOUT -> "error_network_timeout"
                    SpeechRecognizer.ERROR_NO_MATCH -> "error_no_match"
                    SpeechRecognizer.ERROR_RECOGNIZER_BUSY -> "error_busy"
                    SpeechRecognizer.ERROR_SERVER -> "error_server"
                    SpeechRecognizer.ERROR_SPEECH_TIMEOUT -> "error_speech_timeout"
                    else -> "error_unknown_$error"
                }

                runOnUiThread {
                    sttMethodChannel?.invokeMethod("onError", errorMsg)
                }

                // Auto-restart for transient errors
                val isFatal = error == SpeechRecognizer.ERROR_AUDIO ||
                        error == SpeechRecognizer.ERROR_INSUFFICIENT_PERMISSIONS
                val isNetwork = error == SpeechRecognizer.ERROR_NETWORK ||
                        error == SpeechRecognizer.ERROR_NETWORK_TIMEOUT ||
                        error == SpeechRecognizer.ERROR_SERVER
                if (isListening && !isFatal) {
                    if (isNetwork) {
                        // Delay restart for network errors to avoid rapid restart loop
                        Log.i(TAG, "Network error $error — retrying in 2s")
                        window.decorView.postDelayed({
                            if (isListening) restartRecognition()
                        }, 2000)
                    } else {
                        restartRecognition()
                    }
                } else if (isFatal) {
                    isListening = false
                    runOnUiThread {
                        sttMethodChannel?.invokeMethod("onStatus", "error")
                    }
                }
            }

            override fun onResults(results: Bundle?) {
                val matches = results?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
                if (!matches.isNullOrEmpty()) {
                    Log.i(TAG, "Result: ${matches[0]}")
                    runOnUiThread {
                        sttMethodChannel?.invokeMethod("onResult", mapOf(
                            "words" to matches[0],
                            "isFinal" to true
                        ))
                    }
                }
                if (isListening) restartRecognition()
            }

            override fun onPartialResults(partialResults: Bundle?) {
                val matches = partialResults?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
                if (!matches.isNullOrEmpty() && matches[0].isNotEmpty()) {
                    runOnUiThread {
                        sttMethodChannel?.invokeMethod("onResult", mapOf(
                            "words" to matches[0],
                            "isFinal" to false
                        ))
                    }
                }
            }

            override fun onEvent(eventType: Int, params: Bundle?) {}
        })
    }

    private fun buildRecognizerIntent(locale: String?, preferOffline: Boolean = false): Intent {
        return Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
            putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
            putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true)
            putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 1)
            if (preferOffline) {
                putExtra(RecognizerIntent.EXTRA_PREFER_OFFLINE, true)
            }
            if (!locale.isNullOrEmpty()) {
                val formatted = locale.replace('_', '-')
                putExtra(RecognizerIntent.EXTRA_LANGUAGE, formatted)
                if (preferOffline) {
                    // Only set strict language prefs for on-device (offline) stages.
                    // Regular recognizers (cloud) reject languages that aren't
                    // available offline when these extras are present.
                    putExtra(RecognizerIntent.EXTRA_LANGUAGE_PREFERENCE, formatted)
                    putExtra("android.speech.extra.ONLY_RETURN_LANGUAGE_PREFERENCE", formatted)
                }
            }
        }
    }

    private fun restartRecognition() {
        if (!isListening) return
        val locale = if (attemptStage == 1) null else currentLocale
        val offline = usingOnDevice
        window.decorView.postDelayed({
            if (!isListening) return@postDelayed
            try {
                speechRecognizer?.cancel()
                speechRecognizer?.startListening(buildRecognizerIntent(locale, preferOffline = offline))
            } catch (e: Exception) {
                Log.e(TAG, "Restart failed, recreating", e)
                try {
                    speechRecognizer?.destroy()
                    speechRecognizer = when {
                        usingOnDevice && Build.VERSION.SDK_INT >= 31 ->
                            SpeechRecognizer.createOnDeviceSpeechRecognizer(this)
                        attemptStage == 2 ->
                            SpeechRecognizer.createSpeechRecognizer(this, ComponentName(
                                "com.google.android.tts",
                                "com.google.android.apps.speech.tts.googletts.service.GoogleTTSRecognitionService"
                            ))
                        else ->
                            SpeechRecognizer.createSpeechRecognizer(this)
                    }
                    setupRecognitionListener()
                    speechRecognizer?.startListening(buildRecognizerIntent(locale, preferOffline = offline))
                } catch (_: Exception) {}
            }
        }, 150)
    }

    private fun stopRecognition() {
        isListening = false
        try {
            speechRecognizer?.cancel()
            speechRecognizer?.destroy()
        } catch (_: Exception) {}
        speechRecognizer = null
    }

    override fun onDestroy() {
        stopRecognition()
        super.onDestroy()
    }
}
