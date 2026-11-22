import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/database/database_provider.dart';
import '../../../core/database/local_note_repository.dart';
import '../../../shared/models/reminder_entity.dart';
import '../services/reminder_service.dart';
import '../services/reminder_action_coordinator.dart';
import '../services/reminder_native_bridge.dart';

final reminderServiceProvider = Provider<ReminderService>((ref) {
  final repo = ref.watch(noteRepositoryProvider) as LocalNoteRepository;
  return ReminderService(repository: repo);
});

final reminderActionCoordinatorProvider = Provider<ReminderActionCoordinator>((ref) {
  final repo = ref.watch(noteRepositoryProvider) as LocalNoteRepository;
  final service = ref.watch(reminderServiceProvider);
  return ReminderActionCoordinator(
    repository: repo,
    reminderService: service,
    bridge: const ReminderNativeJournalBridge(),
  );
});

final remindersStreamProvider = StreamProvider<List<ReminderEntity>>((ref) {
  final repo = ref.watch(noteRepositoryProvider);
  return repo.watchReminders();
});

final activeRemindersStreamProvider = Provider<AsyncValue<List<ReminderEntity>>>((ref) {
  final asyncReminders = ref.watch(remindersStreamProvider);
  return asyncReminders.whenData(
    (reminders) => reminders.where((r) => !r.isCompleted).toList()
      ..sort((a, b) => a.effectiveScheduledAt.compareTo(b.effectiveScheduledAt)),
  );
});

final todayRemindersProvider = Provider<AsyncValue<List<ReminderEntity>>>((ref) {
  final asyncReminders = ref.watch(remindersStreamProvider);
  return asyncReminders.whenData(
    (reminders) => reminders.where((r) => !r.isCompleted && r.isToday).toList()
      ..sort((a, b) => a.effectiveScheduledAt.compareTo(b.effectiveScheduledAt)),
  );
});

final overdueRemindersProvider = Provider<AsyncValue<List<ReminderEntity>>>((ref) {
  final asyncReminders = ref.watch(remindersStreamProvider);
  return asyncReminders.whenData(
    (reminders) => reminders.where((r) => !r.isCompleted && r.isOverdue).toList()
      ..sort((a, b) => a.effectiveScheduledAt.compareTo(b.effectiveScheduledAt)),
  );
});

final upcomingRemindersProvider = Provider<AsyncValue<List<ReminderEntity>>>((ref) {
  final asyncReminders = ref.watch(remindersStreamProvider);
  return asyncReminders.whenData(
    (reminders) => reminders.where((r) => !r.isCompleted && !r.isOverdue).toList()
      ..sort((a, b) => a.effectiveScheduledAt.compareTo(b.effectiveScheduledAt)),
  );
});

final completedRemindersProvider = Provider<AsyncValue<List<ReminderEntity>>>((ref) {
  final asyncReminders = ref.watch(remindersStreamProvider);
  return asyncReminders.whenData(
    (reminders) => reminders.where((r) => r.isCompleted).toList()
      ..sort((a, b) => (b.completedAt ?? b.updatedAt).compareTo(a.completedAt ?? a.updatedAt)),
  );
});

/// Family provider for whole-note reminder
final noteReminderProvider = Provider.family<ReminderEntity?, String>((ref, noteId) {
  final asyncReminders = ref.watch(remindersStreamProvider);
  return asyncReminders.maybeWhen(
    data: (reminders) {
      final matches = reminders.where((r) => r.noteId == noteId && r.isWholeNoteReminder && !r.isCompleted);
      return matches.isEmpty ? null : matches.first;
    },
    orElse: () => null,
  );
});

/// Family provider for checklist item reminder
class ChecklistItemParam {
  final String noteId;
  final String checklistItemId;

  const ChecklistItemParam({required this.noteId, required this.checklistItemId});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChecklistItemParam &&
          runtimeType == other.runtimeType &&
          noteId == other.noteId &&
          checklistItemId == other.checklistItemId;

  @override
  int get hashCode => noteId.hashCode ^ checklistItemId.hashCode;
}

final checklistItemReminderProvider = Provider.family<ReminderEntity?, ChecklistItemParam>((ref, param) {
  final asyncReminders = ref.watch(remindersStreamProvider);
  return asyncReminders.maybeWhen(
    data: (reminders) {
      final matches = reminders.where((r) =>
          r.noteId == param.noteId &&
          r.checklistItemId == param.checklistItemId &&
          !r.isCompleted);
      return matches.isEmpty ? null : matches.first;
    },
    orElse: () => null,
  );
});

/// Family provider for voice recording reminder
final voiceRecordingReminderProvider = Provider.family<ReminderEntity?, String>((ref, recordingId) {
  final asyncReminders = ref.watch(remindersStreamProvider);
  return asyncReminders.maybeWhen(
    data: (reminders) {
      final matches = reminders.where((r) => r.voiceRecordingId == recordingId && !r.isCompleted);
      return matches.isEmpty ? null : matches.first;
    },
    orElse: () => null,
  );
});
