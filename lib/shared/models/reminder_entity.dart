enum ReminderRepeatMode {
  never,
  daily,
  weekly,
  monthly,
  custom;

  static ReminderRepeatMode fromString(String? val) {
    switch (val?.toLowerCase()) {
      case 'daily':
        return ReminderRepeatMode.daily;
      case 'weekly':
        return ReminderRepeatMode.weekly;
      case 'monthly':
        return ReminderRepeatMode.monthly;
      case 'custom':
        return ReminderRepeatMode.custom;
      case 'never':
      default:
        return ReminderRepeatMode.never;
    }
  }

  String get displayName {
    switch (this) {
      case ReminderRepeatMode.never:
        return 'Does not repeat';
      case ReminderRepeatMode.daily:
        return 'Daily';
      case ReminderRepeatMode.weekly:
        return 'Weekly';
      case ReminderRepeatMode.monthly:
        return 'Monthly';
      case ReminderRepeatMode.custom:
        return 'Custom';
    }
  }
}

class ReminderEntity {
  final String id;
  final String noteId;
  final String? checklistItemId;
  final String? voiceRecordingId;
  final String title;
  final String notesPreview;
  final DateTime scheduledAt;
  final String timeZone;
  final ReminderRepeatMode repeatMode;
  final int repeatIntervalValue;
  final bool isCompleted;
  final DateTime? completedAt;
  final int snoozeCount;
  final DateTime? snoozedUntil;
  final int notificationId;
  final DateTime createdAt;
  final DateTime updatedAt;

  const ReminderEntity({
    required this.id,
    required this.noteId,
    this.checklistItemId,
    this.voiceRecordingId,
    required this.title,
    this.notesPreview = '',
    required this.scheduledAt,
    this.timeZone = 'UTC',
    this.repeatMode = ReminderRepeatMode.never,
    this.repeatIntervalValue = 1,
    this.isCompleted = false,
    this.completedAt,
    this.snoozeCount = 0,
    this.snoozedUntil,
    required this.notificationId,
    required this.createdAt,
    required this.updatedAt,
  });

  /// The active trigger timestamp (snoozed time takes precedence if present)
  DateTime get effectiveScheduledAt => snoozedUntil ?? scheduledAt;

  bool get isOverdue => !isCompleted && effectiveScheduledAt.isBefore(DateTime.now());

  bool get isSnoozed => snoozedUntil != null && snoozedUntil!.isAfter(DateTime.now());

  bool get isToday {
    final now = DateTime.now();
    final eff = effectiveScheduledAt;
    return eff.year == now.year && eff.month == now.month && eff.day == now.day;
  }

  bool get isUpcoming => !isCompleted && effectiveScheduledAt.isAfter(DateTime.now());

  bool get isChecklistItemReminder => checklistItemId != null && checklistItemId!.trim().isNotEmpty;

  bool get isVoiceRecordingReminder => voiceRecordingId != null && voiceRecordingId!.trim().isNotEmpty;

  bool get isWholeNoteReminder => !isChecklistItemReminder && !isVoiceRecordingReminder;

  ReminderEntity copyWith({
    String? id,
    String? noteId,
    String? checklistItemId,
    bool clearChecklistItemId = false,
    String? voiceRecordingId,
    bool clearVoiceRecordingId = false,
    String? title,
    String? notesPreview,
    DateTime? scheduledAt,
    String? timeZone,
    ReminderRepeatMode? repeatMode,
    int? repeatIntervalValue,
    bool? isCompleted,
    DateTime? completedAt,
    bool clearCompletedAt = false,
    int? snoozeCount,
    DateTime? snoozedUntil,
    bool clearSnoozedUntil = false,
    int? notificationId,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return ReminderEntity(
      id: id ?? this.id,
      noteId: noteId ?? this.noteId,
      checklistItemId: clearChecklistItemId ? null : (checklistItemId ?? this.checklistItemId),
      voiceRecordingId: clearVoiceRecordingId ? null : (voiceRecordingId ?? this.voiceRecordingId),
      title: title ?? this.title,
      notesPreview: notesPreview ?? this.notesPreview,
      scheduledAt: scheduledAt ?? this.scheduledAt,
      timeZone: timeZone ?? this.timeZone,
      repeatMode: repeatMode ?? this.repeatMode,
      repeatIntervalValue: repeatIntervalValue ?? this.repeatIntervalValue,
      isCompleted: isCompleted ?? this.isCompleted,
      completedAt: clearCompletedAt ? null : (completedAt ?? this.completedAt),
      snoozeCount: snoozeCount ?? this.snoozeCount,
      snoozedUntil: clearSnoozedUntil ? null : (snoozedUntil ?? this.snoozedUntil),
      notificationId: notificationId ?? this.notificationId,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'note_id': noteId,
      'checklist_item_id': checklistItemId,
      'voice_recording_id': voiceRecordingId,
      'title': title,
      'notes_preview': notesPreview,
      'scheduled_at': scheduledAt.toIso8601String(),
      'time_zone': timeZone,
      'repeat_mode': repeatMode.name,
      'repeat_interval_value': repeatIntervalValue,
      'is_completed': isCompleted ? 1 : 0,
      'completed_at': completedAt?.toIso8601String(),
      'snooze_count': snoozeCount,
      'snoozed_until': snoozedUntil?.toIso8601String(),
      'notification_id': notificationId,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  factory ReminderEntity.fromMap(Map<String, dynamic> map) {
    return ReminderEntity(
      id: map['id'] as String,
      noteId: map['note_id'] as String? ?? '',
      checklistItemId: map['checklist_item_id'] as String?,
      voiceRecordingId: map['voice_recording_id'] as String?,
      title: map['title'] as String? ?? '',
      notesPreview: map['notes_preview'] as String? ?? '',
      scheduledAt: DateTime.tryParse(map['scheduled_at'] as String? ?? '') ?? DateTime.now(),
      timeZone: map['time_zone'] as String? ?? 'UTC',
      repeatMode: ReminderRepeatMode.fromString(map['repeat_mode'] as String?),
      repeatIntervalValue: map['repeat_interval_value'] as int? ?? 1,
      isCompleted: (map['is_completed'] as int? ?? 0) == 1,
      completedAt: map['completed_at'] != null ? DateTime.tryParse(map['completed_at'] as String) : null,
      snoozeCount: map['snooze_count'] as int? ?? 0,
      snoozedUntil: map['snoozed_until'] != null ? DateTime.tryParse(map['snoozed_until'] as String) : null,
      notificationId: map['notification_id'] as int? ?? 1000,
      createdAt: DateTime.tryParse(map['created_at'] as String? ?? '') ?? DateTime.now(),
      updatedAt: DateTime.tryParse(map['updated_at'] as String? ?? '') ?? DateTime.now(),
    );
  }
}
