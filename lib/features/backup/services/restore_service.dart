import 'dart:convert';
import 'dart:io';
import '../../../core/database/local_note_repository.dart';
import '../../../shared/models/backup_models.dart';
import '../../../shared/models/folder_entity.dart';
import '../../../shared/models/note_entity.dart';
import '../../../shared/models/voice_recording_entity.dart';
import '../../../shared/models/reminder_entity.dart';

class RestoreService {
  final LocalNoteRepository repository;

  RestoreService({required this.repository});

  Future<String?> getBaseDirectory() async {
    return repository.getBaseDirectory();
  }

  bool isGzipBytes(List<int> bytes) {
    if (bytes.length < 2) return false;
    return bytes[0] == 0x1F && bytes[1] == 0x8B;
  }

  Future<BackupPreview> inspectArchive(String source) async {
    final trimmed = source.trim();

    if (trimmed.startsWith('{') && trimmed.endsWith('}')) {
      return _inspectJsonString(trimmed);
    }

    final file = File(trimmed);
    if (!await file.exists()) {
      throw FileSystemException('Backup file not found', trimmed);
    }

    final fileSize = await file.length();
    final fileName = file.uri.pathSegments.isNotEmpty
        ? file.uri.pathSegments.last
        : file.path;

    final bytes = await file.readAsBytes();
    final String content;
    final bool isCompressed = isGzipBytes(bytes);

    if (isCompressed) {
      final decompressed = gzip.decode(bytes);
      content = utf8.decode(decompressed);
    } else {
      content = utf8.decode(bytes);
    }

    return _inspectJsonString(
      content,
      filePath: file.path,
      fileName: fileName,
      fileSize: fileSize,
      isZipArchive: isCompressed,
    );
  }

  Future<BackupPreview> _inspectJsonString(
    String content, {
    String? filePath,
    String? fileName,
    int? fileSize,
    bool isZipArchive = false,
  }) async {
    final dynamic parsed;
    try {
      parsed = jsonDecode(content);
    } catch (e) {
      throw FormatException('File is not a valid JSON or .noteflow backup: $e');
    }

    if (parsed is! Map<String, dynamic>) {
      throw const FormatException('Invalid backup format: root must be a JSON object');
    }

    final app = parsed['app'] as String? ?? parsed['app_identifier'] as String? ?? '';
    if (app != 'NoteFlow' && app != 'com.noteflow.app' && !parsed.containsKey('notes')) {
      throw const FormatException('Invalid backup file: not a recognized NoteFlow backup');
    }

    final createdAt = parsed['created_at'] != null
        ? DateTime.tryParse(parsed['created_at'] as String) ?? DateTime.now()
        : DateTime.now();

    final notesList = (parsed['notes'] as List<dynamic>?) ?? [];
    final foldersList = (parsed['folders'] as List<dynamic>?) ?? [];
    final recordingsList = (parsed['voice_recordings'] as List<dynamic>?) ?? [];
    final rawReminders = (parsed['reminders'] as List<dynamic>?) ?? [];
    final audioPayloads = (parsed['audio_payloads'] as Map<String, dynamic>?) ?? {};

    final stats = parsed['stats'] as Map<String, dynamic>?;
    final notesCount = stats?['notes_count'] as int? ?? notesList.length;
    final foldersCount = stats?['folders_count'] as int? ?? foldersList.length;
    final recordingsCount = stats?['recordings_count'] as int? ?? recordingsList.length;
    final audioFilesCount = stats?['audio_files_count'] as int? ?? audioPayloads.length;
    final remindersCount = stats?['reminders_count'] as int? ?? rawReminders.length;
    final hasAudio = stats?['has_audio'] as bool? ?? (audioFilesCount > 0);

    final calculatedSize = fileSize ?? utf8.encode(content).length;

    return BackupPreview(
      appName: app.isNotEmpty ? app : 'NoteFlow',
      version: parsed['version'] as int? ?? 1,
      createdAt: createdAt,
      notesCount: notesCount,
      foldersCount: foldersCount,
      recordingsCount: recordingsCount,
      hasAudio: hasAudio,
      audioFilesCount: audioFilesCount,
      remindersCount: remindersCount,
      totalSizeBytes: calculatedSize,
      filePath: filePath,
      fileName: fileName,
      isZipArchive: isZipArchive,
    );
  }

