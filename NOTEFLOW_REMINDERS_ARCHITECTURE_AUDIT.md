# NoteFlow — Reminders & Notifications: Complete Architecture & Reliability Audit

> **Document Type:** Comprehensive Architecture, Reliability, Lifecycle & Security Audit  
> **Application:** NoteFlow (v1.7.3+29)  
> **Target Platform:** Android (Flutter >=3.22.0 / Dart >=3.3.0 / Kotlin 1.9+ / Material 3)  
> **Target Android SDK:** minSdk 24, compileSdk 36, targetSdk 36, AGP 9  
> **Audit Mode:** Read-Only Technical Inspection & Final Architecture Hardening  
> **Date:** November 2026  
> **Audit Status:** Final Approved Blueprint — Ready for Implementation Authorization

---

## 1. Executive Summary

A comprehensive, read-only architectural inspection and reliability evaluation was conducted on the **NoteFlow** codebase to establish the definitive technical blueprint for a fully reliable, secure, offline-first **Reminders & Local Notifications** subsystem.

### Key Audit Findings & Clarifications

1. **Native Kotlin Architecture Over Fragile Plugins (Source Verified):**  
   `pubspec.yaml` contains **zero third-party notification or background execution dependencies** (no `flutter_local_notifications`, `workmanager`, or `android_alarm_manager`). Reminders and alarms are orchestrated via a dedicated custom Android native Kotlin subsystem located in `android/app/src/main/kotlin/com/noteflow/app/reminders/` (`ReminderManager.kt`, `AlarmReceiver.kt`, `NotificationActionReceiver.kt`, `BootReceiver.kt`) interfaced through a bidirectional Flutter platform channel (`com.noteflow.app/reminders`). This design completely insulates the project from plugin build failures under modern toolchains (AGP 9, compileSdk 36, targetSdk 36).

2. **Dormant SQLite vs. Authoritative JSON Persistence (Source Verified):**  
   Drift SQLite (`drift: ^2.20.0`) is configured in the codebase but entirely dormant at runtime. The authoritative single source of truth is `LocalNoteRepository` (`lib/core/database/local_note_repository.dart`). Reminder metadata is serialized directly into `<Documents>/noteflow_data.json` under the `'reminders'` top-level key. Reminders are maintained as first-class domain entities (`ReminderEntity`) associated with notes, checklist items, and audio clips via foreign keys.

3. **Substantial Existing Foundation (Source Verified):**  
   NoteFlow already contains a mature reminder implementation spanning:
   * Domain models (`ReminderEntity`, `ReminderRepeatMode`).
   * Repository CRUD, monotonic ID tracking, and stream controllers.
   * `ReminderService` with RFC 5545 calendar recurrence calculations.
   * Presentation widgets (`ReminderBottomSheet`, `ReminderChip`, `ReminderCard`, `ReminderManagementScreen`).
   * Android `AlarmManager` scheduling with Android 12–14 permission guards.
   * Action tray buttons ("Snooze 15m", "Mark Done") with headless action journaling.
   * Device boot and app update broadcast recovery (`BootReceiver.kt`).
   * 16 automated integration checks in `test/unit/noteflow_core_test.dart` (Suite 29).

4. **Hardened Architecture & Reliability Guardrails (Final Round Additions):**  
   * **Durable Journal Idempotency:** Replaces in-memory LRU tracking with durable action logging (`processed_action_records`), occurrence-bound identity tokens (`occurrenceEpochMs`), and a 5-stage transactional acknowledgement state machine.
   * **Clean Orchestration Layer:** Eliminates circular dependencies between `LocalNoteRepository` and `ReminderService` by introducing `ReminderActionCoordinator`.
   * **Channel Migration & Private-by-Default Privacy:** Migrates legacy public notification channels to `noteflow_reminders_channel_v2` with `NotificationCompat.VISIBILITY_PRIVATE`, redacted public fallbacks (`setPublicVersion`), and user preference toggles that strictly honor Android OS privacy controls.
   * **Authoritative Timezone Engine:** Assigns Kotlin as authoritative for local-to-UTC epoch millisecond conversion via `java.time.*`, while Dart manages calendar components and IANA identifier storage.
   * **Validated JSON Persistence & Recovery Mode:** Specifies serialized mutex writes, temporary file validation, atomic POSIX replacement, and a dedicated **Data Recovery Mode** that never silently initializes an empty database over unreadable files.
   * **Deterministic PendingIntent Identity:** Uses namespaced Data URIs (`noteflow://...`) and distinct actions rather than multiplier arithmetic, eliminating integer overflow and namespace collision.
   * **Canonical Flutter Documents Path:** Resolves native data files via `context.getDir("app_flutter", Context.MODE_PRIVATE)` matching `path_provider_android`, reinforced with runtime path cross-verification.
   * **Missed Reminders Anti-Flood:** Consolidates multiple power-off missed reminders into a single bundled summary alert, forward-clamping recurring reminders without notification storms.
   * **Existing Navigation Conformance:** Implements deep-link target scrolling and transient border highlights without opening the keyboard or auto-playing audio, using standard Flutter Navigator without external event buses.

---

## 2. Actual Project Architecture

### 2.1 Layering and Corrected Dependency Flow

To maintain Clean Architecture principles, **`LocalNoteRepository` must never import or call `ReminderService`**. Instead, an orchestration layer (`ReminderActionCoordinator`) coordinates incoming native journal actions, repository updates, and service-level recurrence calculations.

