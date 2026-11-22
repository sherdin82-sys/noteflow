package com.noteflow.app.reminders

import android.app.AlarmManager
import android.app.NotificationManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.core.app.NotificationManagerCompat
import org.json.JSONObject
import java.io.File
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Locale
import java.util.TimeZone

class BootReceiver : BroadcastReceiver() {

    companion object {
        @Volatile
        var customDocumentsDir: File? = null

        /**
         * Resolves the authoritative NoteFlow JSON data file.
         * 1. Verified custom documents directory (if provided by runtime verification)
         * 2. Canonical Flutter documents directory: context.getDir("app_flutter", Context.MODE_PRIVATE)
         * 3. Fallback standard internal filesDir
         */
        fun getAuthoritativeDataFile(context: Context): File? {
            val customDir = customDocumentsDir
            if (customDir != null) {
                val customFile = File(customDir, "noteflow_data.json")
                if (customFile.exists() && customFile.length() > 0) return customFile
            }

            val flutterDir = context.getDir("app_flutter", Context.MODE_PRIVATE)
            val canonicalFile = File(flutterDir, "noteflow_data.json")
            if (canonicalFile.exists() && canonicalFile.length() > 0) return canonicalFile

            val fallbackFile = File(context.filesDir, "noteflow_data.json")
            if (fallbackFile.exists() && fallbackFile.length() > 0) return fallbackFile

            return null
        }

        fun rearmActiveReminders(context: Context, isBootAction: Boolean = false) {
        try {
            val dataFile = getAuthoritativeDataFile(context) ?: return
            val content = dataFile.readText(Charsets.UTF_8)
            if (content.isBlank()) return

            val root = JSONObject(content)
            if (!root.has("reminders")) return

            val remindersArray = root.getJSONArray("reminders")
            val now = System.currentTimeMillis()
            val graceWindowMs = 24 * 60 * 60 * 1000L // 24-hour grace window

            val missedReminders = mutableListOf<MissedReminder>()
            var jsonModified = false

            for (i in 0 until remindersArray.length()) {
                val rem = remindersArray.getJSONObject(i)
                val isCompleted = rem.optBoolean("is_completed", false) || rem.optInt("is_completed", 0) == 1
                if (isCompleted) continue

                val notificationId = rem.optInt("notification_id", -1)
                if (notificationId <= 0) continue

                val title = rem.optString("title", "Note Reminder")
                val body = rem.optString("notes_preview", "")
                val noteId = rem.optString("note_id", "")
                val checklistItemId = if (rem.has("checklist_item_id") && !rem.isNull("checklist_item_id")) rem.getString("checklist_item_id") else null
                val voiceRecordingId = if (rem.has("voice_recording_id") && !rem.isNull("voice_recording_id")) rem.getString("voice_recording_id") else null

                val repeatMode = rem.optString("repeat_mode", "never")
                val isRecurring = repeatMode.isNotBlank() &&
                    !repeatMode.equals("never", ignoreCase = true) &&
                    !repeatMode.equals("none", ignoreCase = true)

                // Determine target trigger time: snoozed_until takes precedence if set
                val snoozedUntilStr = rem.optString("snoozed_until", "")
                val scheduledAtStr = rem.optString("scheduled_at", "")

                var triggerTimeMs: Long = -1

                if (snoozedUntilStr.isNotBlank()) {
                    triggerTimeMs = parseToEpochMs(snoozedUntilStr)
                }

                if (triggerTimeMs <= 0 && scheduledAtStr.isNotBlank()) {
                    triggerTimeMs = parseToEpochMs(scheduledAtStr)
                }

                if (triggerTimeMs <= 0) continue

                if (triggerTimeMs > now) {
                    // Future reminder: re-schedule with AlarmManager
                    ReminderManager.scheduleAlarm(
                        context = context,
                        notificationId = notificationId,
                        triggerEpochMs = triggerTimeMs,
                        title = title,
                        body = body,
                        noteId = noteId,
                        checklistItemId = checklistItemId,
                        voiceRecordingId = voiceRecordingId
                    )
                } else {
                    // Past reminder (missed or expired while off)
                    if (!isRecurring) {
                        // 1. One-Time Reminder: Check 24-hour grace window
                        val elapsedMs = now - triggerTimeMs
                        if (elapsedMs <= graceWindowMs) {
                            missedReminders.add(
                                MissedReminder(
                                    notificationId = notificationId,
                                    title = title,
                                    body = body,
                                    noteId = noteId,
                                    checklistItemId = checklistItemId,
                                    voiceRecordingId = voiceRecordingId
                                )
                            )
                        }
                        // Reminders expired > 24 hours remain marked overdue in DB without alert
                    } else {
                        // 2. Recurring Reminder: Single summary inclusion + forward-clamping
                        missedReminders.add(
                            MissedReminder(
                                notificationId = notificationId,
                                title = title,
                                body = body,
                                noteId = noteId,
                                checklistItemId = checklistItemId,
                                voiceRecordingId = voiceRecordingId
                            )
                        )

                        // Forward-clamp to next future occurrence
                        val repeatInterval = rem.optInt("repeat_interval_value", 1)
                        val advanceResult = advanceRecurring(
                            baseIso = scheduledAtStr,
                            repeatMode = repeatMode,
                            intervalValue = repeatInterval,
                            nowMs = now
                        )

                        if (advanceResult != null) {
                            val (nextEpochMs, nextIso) = advanceResult
                            // Re-arm AlarmManager for next cycle
                            ReminderManager.scheduleAlarm(
                                context = context,
                                notificationId = notificationId,
                                triggerEpochMs = nextEpochMs,
                                title = title,
                                body = body,
                                noteId = noteId,
                                checklistItemId = checklistItemId,
                                voiceRecordingId = voiceRecordingId
                            )

                            // Update JSON entry
                            rem.put("scheduled_at", nextIso)
                            rem.put("snooze_count", 0)
                            rem.remove("snoozed_until")
                            jsonModified = true
                        }
                    }
                }
            }

            // Persist updated forward-clamped series to JSON if modified
            if (jsonModified) {
                saveJsonSafely(dataFile, root)
            }

            // Anti-Flood Alert Throttling (only during boot recovery)
            if (isBootAction && missedReminders.isNotEmpty()) {
                postAntiFloodAlerts(context, missedReminders)
            }
        } catch (e: Exception) {
            // Boot re-arming must never crash the system broadcast receiver
        }
    }

    private fun postAntiFloodAlerts(context: Context, missed: List<MissedReminder>) {
        try {
            if (!NotificationManagerCompat.from(context).areNotificationsEnabled()) {
                return
            }

            val notificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            ReminderManager.createNotificationChannel(context)

            if (missed.size == 1) {
                val single = missed[0]
                val notification = ReminderManager.buildNotification(
                    context = context,
                    notificationId = single.notificationId,
                    title = "Missed Reminder: ${single.title}",
                    body = single.body.ifEmpty { "You have a scheduled reminder that expired while your device was off" },
                    noteId = single.noteId,
                    checklistItemId = single.checklistItemId,
                    voiceRecordingId = single.voiceRecordingId
                )
                notificationManager.notify(single.notificationId, notification)
            } else if (missed.size > 1) {
                val summaryNotification = ReminderManager.buildMissedSummaryNotification(
                    context = context,
                    count = missed.size
                )
                notificationManager.notify(ReminderManager.MISSED_SUMMARY_NOTIFICATION_ID, summaryNotification)
            }
        } catch (_: Exception) {}
    }

    private fun parseToEpochMs(isoStr: String): Long {
        if (isoStr.isBlank()) return -1L
        val clean = if (isoStr.length >= 19) isoStr.substring(0, 19) else isoStr
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            try {
                val localDt = java.time.LocalDateTime.parse(clean)
                // atZone(ZoneId.systemDefault()) handles Spring Gap & Fall Overlap per Section 5.3
                return localDt.atZone(java.time.ZoneId.systemDefault()).toInstant().toEpochMilli()
            } catch (_: Exception) {}
        }
        return try {
            val sdf = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss", Locale.US).apply {
                timeZone = TimeZone.getDefault()
            }
            sdf.parse(clean)?.time ?: -1L
        } catch (_: Exception) {
            -1L
        }
    }

    private fun advanceRecurring(
        baseIso: String,
        repeatMode: String,
        intervalValue: Int,
        nowMs: Long
    ): Pair<Long, String>? {
        val step = if (intervalValue > 0) intervalValue else 1
        val clean = if (baseIso.length >= 19) baseIso.substring(0, 19) else baseIso
        val cal = Calendar.getInstance()
        try {
            val sdf = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss", Locale.US).apply {
                timeZone = TimeZone.getDefault()
            }
            val date = sdf.parse(clean) ?: return null
            cal.time = date
        } catch (_: Exception) {
            return null
        }

        var safetyIterations = 0
        while (cal.timeInMillis <= nowMs && safetyIterations < 1000) {
            safetyIterations++
            when (repeatMode.lowercase(Locale.US)) {
                "daily" -> cal.add(Calendar.DAY_OF_YEAR, step)
                "weekly" -> cal.add(Calendar.DAY_OF_YEAR, 7 * step)
                "monthly" -> cal.add(Calendar.MONTH, step)
                "custom" -> cal.add(Calendar.DAY_OF_YEAR, step)
                else -> return null
            }
        }

        if (cal.timeInMillis <= nowMs) return null

        val outSdf = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS", Locale.US).apply {
            timeZone = TimeZone.getDefault()
        }
        return Pair(cal.timeInMillis, outSdf.format(cal.time))
    }

        private fun saveJsonSafely(targetFile: File, root: JSONObject) {
            try {
                val parentDir = targetFile.parentFile ?: return
                val tmpFile = File(parentDir, "${targetFile.name}.tmp")
                val content = root.toString()
                tmpFile.writeText(content, Charsets.UTF_8)
                if (tmpFile.exists() && tmpFile.length() > 0) {
                    tmpFile.renameTo(targetFile)
                }
            } catch (_: Exception) {}
        }
    }

    data class MissedReminder(
        val notificationId: Int,
        val title: String,
        val body: String,
        val noteId: String,
        val checklistItemId: String?,
        val voiceRecordingId: String?
    )

    override fun onReceive(context: Context, intent: Intent) {
        val action = intent.action ?: return
        val isExactAlarmPermissionChange = action == "android.app.action.SCHEDULE_EXACT_ALARM_PERMISSION_STATE_CHANGED" ||
            (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S && action == AlarmManager.ACTION_SCHEDULE_EXACT_ALARM_PERMISSION_STATE_CHANGED)

        if (action == Intent.ACTION_BOOT_COMPLETED ||
            action == "android.intent.action.QUICKBOOT_POWERON" ||
            action == Intent.ACTION_MY_PACKAGE_REPLACED ||
            action == Intent.ACTION_TIME_CHANGED ||
            action == Intent.ACTION_TIMEZONE_CHANGED ||
            isExactAlarmPermissionChange
        ) {
            val isBootAction = action == Intent.ACTION_BOOT_COMPLETED ||
                action == "android.intent.action.QUICKBOOT_POWERON" ||
                action == Intent.ACTION_MY_PACKAGE_REPLACED

            rearmActiveReminders(context, isBootAction)
        }
    }
}
