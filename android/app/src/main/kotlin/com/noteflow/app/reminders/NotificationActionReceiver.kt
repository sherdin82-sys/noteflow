package com.noteflow.app.reminders

import android.app.NotificationManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import com.noteflow.app.MainActivity
import org.json.JSONObject

class NotificationActionReceiver : BroadcastReceiver() {
    companion object {
        const val PREFS_NAME = "noteflow_pending_reminder_actions"
        const val SNOOZE_DURATION_MS = 15 * 60 * 1000L // 15 minutes
    }

    override fun onReceive(context: Context, intent: Intent) {
        val notificationId = intent.getIntExtra(ReminderManager.EXTRA_NOTIFICATION_ID, -1)
        if (notificationId == -1) return

        val noteId = intent.getStringExtra(ReminderManager.EXTRA_NOTE_ID) ?: ""
        val checklistItemId = intent.getStringExtra(ReminderManager.EXTRA_CHECKLIST_ITEM_ID)
        val voiceRecordingId = intent.getStringExtra(ReminderManager.EXTRA_VOICE_RECORDING_ID)
        val title = intent.getStringExtra(ReminderManager.EXTRA_TITLE) ?: ""
        val body = intent.getStringExtra(ReminderManager.EXTRA_BODY) ?: ""

        // Dismiss the active notification in system tray immediately
        val notificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        notificationManager.cancel(notificationId)

        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val now = System.currentTimeMillis()

        when (intent.action) {
            ReminderManager.ACTION_SNOOZE -> {
                val newTriggerTime = now + SNOOZE_DURATION_MS

                // Re-arm exact alarm immediately in native OS
                ReminderManager.scheduleAlarm(
                    context = context,
                    notificationId = notificationId,
                    triggerEpochMs = newTriggerTime,
                    title = title,
                    body = body,
                    noteId = noteId,
                    checklistItemId = checklistItemId,
                    voiceRecordingId = voiceRecordingId
                )

                // Journal action in SharedPreferences for Flutter repository sync
                val actionData = JSONObject().apply {
                    put("action", "snooze")
                    put("notificationId", notificationId)
                    put("noteId", noteId)
                    put("checklistItemId", checklistItemId)
                    put("voiceRecordingId", voiceRecordingId)
                    put("snoozedUntilMs", newTriggerTime)
                    put("timestampMs", now)
                }
                prefs.edit().putString("action_${notificationId}_$now", actionData.toString()).apply()

                // Notify running Flutter instance if active
                MainActivity.notifyActionReceived(actionData.toString())
            }

            ReminderManager.ACTION_MARK_DONE -> {
                // Cancel any pending alarms
                ReminderManager.cancelAlarm(context, notificationId)

                // Journal action in SharedPreferences for Flutter repository sync
                val actionData = JSONObject().apply {
                    put("action", "markDone")
                    put("notificationId", notificationId)
                    put("noteId", noteId)
                    put("checklistItemId", checklistItemId)
                    put("voiceRecordingId", voiceRecordingId)
                    put("timestampMs", now)
                }
                prefs.edit().putString("action_${notificationId}_$now", actionData.toString()).apply()

                // Notify running Flutter instance if active
                MainActivity.notifyActionReceived(actionData.toString())
            }
        }
    }
}