```
                           ┌──────────────────────────────────────────────┐
                           │          Flutter UI Presentation             │
                           │  - NoteEditorScreen / ChecklistView          │
                           │  - VoiceNoteEditorScreen / RecordingTile     │
                           │  - ReminderBottomSheet / ReminderChip        │
                           │  - ReminderManagementScreen / ReminderCard   │
                           └──────────────────────┬───────────────────────┘
                                                  │ watches / reads
                                                  ▼
                           ┌──────────────────────────────────────────────┐
                           │            Riverpod Providers                │
                           │  - noteReminderProvider(noteId)              │
                           │  - checklistItemReminderProvider(param)      │
                           │  - voiceRecordingReminderProvider(recId)     │
                           │  - reminderActionCoordinatorProvider         │
                           └──────────────────────┬───────────────────────┘
                                                  │ coordinates
                                                  ▼
                           ┌──────────────────────────────────────────────┐
                           │      ReminderActionCoordinator (New)         │
                           │  - Drains & acknowledges native journal      │
                           │  - Durable deduplication via actionId        │
                           │  - Routes markDone to ReminderService        │
                           │  - Routes snooze to ReminderService          │
                           └──────────────┬───────────────────────────────┘
                                          │ delegates
                    ┌─────────────────────┴────────────────────────┐
                    ▼                                              ▼
┌───────────────────────────────────────┐      ┌────────────────────────────────────────┐
│            ReminderService            │      │       ReminderNativeBridge             │
│  - computeNextOccurrence (RFC 5545)   │      │  - MethodChannel:                      │
│  - completeReminder (recurring logic) │      │    com.noteflow.app/reminders          │
│  - snoozeReminder                     │      │  - ackPendingJournalActions            │
│  - createReminder / updateReminder    │      │  - NativeReminderScheduler             │
└───────────────────┬───────────────────┘      └───────────────────┬────────────────────┘
                    │ calls                                        │ MethodChannel IPC
                    ▼                                              ▼
┌───────────────────────────────────────┐      ┌────────────────────────────────────────┐
│      LocalNoteRepository              │      │        Android Native (Kotlin)         │
│  - In-memory List<ReminderEntity>     │      │  - MainActivity.kt                     │
│  - StreamController (broadcast)       │      │  - ReminderManager.kt                  │
│  - Validated atomic disk persistence  │      │  - AlarmReceiver.kt (Wakeup)           │
│  - Cascade deletion & item validation │      │  - NotificationActionReceiver.kt       │
└───────────────────────────────────────┘      │  - BootReceiver.kt (Boot/Timezone)     │
                                               └────────────────────────────────────────┘
```

### 2.2 Layer Boundaries and Responsibilities

1. **Domain Layer:** Pure Dart entities (`ReminderEntity`, `ReminderRepeatMode`, `NoteEntity`). Entities are immutable with pure `toMap()`, `fromMap()`, and `copyWith()` methods.
2. **Repository Layer:** `LocalNoteRepository` is the sole data gatekeeper. It holds the in-memory cache, broadcasts updates via streams, cascades deletes when notes or clips are removed, prunes deleted checklist items, and serializes state to disk. **It has zero knowledge of `ReminderService` or recurring calendar math.**
3. **Service Layer:** `ReminderService` encapsulates reminder domain logic: monotonic notification ID assignment, RFC 5545 calendar recurrence step-forward, and coordinating repository saves with `ReminderScheduler`.
4. **Orchestrator Layer (`ReminderActionCoordinator`):** Sits above both `LocalNoteRepository` and `ReminderService`. Listens to incoming platform channel events and drains cold-boot journals, deduplicating actions via durable ledgers and dispatching recurring completions safely.
5. **Platform Bridge Layer:** `ReminderNativeBridge` handles Dart-to-Kotlin `MethodChannel` invocations and receives native broadcast events (`onNotificationTapped`, `onReminderActionReceived`).
6. **Native Android Subsystem:** Direct calls to `AlarmManager` (`RTC_WAKEUP`), `NotificationManager` (NotificationCompat, High Importance Channel), and BroadcastReceivers for background actions and cold-boot recovery.

---

## 3. Existing Reminder Implementation Inventory

Every reminder capability was inspected against the codebase and classified:

| Capability | Classification | Evidence & Source Reference |
| :--- | :--- | :--- |
| **Reminder creation and editing** | **Source Verified** | `ReminderService.createReminder()`, `ReminderService.updateReminder()`, `ReminderBottomSheet.dart` |
| **One-time reminders** | **Source Verified** | `ReminderRepeatMode.never`, `ReminderEntity.isCompleted`, `ReminderService.completeReminder()`, tested in `noteflow_core_test.dart` (Test 29.8) |
| **Recurring reminders** | **Partially implemented** | RFC 5545 engine in `ReminderService.computeNextOccurrence()`, but headless notification "Mark Done" bypasses recurrence advancement |
| **Reminder scheduling** | **Source Verified** | `ReminderManager.scheduleAlarm()` via `AlarmManager.setExactAndAllowWhileIdle()` and `setAndAllowWhileIdle()` |
| **Local notifications** | **Source Verified** | `ReminderManager.buildNotification()`, Notification Channel `noteflow_reminders_channel` (Importance HIGH, lights, vibration) |
| **Notification permission handling** | **Partially implemented** | `POST_NOTIFICATIONS` declared, checked in `areNotificationsEnabled()`, but lacks lifecycle resumption auto-refresh |
| **Exact alarm permission handling** | **Source Verified** | `SCHEDULE_EXACT_ALARM` declared, `canScheduleExactAlarms()` checked, graceful fallback to `setAndAllowWhileIdle()`, settings intent |
| **Android reboot recovery** | **Partially implemented** | `BootReceiver.kt` listens to `BOOT_COMPLETED`, parses data file, re-arms future alarms. Missed alarms during power-off are dropped |
| **Time-zone & date-change handling** | **Partially implemented** | `BootReceiver.kt` handles `ACTION_TIMEZONE_CHANGED`, but parses with `TimeZone.getDefault()`, reinterpreting local wall clock as new local time |
| **Reminder cancellation & rescheduling** | **Source Verified** | `ReminderManager.cancelAlarm()`, `ReminderService.deleteReminder()`, cancels both AlarmManager PendingIntent and active tray alert |
| **Reminder completion & dismissal** | **Partially implemented** | In-app completion works cleanly; notification tray "Mark Done" journals correctly but drops recurring series advancement |
| **Notification tap navigation** | **Partially implemented** | Native payload captured, but `HomeScreen` ignores `checklistItemId` / `voiceRecordingId` and does not check for voice note mode |
| **Persistence after app restart** | **Source Verified** | `LocalNoteRepository.init()` loads `'reminders'` from `noteflow_data.json`, monotonic `next_notification_id` preserved across reboots |
| **Backup and restore support** | **Source Verified** | `BackupService` exports `'reminders'` in v3 ZIP and JSON formats; `RestoreService` restores in both Replace and Merge modes |

---

