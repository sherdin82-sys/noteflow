package com.noteflow.app

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.app.ActivityCompat
import androidx.core.app.NotificationManagerCompat
import com.noteflow.app.reminders.NotificationActionReceiver
import com.noteflow.app.reminders.ReminderManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val NATIVE_CHANNEL = "com.noteflow.app/native"
    private val REMINDERS_CHANNEL = "com.noteflow.app/reminders"

    companion object {
        private var remindersChannel: MethodChannel? = null

        fun notifyActionReceived(actionJson: String) {
            remindersChannel?.invokeMethod("onReminderActionReceived", actionJson)
        }
    }

    private var initialNotificationPayload: Map<String, Any?>? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Native info channel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, NATIVE_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getAppVersion" -> {
                    result.success("1.6.0")
                }
                "getDeviceInfo" -> {
                    val info = mapOf(
                        "manufacturer" to android.os.Build.MANUFACTURER,
                        "model" to android.os.Build.MODEL,
                        "sdk" to android.os.Build.VERSION.SDK_INT
                    )
                    result.success(info)
                }
                else -> {
                    result.notImplemented()
                }
            }
        }

        // Reminders & Notifications platform channel
        val reminderChan = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, REMINDERS_CHANNEL)
        remindersChannel = reminderChan

        reminderChan.setMethodCallHandler { call, result ->
            when (call.method) {
                "scheduleAlarm" -> {
                    val notificationId = call.argument<Int>("notificationId") ?: -1
                    val triggerEpochMs = call.argument<Number>("triggerEpochMs")?.toLong() ?: -1L
                    val title = call.argument<String>("title") ?: ""
                    val body = call.argument<String>("body") ?: ""
                    val noteId = call.argument<String>("noteId") ?: ""
                    val checklistItemId = call.argument<String>("checklistItemId")
                    val voiceRecordingId = call.argument<String>("voiceRecordingId")

                    if (notificationId > 0 && triggerEpochMs > 0 && noteId.isNotEmpty()) {
                        ReminderManager.scheduleAlarm(
                            context = this,
                            notificationId = notificationId,
                            triggerEpochMs = triggerEpochMs,
                            title = title,
                            body = body,
                            noteId = noteId,
                            checklistItemId = checklistItemId,
                            voiceRecordingId = voiceRecordingId
                        )
                        result.success(true)
                    } else {
                        result.error("INVALID_ARGS", "Missing required reminder arguments", null)
                    }
                }

                "cancelAlarm" -> {
                    val notificationId = call.argument<Int>("notificationId") ?: -1
                    if (notificationId > 0) {
                        ReminderManager.cancelAlarm(this, notificationId)
                        result.success(true)
                    } else {
                        result.error("INVALID_ARGS", "Missing notificationId", null)
                    }
                }

                "canScheduleExactAlarms" -> {
                    result.success(ReminderManager.canScheduleExactAlarms(this))
                }

                "requestExactAlarmPermission" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                        try {
                            val intent = Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM).apply {
                                data = Uri.parse("package:$packageName")
                            }
                            startActivity(intent)
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("SETTINGS_ERROR", e.message, null)
                        }
                    } else {
                        result.success(true)
                    }
                }

                "areNotificationsEnabled" -> {
                    val enabled = NotificationManagerCompat.from(this).areNotificationsEnabled()
                    result.success(enabled)
                }

                "requestNotificationPermission" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                        if (checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
                            ActivityCompat.requestPermissions(
                                this,
                                arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                                1001
                            )
                        }
                    }
                    result.success(true)
                }

                "openNotificationSettings" -> {
                    try {
                        val intent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).apply {
                                putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
                            }
                        } else {
                            Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                                data = Uri.parse("package:$packageName")
                            }
                        }
                        startActivity(intent)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("SETTINGS_ERROR", e.message, null)
                    }
                }

                "getPendingJournalActions" -> {
                    val prefs = getSharedPreferences(NotificationActionReceiver.PREFS_NAME, Context.MODE_PRIVATE)
                    val allEntries = prefs.all
                    val actionsList = mutableListOf<String>()

                    for ((_, value) in allEntries) {
                        if (value is String) {
                            actionsList.add(value)
                        }
                    }

                    // Clear journal after reading
                    prefs.edit().clear().apply()
                    result.success(actionsList)
                }

                "getInitialNotificationPayload" -> {
                    val payload = initialNotificationPayload
                    initialNotificationPayload = null
                    result.success(payload)
                }

                else -> {
                    result.notImplemented()
                }
            }
        }

        // Check if app was launched via notification click
        checkNotificationIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        checkNotificationIntent(intent)
    }

    private fun checkNotificationIntent(intent: Intent?) {
        if (intent == null) return
        val noteId = intent.getStringExtra(ReminderManager.EXTRA_NOTE_ID) ?: return
        val checklistItemId = intent.getStringExtra(ReminderManager.EXTRA_CHECKLIST_ITEM_ID)
        val voiceRecordingId = intent.getStringExtra(ReminderManager.EXTRA_VOICE_RECORDING_ID)
        val notificationId = intent.getIntExtra(ReminderManager.EXTRA_NOTIFICATION_ID, -1)

        val payload = mapOf(
            "noteId" to noteId,
            "checklistItemId" to checklistItemId,
            "voiceRecordingId" to voiceRecordingId,
            "notificationId" to notificationId
        )

        initialNotificationPayload = payload
        remindersChannel?.invokeMethod("onNotificationTapped", payload)
    }

    override fun onDestroy() {
        if (remindersChannel != null) {
            remindersChannel = null
        }
        super.onDestroy()
    }
}
