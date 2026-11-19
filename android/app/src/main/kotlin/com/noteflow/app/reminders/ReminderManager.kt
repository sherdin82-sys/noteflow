package com.noteflow.app.reminders

import android.app.AlarmManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.os.Build
import androidx.core.app.NotificationCompat
import com.noteflow.app.MainActivity

object ReminderManager {
    const val CHANNEL_ID = "noteflow_reminders_channel"
    const val CHANNEL_NAME = "NoteFlow Reminders"
    const val CHANNEL_DESC = "Notifications for NoteFlow note, checklist, and audio reminders"

    const val EXTRA_NOTIFICATION_ID = "extra_notification_id"
    const val EXTRA_TITLE = "extra_title"
    const val EXTRA_BODY = "extra_body"
    const val EXTRA_NOTE_ID = "extra_note_id"
    const val EXTRA_CHECKLIST_ITEM_ID = "extra_checklist_item_id"
    const val EXTRA_VOICE_RECORDING_ID = "extra_voice_recording_id"
    const val EXTRA_ACTION_TYPE = "extra_action_type"

    const val ACTION_SNOOZE = "com.noteflow.app.ACTION_SNOOZE"
    const val ACTION_MARK_DONE = "com.noteflow.app.ACTION_MARK_DONE"

    fun createNotificationChannel(context: Context) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val notificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            val existing = notificationManager.getNotificationChannel(CHANNEL_ID)
            if (existing == null) {
                val channel = NotificationChannel(
                    CHANNEL_ID,
                    CHANNEL_NAME,
                    NotificationManager.IMPORTANCE_HIGH
                ).apply {
                    description = CHANNEL_DESC
                    enableLights(true)
                    lightColor = Color.parseColor("#2563EB")
                    enableVibration(true)
                    vibrationPattern = longArrayOf(0, 250, 200, 250)
                    lockscreenVisibility = Notification.VISIBILITY_PUBLIC
                }
                notificationManager.createNotificationChannel(channel)
            }
        }
    }

    fun canScheduleExactAlarms(context: Context): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
            alarmManager.canScheduleExactAlarms()
        } else {
            true
        }
    }

    fun scheduleAlarm(
        context: Context,
        notificationId: Int,
        triggerEpochMs: Long,
        title: String,
        body: String,
        noteId: String,
        checklistItemId: String?,
        voiceRecordingId: String?
    ) {
        createNotificationChannel(context)

        val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager

        val intent = Intent(context, AlarmReceiver::class.java).apply {
            putExtra(EXTRA_NOTIFICATION_ID, notificationId)
            putExtra(EXTRA_TITLE, title)
            putExtra(EXTRA_BODY, body)
            putExtra(EXTRA_NOTE_ID, noteId)
            putExtra(EXTRA_CHECKLIST_ITEM_ID, checklistItemId)
            putExtra(EXTRA_VOICE_RECORDING_ID, voiceRecordingId)
        }

        val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        } else {
            PendingIntent.FLAG_UPDATE_CURRENT
        }

        val pendingIntent = PendingIntent.getBroadcast(
            context,
            notificationId,
            intent,
            flags
        )

        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                if (alarmManager.canScheduleExactAlarms()) {
                    alarmManager.setExactAndAllowWhileIdle(
                        AlarmManager.RTC_WAKEUP,
                        triggerEpochMs,
                        pendingIntent
                    )
                } else {
                    // Safe fallback for Android 14+ if user revoked exact alarms
                    alarmManager.setAndAllowWhileIdle(
                        AlarmManager.RTC_WAKEUP,
                        triggerEpochMs,
                        pendingIntent
                    )
                }
            } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                alarmManager.setExactAndAllowWhileIdle(
                    AlarmManager.RTC_WAKEUP,
                    triggerEpochMs,
                    pendingIntent
                )
            } else {
                alarmManager.setExact(
                    AlarmManager.RTC_WAKEUP,
                    triggerEpochMs,
                    pendingIntent
                )
            }
        } catch (e: SecurityException) {
            // In case of unexpected permission revocation, fall back gracefully
            alarmManager.set(
                AlarmManager.RTC_WAKEUP,
                triggerEpochMs,
                pendingIntent
            )
        }
    }

    fun cancelAlarm(context: Context, notificationId: Int) {
        val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val intent = Intent(context, AlarmReceiver::class.java)

        val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        } else {
            PendingIntent.FLAG_UPDATE_CURRENT
        }

        val pendingIntent = PendingIntent.getBroadcast(
            context,
            notificationId,
            intent,
            flags
        )

        alarmManager.cancel(pendingIntent)
        pendingIntent.cancel()

        // Also cancel any active alert currently visible in the system tray
        val notificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        notificationManager.cancel(notificationId)
    }

    fun buildNotification(
        context: Context,
        notificationId: Int,
        title: String,
        body: String,
        noteId: String,
        checklistItemId: String?,
        voiceRecordingId: String?
    ): Notification {
        createNotificationChannel(context)

        // Content Intent: Open MainActivity with deep link payload
        val openIntent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
            putExtra(EXTRA_NOTE_ID, noteId)
            putExtra(EXTRA_CHECKLIST_ITEM_ID, checklistItemId)
            putExtra(EXTRA_VOICE_RECORDING_ID, voiceRecordingId)
            putExtra(EXTRA_NOTIFICATION_ID, notificationId)
        }

        val piFlags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        } else {
            PendingIntent.FLAG_UPDATE_CURRENT
        }

        val contentPendingIntent = PendingIntent.getActivity(
            context,
            notificationId,
            openIntent,
            piFlags
        )

        // Action 1: Snooze 15 minutes
        val snoozeIntent = Intent(context, NotificationActionReceiver::class.java).apply {
            action = ACTION_SNOOZE
            putExtra(EXTRA_NOTIFICATION_ID, notificationId)
            putExtra(EXTRA_TITLE, title)
            putExtra(EXTRA_BODY, body)
            putExtra(EXTRA_NOTE_ID, noteId)
            putExtra(EXTRA_CHECKLIST_ITEM_ID, checklistItemId)
            putExtra(EXTRA_VOICE_RECORDING_ID, voiceRecordingId)
        }
        val snoozePendingIntent = PendingIntent.getBroadcast(
            context,
            notificationId * 10 + 1,
            snoozeIntent,
            piFlags
        )

        // Action 2: Mark Done
        val doneIntent = Intent(context, NotificationActionReceiver::class.java).apply {
            action = ACTION_MARK_DONE
            putExtra(EXTRA_NOTIFICATION_ID, notificationId)
            putExtra(EXTRA_NOTE_ID, noteId)
            putExtra(EXTRA_CHECKLIST_ITEM_ID, checklistItemId)
            putExtra(EXTRA_VOICE_RECORDING_ID, voiceRecordingId)
        }
        val donePendingIntent = PendingIntent.getBroadcast(
            context,
            notificationId * 10 + 2,
            doneIntent,
            piFlags
        )

        val smallIconRes = context.resources.getIdentifier(
            "ic_launcher_foreground",
            "drawable",
            context.packageName
        ).let { if (it != 0) it else android.R.drawable.ic_lock_idle_alarm }

        return NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(smallIconRes)
            .setContentTitle(if (title.isNotEmpty()) title else "Note Reminder")
            .setContentText(body)
            .setStyle(NotificationCompat.BigTextStyle().bigText(body))
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setCategory(NotificationCompat.CATEGORY_REMINDER)
            .setAutoCancel(true)
            .setColor(Color.parseColor("#2563EB"))
            .setContentIntent(contentPendingIntent)
            .addAction(android.R.drawable.ic_popup_sync, "Snooze 15m", snoozePendingIntent)
            .addAction(android.R.drawable.checkbox_on_background, "Mark Done", donePendingIntent)
            .build()
    }
}