## 4. Relevant Source Files and Their Responsibilities

### 4.1 Dart / Flutter Files

* **`lib/shared/models/reminder_entity.dart`:**  
  Declares `ReminderEntity` and `ReminderRepeatMode` enum (`never`, `daily`, `weekly`, `monthly`, `custom`). Computed properties: `effectiveScheduledAt`, `isOverdue`, `isSnoozed`, `isToday`, `isUpcoming`, `isChecklistItemReminder`, `isVoiceRecordingReminder`, `isWholeNoteReminder`.
* **`lib/features/reminders/services/reminder_action_coordinator.dart` (New Proposed Orchestrator):**  
  Orchestrates journal action draining, maintains durable action logs, routes recurring completions to `ReminderService.completeReminder()`, and acknowledges processed actions back to native storage.
* **`lib/features/reminders/services/reminder_service.dart`:**  
  Encapsulates reminder domain logic: `computeNextOccurrence` (RFC 5545), `createReminder`, `updateReminder`, `completeReminder`, `snoozeReminder`, and `deleteReminder`.
* **`lib/features/reminders/services/reminder_scheduler.dart`:**  
  Abstract interface `ReminderScheduler` and `NoOpReminderScheduler` enabling mock-based unit testing without Android platform channels.
* **`lib/features/reminders/services/reminder_native_bridge.dart`:**  
  Static communication gateway for `MethodChannel('com.noteflow.app/reminders')`. Handles native scheduling, cancellations, permission queries, action journal draining, and selective acknowledgement.
* **`lib/features/reminders/providers/reminder_providers.dart`:**  
  Riverpod providers for UI bindings: `remindersStreamProvider`, `activeRemindersStreamProvider`, `upcomingRemindersProvider`, `todayRemindersProvider`, `overdueRemindersProvider`, `completedRemindersProvider`, `noteReminderProvider`, `checklistItemReminderProvider`, `voiceRecordingReminderProvider`.
* **`lib/features/reminders/presentation/widgets/reminder_chip.dart`:**  
  Visual chip rendering relative time, overdue alerts, snooze count, repeat icon, and quick deletion.
* **`lib/features/reminders/presentation/widgets/reminder_bottom_sheet.dart`:**  
  Interactive modal for creating/editing reminders with quick presets, date/time pickers, recurrence selector, and permission guidance.
* **`lib/features/reminders/presentation/widgets/reminder_card.dart`:**  
  Full reminder card used in `ReminderManagementScreen` with completion checkbox, note preview, context badge, snooze indicator, and quick action bar.
* **`lib/features/reminders/presentation/reminder_management_screen.dart`:**  
  Tabbed reminder management hub (`Upcoming`, `Today`, `Overdue`, `Completed`) with badge counts and settings shortcuts.
* **`lib/core/database/local_note_repository.dart`:**  
  Authoritative single-file persistence engine. Manages `_reminders`, broadcast streams, cascading deletions, checklist item tag pruning, and disk writes.
* **`lib/features/editor/presentation/widgets/checklist_view.dart`:**  
  Embeds invisible comment tags `<!--id:uuid-->` to stably link reminders to specific markdown checklist items.
* **`lib/features/voice_notes/presentation/widgets/voice_recording_tile.dart`:**  
  Integrates per-clip reminders via `voiceRecordingReminderProvider`.
* **`lib/features/backup/services/backup_service.dart` & `restore_service.dart`:**  
  Handles atomic backup export and restoration of reminder data across Replace and Merge strategies.

### 4.2 Android Native (Kotlin) Files

* **`android/app/src/main/kotlin/com/noteflow/app/MainActivity.kt`:**  
  Registers `com.noteflow.app/reminders` MethodChannel. Handles permission requests, drains SharedPreferences journal, captures cold-boot notification launch intents, and dispatches events to Flutter.
* **`android/app/src/main/kotlin/com/noteflow/app/reminders/ReminderManager.kt`:**  
  Direct bridge to Android system services. Configures `NotificationChannel`, handles `AlarmManager` exact/inexact scheduling with Android 12–14 compatibility, constructs notifications with deep links, lock-screen privacy, and action buttons.
* **`android/app/src/main/kotlin/com/noteflow/app/reminders/AlarmReceiver.kt`:**  
  `BroadcastReceiver` triggered by `AlarmManager.RTC_WAKEUP`. Rebuilds notification and posts it via `NotificationManager.notify()`.
* **`android/app/src/main/kotlin/com/noteflow/app/reminders/NotificationActionReceiver.kt`:**  
  Headless `BroadcastReceiver` handling notification action buttons ("Snooze 15m", "Mark Done"). Cancels active alerts, re-schedules alarms for snoozes, journals actions with unique action IDs and occurrence timestamps to SharedPreferences, and notifies running Flutter engine if attached.
* **`android/app/src/main/kotlin/com/noteflow/app/reminders/BootReceiver.kt`:**  
  `BroadcastReceiver` listening to `BOOT_COMPLETED`, `MY_PACKAGE_REPLACED`, `TIME_SET`, and `TIMEZONE_CHANGED`. Parses canonical Flutter data file and re-arms future alarms.
* **`android/app/src/main/AndroidManifest.xml`:**  
  Declares permissions (`POST_NOTIFICATIONS`, `SCHEDULE_EXACT_ALARM`, `RECEIVE_BOOT_COMPLETED`, `VIBRATE`) and registers broadcast receivers.

---

## 5. Detailed Architecture Corrections

### 5.1 Durable Journal Idempotency & Clean Orchestration

#### Limitation of In-Memory Tracking
In-memory LRU cache tracking of `actionId` strings fails when the Android OS kills the application process between notification clicks or during cold boots. If the process is terminated, an unacknowledged action redelivered by SharedPreferences would be re-processed as new.

#### Durable Action Ledger
To guarantee idempotency across process death without adding external database engines:
1. `LocalNoteRepository` stores a persisted array of processed action IDs:
   ```json
   "processed_action_ids": [
     "action_a1b2c3d4-...",
     "action_e5f6g7h8-..."
   ]
   ```
2. The ledger is capped at the 500 most recent action IDs (pruning oldest entries during save).

#### Occurrence-Bound Action Identity
Relying on `isCompleted == true` fails for recurring reminders because recurring reminders remain `isCompleted == false` after advancing to the next cycle.

