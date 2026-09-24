package com.vicintelligentsia.vicconnect

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.content.pm.ServiceInfo
import android.media.AudioAttributes
import android.media.RingtoneManager
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import androidx.core.app.NotificationCompat
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import java.time.Instant
import java.time.OffsetDateTime

private const val PREFS_NAME = "vic_connect_local"
private const val PREF_CURSOR = "notification_cursor"
private const val PREF_SEEN = "notified_ids"
private const val CHANNEL_BACKGROUND = "vic_background"
private const val CHANNEL_MESSAGES = "vic_messages_v2"
private const val SERVICE_NOTIFICATION_ID = 1001
private const val POLL_INTERVAL_MS = 30_000L

/** Lit une date renvoyée par Supabase (ex. 2026-09-22T10:37:12.123456+00:00) sans jamais planter. */
private fun parseServerInstant(raw: String): Instant =
    runCatching { OffsetDateTime.parse(raw).toInstant() }
        .getOrElse { runCatching { Instant.parse(raw) }.getOrElse { Instant.EPOCH } }

/**
 * Service de premier plan : surveille les nouveaux messages (Direction, parents, enseignants)
 * et affiche une vraie notification système (bannière en haut de l'écran, son, vibration),
 * même quand l'application est fermée ou en arrière-plan.
 */
class VicNotificationService : Service() {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private var pollJob: Job? = null
    private val api by lazy { VicApi() }

    override fun onCreate() {
        super.onCreate()
        createNotificationChannels(this)
        val notification = serviceNotification()
        if (Build.VERSION.SDK_INT >= 34) {
            startForeground(SERVICE_NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_REMOTE_MESSAGING)
        } else {
            startForeground(SERVICE_NOTIFICATION_ID, notification)
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val code = prefs.getString("last_access_code", "") ?: ""
        val role = prefs.getString("last_role", "") ?: ""
        if (code.isBlank() || role.isBlank()) {
            stopSelf()
            return START_NOT_STICKY
        }

        // Une seule boucle de surveillance à la fois (évite les doublons à chaque ouverture de l'app).
        pollJob?.cancel()
        pollJob = scope.launch { pollLoop(prefs, code, role) }
        return START_STICKY
    }

    private suspend fun pollLoop(prefs: SharedPreferences, code: String, role: String) {
        var since = prefs.getString(PREF_CURSOR, "")?.takeIf { it.isNotBlank() }
            ?: Instant.now().minusSeconds(90).toString()

        while (currentCoroutineContext().isActive) {
            val lock = acquireShortWakeLock()
            try {
                val incoming = api.mobileNotifications(code, role, since)
                if (incoming.isNotEmpty()) {
                    val seen = loadSeen(prefs)
                    incoming.sortedBy { parseServerInstant(it.createdAt) }.forEach { item ->
                        if (!seen.contains(item.id)) {
                            showIncoming(item)
                            seen.add(item.id)
                        }
                    }
                    saveSeen(prefs, seen)
                    val newest = incoming.maxOf { parseServerInstant(it.createdAt) }
                    if (newest.isAfter(Instant.EPOCH)) {
                        since = newest.toString()
                        prefs.edit().putString(PREF_CURSOR, since).apply()
                    }
                }
            } catch (_: Exception) {
                // Réseau indisponible : nouvelle tentative au prochain cycle.
            } finally {
                runCatching { if (lock?.isHeld == true) lock.release() }
            }
            delay(POLL_INTERVAL_MS)
        }
    }

    private fun acquireShortWakeLock(): PowerManager.WakeLock? = runCatching {
        val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
        pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "VicConnect:poll").apply { acquire(25_000L) }
    }.getOrNull()

    private fun loadSeen(prefs: SharedPreferences): MutableList<String> =
        (prefs.getString(PREF_SEEN, "") ?: "").split(',').filter { it.isNotBlank() }.toMutableList()

