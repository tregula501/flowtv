package io.github.tregula501.flowtv

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "io.github.tregula501.flowtv/audio_transcode"
    private var transcoder: AudioTranscoder? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Run transcode handler on a background thread so the blocking
        // MediaCodec decode/encode loop doesn't stall the Android main thread.
        val taskQueue = flutterEngine.dartExecutor.binaryMessenger.makeBackgroundTaskQueue()
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL, io.flutter.plugin.common.StandardMethodCodec.INSTANCE, taskQueue).setMethodCallHandler { call, result ->
            when (call.method) {
                "isSupported" -> {
                    result.success(AudioTranscoder.isAc3Supported())
                }
                "start" -> {
                    transcoder?.stop()
                    transcoder = AudioTranscoder()
                    val success = transcoder!!.start()
                    if (!success) {
                        transcoder = null
                    }
                    result.success(success)
                }
                "transcode" -> {
                    val ac3Data = call.argument<ByteArray>("data")
                    if (ac3Data == null || transcoder == null) {
                        result.success(listOf<ByteArray>())
                        return@setMethodCallHandler
                    }
                    val aacFrames = transcoder!!.transcode(ac3Data)
                    // Return as list of byte arrays
                    result.success(aacFrames)
                }
                "stop" -> {
                    transcoder?.stop()
                    transcoder = null
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onDestroy() {
        transcoder?.stop()
        transcoder = null
        super.onDestroy()
    }
}