To prevent duplicate advancement:
1. When `AlarmReceiver` schedules or posts an alarm, it embeds the exact planned trigger timestamp:
   ```kotlin
   intent.putExtra(ReminderManager.EXTRA_OCCURRENCE_EPOCH_MS, triggerEpochMs)
   ```
2. When the user taps "Mark Done" in the notification tray, `NotificationActionReceiver.kt` includes `occurrenceEpochMs` in the journaled JSON:
   ```kotlin
   val actionData = JSONObject().apply {
       put("actionId", UUID.randomUUID().toString())
       put("action", "markDone")
       put("notificationId", notificationId)
       put("noteId", noteId)
       put("occurrenceEpochMs", occurrenceEpochMs)
       put("timestampMs", System.currentTimeMillis())
   }
   ```
3. **Idempotency Rule for Recurring Reminders:**  
   When `ReminderActionCoordinator` processes a `markDone` action:
   * It inspects the target reminder's current `scheduledAt.millisecondsSinceEpoch`.
   * **If `reminder.scheduledAt.millisecondsSinceEpoch > action.occurrenceEpochMs`:** The target occurrence was **already completed and advanced** (e.g. by an earlier in-app interaction or prior journal pass).
   * The action is immediately marked acknowledged without re-advancing the cycle or scheduling a redundant alarm.

#### 5-Stage Processing Protocol & Crash Recovery

```
Stage 1: PENDING_NATIVE
- NotificationActionReceiver writes action JSON to SharedPreferences ("action_<id>")
- Crash recovery: Data safe in Android private XML. Re-delivered on next launch.

Stage 2: DISPATCHED_DART
- ReminderNativeBridge.getPendingJournalActions() delivers batch to ReminderActionCoordinator
- Crash recovery: Actions remain in SharedPreferences (unacknowledged).

Stage 3: COMMITTED_REPO
- Coordinator verifies occurrenceEpochMs and processed_action_ids
- ReminderService advances recurring date or marks one-time done
- LocalNoteRepository writes updated reminder AND records actionId in processed_action_ids
- Crash recovery: Database is valid. On next boot, redelivered action matches processed_action_ids -> skips re-execution.

Stage 4: SCHEDULED_NATIVE
- ReminderScheduler schedules next occurrence alarm in AlarmManager
- Crash recovery: If crash occurs before Stage 4, startup alarm reconciliation re-arms any active future reminder whose OS alarm is missing.

Stage 5: ACKNOWLEDGED_NATIVE
- ReminderNativeBridge.ackPendingJournalActions([actionId]) called
- Native SharedPreferences removes "action_<id>"
- Complete.
```

---

### 5.2 Notification Deep Links & Existing Navigation Architecture

#### Constraint Verification
The routing implementation must integrate strictly within NoteFlow's **existing navigation architecture** (`Navigator.push`, `MaterialPageRoute`, constructor properties). No third-party router or event bus is introduced.

#### Deep-Link Routing Specifications

```
                       [Notification Tapped]
                                 │
                                 ▼
                     [MainActivity.onNewIntent]
            Captures noteId, checklistItemId, voiceRecordingId
                                 │
                                 ▼
                      [HomeScreen Notification Handler]
                                 │
                                 ▼
                   Query: repo.getNoteById(noteId)
                                 │
         ┌───────────────────────┼───────────────────────┐
         ▼                       ▼                       ▼
    [note == null]        [note.isArchived]         [note != null]
    Show SnackBar:        Open editor with          Check current route:
    "Target note was      persistent unarchive      Is user editing same noteId?
    deleted". Dismiss.    banner.                   ├── YES: Pop dialogs, focus item
                                                    └── NO:  Push respective editor
                                                                  │
                                            ┌─────────────────────┴─────────────────────┐
                                            ▼                                           ▼
                                 [note.isChecklist == true]                    [note.hasAudio == true]
                                 NoteEditorScreen(                             VoiceNoteEditorScreen(
                                   isChecklist: true,                            noteId: noteId,
                                   targetChecklistItemId: itemId,                targetVoiceRecordingId: recId,
                                 )                                             )
                                 - Scrollable.ensureVisible                    - Scroll to VoiceRecordingTile
                                 - 1.2s border pulse                           - 1.2s border pulse
                                 - autoFocus: FALSE                            - autoPlay: FALSE
```

1. **Checklist Item Focus Without Keyboard:**  
   When navigating to a checklist item, `ChecklistView` calls `Scrollable.ensureVisible` on the targeted item's context and activates a transient 1.2-second highlight pulse border. It sets `autoFocus: false` to ensure the soft keyboard does not auto-open and obscure the checklist context.
2. **Voice Recording Focus Without Playback:**  
   When navigating to an audio clip reminder, `VoiceNoteEditorScreen` scrolls to the `VoiceRecordingTile` and pulses its border. It **does not auto-play audio**, preventing unexpected loud playback in public environments.
3. **Archived Notes:**  
   Opens in the appropriate editor with a persistent top banner: *"This note is in the Archive"* with an *"Unarchive"* button.
4. **Deleted Targets:**  
   If `repo.getNoteById(noteId)` returns null, display a standard SnackBar (*"Target note has been deleted"*), cancel any lingering system notification, and stay on the current screen.
5. **Stack Deduplication:**  
   Inspect `ModalRoute.of(context)?.settings.name`. If the top route is already editing `noteId`, pop any open bottom sheets/modals and apply the highlight to the existing screen without pushing a duplicate route.

---

### 5.3 Authoritative Timezone Engine & Calendar Recurrence

#### Authoritative Separation: Dart vs. Kotlin
* **Dependency Reality:** `pubspec.yaml` does not contain `package:timezone`. Standard Dart `DateTime` only supports UTC and local device time.
* **Authoritative Division:**
  * **Dart (Feature Layer):** Authoritative for **calendar date arithmetic** (`year`, `month`, `day`, `hour`, `minute`). When recurring reminders advance, Dart computes the next calendar date using RFC 5545 logic, preserving floating wall-clock time across DST transitions.
  * **Kotlin (Native Layer):** Authoritative for **local-to-UTC epoch millisecond conversion** for `AlarmManager.RTC_WAKEUP`. Android SDK (API 26+) provides full built-in IANA timezone rules via `java.time.ZoneId` and `java.time.ZonedDateTime`.

