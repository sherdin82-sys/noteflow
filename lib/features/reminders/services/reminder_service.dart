import 'dart:async';
import 'dart:math';
import '../../../core/database/local_note_repository.dart';
import '../../../shared/models/reminder_entity.dart';
import 'reminder_scheduler.dart';

class ReminderService {
  final LocalNoteRepository repository;
  final ReminderScheduler scheduler;
  final String Function() idGenerator;

  ReminderService({
    required this.repository,
    ReminderScheduler? scheduler,
    String Function()? idGenerator,
  })  : scheduler = scheduler ?? repository.reminderScheduler,
        idGenerator = idGenerator ?? _generateUuidV4;

  static String _generateUuidV4() {
    final random = Random();
    final values = List<int>.generate(16, (i) => random.nextInt(256));
    values[6] = (values[6] & 0x0f) | 0x40; // RFC 4122 version 4
    values[8] = (values[8] & 0x3f) | 0x80; // RFC 4122 variant
    return [
      values.sublist(0, 4).map((b) => b.toRadixString(16).padLeft(2, '0')).join(),
      values.sublist(4, 6).map((b) => b.toRadixString(16).padLeft(2, '0')).join(),
      values.sublist(6, 8).map((b) => b.toRadixString(16).padLeft(2, '0')).join(),
      values.sublist(8, 10).map((b) => b.toRadixString(16).padLeft(2, '0')).join(),
      values.sublist(10, 16).map((b) => b.toRadixString(16).padLeft(2, '0')).join(),
    ].join('-');
  }

  /// Computes the exact calendar recurrence without day drift (RFC 5545)
  static DateTime? computeNextOccurrence(
    DateTime current,
    ReminderRepeatMode mode, {
    int? anchorDay,
    int intervalValue = 1,
  }) {
    if (mode == ReminderRepeatMode.never) return null;

    final interval = intervalValue < 1 ? 1 : intervalValue;

    switch (mode) {
      case ReminderRepeatMode.daily:
        return DateTime(
          current.year,
          current.month,
          current.day + interval,
          current.hour,
          current.minute,
          current.second,
        );

      case ReminderRepeatMode.weekly:
        return DateTime(
          current.year,
          current.month,
          current.day + (7 * interval),
          current.hour,
          current.minute,
          current.second,
        );

      case ReminderRepeatMode.monthly:
        int targetYear = current.year;
        int targetMonth = current.month + interval;
        while (targetMonth > 12) {
          targetMonth -= 12;
          targetYear += 1;
        }

        // Clamp target anchor day to the maximum number of days in the target month (e.g. Jan 31 -> Feb 28/29)
        final maxDaysInMonth = DateTime(targetYear, targetMonth + 1, 0).day;
        final targetAnchor = anchorDay ?? current.day;
        final resolvedDay = targetAnchor <= maxDaysInMonth ? targetAnchor : maxDaysInMonth;

        return DateTime(
          targetYear,
          targetMonth,
          resolvedDay,
          current.hour,
          current.minute,
          current.second,
        );

      case ReminderRepeatMode.custom:
        return DateTime(
          current.year,
          current.month,
          current.day + interval,
          current.hour,
          current.minute,
          current.second,
        );

      case ReminderRepeatMode.never:
        return null;
    }
  }

  /// Creates and schedules a reminder atomically
  Future<ReminderEntity> createReminder({
    required String noteId,
    String? checklistItemId,
    String? voiceRecordingId,
    required String title,
    String notesPreview = '',
    required DateTime scheduledAt,
    ReminderRepeatMode repeatMode = ReminderRepeatMode.never,
    int repeatIntervalValue = 1,
  }) async {
    final now = DateTime.now();
    final notificationId = repository.getNextNotificationId();

    final reminder = ReminderEntity(
      id: idGenerator(),
      noteId: noteId,
      checklistItemId: checklistItemId,
      voiceRecordingId: voiceRecordingId,
      title: title,
      notesPreview: notesPreview,
      scheduledAt: scheduledAt,
      timeZone: DateTime.now().timeZoneName,
      repeatMode: repeatMode,
      repeatIntervalValue: repeatIntervalValue,
      isCompleted: false,
      snoozeCount: 0,
      notificationId: notificationId,
      createdAt: now,
      updatedAt: now,
    );

    await repository.saveReminder(reminder);

    // Schedule native alarm if in the future
    if (scheduledAt.isAfter(now)) {
      await scheduler.scheduleAlarm(
        notificationId: reminder.notificationId,
        triggerEpochMs: scheduledAt.millisecondsSinceEpoch,
        title: reminder.title,
        body: reminder.notesPreview.isNotEmpty ? reminder.notesPreview : 'Note Reminder',
        noteId: reminder.noteId,
        checklistItemId: reminder.checklistItemId,
        voiceRecordingId: reminder.voiceRecordingId,
      );
    }

    return reminder;
  }

