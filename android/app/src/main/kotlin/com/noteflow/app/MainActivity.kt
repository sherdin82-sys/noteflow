package com.noteflow.app

import android.Manifest
import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.OpenableColumns
import android.provider.Settings
import androidx.activity.result.ActivityResultLauncher
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.core.app.ActivityCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.FileProvider
import com.noteflow.app.reminders.NotificationActionReceiver
import com.noteflow.app.reminders.ReminderManager
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.io.FileOutputStream
import java.io.IOException
import java.util.UUID

class MainActivity : FlutterFragmentActivity() {
    private val NATIVE_CHANNEL = "com.noteflow.app/native"
    private val REMINDERS_CHANNEL = "com.noteflow.app/reminders"
    private val ATTACHMENTS_CHANNEL = "com.noteflow.app/attachments"

    private var photoPickerLauncher: ActivityResultLauncher<PickVisualMediaRequest>? = null
    private var docPickerLauncher: ActivityResultLauncher<Array<String>>? = null
    private var pendingPickerResult: MethodChannel.Result? = null
    private var currentRequestId: String? = null
    private var currentMaxBytes: Long = 25 * 1024 * 1024L

    companion object {
        private var remindersChannel: MethodChannel? = null

        fun notifyActionReceived(actionJson: String) {
            remindersChannel?.invokeMethod("onReminderActionReceived", actionJson)
        }
    }

    private var initialNotificationPayload: Map<String, Any?>? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // Pre-register Photo Picker Contract
        photoPickerLauncher = registerForActivityResult(
            ActivityResultContracts.PickMultipleVisualMedia()
        ) { uris: List<Uri>? ->
            handleSelectedUris(uris)
        }

        // Pre-register Storage Access Framework Document Contract
        docPickerLauncher = registerForActivityResult(
            ActivityResultContracts.OpenMultipleDocuments()
        ) { uris: List<Uri>? ->
            handleSelectedUris(uris)
        }

        // Prune stale staging files older than 10 minutes on cold boot
        pruneStaleStagingFiles()
        // Prune stale sharing cache files older than 24 hours on cold boot
        pruneSharingCache()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Native info channel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, NATIVE_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getAppVersion" -> {
                    result.success("1.8.0")
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