#### IANA Storage & Legacy Abbreviation Safety
* **Storage:** All new reminders store canonical IANA strings (e.g. `'America/New_York'`, `'Europe/London'`).
* **Legacy Ambiguity:** NoteFlow contains legacy records with 3-letter abbreviations (`'EST'`, `'PST'`).
* **Non-Reinterpretation Rule:** Legacy records are mapped via standard mappings (`EST` -> `America/New_York`), but their original `scheduled_at` ISO timestamp is treated as **floating local time**. The system will **never silently shift or re-calculate historical timestamps**; the stored wall-clock hour/minute is preserved.

#### Daylight Saving Time (DST) Transitions
* **Spring Gap (2:00 AM -> 3:00 AM):** If a reminder is set for 2:30 AM during a spring-forward transition, Kotlin detects the invalid local time using `java.time.ZoneRules` and advances the alarm trigger to the transition boundary (3:00 AM local).
* **Fall Overlap (1:00 AM -> 2:00 AM repeated):** If set for 1:30 AM during an autumn fall-back transition, Kotlin resolves to the **first occurrence** (pre-transition) to prevent late alerts.

#### Device Timezone Changes
* `BootReceiver.kt` listens to `ACTION_TIMEZONE_CHANGED`.
* Floating wall-clock reminders maintain their local hour (9:00 AM remains 9:00 AM in the new timezone). `BootReceiver` converts the target local hour into the new timezone's UTC epoch milliseconds and re-arms `AlarmManager`.

---

### 5.4 Android Notification Privacy & Channel Migration

#### Channel Immutability & Migration
In Android 8.0+ (API 26+), notification channels are immutable once created. The existing channel `noteflow_reminders_channel` was created with `Notification.VISIBILITY_PUBLIC`.

To establish private defaults across all devices:
1. **Channel Migration:**  
   Create a new channel: `noteflow_reminders_channel_v2` with `lockscreenVisibility = Notification.VISIBILITY_PRIVATE`.
2. **Legacy Cleanup:**  
   Delete the old channel: `notificationManager.deleteNotificationChannel("noteflow_reminders_channel")`. Existing user custom ringtones are migrated cleanly to the v2 channel.

#### Lock-Screen Privacy Enforcement
```kotlin
// Public Redacted Notification (Shown on secure lock screen)
val publicNotification = NotificationCompat.Builder(context, CHANNEL_ID)
    .setSmallIcon(smallIconRes)
    .setContentTitle("NoteFlow Reminder")
    .setContentText("You have a scheduled reminder")
    .setColor(Color.parseColor("#2563EB"))
    .build()

// Private Detailed Notification (Shown only after unlock)
val privateNotification = NotificationCompat.Builder(context, CHANNEL_ID)
    .setSmallIcon(smallIconRes)
    .setContentTitle(if (showPreview) title else "NoteFlow Reminder")
    .setContentText(if (showPreview) body else "You have a scheduled reminder")
    .setVisibility(if (showPreview) NotificationCompat.VISIBILITY_PUBLIC else NotificationCompat.VISIBILITY_PRIVATE)
    .setPublicVersion(publicNotification)
    .setContentIntent(contentPendingIntent)
    .addAction(...)
    .build()
```
* **Strict Respect for System Privacy:** If the user sets Android OS settings to "Don't show sensitive notification content", Android automatically renders `publicNotification`. NoteFlow never attempts to bypass system-level privacy configurations.
* **User In-App Toggle:** Setting: *"Show note previews on lock screen"* (defaults to `false` / Private).

---

### 5.5 PendingIntent Identity & Collision Prevention

#### Removal of Multiplier Arithmetic
The existing implementation used arithmetic multipliers:
```kotlin
// INSECURE: Risk of integer overflow and request code collisions
val snoozePi = PendingIntent.getBroadcast(context, notificationId * 10 + 1, snoozeIntent, flags)
val donePi = PendingIntent.getBroadcast(context, notificationId * 10 + 2, doneIntent, flags)
```

#### Deterministic URI-Based Identity
Android's `Intent.filterEquals()` specification guarantees that intents with differing `action` or `data` URIs are treated as distinct `PendingIntent` instances by the OS kernel, even when sharing identical request codes.

```kotlin
// 1. Alarm PendingIntent
val alarmIntent = Intent(context, AlarmReceiver::class.java).apply {
    action = "com.noteflow.app.TRIGGER_ALARM"
    data = Uri.parse("noteflow://alarm/$notificationId")
}
val alarmPi = PendingIntent.getBroadcast(context, notificationId, alarmIntent, flags)

// 2. Tap Content PendingIntent
val tapIntent = Intent(context, MainActivity::class.java).apply {
    action = "com.noteflow.app.OPEN_REMINDER"
    data = Uri.parse("noteflow://tap/$notificationId")
    flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
}
val tapPi = PendingIntent.getActivity(context, notificationId, tapIntent, flags)

// 3. Snooze Action PendingIntent
val snoozeIntent = Intent(context, NotificationActionReceiver::class.java).apply {
    action = "com.noteflow.app.ACTION_SNOOZE"
    data = Uri.parse("noteflow://snooze/$notificationId")
}
val snoozePi = PendingIntent.getBroadcast(context, notificationId, snoozeIntent, flags)

// 4. Mark Done Action PendingIntent
val doneIntent = Intent(context, NotificationActionReceiver::class.java).apply {
    action = "com.noteflow.app.ACTION_MARK_DONE"
    data = Uri.parse("noteflow://done/$notificationId")
}
val donePi = PendingIntent.getBroadcast(context, notificationId, doneIntent, flags)
```

#### Monotonic ID Management & Overflow Safety
* `notificationId` allocation increments sequentially (`1000`, `1001`, ...).
* During backup restoration, `_nextNotificationId = max(restored_ids) + 1`.
* **Overflow Protection:** If `_nextNotificationId` approaches `1,000,000,000` (well below `Int.MAX_VALUE`), the allocator compacts and reclaims IDs not currently bound to active reminders, keeping IDs strictly within positive 32-bit limits.
* **Stale Alarm Cancellation:** When a reminder is updated or deleted, `cancelAlarm(notificationId)` cancels the exact PendingIntent matching `noteflow://alarm/$notificationId`.

