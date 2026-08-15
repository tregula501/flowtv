package io.github.tregula501.flowtv

import android.content.Intent
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    companion object {
        private const val CAST_FOREGROUND_CHANNEL = "flowtv/cast_foreground"
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CAST_FOREGROUND_CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "start" -> {
                    val intent = Intent(this, CastForegroundService::class.java)
                        .setAction(CastForegroundService.ACTION_START)
                        .putExtra(
                            CastForegroundService.EXTRA_DEVICE_NAME,
                            call.argument<String>("deviceName"),
                        )
                        .putExtra(
                            CastForegroundService.EXTRA_TITLE,
                            call.argument<String>("title"),
                        )
                    try {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            startForegroundService(intent)
                        } else {
                            startService(intent)
                        }
                        result.success(true)
                    } catch (e: Exception) {
                        // e.g. ForegroundServiceStartNotAllowedException when the
                        // app is backgrounded on API 31+.
                        result.error("START_FAILED", e.message, null)
                    }
                }
                "stop" -> {
                    stopService(Intent(this, CastForegroundService::class.java))
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }
}