  /// Edits an existing reminder and updates native alarm
  Future<void> updateReminder(ReminderEntity updated) async {
    final existing = await repository.getReminderById(updated.id);
    if (existing != null) {
      // Cancel previous alarm
      await scheduler.cancelAlarm(existing.notificationId);
    }

    final entityToSave = updated.copyWith(updatedAt: DateTime.now());
    await repository.saveReminder(entityToSave);

    // Re-schedule alarm if future and active
    final effectiveTime = entityToSave.effectiveScheduledAt;
    if (!entityToSave.isCompleted && effectiveTime.isAfter(DateTime.now())) {
      await scheduler.scheduleAlarm(
        notificationId: entityToSave.notificationId,
        triggerEpochMs: effectiveTime.millisecondsSinceEpoch,
        title: entityToSave.title,
        body: entityToSave.notesPreview.isNotEmpty ? entityToSave.notesPreview : 'Note Reminder',
        noteId: entityToSave.noteId,
        checklistItemId: entityToSave.checklistItemId,
        voiceRecordingId: entityToSave.voiceRecordingId,
      );
    }
  }

  /// Completes a reminder. If repeating, automatically advances to next cycle
  Future<void> completeReminder(String reminderId) async {
    final rem = await repository.getReminderById(reminderId);
    if (rem == null) return;

    await scheduler.cancelAlarm(rem.notificationId);

    if (rem.repeatMode == ReminderRepeatMode.never) {
      final completed = rem.copyWith(
        isCompleted: true,
        completedAt: DateTime.now(),
        clearSnoozedUntil: true,
        updatedAt: DateTime.now(),
      );
      await repository.saveReminder(completed);
    } else {
      // Advance to next recurring cycle
      final nextDate = computeNextOccurrence(
        rem.scheduledAt,
        rem.repeatMode,
        anchorDay: rem.scheduledAt.day,
        intervalValue: rem.repeatIntervalValue,
      );

      if (nextDate != null) {
        final recurringNext = rem.copyWith(
          scheduledAt: nextDate,
          isCompleted: false,
          clearCompletedAt: true,
          snoozeCount: 0,
          clearSnoozedUntil: true,
          updatedAt: DateTime.now(),
        );
        await repository.saveReminder(recurringNext);

        if (nextDate.isAfter(DateTime.now())) {
          await scheduler.scheduleAlarm(
            notificationId: recurringNext.notificationId,
            triggerEpochMs: nextDate.millisecondsSinceEpoch,
            title: recurringNext.title,
            body: recurringNext.notesPreview.isNotEmpty ? recurringNext.notesPreview : 'Note Reminder',
            noteId: recurringNext.noteId,
            checklistItemId: recurringNext.checklistItemId,
            voiceRecordingId: recurringNext.voiceRecordingId,
          );
        }
      } else {
        final completed = rem.copyWith(
          isCompleted: true,
          completedAt: DateTime.now(),
          clearSnoozedUntil: true,
          updatedAt: DateTime.now(),
        );
        await repository.saveReminder(completed);
      }
    }
  }

  /// Snoozes a reminder by a duration (default 15 minutes)
  Future<void> snoozeReminder(String reminderId, [Duration duration = const Duration(minutes: 15)]) async {
    final rem = await repository.getReminderById(reminderId);
    if (rem == null) return;

    final now = DateTime.now();
    final newSnoozeTime = now.add(duration);

    final snoozed = rem.copyWith(
      snoozeCount: rem.snoozeCount + 1,
      snoozedUntil: newSnoozeTime,
      updatedAt: now,
    );

    await repository.saveReminder(snoozed);

    await scheduler.scheduleAlarm(
      notificationId: snoozed.notificationId,
      triggerEpochMs: newSnoozeTime.millisecondsSinceEpoch,
      title: snoozed.title,
      body: snoozed.notesPreview.isNotEmpty ? snoozed.notesPreview : 'Note Reminder (Snoozed)',
      noteId: snoozed.noteId,
      checklistItemId: snoozed.checklistItemId,
      voiceRecordingId: snoozed.voiceRecordingId,
    );
  }

  /// Deletes a reminder and cancels its native alarm
  Future<void> deleteReminder(String reminderId) async {
    final rem = await repository.getReminderById(reminderId);
    if (rem != null) {
      await scheduler.cancelAlarm(rem.notificationId);
    }
    await repository.deleteReminder(reminderId);
  }
}
