package com.adriano.lumemusic.platform

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import com.adriano.lumemusic.MainActivity
import com.adriano.lumemusic.R
import com.adriano.lumemusic.data.DownloadManager
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch

/** Mantém o processo vivo e mostra o progresso enquanto há downloads offline em andamento. */
class DownloadService : Service() {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private var job: Job? = null

    companion object {
        private const val CHANNEL = "lume_downloads"
        private const val ID = 4201
        @Volatile private var running = false

        fun sync(context: Context, active: Boolean) {
            if (active && !running) {
                running = true
                try { ContextCompat.startForegroundService(context, Intent(context, DownloadService::class.java)) }
                catch (_: Exception) { running = false }
            }
            // parada é feita pelo próprio serviço quando a fila zera
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        ensureChannel()
        val n = notification()
        if (Build.VERSION.SDK_INT >= 29) startForeground(ID, n, ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC) else startForeground(ID, n)
        if (job?.isActive != true) job = scope.launch {
            while (isActive) {
                if (DownloadManager.activeCount == 0 || DownloadManager.paused) { delay(800); if (DownloadManager.activeCount == 0 || DownloadManager.paused) break }
                getSystemService(NotificationManager::class.java).notify(ID, notification())
                delay(700)
            }
            running = false
            stopForeground(STOP_FOREGROUND_REMOVE)
            stopSelf()
        }
        return START_NOT_STICKY
    }

    private fun ensureChannel() {
        val nm = getSystemService(NotificationManager::class.java)
        if (nm.getNotificationChannel(CHANNEL) == null) {
            nm.createNotificationChannel(NotificationChannel(CHANNEL, getString(R.string.notif_channel_downloads), NotificationManager.IMPORTANCE_LOW))
        }
    }

    private fun notification(): Notification {
        val open = PendingIntent.getActivity(this, 1, Intent(this, MainActivity::class.java), PendingIntent.FLAG_IMMUTABLE)
        val pending = DownloadManager.pendingCount
        val pct = (DownloadManager.overallProgress * 100).toInt().coerceIn(0, 100)
        return NotificationCompat.Builder(this, CHANNEL)
            .setSmallIcon(R.drawable.ic_stat_lume)
            .setContentTitle("Baixando músicas")
            .setContentText(if (pending > 0) "$pending na fila · $pct%" else "Finalizando…")
            .setProgress(100, pct, pending == 0)
            .setOngoing(true).setOnlyAlertOnce(true).setContentIntent(open).build()
    }

    override fun onDestroy() { scope.coroutineContext[Job]?.cancel(); running = false; super.onDestroy() }
}
