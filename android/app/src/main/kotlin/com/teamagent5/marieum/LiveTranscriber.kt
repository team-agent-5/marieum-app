package com.teamagent5.marieum

import android.content.Context
import android.content.Intent
import android.media.AudioFormat
import android.os.Build
import android.os.Bundle
import android.os.ParcelFileDescriptor
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.IOException
import java.util.concurrent.Executors

/** On-device recognition fed with PCM16 16kHz mono chunks from Dart (Android 13+). */
class LiveTranscriber(
    private val context: Context,
    private val channel: MethodChannel,
) : MethodChannel.MethodCallHandler {
    private val writer = Executors.newSingleThreadExecutor()
    private var recognizer: SpeechRecognizer? = null
    private var input: ParcelFileDescriptor? = null
    private var output: ParcelFileDescriptor.AutoCloseOutputStream? = null
    private var session = 0

    init {
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "start" -> result.success(start(call.arguments as? String ?: "ko-KR"))
            "append" -> {
                (call.arguments as? ByteArray)?.let(::append)
                result.success(null)
            }
            "stop" -> {
                stop()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun start(locale: String): Boolean {
        stop()
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
            !SpeechRecognizer.isOnDeviceRecognitionAvailable(context)
        ) {
            return false
        }
        val current = ++session
        return try {
            val pipe = ParcelFileDescriptor.createPipe()
            val recognizer = SpeechRecognizer.createOnDeviceSpeechRecognizer(context)
            recognizer.setRecognitionListener(Listener(current))
            recognizer.startListening(
                Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
                    putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
                    putExtra(RecognizerIntent.EXTRA_LANGUAGE, locale)
                    putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true)
                    putExtra(RecognizerIntent.EXTRA_AUDIO_SOURCE, pipe[0])
                    putExtra(RecognizerIntent.EXTRA_AUDIO_SOURCE_CHANNEL_COUNT, 1)
                    putExtra(RecognizerIntent.EXTRA_AUDIO_SOURCE_ENCODING, AudioFormat.ENCODING_PCM_16BIT)
                    putExtra(RecognizerIntent.EXTRA_AUDIO_SOURCE_SAMPLING_RATE, 16000)
                },
            )
            this.recognizer = recognizer
            input = pipe[0]
            output = ParcelFileDescriptor.AutoCloseOutputStream(pipe[1])
            true
        } catch (error: Exception) {
            stop()
            false
        }
    }

    private fun append(bytes: ByteArray) {
        val stream = output ?: return
        writer.execute {
            try {
                stream.write(bytes)
            } catch (error: IOException) {
                // The recognizer may have finished early; live text is optional.
            }
        }
    }

    private fun stop() {
        session++
        recognizer?.apply {
            stopListening()
            destroy()
        }
        recognizer = null
        val stream = output
        val source = input
        output = null
        input = null
        writer.execute {
            try {
                stream?.close()
                source?.close()
            } catch (error: IOException) {
                // Already closed.
            }
        }
    }

    fun dispose() {
        stop()
        channel.setMethodCallHandler(null)
        writer.shutdown()
    }

    private inner class Listener(private val current: Int) : RecognitionListener {
        private fun send(results: Bundle?) {
            if (current != session) return
            val text = results
                ?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
                ?.firstOrNull() ?: return
            channel.invokeMethod("partial", text)
        }

        override fun onPartialResults(partialResults: Bundle?) = send(partialResults)
        override fun onResults(results: Bundle?) = send(results)
        override fun onReadyForSpeech(params: Bundle?) {}
        override fun onBeginningOfSpeech() {}
        override fun onRmsChanged(rmsdB: Float) {}
        override fun onBufferReceived(buffer: ByteArray?) {}
        override fun onEndOfSpeech() {}
        override fun onError(error: Int) {}
        override fun onEvent(eventType: Int, params: Bundle?) {}
    }
}
