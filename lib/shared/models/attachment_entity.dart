enum AttachmentCategory {
  image,
  document,
  audio,
  video,
  other;

  static AttachmentCategory fromMime(String mimeType, String extension) {
    final lowerMime = mimeType.trim().toLowerCase();
    final lowerExt = extension.trim().toLowerCase().replaceAll(RegExp(r'^\.+'), '');

    if (lowerMime.startsWith('image/') ||
        {'jpg', 'jpeg', 'png', 'webp', 'gif', 'bmp', 'svg'}.contains(lowerExt)) {
      return AttachmentCategory.image;
    }
    if (lowerMime.startsWith('audio/') ||
        {'mp3', 'm4a', 'wav', 'aac', 'ogg', 'flac'}.contains(lowerExt)) {
      return AttachmentCategory.audio;
    }
    if (lowerMime.startsWith('video/') ||
        {'mp4', 'mkv', 'mov', 'webm', 'avi'}.contains(lowerExt)) {
      return AttachmentCategory.video;
    }
    if (lowerMime.contains('pdf') ||
        lowerMime.contains('document') ||
        lowerMime.contains('text') ||
        lowerMime.contains('sheet') ||
        lowerMime.contains('presentation') ||
        {'pdf', 'doc', 'docx', 'txt', 'rtf', 'xls', 'xlsx', 'csv', 'ppt', 'pptx', 'json', 'xml'}.contains(lowerExt)) {
      return AttachmentCategory.document;
    }
    return AttachmentCategory.other;
  }
}

class AttachmentEntity {
  final String id;
  final String noteId;
  final String originalName;
  final String storedName;
  final String relativePath;
  final String mimeType;
  final String fileExtension;
  final int fileSizeBytes;
  final AttachmentCategory category;
  final DateTime createdAt;

  const AttachmentEntity({
    required this.id,
    required this.noteId,
    required this.originalName,
    required this.storedName,
    required this.relativePath,
    required this.mimeType,
    required this.fileExtension,
    required this.fileSizeBytes,
    required this.category,
    required this.createdAt,
  });

  bool get isImage => category == AttachmentCategory.image;
  bool get isDocument => category == AttachmentCategory.document;
  bool get isAudio => category == AttachmentCategory.audio;
  bool get isVideo => category == AttachmentCategory.video;

  String get formattedSize {
    if (fileSizeBytes <= 0) return '0 B';
    if (fileSizeBytes < 1024) return '$fileSizeBytes B';
    if (fileSizeBytes < 1024 * 1024) {
      return '${(fileSizeBytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(fileSizeBytes / (1024 * 1024)).toStringAsFixed(2)} MB';
  }

  AttachmentEntity copyWith({
    String? id,
    String? noteId,
    String? originalName,
    String? storedName,
    String? relativePath,
    String? mimeType,
    String? fileExtension,
    int? fileSizeBytes,
    AttachmentCategory? category,
    DateTime? createdAt,
  }) {
    return AttachmentEntity(
      id: id ?? this.id,
      noteId: noteId ?? this.noteId,
      originalName: originalName ?? this.originalName,
      storedName: storedName ?? this.storedName,
      relativePath: relativePath ?? this.relativePath,
      mimeType: mimeType ?? this.mimeType,
      fileExtension: fileExtension ?? this.fileExtension,
      fileSizeBytes: fileSizeBytes ?? this.fileSizeBytes,
      category: category ?? this.category,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'note_id': noteId,
      'original_name': originalName,
      'stored_name': storedName,
      'relative_path': relativePath,
      'mime_type': mimeType,
      'file_extension': fileExtension,
      'file_size_bytes': fileSizeBytes,
      'category': category.name,
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory AttachmentEntity.fromMap(Map<String, dynamic> map) {
    final ext = (map['file_extension'] as String? ?? '').replaceAll(RegExp(r'^\.+'), '');
    final mime = map['mime_type'] as String? ?? 'application/octet-stream';
    final catName = map['category'] as String?;
    final cat = catName != null
        ? AttachmentCategory.values.firstWhere(
            (e) => e.name == catName,
            orElse: () => AttachmentCategory.fromMime(mime, ext),
          )
        : AttachmentCategory.fromMime(mime, ext);

    return AttachmentEntity(
      id: map['id'] as String,
      noteId: map['note_id'] as String? ?? '',
      originalName: map['original_name'] as String? ?? 'attachment',
      storedName: map['stored_name'] as String? ?? '',
      relativePath: map['relative_path'] as String? ?? '',
      mimeType: mime,
      fileExtension: ext,
      fileSizeBytes: map['file_size_bytes'] as int? ?? 0,
      category: cat,
      createdAt: DateTime.tryParse(map['created_at'] as String? ?? '') ?? DateTime.now(),
    );
  }
}
