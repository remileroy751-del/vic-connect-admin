package com.vicintelligentsia.vicconnect

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import java.time.Instant
import java.time.temporal.ChronoUnit


class VicNotificationService : Service() {
    private val job = SupervisorJob()
    private val scope = CoroutineScope(Dispatchers.IO + job)
    private val api by lazy { VicApi() }

    override fun onCreate() {
        super.onCreate()
        createChannels()
        startForeground(1001, serviceNotification())
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val prefs = getSharedPreferences("vic_connect_local", Context.MODE_PRIVATE)
        val code = prefs.getString("last_access_code", "") ?: ""
        val role = prefs.getString("last_role", "") ?: ""
        if (code.isBlank() || role.isBlank()) {
            stopSelf()
            return START_NOT_STICKY
        }

        scope.launch {
            var since = prefs.getString("notification_cursor", "")
                ?.takeIf { it.isNotBlank() }
                ?: Instant.now().minus(2, ChronoUnit.MINUTES).toString()

            while (isActive) {
                try {
                    val incoming = api.mobileNotifications(code, role, since)
                    incoming.forEach { showIncoming(it) }
                    if (incoming.isNotEmpty()) {
                        since = incoming.maxBy { it.createdAt }.createdAt
                        prefs.edit().putString("notification_cursor", since).apply()
                    }
                } catch (_: Exception) {
                    // Le service réessaiera automatiquement.
                }
                delay(30_000L)
            }
        }
        return START_STICKY
    }

    private fun createChannels() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val manager = getSystemService(NotificationManager::class.java)
            manager.createNotificationChannel(
                NotificationChannel("vic_background", "VIC-CONNECT", NotificationManager.IMPORTANCE_LOW).apply {
                    description = "Surveillance des nouveaux messages VIC-CONNECT"
                    setShowBadge(false)
                }
            )
            manager.createNotificationChannel(
                NotificationChannel("vic_messages", "Messages VIC-CONNECT", NotificationManager.IMPORTANCE_HIGH).apply {
                    description = "Messages de la Direction, des parents et des enseignants"
                    enableVibration(true)
                }
            )
        }
    }

    private fun serviceNotification(): Notification {
        val pending = PendingIntent.getActivity(
            this, 0, Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        return NotificationCompat.Builder(this, "vic_background")
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setContentTitle("VIC-CONNECT")
            .setContentText("Service de notifications actif")
            .setContentIntent(pending)
            .setOngoing(true)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .build()
    }

    private fun showIncoming(item: MobileNotification) {
        val notificationId = item.id.hashCode()
        val pending = PendingIntent.getActivity(
            this, notificationId, Intent(this, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
            }, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val notification = NotificationCompat.Builder(this, "vic_messages")
            .setSmallIcon(android.R.drawable.ic_dialog_email)
            .setContentTitle(item.title.ifBlank { "Nouveau message — VIC-CONNECT" })
            .setContentText(item.body)
            .setStyle(NotificationCompat.BigTextStyle().bigText(item.body))
            .setContentIntent(pending)
            .setAutoCancel(true)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .build()
        getSystemService(NotificationManager::class.java).notify(notificationId, notification)
    }

    override fun onDestroy() {
        scope.cancel()
        job.cancel()
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null
}

fun startVicNotificationService(context: Context) {
    val intent = Intent(context, VicNotificationService::class.java)
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) context.startForegroundService(intent) else context.startService(intent)
}

fun stopVicNotificationService(context: Context) {
    context.stopService(Intent(context, VicNotificationService::class.java))
}