                    // Return pending actions without blind clearing (two-phase commit with ackPendingJournalActions)
                    result.success(actionsList)
                }

                "ackPendingJournalActions" -> {
                    val actionIds = call.argument<List<String>>("actionIds") ?: emptyList()
                    val prefs = getSharedPreferences(NotificationActionReceiver.PREFS_NAME, Context.MODE_PRIVATE)
                    val editor = prefs.edit()
                    for (actionId in actionIds) {
                        editor.remove("action_$actionId")
                        editor.remove(actionId)
                    }
                    editor.apply()
                    result.success(true)
                }

                "getInitialNotificationPayload" -> {
                    val payload = initialNotificationPayload
                    initialNotificationPayload = null
                    result.success(payload)
                }

                "areLockscreenPreviewsEnabled" -> {
                    val prefs = getSharedPreferences(com.noteflow.app.reminders.ReminderManager.PREFS_SETTINGS_NAME, Context.MODE_PRIVATE)
                    val enabled = prefs.getBoolean(com.noteflow.app.reminders.ReminderManager.KEY_SHOW_LOCKSCREEN_PREVIEWS, false)
                    result.success(enabled)
                }

                "setLockscreenPreviewsEnabled" -> {
                    val enabled = call.argument<Boolean>("enabled") ?: false
                    val prefs = getSharedPreferences(com.noteflow.app.reminders.ReminderManager.PREFS_SETTINGS_NAME, Context.MODE_PRIVATE)
                    prefs.edit().putBoolean(com.noteflow.app.reminders.ReminderManager.KEY_SHOW_LOCKSCREEN_PREVIEWS, enabled).apply()
                    result.success(true)
                }

                "verifyDocumentsPath" -> {
                    val dartPath = call.argument<String>("path") ?: ""
                    val canonicalDir = getDir("app_flutter", Context.MODE_PRIVATE)
                    val canonicalPath = canonicalDir.absolutePath
                    val matches = dartPath == canonicalPath
                    if (!matches) {
                        android.util.Log.w("NoteFlow", "Documents path discrepancy: Dart=$dartPath, Kotlin=$canonicalPath")
                        if (dartPath.isNotBlank()) {
                            val dir = File(dartPath)
                            if (dir.exists() && dir.isDirectory) {
                                com.noteflow.app.reminders.BootReceiver.customDocumentsDir = dir
                            }
                        }
                    }
                    result.success(matches)
                }

                else -> {
                    result.notImplemented()
                }
            }
        }

        // Attachments platform channel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, ATTACHMENTS_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "pickAttachments" -> {
                    if (pendingPickerResult != null) {
                        result.error("PICKER_ACTIVE", "A picker operation is already in progress", null)
                        return@setMethodCallHandler
                    }
                    val reqId = call.argument<String>("requestId") ?: UUID.randomUUID().toString()
                    val maxBytes = call.argument<Number>("maxSingleFileBytes")?.toLong() ?: (25 * 1024 * 1024L)
                    val category = call.argument<String>("category") ?: "all"

                    pendingPickerResult = result
                    currentRequestId = reqId
                    currentMaxBytes = maxBytes

                    try {
                        when (category.lowercase()) {
                            "images" -> {
                                photoPickerLauncher?.launch(
                                    PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly)
                                )
                            }
                            "video", "videos" -> {
                                photoPickerLauncher?.launch(
                                    PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.VideoOnly)
                                )
                            }
                            else -> {
                                docPickerLauncher?.launch(arrayOf("*/*"))
                            }
                        }
                    } catch (e: Exception) {
                        pendingPickerResult = null
                        currentRequestId = null
                        result.error("LAUNCH_ERROR", "Failed to launch picker: ${e.message}", null)
                    }
                }

                "getPendingPickerResult" -> {
                    val pendingFile = File(File(cacheDir, "attachment_staging"), "pending_picker_result.json")
                    if (pendingFile.exists()) {
                        try {
                            val jsonString = pendingFile.readText()
                            val payload = parseJsonToPayload(jsonString)
                            pendingFile.delete()
                            result.success(payload)
                        } catch (e: Exception) {
                            pendingFile.delete()
                            result.success(null)
                        }
                    } else {
                        result.success(null)
                    }
                }

                "clearPendingPickerResult" -> {
                    val pendingFile = File(File(cacheDir, "attachment_staging"), "pending_picker_result.json")
                    if (pendingFile.exists()) {
                        pendingFile.delete()
                    }
                    result.success(true)
                }

                "openAttachment" -> {
                    val relativePath = call.argument<String>("relativePath")
                    val mimeType = call.argument<String>("mimeType") ?: "*/*"
                    val originalName = call.argument<String>("originalName")

                    if (relativePath.isNullOrBlank()) {
                        result.error("INVALID_ARGUMENT", "relativePath is required", null)
                        return@setMethodCallHandler
                    }

                    try {
                        val stagedFile = stageAttachmentForSharing(relativePath, originalName)
                        val uri = FileProvider.getUriForFile(this, "$packageName.fileprovider", stagedFile)
                        val intent = Intent(Intent.ACTION_VIEW).apply {
                            setDataAndType(uri, mimeType)
                            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        }
                        val chooser = Intent.createChooser(intent, "Open with")
                        chooser.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        startActivity(chooser)
                        result.success(true)
                    } catch (e: SecurityException) {
                        result.error("SECURITY_VIOLATION", e.message, null)
                    } catch (e: ActivityNotFoundException) {
                        result.error("NO_ACTIVITY", "No application found to open $mimeType", null)
                    } catch (e: Exception) {
                        result.error("OPEN_FAILED", "Failed to open attachment: ${e.message}", null)
                    }
                }

                "shareAttachment" -> {
                    val relativePath = call.argument<String>("relativePath")
                    val mimeType = call.argument<String>("mimeType") ?: "*/*"
                    val originalName = call.argument<String>("originalName")

                    if (relativePath.isNullOrBlank()) {
                        result.error("INVALID_ARGUMENT", "relativePath is required", null)
                        return@setMethodCallHandler
                    }

                    try {
                        val stagedFile = stageAttachmentForSharing(relativePath, originalName)
                        val uri = FileProvider.getUriForFile(this, "$packageName.fileprovider", stagedFile)
                        val intent = Intent(Intent.ACTION_SEND).apply {
                            type = mimeType
                            putExtra(Intent.EXTRA_STREAM, uri)
                            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                        }
                        val chooser = Intent.createChooser(intent, "Share Attachment").apply {
                            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        }
                        startActivity(chooser)
                        result.success(true)
                    } catch (e: SecurityException) {
                        result.error("SECURITY_VIOLATION", e.message, null)
                    } catch (e: Exception) {
                        result.error("SHARE_FAILED", "Failed to share attachment: ${e.message}", null)
                    }
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
        val actionType = intent.getStringExtra(ReminderManager.EXTRA_ACTION_TYPE)
        val initialTabIndex = intent.getIntExtra("initialTabIndex", -1)
        if (actionType == "open_overdue" || intent.action == ReminderManager.ACTION_OPEN_OVERDUE) {
            val payload = mapOf(
                "action" to "open_overdue",
                "initialTabIndex" to if (initialTabIndex >= 0) initialTabIndex else 2
            )
            initialNotificationPayload = payload
            remindersChannel?.invokeMethod("onNotificationTapped", payload)
            return
        }

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

    private fun handleSelectedUris(uris: List<Uri>?) {
        val reqId = currentRequestId ?: UUID.randomUUID().toString()

        if (uris == null || uris.isEmpty()) {
            val emptyPayload = mapOf<String, Any?>(
                "requestId" to reqId,
                "cancelled" to true,
                "items" to emptyList<Map<String, Any?>>()
            )
            writePendingResultToFile(emptyPayload)

            val activeResult = pendingPickerResult
            pendingPickerResult = null
            currentRequestId = null

            if (activeResult != null) {
                activeResult.success(emptyPayload)
                clearPendingResultFile()
            }
            return
        }

        val maxBytes = currentMaxBytes

        CoroutineScope(Dispatchers.IO).launch {
            val stagingDir = File(cacheDir, "attachment_staging").apply { mkdirs() }
            pruneStaleStagingFiles(stagingDir)

            val resultsList = mutableListOf<Map<String, Any?>>()

            for (uri in uris) {
                var displayName: String? = null
                var declaredSize: Long = -1L

                try {
                    contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE), null, null, null)?.use { cursor ->
                        if (cursor.moveToFirst()) {
                            val nameIdx = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                            if (nameIdx >= 0) displayName = cursor.getString(nameIdx)
                            val sizeIdx = cursor.getColumnIndex(OpenableColumns.SIZE)
                            if (sizeIdx >= 0) declaredSize = cursor.getLong(sizeIdx)
                        }
                    }
                } catch (_: Exception) {}

                if (displayName.isNullOrBlank()) {
                    displayName = uri.lastPathSegment ?: "attachment_${System.currentTimeMillis()}"
                }

                val mimeType = try {
                    contentResolver.getType(uri) ?: "application/octet-stream"
                } catch (_: Exception) {
                    "application/octet-stream"
                }

                if (declaredSize > maxBytes) {
                    resultsList.add(mapOf(
                        "status" to "ERROR",
                        "errorCode" to "SIZE_LIMIT_EXCEEDED",
                        "errorMessage" to "File exceeds limit of $maxBytes bytes",
                        "originalName" to displayName,
                        "mimeType" to mimeType,
                        "fileSizeBytes" to declaredSize
                    ))
                    continue
                }

                val tempFile = File(stagingDir, "${UUID.randomUUID()}.tmp")
                try {
                    var bytesCopied = 0L
                    var exceeded = false
                    contentResolver.openInputStream(uri)?.use { input ->
                        FileOutputStream(tempFile).use { output ->
                            val buffer = ByteArray(8192)
                            var read = input.read(buffer)
                            while (read != -1) {
                                bytesCopied += read
                                if (bytesCopied > maxBytes) {
                                    exceeded = true
                                    break
                                }
                                output.write(buffer, 0, read)
                                read = input.read(buffer)
                            }
                            output.flush()
                        }
                    } ?: throw IOException("Could not open stream for URI")

                    if (exceeded) {
                        if (tempFile.exists()) tempFile.delete()
                        resultsList.add(mapOf(
                            "status" to "ERROR",
                            "errorCode" to "SIZE_LIMIT_EXCEEDED",
                            "errorMessage" to "File exceeds limit of $maxBytes bytes",
                            "originalName" to displayName,
                            "mimeType" to mimeType,
                            "fileSizeBytes" to bytesCopied
                        ))
                    } else {
                        resultsList.add(mapOf(
                            "status" to "SUCCESS",
                            "stagingPath" to tempFile.absolutePath,
                            "originalName" to displayName,
                            "mimeType" to mimeType,
                            "fileSizeBytes" to tempFile.length()
                        ))
                    }
                } catch (e: Exception) {
                    if (tempFile.exists()) tempFile.delete()
                    resultsList.add(mapOf(
                        "status" to "ERROR",
                        "errorCode" to "IO_ERROR",
                        "errorMessage" to (e.message ?: "Failed to read file"),
                        "originalName" to displayName,
                        "mimeType" to mimeType,
                        "fileSizeBytes" to 0L
                    ))
                }
            }

            val responsePayload = mapOf<String, Any?>(
                "requestId" to reqId,
                "cancelled" to false,
                "items" to resultsList
            )

            writePendingResultToFile(responsePayload)

            withContext(Dispatchers.Main) {
                val activeResult = pendingPickerResult
                pendingPickerResult = null
                currentRequestId = null

                if (activeResult != null) {
                    activeResult.success(responsePayload)
                    clearPendingResultFile()
                }
            }
        }
    }

    private fun writePendingResultToFile(payload: Map<String, Any?>) {
        try {
            val stagingDir = File(cacheDir, "attachment_staging").apply { mkdirs() }
            val tmpResultFile = File(stagingDir, "pending_picker_result.json.tmp")
            val finalResultFile = File(stagingDir, "pending_picker_result.json")
            val jsonStr = serializePayloadToJson(payload)
            tmpResultFile.writeText(jsonStr)
            tmpResultFile.renameTo(finalResultFile)
        } catch (_: Exception) {}
    }

    private fun clearPendingResultFile() {
        try {
            val finalResultFile = File(File(cacheDir, "attachment_staging"), "pending_picker_result.json")
            if (finalResultFile.exists()) {
                finalResultFile.delete()
            }
        } catch (_: Exception) {}
    }

    private fun pruneStaleStagingFiles(dir: File = File(cacheDir, "attachment_staging")) {
        try {
            if (!dir.exists()) return
            val tenMinutesAgo = System.currentTimeMillis() - (10 * 60 * 1000)
            dir.listFiles()?.forEach { file ->
                if (file.name.endsWith(".tmp") && file.lastModified() < tenMinutesAgo) {
                    file.delete()
                }
            }
        } catch (_: Exception) {}
    }

    private fun serializePayloadToJson(payload: Map<String, Any?>): String {
        val json = JSONObject()
        json.put("requestId", payload["requestId"] ?: "")
        json.put("cancelled", payload["cancelled"] ?: false)
        val itemsArray = JSONArray()
        val items = payload["items"] as? List<Map<String, Any?>> ?: emptyList()
        for (item in items) {
            val itemObj = JSONObject()
            for ((k, v) in item) {
                itemObj.put(k, v)
            }
            itemsArray.put(itemObj)
        }
        json.put("items", itemsArray)
        return json.toString()
    }

    private fun parseJsonToPayload(jsonStr: String): Map<String, Any?> {
        val json = JSONObject(jsonStr)
        val map = mutableMapOf<String, Any?>()
        map["requestId"] = json.optString("requestId", "")
        map["cancelled"] = json.optBoolean("cancelled", false)
        val itemsList = mutableListOf<Map<String, Any?>>()
        val itemsArray = json.optJSONArray("items")
        if (itemsArray != null) {
            for (i in 0 until itemsArray.length()) {
                val itemObj = itemsArray.getJSONObject(i)
                val itemMap = mutableMapOf<String, Any?>()
                val keys = itemObj.keys()
                while (keys.hasNext()) {
                    val key = keys.next()
                    itemMap[key] = itemObj.opt(key)
                }
                itemsList.add(itemMap)
            }
        }
        map["items"] = itemsList
        return map
    }

    private fun pruneSharingCache() {
        val shareDir = File(cacheDir, "shared_attachments")
        if (!shareDir.exists() || !shareDir.isDirectory) return

        val files = shareDir.listFiles() ?: return
        val now = System.currentTimeMillis()
        val maxAgeMs = 24 * 60 * 60 * 1000L // 24 hours
        val maxAggregateBytes = 50 * 1024 * 1024L // 50 MB
        val targetAggregateBytes = 25 * 1024 * 1024L // 25 MB

        var totalSize = 0L
        val activeFiles = mutableListOf<File>()

        for (file in files) {
            val age = now - file.lastModified()
            if (age > maxAgeMs) {
                file.delete()
            } else {
                totalSize += file.length()
                activeFiles.add(file)
            }
        }

        // If total size still exceeds 50 MB, prune oldest files until under 25 MB
        if (totalSize > maxAggregateBytes) {
            activeFiles.sortBy { it.lastModified() } // oldest first
            for (file in activeFiles) {
                if (totalSize <= targetAggregateBytes) break
                val len = file.length()
                if (file.delete()) {
                    totalSize -= len
                }
            }
        }
    }

    private fun stageAttachmentForSharing(relativePath: String, originalName: String?): File {
        if (relativePath.contains("\u0000") || relativePath.contains("..")) {
            throw SecurityException("Security violation: path traversal sequence detected: $relativePath")
        }

        val flutterDir = getDir("flutter", Context.MODE_PRIVATE)
        val attachmentsDir = File(flutterDir, "attachments").canonicalFile
        val sourceFile = File(flutterDir, relativePath).canonicalFile

        if (!sourceFile.path.startsWith(attachmentsDir.path + File.separator) && sourceFile.path != attachmentsDir.path) {
            throw SecurityException("Security violation: target path outside attachments directory: $relativePath")
        }
        if (!sourceFile.exists() || !sourceFile.isFile) {
            throw IOException("Attachment file does not exist: $relativePath")
        }

        pruneSharingCache()
        val shareDir = File(cacheDir, "shared_attachments")
        if (!shareDir.exists()) {
            shareDir.mkdirs()
        }

        val rawName = if (!originalName.isNullOrBlank()) originalName.trim() else sourceFile.name
        val safeName = rawName.replace(Regex("[^a-zA-Z0-9._-]"), "_")
        val targetFile = File(shareDir, safeName)

        sourceFile.inputStream().use { input ->
            FileOutputStream(targetFile).use { output ->
                input.copyTo(output)
            }
        }
        return targetFile
    }

    override fun onDestroy() {
        pendingPickerResult = null
        if (remindersChannel != null) {
            remindersChannel = null
        }
        super.onDestroy()
    }
}