---

### 5.6 Missed Reminders & Anti-Flood Recovery

#### Recovery Rules
When `BootReceiver.kt` runs following a reboot:
1. **One-Time Reminders:**
   * If expired within a **24-hour grace window** during power-off: Collected in `missedReminders`.
   * If expired >24 hours ago: Marked overdue in database; no audio alert is triggered.
2. **Recurring Reminders:**
   * **Forward-Clamped:** The reminder advances to the next upcoming occurrence strictly in the future.
   * **Single Summary Inclusion:** Missed recurring cycles do **not** trigger individual alarms. At most, one missed alert is registered.
3. **Anti-Flood Throttling:**
   * If `missedReminders.size == 1`: Post 1 notification: *"Missed Reminder: [Title]"*.
   * If `missedReminders.size > 1`: Post **1 consolidated summary notification**:
     * Title: *"5 Missed Reminders"*
     * Body: *"Tap to view tasks that expired while your device was off"*
     * Tap Target: Opens `ReminderManagementScreen(initialTabIndex: 2)` (Overdue tab).
4. **Permission Denied Handling:**
   * If notification permissions are disabled, alarms are updated in the repository but notification posting is skipped cleanly without throwing exceptions.

---

### 5.7 Atomic JSON Persistence & Safe Recovery Mode

#### Realistic Durability Boundaries
POSIX atomic rename (`File.rename`) ensures that a file replacement operation in the directory table is atomic from a user-space perspective. However, hardware-level durability is subject to flash controller reordering and filesystem sync barriers. We do not claim 100% crash protection under catastrophic power loss, but implement a hardened two-phase protocol that eliminates partial write corruptions.

#### Two-Phase Persist Protocol
```
[Save Triggered] ──► [_dbWriteMutex.lock()]
                           │
                           ▼
             [1. In-Memory Snapshot Taken]
                           │
                           ▼
             [2. Write to noteflow_data.json.tmp]
             (flush: true, file descriptor sync)
                           │
                           ▼
             [3. Validate noteflow_data.json.tmp]
             - File length > 0
             - Valid JSON syntax parse
             - Required root keys: "notes", "reminders"
                           │
                           ▼
             [4. POSIX Atomic Rename]
             (rename .tmp -> noteflow_data.json)
                           │
                           ▼
             [Release _dbWriteMutex]
```

#### Safe Data Recovery Mode (No Silent Data Destruction)
* **Critical Protection:** If `noteflow_data.json` is missing, 0 bytes, or corrupt:
  1. Check for `noteflow_data.json.tmp` and `noteflow_data.json.bak`. If valid, recover from fallback.
  2. **If all files are unreadable:**  
     **NEVER silently seed demo data or initialize a blank repository!** Silently initializing an empty database overwrites user data permanently.
  3. The repository preserves unreadable files as `noteflow_data.json.corrupt.<timestamp>`.
  4. The repository enters a read-only **"Data Recovery Mode"**, prompting the user with an explicit dialog: *"Unable to read note data. Please restore from a backup or contact support."*

---

### 5.8 Native Flutter Documents Path & Runtime Verification

#### Path Resolution Mechanism
In Flutter's `path_provider_android`, `getApplicationDocumentsDirectory()` resolves to `context.getDir("app_flutter", Context.MODE_PRIVATE)`.

Contrast with string path arithmetic:
* `File(context.filesDir.parent, "app_flutter")` is a path hack that can fail in sandboxed or multi-user profiles.

#### Native Resolution in `BootReceiver.kt`
```kotlin
private fun getAuthoritativeDataFile(context: Context): File? {
    // 1. Canonical Flutter documents directory
    val flutterDir = context.getDir("app_flutter", Context.MODE_PRIVATE)
    val canonicalFile = File(flutterDir, "noteflow_data.json")
    if (canonicalFile.exists() && canonicalFile.length() > 0) return canonicalFile

    // 2. Standard internal filesDir fallback
    val fallbackFile = File(context.filesDir, "noteflow_data.json")
    if (fallbackFile.exists() && fallbackFile.length() > 0) return fallbackFile

    return null
}
```

#### Runtime Verification Protocol
During application startup in `MainActivity.kt`:
1. Flutter queries `getApplicationDocumentsDirectory().path`.
2. Passes path to `ReminderNativeBridge.verifyDocumentsPath(path)`.
3. Kotlin asserts `path == context.getDir("app_flutter", Context.MODE_PRIVATE).absolutePath`.
4. If a discrepancy is detected, Kotlin logs a diagnostic warning and updates its internal storage pointer.

---

## 6. Revised Failure and Recovery Matrix