    private fun saveSeen(prefs: SharedPreferences, seen: List<String>) {
        prefs.edit().putString(PREF_SEEN, seen.takeLast(120).joinToString(",")).apply()
    }

    private fun serviceNotification(): Notification {
        val pending = PendingIntent.getActivity(
            this, 0, Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        return NotificationCompat.Builder(this, CHANNEL_BACKGROUND)
            .setSmallIcon(R.drawable.ic_stat_vic)
            .setColor(0xFF0E4B3A.toInt())
            .setContentTitle("VIC-CONNECT")
            .setContentText("Vous serez averti(e) des nouveaux messages")
            .setContentIntent(pending)
            .setOngoing(true)
            .setSilent(true)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .build()
    }

    private fun showIncoming(item: MobileNotification) {
        val notificationId = item.id.hashCode()
        val openApp = PendingIntent.getActivity(
            this, notificationId,
            Intent(this, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
            },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val title = item.title.ifBlank { "Nouveau message — VIC-CONNECT" }
        val notification = NotificationCompat.Builder(this, CHANNEL_MESSAGES)
            .setSmallIcon(R.drawable.ic_stat_vic)
            .setColor(0xFF0E4B3A.toInt())
            .setContentTitle(title)
            .setContentText(item.body)
            .setStyle(NotificationCompat.BigTextStyle().bigText(item.body))
            .setContentIntent(openApp)
            .setAutoCancel(true)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setDefaults(NotificationCompat.DEFAULT_ALL)
            .setCategory(NotificationCompat.CATEGORY_MESSAGE)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setWhen(System.currentTimeMillis())
            .setShowWhen(true)
            .build()
        getSystemService(NotificationManager::class.java).notify(notificationId, notification)
    }

    override fun onDestroy() {
        pollJob?.cancel()
        scope.cancel()
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null
}

/** Crée les canaux de notification (Android 8+). Le canal « messages » est en importance HAUTE = bannière en haut de l'écran. */
fun createNotificationChannels(context: Context) {
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
    val manager = context.getSystemService(NotificationManager::class.java)
    manager.createNotificationChannel(
        NotificationChannel(CHANNEL_BACKGROUND, "VIC-CONNECT (service)", NotificationManager.IMPORTANCE_LOW).apply {
            description = "Maintient VIC-CONNECT à l'écoute des nouveaux messages"
            setShowBadge(false)
        }
    )
    manager.createNotificationChannel(
        NotificationChannel(CHANNEL_MESSAGES, "Messages VIC-CONNECT", NotificationManager.IMPORTANCE_HIGH).apply {
            description = "Messages de la Direction, des parents et des enseignants"
            enableVibration(true)
            vibrationPattern = longArrayOf(0, 300, 200, 300)
            enableLights(true)
            lightColor = 0xFFC9D84A.toInt()
            lockscreenVisibility = Notification.VISIBILITY_PUBLIC
            setShowBadge(true)
            setSound(
                RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION),
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_NOTIFICATION)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                    .build()
            )
        }
    )
    // Ancien canal des versions précédentes.
    manager.deleteNotificationChannel("vic_messages")
}

/** Relance la surveillance après un redémarrage du téléphone ou une mise à jour de l'application. */
class VicBootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        val action = intent?.action ?: return
        if (action != Intent.ACTION_BOOT_COMPLETED &&
            action != Intent.ACTION_MY_PACKAGE_REPLACED &&
            action != "android.intent.action.QUICKBOOT_POWERON"
        ) return
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val hasSession = !prefs.getString("last_access_code", "").isNullOrBlank() &&
            !prefs.getString("last_role", "").isNullOrBlank()
        if (hasSession) startVicNotificationService(context)
    }
}

fun startVicNotificationService(context: Context) {
    runCatching {
        val intent = Intent(context, VicNotificationService::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) context.startForegroundService(intent) else context.startService(intent)
    }
}

fun stopVicNotificationService(context: Context) {
    runCatching { context.stopService(Intent(context, VicNotificationService::class.java)) }
}
