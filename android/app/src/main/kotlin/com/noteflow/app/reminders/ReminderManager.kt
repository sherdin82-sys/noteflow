package com.noteflow.app.reminders

import android.app.AlarmManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.media.AudioAttributes
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.app.NotificationCompat
import com.noteflow.app.MainActivity

object ReminderManager {
    const val CHANNEL_ID = "noteflow_reminders_channel_v2"
    const val LEGACY_CHANNEL_ID = "noteflow_reminders_channel"
    const val CHANNEL_NAME = "NoteFlow Reminders"
    const val CHANNEL_DESC = "Notifications for NoteFlow note, checklist, and audio reminders"

    const val EXTRA_NOTIFICATION_ID = "extra_notification_id"
    const val EXTRA_TITLE = "extra_title"
    const val EXTRA_BODY = "extra_body"
    const val EXTRA_NOTE_ID = "extra_note_id"
    const val EXTRA_CHECKLIST_ITEM_ID = "extra_checklist_item_id"
    const val EXTRA_VOICE_RECORDING_ID = "extra_voice_recording_id"
    const val EXTRA_ACTION_TYPE = "extra_action_type"
    const val EXTRA_OCCURRENCE_EPOCH_MS = "extra_occurrence_epoch_ms"

    const val ACTION_TRIGGER_ALARM = "com.noteflow.app.TRIGGER_ALARM"
    const val ACTION_OPEN_REMINDER = "com.noteflow.app.OPEN_REMINDER"
    const val ACTION_OPEN_OVERDUE = "com.noteflow.app.OPEN_OVERDUE"
    const val ACTION_SNOOZE = "com.noteflow.app.ACTION_SNOOZE"
    const val ACTION_MARK_DONE = "com.noteflow.app.ACTION_MARK_DONE"

    const val MISSED_SUMMARY_NOTIFICATION_ID = 999999

    const val PREFS_SETTINGS_NAME = "noteflow_reminder_settings"
    const val KEY_SHOW_LOCKSCREEN_PREVIEWS = "show_lockscreen_previews"

    fun createNotificationChannel(context: Context) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val notificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

            val existing = notificationManager.getNotificationChannel(CHANNEL_ID)
            if (existing == null) {
                // If legacy channel exists, migrate user's custom settings (sound, vibration, importance)
                val legacy = try {
                    notificationManager.getNotificationChannel(LEGACY_CHANNEL_ID)
                } catch (_: Exception) {
                    null
                }

                val importance = legacy?.importance ?: NotificationManager.IMPORTANCE_HIGH

                val channel = NotificationChannel(
                    CHANNEL_ID,
                    CHANNEL_NAME,
                    importance
                ).apply {
                    description = CHANNEL_DESC
                    enableLights(true)
                    lightColor = Color.parseColor("#2563EB")
                    lockscreenVisibility = Notification.VISIBILITY_PRIVATE

                    if (legacy != null) {
                        enableVibration(legacy.shouldVibrate())
                        if (legacy.vibrationPattern != null) {
                            vibrationPattern = legacy.vibrationPattern
                        }
                        if (legacy.sound != null) {
                            setSound(legacy.sound, legacy.audioAttributes)
                        } else {
                            // User previously configured channel to be silent
                            setSound(null, null)
                        }
                    } else {
                        // Fresh channel: respect system vibration defaults without rigid hardcoded pattern
                        enableVibration(true)
                        val audioAttributes = AudioAttributes.Builder()
                            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                            .setUsage(AudioAttributes.USAGE_NOTIFICATION_EVENT)
                            .build()
                        setSound(Settings.System.DEFAULT_NOTIFICATION_URI, audioAttributes)
                    }
                }
                notificationManager.createNotificationChannel(channel)

                // Safely remove legacy channel after migrating preferences
                if (legacy != null) {
                    try {
                        notificationManager.deleteNotificationChannel(LEGACY_CHANNEL_ID)
                    } catch (_: Exception) {}
                }
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
            action = ACTION_TRIGGER_ALARM
            data = Uri.parse("noteflow://alarm/$notificationId")
            putExtra(EXTRA_NOTIFICATION_ID, notificationId)
            putExtra(EXTRA_TITLE, title)
            putExtra(EXTRA_BODY, body)
            putExtra(EXTRA_NOTE_ID, noteId)
            putExtra(EXTRA_CHECKLIST_ITEM_ID, checklistItemId)
            putExtra(EXTRA_VOICE_RECORDING_ID, voiceRecordingId)
            putExtra(EXTRA_OCCURRENCE_EPOCH_MS, triggerEpochMs)
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
        val intent = Intent(context, AlarmReceiver::class.java).apply {
            action = ACTION_TRIGGER_ALARM
            data = Uri.parse("noteflow://alarm/$notificationId")
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
        voiceRecordingId: String?,
        occurrenceEpochMs: Long = -1L
    ): Notification {
        createNotificationChannel(context)

        val piFlags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        } else {
            PendingIntent.FLAG_UPDATE_CURRENT
        }

        // Content Intent: Open MainActivity with deep link payload
        val openIntent = Intent(context, MainActivity::class.java).apply {
            action = ACTION_OPEN_REMINDER
            data = Uri.parse("noteflow://tap/$notificationId")
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
            putExtra(EXTRA_NOTE_ID, noteId)
            putExtra(EXTRA_CHECKLIST_ITEM_ID, checklistItemId)
            putExtra(EXTRA_VOICE_RECORDING_ID, voiceRecordingId)
            putExtra(EXTRA_NOTIFICATION_ID, notificationId)
            putExtra(EXTRA_OCCURRENCE_EPOCH_MS, occurrenceEpochMs)
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
            data = Uri.parse("noteflow://snooze/$notificationId")
            putExtra(EXTRA_NOTIFICATION_ID, notificationId)
            putExtra(EXTRA_TITLE, title)
            putExtra(EXTRA_BODY, body)
            putExtra(EXTRA_NOTE_ID, noteId)
            putExtra(EXTRA_CHECKLIST_ITEM_ID, checklistItemId)
            putExtra(EXTRA_VOICE_RECORDING_ID, voiceRecordingId)
            putExtra(EXTRA_OCCURRENCE_EPOCH_MS, occurrenceEpochMs)
        }
        val snoozePendingIntent = PendingIntent.getBroadcast(
            context,
            notificationId,
            snoozeIntent,
            piFlags
        )

        // Action 2: Mark Done
        val doneIntent = Intent(context, NotificationActionReceiver::class.java).apply {
            action = ACTION_MARK_DONE
            data = Uri.parse("noteflow://done/$notificationId")
            putExtra(EXTRA_NOTIFICATION_ID, notificationId)
            putExtra(EXTRA_NOTE_ID, noteId)
            putExtra(EXTRA_CHECKLIST_ITEM_ID, checklistItemId)
            putExtra(EXTRA_VOICE_RECORDING_ID, voiceRecordingId)
            putExtra(EXTRA_OCCURRENCE_EPOCH_MS, occurrenceEpochMs)
        }
        val donePendingIntent = PendingIntent.getBroadcast(
            context,
            notificationId,
            doneIntent,
            piFlags
        )

        val smallIconRes = context.resources.getIdentifier(
            "ic_launcher_foreground",
            "drawable",
            context.packageName
        ).let { if (it != 0) it else android.R.drawable.ic_lock_idle_alarm }

        val prefs = context.getSharedPreferences(PREFS_SETTINGS_NAME, Context.MODE_PRIVATE)
        val showPreview = prefs.getBoolean(KEY_SHOW_LOCKSCREEN_PREVIEWS, false)

        // Public Redacted Notification (Shown on secure lock screen)
        val publicNotification = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(smallIconRes)
            .setContentTitle("NoteFlow Reminder")
            .setContentText("You have a scheduled reminder")
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setColor(Color.parseColor("#2563EB"))
            .build()

        return NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(smallIconRes)
            .setContentTitle(if (showPreview || title.isNotEmpty()) (if (title.isNotEmpty()) title else "Note Reminder") else "NoteFlow Reminder")
            .setContentText(if (showPreview || body.isNotEmpty()) body else "You have a scheduled reminder")
            .setStyle(NotificationCompat.BigTextStyle().bigText(body))
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setCategory(NotificationCompat.CATEGORY_REMINDER)
            .setDefaults(NotificationCompat.DEFAULT_ALL)
            .setVisibility(if (showPreview) NotificationCompat.VISIBILITY_PUBLIC else NotificationCompat.VISIBILITY_PRIVATE)
            .setPublicVersion(publicNotification)
            .setAutoCancel(true)
            .setColor(Color.parseColor("#2563EB"))
            .setContentIntent(contentPendingIntent)
            .addAction(android.R.drawable.ic_popup_sync, "Snooze 15m", snoozePendingIntent)
            .addAction(android.R.drawable.checkbox_on_background, "Mark Done", donePendingIntent)
            .build()
    }