| Failure Scenario | Risk / Impact | Source Verified Behavior | Proposed Hardened Safeguard |
| :--- | :--- | :--- | :--- |
| **App Process Killed** | Background reminder lost | Alarms registered in kernel `AlarmManager` (`RTC_WAKEUP`); OS wakes app via `AlarmReceiver` | Verified robust. No changes needed. |
| **Device Rebooted** | OS clears all pending alarms | `BootReceiver` parses JSON and re-arms future alarms | Adopt canonical `context.getDir("app_flutter", ...)`. Add missed-reminder recovery. |
| **Device Powered Off During Alarm** | Alarm time passes while off | Reminder silently dropped; becomes overdue without notice | Consolidated anti-flood notification: *"You missed X reminders"* posted upon boot. |
| **Notification Permission Denied** | Alarms fire in background but cannot post alert | Warning banner shown in bottom sheet | Add `AppLifecycleListener` to auto-clear warning upon returning from Android Settings. |
| **Exact Alarm Revoked (Android 14+)** | `SecurityException` on `setExactAndAllowWhileIdle` | Catches exception, falls back to `setAndAllowWhileIdle` / `set` | Verified robust. User guidance banner links to exact alarm settings. |
| **Headless Action: "Mark Done" on Recurring** | Series terminates prematurely | Repository sets `isCompleted: true`, bypassing recurrence math | Route via `ReminderActionCoordinator` to call `ReminderService.completeReminder()`. |
| **Headless Action Crash** | SharedPreferences journal desync | `getPendingJournalActions` cleared all entries blindly | Two-phase selective ack: `ackPendingJournalActions(List<String> ids)`. |
| **Note Deleted While Scheduled** | Orphaned alarm fires for deleted note | `deleteNote` cascades deletion to all child reminders and cancels OS alarms | Verified robust in `noteflow_core_test.dart` (Test 29.13). |
| **Checklist Item Deleted from Content** | Stale reminder triggers for deleted item | `saveNote` scans for `<!--id:...-->` tags, prunes orphaned reminders | Verified robust in `noteflow_core_test.dart` (Test 29.15). |
| **Duplicate Notification Action Tap** | User taps "Snooze" twice in rapid succession | Potential duplicate alarm scheduling | Unique `actionId` + idempotency check in coordinator drops duplicate actions. |
| **PendingIntent Collision** | `id * 10 + 1` overlaps other requestCodes | Multiplier arithmetic could collide or overflow integer limits | Unique Data URIs (`noteflow://snooze/$id`) guarantee complete OS-level isolation. |
| **Time-Zone Traversal** | Alarm triggers at wrong local or UTC time | Floating wall-clock time preserved via `ACTION_TIMEZONE_CHANGED` re-arm | Canonical IANA identifiers + leap-year and DST transition clamping. |
| **Crash During JSON Write** | Corrupted or 0-byte `noteflow_data.json` | Direct overwrite via `writeAsString(flush: true)` | Two-phase write: write to `.tmp`, validate length/syntax, atomic rename. Safe Data Recovery Mode. |
| **Concurrent Editor Saves** | Race condition overwriting reminders | Single in-memory repository instance | Serialized `dbWriteMutex` locks write operations during disk commit. |

---

## 7. Hardened Testing Strategy

### 7.1 Existing Verified Tests (Suite 29 in `noteflow_core_test.dart`)

* `Test 29.1`: Entity serialization and deserialization.
* `Test 29.2`: Entity `copyWith` and computed properties (`effectiveScheduledAt`, `isOverdue`, `isToday`).
* `Test 29.3`: Whole-note reminder scheduling.
* `Test 29.4`: Checklist item reminder scheduling with `checklistItemId`.
* `Test 29.5`: Voice recording reminder scheduling with `voiceRecordingId`.
* `Test 29.6`: Monotonic notification ID allocation and zero collision.
* `Test 29.7`: RFC 5545 calendar recurrence engine (daily, weekly, monthly anchor day clamping in non-leap vs leap years).
* `Test 29.8`: One-time vs recurring completion advancement.
* `Test 29.9`: Multi-stage snooze incrementation and effective scheduled time.
* `Test 29.10`: Update reminder (cancels previous alarm and re-arms new alarm).
* `Test 29.11`: Delete reminder (removes from repo and cancels alarm).
* `Test 29.12`: Cold restart recovery and disk persistence roundtrip.
* `Test 29.13`: Note cascade deletion (cancels child alarms and removes reminders).
* `Test 29.14`: Voice recording cascade deletion (cancels clip alarm and removes reminder).
* `Test 29.15`: Checklist item removal auto-invalidation (`<!--id:...-->` tag parsing).
* `Test 29.16`: Action journal draining and backup/restore roundtrip (Replace & Merge).

### 7.2 Required Additional Automated & Integration Tests

```
┌────────────────────────────────────────────────────────────────────────┐
│                        Comprehensive Test Tiers                        │
├────────────────────────┬───────────────────────┬───────────────────────┤
│ Tier 1: Unit Tests     │ Tier 2: Integration   │ Tier 3: Physical Device│
├────────────────────────┼───────────────────────┼───────────────────────┤
│ - Durable Action Logs  │ - Journal Draining &  │ - Android 12, 13, 14  │
│ - Forward-Clamping Math│   Two-Phase Ack       │   Cold Boot Alarms    │
│ - DST Transition Gaps  │ - Atomic Rename &     │ - Headless Action Tray│
│ - Data URI Identity    │   Corrupt .tmp Rollback│  ("Snooze" / "Done") │
│ - IANA Tz Fallback     │ - Deep Link Routing   │ - Lock-Screen Redaction│
│ - Mutex Write Queue    │   to Checklist/Voice  │ - Doze Mode Wakeup    │
└────────────────────────┴───────────────────────┴───────────────────────┘
```

#### Detailed Test Specifications
1. **Tier 1 (Unit & Domain):**
   * `Test 29.17: Action Journal Durable Idempotency`: Deliver action with existing `actionId`; verify repository updates only once.
   * `Test 29.18: Recurring Series Headless Advancement`: Simulate `markDone` with `occurrenceEpochMs`; verify `scheduledAt` advances to next cycle, `isCompleted` remains `false`, and next alarm is scheduled.
   * `Test 29.19: Multi-Occurrence Missed Forward Clamping`: Given a daily reminder from 5 days ago, verify completing it clamps `scheduledAt` to tomorrow.
   * `Test 29.20: IANA Time-Zone Parsing & Legacy Fallback`: Verify that `'EST'`, `'PST'`, and `'UTC'` resolve cleanly without throwing exceptions.
   * `Test 29.21: Data URI PendingIntent Uniqueness`: Verify URI generation produces non-colliding identity strings across 100,000 simulated IDs.
2. **Tier 2 (Repository & Persistence Integration):**
   * `Test 29.22: Atomic Two-Phase JSON Save`: Simulate an interrupted write (kill process mid-write); verify startup recovers from valid `.tmp` or preserves existing database.
   * `Test 29.23: Concurrent Write Serialization`: Fire 20 parallel `saveReminder` calls; verify zero file write contention and valid resulting JSON.
   * `Test 29.24: Selective Journal Acknowledgement`: Deliver 3 actions; acknowledge 2; verify only the 2 acknowledged actions are removed from native preferences.
   * `Test 29.25: Deep Link Parameter Disambiguation`: Verify that navigation payloads containing `checklistItemId` route to checklist mode and pass focus parameters without opening keyboard.
