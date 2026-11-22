package com.noteflow.app.reminders

import android.app.NotificationManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

class AlarmReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val notificationId = intent.getIntExtra(ReminderManager.EXTRA_NOTIFICATION_ID, -1)
        if (notificationId == -1) return

        val title = intent.getStringExtra(ReminderManager.EXTRA_TITLE) ?: ""
        val body = intent.getStringExtra(ReminderManager.EXTRA_BODY) ?: ""
        val noteId = intent.getStringExtra(ReminderManager.EXTRA_NOTE_ID) ?: ""
        val checklistItemId = intent.getStringExtra(ReminderManager.EXTRA_CHECKLIST_ITEM_ID)
        val voiceRecordingId = intent.getStringExtra(ReminderManager.EXTRA_VOICE_RECORDING_ID)
        val occurrenceEpochMs = intent.getLongExtra(ReminderManager.EXTRA_OCCURRENCE_EPOCH_MS, -1L)
        val effectiveOccurrenceEpochMs = if (occurrenceEpochMs > 0) occurrenceEpochMs else System.currentTimeMillis()

        val notification = ReminderManager.buildNotification(
            context = context,
            notificationId = notificationId,
            title = title,
            body = body,
            noteId = noteId,
            checklistItemId = checklistItemId,
            voiceRecordingId = voiceRecordingId,
            occurrenceEpochMs = effectiveOccurrenceEpochMs
        )

        val notificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        notificationManager.notify(notificationId, notification)
    }
}
