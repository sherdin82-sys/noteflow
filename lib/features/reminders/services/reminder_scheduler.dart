abstract class ReminderScheduler {
  Future<void> scheduleAlarm({
    required int notificationId,
    required int triggerEpochMs,
    required String title,
    required String body,
    String? noteId,
    String? checklistItemId,
    String? voiceRecordingId,
  });

  Future<void> cancelAlarm(int notificationId);
}

class NoOpReminderScheduler implements ReminderScheduler {
  const NoOpReminderScheduler();

  @override
  Future<void> scheduleAlarm({
    required int notificationId,
    required int triggerEpochMs,
    required String title,
    required String body,
    String? noteId,
    String? checklistItemId,
    String? voiceRecordingId,
  }) async {}

  @override
  Future<void> cancelAlarm(int notificationId) async {}
}
