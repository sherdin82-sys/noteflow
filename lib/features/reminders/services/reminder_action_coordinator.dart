import 'dart:async';
import '../../../core/database/local_note_repository.dart';
import '../../../shared/models/reminder_entity.dart';
import 'reminder_service.dart';

abstract class ReminderJournalBridge {
  Future<List<Map<String, dynamic>>> getPendingJournalActions();
  Future<bool> ackPendingJournalActions(List<String> actionIds);
  Stream<Map<String, dynamic>> get onActionReceived;
  void initialize();
}

class NoOpReminderJournalBridge implements ReminderJournalBridge {
  const NoOpReminderJournalBridge();

  @override
  void initialize() {}

  @override
  Stream<Map<String, dynamic>> get onActionReceived => const Stream.empty();

  @override
  Future<List<Map<String, dynamic>>> getPendingJournalActions() async => [];

  @override
  Future<bool> ackPendingJournalActions(List<String> actionIds) async => true;
}

/// Orchestrates headless and runtime notification actions ("snooze", "markDone").
/// Decouples [LocalNoteRepository] from [ReminderService] to prevent circular dependencies.
/// Guarantees durable idempotency using persisted action IDs and occurrence-bound timestamps.
class ReminderActionCoordinator {
  final LocalNoteRepository repository;
  final ReminderService reminderService;
  final ReminderJournalBridge bridge;
  final Future<bool> Function(List<String> actionIds)? ackHandler;

  StreamSubscription? _nativeActionSub;

  ReminderActionCoordinator({
    required this.repository,
    required this.reminderService,
    this.bridge = const NoOpReminderJournalBridge(),
    this.ackHandler,
  });

  /// Drains any pending journal actions on startup and registers a stream listener for runtime actions.
  Future<void> initializeAndDrain() async {
    bridge.initialize();
    try {
      final pendingActions = await bridge.getPendingJournalActions();
      if (pendingActions.isNotEmpty) {
        await processJournalActions(pendingActions);
      }
    } catch (_) {}

    _nativeActionSub?.cancel();
    _nativeActionSub = bridge.onActionReceived.listen((action) {
      processJournalActions([action]);
    });
  }

  void dispose() {
    _nativeActionSub?.cancel();
    _nativeActionSub = null;
  }

  /// Processes a batch of action journal entries idempotently and acknowledges them.
  Future<List<String>> processJournalActions(List<Map<String, dynamic>> actions) async {
    final acknowledgedIds = <String>[];

    for (final action in actions) {
      final actionId = (action['actionId'] as String? ?? action['id'] as String? ?? '').trim();
      final actionType = action['action'] as String? ?? '';
      final notificationId = action['notificationId'] as int? ?? -1;
      final noteId = action['noteId'] as String? ?? '';
      final occurrenceEpochMs = action['occurrenceEpochMs'] as int?;

      // 1. Durable Idempotency Check
      if (actionId.isNotEmpty && repository.isActionProcessed(actionId)) {
        acknowledgedIds.add(actionId);
        continue;
      }

      // 2. Locate target reminder in repository
      final reminders = await repository.getReminders();
      final idx = reminders.indexWhere((r) =>
          (notificationId > 0 && r.notificationId == notificationId) ||
          (noteId.isNotEmpty && r.noteId == noteId));

      if (idx < 0) {
        // Target reminder does not exist (e.g. deleted); acknowledge and skip
        if (actionId.isNotEmpty) {
          await repository.recordProcessedActionId(actionId);
          acknowledgedIds.add(actionId);
        }
        continue;
      }

      final rem = reminders[idx];

      if (actionType == 'markDone') {
        if (rem.repeatMode != ReminderRepeatMode.never) {
          // Recurring reminder: check occurrenceEpochMs binding
          if (occurrenceEpochMs != null &&
              rem.scheduledAt.millisecondsSinceEpoch > occurrenceEpochMs) {
            // This occurrence was ALREADY completed and advanced!
            if (actionId.isNotEmpty) {
              await repository.recordProcessedActionId(actionId);
              acknowledgedIds.add(actionId);
            }
            continue;
          }

          // Advance recurring series via ReminderService
          await reminderService.completeReminder(rem.id);
        } else {
          // One-time reminder
          if (rem.isCompleted) {
            // Already completed
            if (actionId.isNotEmpty) {
              await repository.recordProcessedActionId(actionId);
              acknowledgedIds.add(actionId);
            }
            continue;
          }

          await reminderService.completeReminder(rem.id);
        }
      } else if (actionType == 'snooze') {
        final snoozedUntilMs = action['snoozedUntilMs'] as int?;
        if (snoozedUntilMs != null &&
            rem.snoozedUntil != null &&
            rem.snoozedUntil!.millisecondsSinceEpoch >= snoozedUntilMs) {
          // Already snoozed to this timestamp or later
          if (actionId.isNotEmpty) {
            await repository.recordProcessedActionId(actionId);
            acknowledgedIds.add(actionId);
          }
          continue;
        }

        final targetTime = snoozedUntilMs != null
            ? DateTime.fromMillisecondsSinceEpoch(snoozedUntilMs)
            : DateTime.now().add(const Duration(minutes: 15));
        final diff = targetTime.difference(DateTime.now());
        final duration = diff.isNegative ? const Duration(minutes: 15) : diff;

        await reminderService.snoozeReminder(rem.id, duration);
      }

      if (actionId.isNotEmpty) {
        await repository.recordProcessedActionId(actionId);
        acknowledgedIds.add(actionId);
      }
    }

    // 3. Acknowledge processed actions back to native storage
    if (acknowledgedIds.isNotEmpty) {
      if (ackHandler != null) {
        await ackHandler!(acknowledgedIds);
      } else {
        await bridge.ackPendingJournalActions(acknowledgedIds);
      }
    }

    return acknowledgedIds;
  }
}
