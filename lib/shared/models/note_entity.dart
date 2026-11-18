class NoteEntity {
  final String id;
  final String title;
  final String content;
  final String? folderId;
  final bool isPinned;
  final bool isArchived;
  final bool isChecklist;
  final bool isVoiceNote;
  final String voiceMode; // 'list' or 'checklist'
  final int colorIndex;
  final String? audioPath;
  final int? audioDurationMs;
  final DateTime createdAt;
  final DateTime updatedAt;

  const NoteEntity({
    required this.id,
    required this.title,
    required this.content,
    this.folderId,
    this.isPinned = false,
    this.isArchived = false,
    this.isChecklist = false,
    this.isVoiceNote = false,
    this.voiceMode = 'list',
    this.colorIndex = 0,
    this.audioPath,
    this.audioDurationMs,
    required this.createdAt,
    required this.updatedAt,
  });

  bool get hasAudio => isVoiceNote || (audioPath != null && audioPath!.trim().isNotEmpty);

  NoteEntity copyWith({
    String? id,
    String? title,
    String? content,
    String? folderId,
    bool clearFolder = false,
    bool? isPinned,
    bool? isArchived,
    bool? isChecklist,
    bool? isVoiceNote,
    String? voiceMode,
    int? colorIndex,
    String? audioPath,
    bool clearAudio = false,
    int? audioDurationMs,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return NoteEntity(
      id: id ?? this.id,
      title: title ?? this.title,
      content: content ?? this.content,
      folderId: clearFolder ? null : (folderId ?? this.folderId),
      isPinned: isPinned ?? this.isPinned,
      isArchived: isArchived ?? this.isArchived,
      isChecklist: isChecklist ?? this.isChecklist,
      isVoiceNote: isVoiceNote ?? this.isVoiceNote,
      voiceMode: voiceMode ?? this.voiceMode,
      colorIndex: colorIndex ?? this.colorIndex,
      audioPath: clearAudio ? null : (audioPath ?? this.audioPath),
      audioDurationMs: clearAudio ? null : (audioDurationMs ?? this.audioDurationMs),
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'content': content,
      'folder_id': folderId,
      'is_pinned': isPinned ? 1 : 0,
      'is_archived': isArchived ? 1 : 0,
      'is_checklist': isChecklist ? 1 : 0,
      'is_voice_note': isVoiceNote ? 1 : 0,
      'voice_mode': voiceMode,
      'color_index': colorIndex,
      'audio_path': audioPath,
      'audio_duration_ms': audioDurationMs,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  factory NoteEntity.fromMap(Map<String, dynamic> map) {
    return NoteEntity(
      id: map['id'] as String,
      title: map['title'] as String? ?? '',
      content: map['content'] as String? ?? '',
      folderId: map['folder_id'] as String?,
      isPinned: (map['is_pinned'] as int? ?? 0) == 1,
      isArchived: (map['is_archived'] as int? ?? 0) == 1,
      isChecklist: (map['is_checklist'] as int? ?? 0) == 1,
      isVoiceNote: (map['is_voice_note'] as int? ?? 0) == 1,
      voiceMode: map['voice_mode'] as String? ?? 'list',
      colorIndex: map['color_index'] as int? ?? 0,
      audioPath: map['audio_path'] as String?,
      audioDurationMs: map['audio_duration_ms'] as int?,
      createdAt: DateTime.tryParse(map['created_at'] as String? ?? '') ?? DateTime.now(),
      updatedAt: DateTime.tryParse(map['updated_at'] as String? ?? '') ?? DateTime.now(),
    );
  }
}