3. **Tier 3 (Physical Device Acceptance):**
   * **Device Reboot Test:** Schedule reminders on Android 12, 13, and 14 physical devices; power off device; power on; verify `BootReceiver` re-arms alarms.
   * **Power-Off Missed Reminder Test:** Schedule reminder for +2 minutes; power off device for 5 minutes; power on; verify bundled *"Missed Reminder"* notification appears.
   * **Lock-Screen Privacy Verification:** Trigger notification while device is PIN-locked; verify notification displays generic title and hides note content; unlock device and verify note body appears.
   * **Headless Action Execution:** Trigger notification; kill NoteFlow process from Recents; tap "Snooze 15m"; verify alarm re-arms in OS and snooze count updates in app upon launch.

---

## 8. Revised Implementation Phases

| Phase | Title | Scope & Deliverables |
| :--- | :--- | :--- |
| **Phase 1** | **Orchestration Layer & Durable Journal** | Implement `ReminderActionCoordinator`. Update `NotificationActionReceiver.kt` to record `actionId` and `occurrenceEpochMs`. Implement `ackPendingJournalActions`. Fix recurring series advancement. |
| **Phase 2** | **PendingIntent URI Identity & Privacy** | Update `ReminderManager.kt` to use distinct `noteflow://` Data URIs. Implement `noteflow_reminders_channel_v2` with `NotificationCompat.VISIBILITY_PRIVATE` and public fallback. |
| **Phase 3** | **Deep-Link Routing & Stack Safety** | Refactor `HomeScreen._initNotificationRouting` to look up note mode. Pass `checklistItemId` (scroll/highlight without keyboard) and `voiceRecordingId` (scroll/highlight without playback). |
| **Phase 4** | **Reboot Recovery & Missed Alarms** | Update `BootReceiver.kt` to use canonical `context.getDir("app_flutter", Context.MODE_PRIVATE)`. Add missed-reminder recovery logic with anti-flood bundling. |
| **Phase 5** | **Atomic Persistence & Lifecycle Observer** | Add two-phase write pattern (`.tmp` -> validate -> atomic rename) in `LocalNoteRepository._saveToDisk()`. Implement Safe Data Recovery Mode. Add `AppLifecycleListener` to `ReminderBottomSheet`. |
| **Phase 6** | **Test Suite Expansion & Verification** | Implement automated Tests 29.17–29.25 in `test/unit/noteflow_core_test.dart`. Execute full test suite (Suites 1–43). Conduct physical device acceptance testing across Android 12, 13, and 14+. |

---

## 9. Remaining Unresolved Questions

1. **User Exemption for Aggressive OEM Battery Optimizers:**  
   Certain OEM Android distributions (Xiaomi MIUI/HyperOS, Huawei EMUI, Samsung OneUI) throttle background alarms even when using `setExactAndAllowWhileIdle`. Should NoteFlow introduce an optional settings dialog guiding users to disable battery optimization?
2. **Custom Multi-Day Recurrence Rules (RFC 5545 RRULE):**  
   The current recurrence model supports `daily`, `weekly`, `monthly`, and `custom` (interval in days). Should future milestones support arbitrary day-of-week selections (e.g. "Every Monday, Wednesday, and Friday")?
3. **Sound and Ringtone Customization:**  
   Currently, the notification uses the Android system default reminder sound. Should users be given an in-app selector for custom notification ringtones or audio cues?

---

## 10. Architectural Separation: Verified vs. Proposed

To prevent ambiguity, the system distinguishes between verified code and proposed safeguards:

* **Source-Inspected & Implemented Behavior:**
  * Clean single-file JSON persistence in `<app_flutter>/noteflow_data.json`.
  * `AlarmManager.RTC_WAKEUP` scheduling with Android 12/14 exact alarm fallbacks.
  * Headless broadcast receivers (`AlarmReceiver`, `NotificationActionReceiver`, `BootReceiver`).
  * Unit test suite Suite 29 (16 assertions executing in `noteflow_core_test.dart`).
* **Proposed Design Safeguards (To Be Implemented in Phase 1–5):**
  * `ReminderActionCoordinator` decoupling repository from `ReminderService`.
  * Occurrence-bound `occurrenceEpochMs` journal identity and durable action ledger.
  * `noteflow_reminders_channel_v2` migration with lock-screen content redaction.
  * Deterministic Data URIs for PendingIntent identity isolation.
  * Two-phase atomic write with Safe Data Recovery Mode.
  * Anti-flood bundled missed-reminder notifications upon reboot.

---

## 11. Final Review — Remaining Reliability Safeguards

### Reliability Safeguards Checklist

#### Resolved in This Specification
- [x] **No Circular Repository Dependencies:** `LocalNoteRepository` does not depend on `ReminderService`; orchestration handled by `ReminderActionCoordinator`.
- [x] **Durable Idempotency:** Processed action IDs are persisted to disk; recurring actions are bound to `occurrenceEpochMs` to prevent multi-advance bugs.
- [x] **Selective Journal Acknowledgement:** Two-phase commit protocol removes only verified actions from SharedPreferences.
- [x] **Lock-Screen Privacy:** Default `NotificationCompat.VISIBILITY_PRIVATE` with generic public version prevents exposing sensitive note text.
- [x] **PendingIntent Identity:** Distinct Data URIs (`noteflow://...`) eliminate integer multiplier overflow and requestCode collisions.
- [x] **Canonical Android Path:** Native `BootReceiver` resolves storage via `context.getDir("app_flutter", Context.MODE_PRIVATE)` matching `path_provider_android`.
- [x] **Anti-Flood Missed Alarms:** Aggregates multi-day missed reminders into a single summary notification upon boot.
- [x] **Safe Recovery Mode:** Database corruption triggers read-only recovery mode rather than silently wiping data or seeding demo notes.
- [x] **Deep-Link UX Safety:** Checklist items and audio clips scroll and highlight without auto-opening keyboards or auto-playing audio.

#### Remaining Items Requiring Implementation Authorization
- [ ] Implement `ReminderActionCoordinator` and update `NotificationActionReceiver.kt` payload.
- [ ] Migrate notification channel to `noteflow_reminders_channel_v2`.
- [ ] Implement two-phase atomic write and corrupted file recovery in `LocalNoteRepository`.
- [ ] Expand `test/unit/noteflow_core_test.dart` with Tests 29.17–29.25.
- [ ] Conduct physical-device acceptance tests across Android 12, 13, and 14 hardware.
