class VoiceRecordingEntity {
  final String id;
  final String voiceNoteId;
  final String title;
  final String audioPath;
  final int durationMs;
  final int fileSize;
  final DateTime createdAt;
  final int sortOrder;
  final bool isCompleted;
  final String format;

  const VoiceRecordingEntity({
    required this.id,
    required this.voiceNoteId,
    required this.title,
    required this.audioPath,
    required this.durationMs,
    this.fileSize = 0,
    required this.createdAt,
    this.sortOrder = 0,
    this.isCompleted = false,
    this.format = 'm4a',
  });

  VoiceRecordingEntity copyWith({
    String? id,
    String? voiceNoteId,
    String? title,
    String? audioPath,
    int? durationMs,
    int? fileSize,
    DateTime? createdAt,
    int? sortOrder,
    bool? isCompleted,
    String? format,
  }) {
    return VoiceRecordingEntity(
      id: id ?? this.id,
      voiceNoteId: voiceNoteId ?? this.voiceNoteId,
      title: title ?? this.title,
      audioPath: audioPath ?? this.audioPath,
      durationMs: durationMs ?? this.durationMs,
      fileSize: fileSize ?? this.fileSize,
      createdAt: createdAt ?? this.createdAt,
      sortOrder: sortOrder ?? this.sortOrder,
      isCompleted: isCompleted ?? this.isCompleted,
      format: format ?? this.format,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'voice_note_id': voiceNoteId,
      'title': title,
      'audio_path': audioPath,
      'duration_ms': durationMs,
      'file_size': fileSize,
      'created_at': createdAt.toIso8601String(),
      'sort_order': sortOrder,
      'is_completed': isCompleted ? 1 : 0,
      'format': format,
    };
  }

  factory VoiceRecordingEntity.fromMap(Map<String, dynamic> map) {
    return VoiceRecordingEntity(
      id: map['id'] as String,
      voiceNoteId: map['voice_note_id'] as String? ?? '',
      title: map['title'] as String? ?? 'Recording',
      audioPath: map['audio_path'] as String? ?? '',
      durationMs: map['duration_ms'] as int? ?? 0,
      fileSize: map['file_size'] as int? ?? 0,
      createdAt: DateTime.tryParse(map['created_at'] as String? ?? '') ?? DateTime.now(),
      sortOrder: map['sort_order'] as int? ?? 0,
      isCompleted: (map['is_completed'] as int? ?? 0) == 1,
      format: map['format'] as String? ?? 'm4a',
    );
  }
}