    fun buildMissedSummaryNotification(
        context: Context,
        count: Int
    ): Notification {
        createNotificationChannel(context)

        val piFlags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        } else {
            PendingIntent.FLAG_UPDATE_CURRENT
        }

        val openIntent = Intent(context, MainActivity::class.java).apply {
            action = ACTION_OPEN_OVERDUE
            data = Uri.parse("noteflow://overdue_reminders")
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
            putExtra(EXTRA_ACTION_TYPE, "open_overdue")
            putExtra("initialTabIndex", 2)
        }

        val contentPendingIntent = PendingIntent.getActivity(
            context,
            MISSED_SUMMARY_NOTIFICATION_ID,
            openIntent,
            piFlags
        )

        val smallIconRes = context.resources.getIdentifier(
            "ic_launcher_foreground",
            "drawable",
            context.packageName
        ).let { if (it != 0) it else android.R.drawable.ic_lock_idle_alarm }

        val prefs = context.getSharedPreferences(PREFS_SETTINGS_NAME, Context.MODE_PRIVATE)
        val showPreview = prefs.getBoolean(KEY_SHOW_LOCKSCREEN_PREVIEWS, false)

        val title = "$count Missed Reminders"
        val body = "Tap to view tasks that expired while your device was off"

        val publicNotification = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(smallIconRes)
            .setContentTitle("NoteFlow Reminders")
            .setContentText("You have missed reminders")
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setColor(Color.parseColor("#2563EB"))
            .build()

        return NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(smallIconRes)
            .setContentTitle(if (showPreview) title else "NoteFlow Reminders")
            .setContentText(if (showPreview) body else "You have missed reminders")
            .setStyle(NotificationCompat.BigTextStyle().bigText(body))
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setCategory(NotificationCompat.CATEGORY_REMINDER)
            .setDefaults(NotificationCompat.DEFAULT_ALL)
            .setVisibility(if (showPreview) NotificationCompat.VISIBILITY_PUBLIC else NotificationCompat.VISIBILITY_PRIVATE)
            .setPublicVersion(publicNotification)
            .setAutoCancel(true)
            .setColor(Color.parseColor("#2563EB"))
            .setContentIntent(contentPendingIntent)
            .build()
    }
}
