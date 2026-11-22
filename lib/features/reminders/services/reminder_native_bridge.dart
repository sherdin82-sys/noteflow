import 'dart:async';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'reminder_scheduler.dart';
import 'reminder_action_coordinator.dart';

class ReminderNativeBridge {
  static const MethodChannel _channel = MethodChannel('com.noteflow.app/reminders');

  static final StreamController<Map<String, dynamic>> _notificationTapController =
      StreamController<Map<String, dynamic>>.broadcast();

  static final StreamController<Map<String, dynamic>> _actionReceivedController =
      StreamController<Map<String, dynamic>>.broadcast();

  static bool _initialized = false;

  static Stream<Map<String, dynamic>> get onNotificationTapped => _notificationTapController.stream;
  static Stream<Map<String, dynamic>> get onActionReceived => _actionReceivedController.stream;

  static void initialize() {
    if (_initialized) return;
    _initialized = true;

    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'onNotificationTapped':
          final args = call.arguments;
          if (args is Map) {
            _notificationTapController.add(Map<String, dynamic>.from(args));
          }
          break;
        case 'onReminderActionReceived':
          final raw = call.arguments as String?;
          if (raw != null && raw.isNotEmpty) {
            try {
              final parsed = jsonDecode(raw) as Map<String, dynamic>;
              _actionReceivedController.add(parsed);
            } catch (_) {}
          }
          break;
      }
    });
  }

  /// Schedule alarm via native Android AlarmManager
  static Future<bool> scheduleAlarm({
    required int notificationId,
    required int triggerEpochMs,
    required String title,
    required String body,
    required String noteId,
    String? checklistItemId,
    String? voiceRecordingId,
  }) async {
    try {
      final result = await _channel.invokeMethod<bool>('scheduleAlarm', {
        'notificationId': notificationId,
        'triggerEpochMs': triggerEpochMs,
        'title': title,
        'body': body,
        'noteId': noteId,
        'checklistItemId': checklistItemId,
        'voiceRecordingId': voiceRecordingId,
      });
      return result ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Cancel alarm and dismiss tray notification
  static Future<bool> cancelAlarm(int notificationId) async {
    try {
      final result = await _channel.invokeMethod<bool>('cancelAlarm', {
        'notificationId': notificationId,
      });
      return result ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Check whether exact alarms can be scheduled on Android 12+
  static Future<bool> canScheduleExactAlarms() async {
    try {
      final result = await _channel.invokeMethod<bool>('canScheduleExactAlarms');
      return result ?? true;
    } catch (_) {
      return true;
    }
  }

  /// Open Android system settings to grant exact alarm permissions
  static Future<void> requestExactAlarmPermission() async {
    try {
      await _channel.invokeMethod('requestExactAlarmPermission');
    } catch (_) {}
  }

  /// Reconciles all active reminders by rescheduling with AlarmManager
  /// (e.g. when exact-alarm permission is granted in system settings)
  static Future<bool> reconcileAlarms() async {
    try {
      final result = await _channel.invokeMethod<bool>('reconcileAlarms');
      return result ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Check if app notifications are enabled in Android settings
  static Future<bool> areNotificationsEnabled() async {
    try {
      final result = await _channel.invokeMethod<bool>('areNotificationsEnabled');
      return result ?? true;
    } catch (_) {
      return true;
    }
  }

  /// Request POST_NOTIFICATIONS permission on Android 13+
  static Future<void> requestNotificationPermission() async {
    try {
      await _channel.invokeMethod('requestNotificationPermission');
    } catch (_) {}
  }

  /// Open app notification settings screen
  static Future<void> openNotificationSettings() async {
    try {
      await _channel.invokeMethod('openNotificationSettings');
    } catch (_) {}
  }

  /// Drains action journal entries from SharedPreferences
  static Future<List<Map<String, dynamic>>> getPendingJournalActions() async {
    try {
      final rawList = await _channel.invokeListMethod<String>('getPendingJournalActions');
      if (rawList == null) return [];
      final result = <Map<String, dynamic>>[];
      for (final raw in rawList) {
        try {
          final map = jsonDecode(raw) as Map<String, dynamic>;
          result.add(map);
        } catch (_) {}
      }
      return result;
    } catch (_) {
      return [];
    }
  }

  /// Acknowledges processed action IDs so native SharedPreferences can selectively delete them
  static Future<bool> ackPendingJournalActions(List<String> actionIds) async {
    if (actionIds.isEmpty) return true;
    try {
      final result = await _channel.invokeMethod<bool>('ackPendingJournalActions', {
        'actionIds': actionIds,
      });
      return result ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Check if app was cold-started from notification click
  static Future<Map<String, dynamic>?> getInitialNotificationPayload() async {
    try {
      final result = await _channel.invokeMethod<Map<dynamic, dynamic>>('getInitialNotificationPayload');
      if (result != null) {
        return Map<String, dynamic>.from(result);
      }
    } catch (_) {}
    return null;
  }

  /// Check whether lock screen note previews are enabled (default: false / Private)
  static Future<bool> areLockscreenPreviewsEnabled() async {
    try {
      final result = await _channel.invokeMethod<bool>('areLockscreenPreviewsEnabled');
      return result ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Toggle lock screen note previews
  static Future<bool> setLockscreenPreviewsEnabled(bool enabled) async {
    try {
      final result = await _channel.invokeMethod<bool>('setLockscreenPreviewsEnabled', {
        'enabled': enabled,
      });
      return result ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Verifies that Flutter's getApplicationDocumentsDirectory matches Kotlin's canonical app_flutter dir
  static Future<bool> verifyDocumentsPath(String path) async {
    try {
      final result = await _channel.invokeMethod<bool>('verifyDocumentsPath', {
        'path': path,
      });
      return result ?? true;
    } catch (_) {
      return true;
    }
  }
}

class NativeReminderScheduler implements ReminderScheduler {
  const NativeReminderScheduler();

  @override
  Future<void> scheduleAlarm({
    required int notificationId,
    required int triggerEpochMs,
    required String title,
    required String body,
    String? noteId,
    String? checklistItemId,
    String? voiceRecordingId,
  }) async {
    await ReminderNativeBridge.scheduleAlarm(
      notificationId: notificationId,
      triggerEpochMs: triggerEpochMs,
      title: title,
      body: body,
      noteId: noteId ?? '',
      checklistItemId: checklistItemId,
      voiceRecordingId: voiceRecordingId,
    );
  }

  @override
  Future<void> cancelAlarm(int notificationId) async {
    await ReminderNativeBridge.cancelAlarm(notificationId);
  }
}

class ReminderNativeJournalBridge implements ReminderJournalBridge {
  const ReminderNativeJournalBridge();

  @override
  void initialize() => ReminderNativeBridge.initialize();

  @override
  Stream<Map<String, dynamic>> get onActionReceived => ReminderNativeBridge.onActionReceived;

  @override
  Future<List<Map<String, dynamic>>> getPendingJournalActions() => ReminderNativeBridge.getPendingJournalActions();

  @override
  Future<bool> ackPendingJournalActions(List<String> actionIds) => ReminderNativeBridge.ackPendingJournalActions(actionIds);
}
