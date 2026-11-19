package com.noteflow.app.reminders

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import org.json.JSONObject
import java.io.File
import java.text.SimpleDateFormat
import java.util.Locale
import java.util.TimeZone

class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val action = intent.action ?: return
        if (action == Intent.ACTION_BOOT_COMPLETED ||
            action == "android.intent.action.QUICKBOOT_POWERON" ||
            action == Intent.ACTION_MY_PACKAGE_REPLACED ||
            action == Intent.ACTION_TIME_CHANGED ||
            action == Intent.ACTION_TIMEZONE_CHANGED
        ) {
            rearmActiveReminders(context)
        }
    }

    private fun rearmActiveReminders(context: Context) {
        try {
            // Locate noteflow_data.json in Flutter application documents directory
            val appFlutterDir = File(context.filesDir.parent, "app_flutter")
            val dataFile = if (File(appFlutterDir, "noteflow_data.json").exists()) {
                File(appFlutterDir, "noteflow_data.json")
            } else if (File(context.filesDir, "noteflow_data.json").exists()) {
                File(context.filesDir, "noteflow_data.json")
            } else {
                null
            }

            if (dataFile == null || !dataFile.exists()) return

            val content = dataFile.readText(Charsets.UTF_8)
            if (content.isBlank()) return

            val root = JSONObject(content)
            if (!root.has("reminders")) return

            val remindersArray = root.getJSONArray("reminders")
            val now = System.currentTimeMillis()

            val isoFormat = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss", Locale.US).apply {
                timeZone = TimeZone.getDefault()
            }

            for (i in 0 until remindersArray.length()) {
                val rem = remindersArray.getJSONObject(i)
                val isCompleted = rem.optBoolean("is_completed", false) || rem.optInt("is_completed", 0) == 1
                if (isCompleted) continue

                val notificationId = rem.optInt("notification_id", -1)
                if (notificationId <= 0) continue

                // Determine target trigger time: snoozed_until takes precedence if set
                val snoozedUntilStr = rem.optString("snoozed_until", "")
                val scheduledAtStr = rem.optString("scheduled_at", "")

                var triggerTimeMs: Long = -1

                if (snoozedUntilStr.isNotBlank()) {
                    try {
                        triggerTimeMs = isoFormat.parse(snoozedUntilStr.substring(0, minOf(19, snoozedUntilStr.length)))?.time ?: -1
                    } catch (_) {}
                }

                if (triggerTimeMs <= now && scheduledAtStr.isNotBlank()) {
                    try {
                        triggerTimeMs = isoFormat.parse(scheduledAtStr.substring(0, minOf(19, scheduledAtStr.length)))?.time ?: -1
                    } catch (_) {}
                }

                // If scheduled time is in future, re-schedule with AlarmManager
                if (triggerTimeMs > now) {
                    val title = rem.optString("title", "Note Reminder")
                    val body = rem.optString("notes_preview", "")
                    val noteId = rem.optString("note_id", "")
                    val checklistItemId = if (rem.has("checklist_item_id") && !rem.isNull("checklist_item_id")) rem.getString("checklist_item_id") else null
                    val voiceRecordingId = if (rem.has("voice_recording_id") && !rem.isNull("voice_recording_id")) rem.getString("voice_recording_id") else null

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
                }
            }
        } catch (e: Exception) {
            // Boot re-arming should fail silently without crashing the system broadcast
        }
    }
}