  Future<void> restoreArchive(
    String source, {
    required RestoreStrategy strategy,
    void Function(double progress, String status)? onProgress,
  }) async {
    final trimmed = source.trim();
    final baseDir = await getBaseDirectory();

    onProgress?.call(0.1, 'Inspecting backup container...');

    String content;
    if (trimmed.startsWith('{') && trimmed.endsWith('}')) {
      content = trimmed;
    } else {
      final file = File(trimmed);
      if (!await file.exists()) {
        throw FileSystemException('Backup file not found', trimmed);
      }
      final bytes = await file.readAsBytes();
      if (isGzipBytes(bytes)) {
        final decompressed = gzip.decode(bytes);
        content = utf8.decode(decompressed);
      } else {
        content = utf8.decode(bytes);
      }
    }

    onProgress?.call(0.25, 'Validating backup integrity...');
    final dynamic parsed;
    try {
      parsed = jsonDecode(content);
    } catch (e) {
      throw FormatException('Malformed backup data: $e');
    }

    if (parsed is! Map<String, dynamic>) {
      throw const FormatException('Invalid backup structure: root must be an object');
    }

    final app = parsed['app'] as String? ?? parsed['app_identifier'] as String? ?? '';
    if (app != 'NoteFlow' && app != 'com.noteflow.app' && !parsed.containsKey('notes')) {
      throw const FormatException('Foreign backup format: not a recognized NoteFlow backup');
    }

    // Pre-restore Safety Snapshot
    onProgress?.call(0.4, 'Creating pre-restore safety snapshot...');
    File? safetyBackupFile;
    if (baseDir != null) {
      final currentDataFile = File('$baseDir/noteflow_data.json');
      if (await currentDataFile.exists()) {
        final backupsDir = Directory('$baseDir/backups');
        if (!await backupsDir.exists()) await backupsDir.create(recursive: true);
        safetyBackupFile = File('${backupsDir.path}/pre_restore_safety.bak');
        await currentDataFile.copy(safetyBackupFile.path);
      }
    }

    try {
      onProgress?.call(0.55, 'Parsing note entities...');
      final rawFolders = parsed['folders'] as List<dynamic>? ?? [];
      final rawNotes = parsed['notes'] as List<dynamic>? ?? [];
      final rawRecordings = parsed['voice_recordings'] as List<dynamic>? ?? [];
      final rawReminders = parsed['reminders'] as List<dynamic>? ?? [];
      final audioPayloads = (parsed['audio_payloads'] as Map<String, dynamic>?) ?? {};
      final themeMode = parsed['theme_mode'] as String? ?? 'dark';

      final backupFolders = rawFolders
          .map((f) => FolderEntity.fromMap(Map<String, dynamic>.from(f as Map)))
          .toList();
      final backupNotes = rawNotes
          .map((n) => NoteEntity.fromMap(Map<String, dynamic>.from(n as Map)))
          .toList();
      final backupRecordings = rawRecordings
          .map((r) => VoiceRecordingEntity.fromMap(Map<String, dynamic>.from(r as Map)))
          .toList();
      final backupReminders = rawReminders
          .map((r) => ReminderEntity.fromMap(Map<String, dynamic>.from(r as Map)))
          .toList();

      // Audio file extraction to permanent storage
      onProgress?.call(0.7, 'Extracting audio recordings...');
      if (baseDir != null && audioPayloads.isNotEmpty) {
        for (int i = 0; i < backupRecordings.length; i++) {
          final rec = backupRecordings[i];
          if (audioPayloads.containsKey(rec.id)) {
            try {
              final ext = rec.format.isNotEmpty ? rec.format : 'm4a';
              final targetDir = Directory('$baseDir/voice_notes/${rec.voiceNoteId}');
              if (!await targetDir.exists()) {
                await targetDir.create(recursive: true);
              }
              final targetFile = File('${targetDir.path}/${rec.id}.$ext');
              final bytes = base64Decode(audioPayloads[rec.id] as String);
              await targetFile.writeAsBytes(bytes, flush: true);
              backupRecordings[i] = rec.copyWith(
                audioPath: targetFile.path,
                fileSize: bytes.length,
              );
            } catch (_) {}
          }
        }

        for (int i = 0; i < backupNotes.length; i++) {
          final note = backupNotes[i];
          if (audioPayloads.containsKey(note.id)) {
            try {
              final targetDir = Directory('$baseDir/voice_notes/${note.id}');
              if (!await targetDir.exists()) {
                await targetDir.create(recursive: true);
              }
              final targetFile = File('${targetDir.path}/standalone_audio.m4a');
              final bytes = base64Decode(audioPayloads[note.id] as String);
              await targetFile.writeAsBytes(bytes, flush: true);
              backupNotes[i] = note.copyWith(audioPath: targetFile.path);
            } catch (_) {}
          }
        }
      }

      onProgress?.call(0.9, 'Applying restored data...');
      if (strategy == RestoreStrategy.replace) {
        await repository.replaceAllData(
          folders: backupFolders,
          notes: backupNotes,
          voiceRecordings: backupRecordings,
          reminders: backupReminders,
          themeMode: themeMode,
        );
      } else {
        await repository.mergeAllData(
          folders: backupFolders,
          notes: backupNotes,
          voiceRecordings: backupRecordings,
          reminders: backupReminders,
          themeMode: themeMode,
        );
      }

      // Cleanup safety backup on success
      if (safetyBackupFile != null && await safetyBackupFile.exists()) {
        try {
          await safetyBackupFile.delete();
        } catch (_) {}
      }

      onProgress?.call(1.0, 'Restoration complete');
    } catch (e) {
      // Rollback
      if (safetyBackupFile != null && await safetyBackupFile.exists() && baseDir != null) {
        try {
          final currentDataFile = File('$baseDir/noteflow_data.json');
          await safetyBackupFile.copy(currentDataFile.path);
        } catch (_) {}
      }
      rethrow;
    }
  }
}
