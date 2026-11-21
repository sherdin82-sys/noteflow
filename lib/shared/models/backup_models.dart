enum RestoreStrategy {
  merge,
  replace,
}

class BackupFileEntry {
  final String path;
  final int sizeBytes;
  final String sha256;

  const BackupFileEntry({
    required this.path,
    required this.sizeBytes,
    required this.sha256,
  });

  Map<String, dynamic> toMap() => {
        'path': path,
        'size_bytes': sizeBytes,
        'sha256': sha256,
      };

  factory BackupFileEntry.fromMap(Map<String, dynamic> map) => BackupFileEntry(
        path: map['path'] as String? ?? '',
        sizeBytes: map['size_bytes'] as int? ?? 0,
        sha256: map['sha256'] as String? ?? '',
      );
}

class BackupManifest {
  final int formatVersion;
  final String appIdentifier;
  final String appVersion;
  final DateTime createdAt;
  final Map<String, dynamic> stats;
  final Map<String, dynamic> preferences;
  final List<BackupFileEntry> files;

  const BackupManifest({
    this.formatVersion = 1,
    this.appIdentifier = 'com.noteflow.app',
    this.appVersion = '1.5.1',
    required this.createdAt,
    required this.stats,
    this.preferences = const {},
    this.files = const [],
  });

  Map<String, dynamic> toMap() => {
        'format_version': formatVersion,
        'app_identifier': appIdentifier,
        'app_version': appVersion,
        'created_at': createdAt.toIso8601String(),
        'stats': stats,
        'preferences': preferences,
        'files': files.map((f) => f.toMap()).toList(),
      };

  factory BackupManifest.fromMap(Map<String, dynamic> map) {
    final rawFiles = map['files'] as List<dynamic>? ?? [];
    return BackupManifest(
      formatVersion: map['format_version'] as int? ?? 1,
      appIdentifier: map['app_identifier'] as String? ?? '',
      appVersion: map['app_version'] as String? ?? '1.0.0',
      createdAt: map['created_at'] != null
          ? DateTime.tryParse(map['created_at'] as String) ?? DateTime.now()
          : DateTime.now(),
      stats: Map<String, dynamic>.from(map['stats'] as Map? ?? {}),
      preferences: Map<String, dynamic>.from(map['preferences'] as Map? ?? {}),
      files: rawFiles
          .map((f) => BackupFileEntry.fromMap(Map<String, dynamic>.from(f as Map)))
          .toList(),
    );
  }
}

class BackupPreview {
  final String appName;
  final int version;
  final DateTime createdAt;
  final int notesCount;
  final int foldersCount;
  final int tagsCount;
  final int recordingsCount;
  final bool hasAudio;
  final int audioFilesCount;
  final int remindersCount;
  final int totalSizeBytes;
  final String? filePath;
  final String? fileName;
  final bool isZipArchive;

  const BackupPreview({
    required this.appName,
    required this.version,
    required this.createdAt,
    required this.notesCount,
    required this.foldersCount,
    this.tagsCount = 0,
    required this.recordingsCount,
    required this.hasAudio,
    required this.audioFilesCount,
    this.remindersCount = 0,
    this.totalSizeBytes = 0,
    this.filePath,
    this.fileName,
    this.isZipArchive = false,
  });

  String get formattedSize {
    if (totalSizeBytes <= 0) return '0 B';
    if (totalSizeBytes < 1024) return '$totalSizeBytes B';
    if (totalSizeBytes < 1024 * 1024) {
      return '${(totalSizeBytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(totalSizeBytes / (1024 * 1024)).toStringAsFixed(2)} MB';
  }

  Map<String, dynamic> toMap() {
    return {
      'app_name': appName,
      'version': version,
      'created_at': createdAt.toIso8601String(),
      'notes_count': notesCount,
      'folders_count': foldersCount,
      'tags_count': tagsCount,
      'recordings_count': recordingsCount,
      'has_audio': hasAudio,
      'audio_files_count': audioFilesCount,
      'reminders_count': remindersCount,
      'total_size_bytes': totalSizeBytes,
      'file_path': filePath,
      'file_name': fileName,
      'is_zip_archive': isZipArchive,
    };
  }
}
