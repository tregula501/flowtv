package io.github.tregula501.flowtv

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.net.wifi.WifiManager
import android.os.Build
import android.os.IBinder
import android.os.PowerManager

/**
 * Foreground service held while a Chromecast session is active.
 *
 * Casting TS/Xtream channels runs an on-device HLS proxy (Dart HTTP server +
 * ffmpeg child process) that the Chromecast pulls segments from. Without this
 * service the app becomes a cached background process as soon as the screen
 * turns off; Doze then suspends CPU/network, ffmpeg stalls, and the receiver
 * starves within its ~10s live window. The service + partial wakelock +
 * Wi-Fi lock keep the pipeline running with the screen off.
 */
class CastForegroundService : Service() {

    companion object {
        const val ACTION_START = "io.github.tregula501.flowtv.cast.START"
        const val EXTRA_DEVICE_NAME = "deviceName"
        const val EXTRA_TITLE = "title"

        private const val CHANNEL_ID = "flowtv_casting"
        private const val NOTIFICATION_ID = 1001
        private const val LOCK_TAG = "FlowTV:cast"
    }

    private var wakeLock: PowerManager.WakeLock? = null
    private var wifiLock: WifiManager.WifiLock? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val deviceName = intent?.getStringExtra(EXTRA_DEVICE_NAME) ?: "Chromecast"
        val title = intent?.getStringExtra(EXTRA_TITLE)

        startAsForeground(deviceName, title)
        acquireLocks()

        // If the system kills us, a restart without the Dart side (which owns
        // the proxy and the cast session) would just hold locks uselessly.
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        releaseLocks()
        super.onDestroy()
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        // App swiped away: the Dart engine is gone, nothing left to keep alive.
        stopSelf()
        super.onTaskRemoved(rootIntent)
    }

    private fun startAsForeground(deviceName: String, title: String?) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            manager.createNotificationChannel(
                NotificationChannel(
                    CHANNEL_ID,
                    "Casting",
                    NotificationManager.IMPORTANCE_LOW,
                ).apply {
                    description = "Shown while casting to a Chromecast device"
                    setShowBadge(false)
                },
            )
        }

        val contentIntent = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java)
                .addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
        val notification = builder
            .setSmallIcon(applicationInfo.icon)
            .setContentTitle("Casting to $deviceName")
            .apply { if (!title.isNullOrBlank()) setContentText(title) }
            .setContentIntent(contentIntent)
            .setOngoing(true)
            .build()

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK,
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    private fun acquireLocks() {
        if (wakeLock == null) {
            val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
            wakeLock = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, LOCK_TAG).apply {
                setReferenceCounted(false)
                acquire()
            }
        }
        if (wifiLock == null) {
            val wm = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
            // HIGH_PERF is deprecated but is the only mode that keeps Wi-Fi
            // fully awake with the screen off (LOW_LATENCY only applies while
            // the acquiring app is foreground with the screen on).
            @Suppress("DEPRECATION")
            wifiLock = wm.createWifiLock(WifiManager.WIFI_MODE_FULL_HIGH_PERF, LOCK_TAG).apply {
                setReferenceCounted(false)
                acquire()
            }
        }
    }

    private fun releaseLocks() {
        wakeLock?.let { if (it.isHeld) it.release() }
        wakeLock = null
        wifiLock?.let { if (it.isHeld) it.release() }
        wifiLock = null
    }
}
