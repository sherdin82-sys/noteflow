import 'dart:convert';
import 'dart:io';
import '../../../core/utils/audio_helper.dart';
import '../../../core/database/local_note_repository.dart';

class BackupService {
  final LocalNoteRepository repository;

  BackupService({required this.repository});

  /// Resolves the app documents directory from the repository.
  Future<String?> getBaseDirectory() async {
    return repository.getBaseDirectory();
  }

  /// Resolves the dedicated local backups directory (`<Documents>/backups`).
  Future<Directory> getBackupDirectory() async {
    final base = await getBaseDirectory();
    final dir = base != null
        ? Directory('$base/backups')
        : Directory('${Directory.systemTemp.path}/noteflow_backups');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// Generates the complete backup payload map including metadata,
  /// notes, folders, voice recordings, and optional audio payloads.
  Future<Map<String, dynamic>> exportBackupPayload({bool includeAudio = true}) async {
    final now = DateTime.now();
    final baseDir = await getBaseDirectory();

    final folders = repository.getAllFolders();
    final tags = repository.getAllTags();
    final notes = repository.getAllNotes();
    final recordings = repository.getAllVoiceRecordings();
    final themeMode = repository.themeMode;

    final Map<String, String> audioPayloads = {};
    int audioFilesCount = 0;
    int totalAudioBytes = 0;

    if (includeAudio && baseDir != null) {
      final processedPaths = <String>{};

      for (final rec in recordings) {
        if (rec.audioPath.isNotEmpty && !processedPaths.contains(rec.audioPath)) {
          processedPaths.add(rec.audioPath);
          try {
            final resolved = await AudioHelper.resolveAudioPath(rec.audioPath, baseDir);
            final targetPath = resolved ?? rec.audioPath;
            final file = File(targetPath);
            if (await file.exists() && await file.length() > 0) {
              final bytes = await file.readAsBytes();
              audioPayloads[rec.id] = base64Encode(bytes);
              audioFilesCount++;
              totalAudioBytes += bytes.length;
            }
          } catch (_) {}
        }
      }

      for (final note in notes) {
        if (note.audioPath != null &&
            note.audioPath!.isNotEmpty &&
            !processedPaths.contains(note.audioPath!)) {
          processedPaths.add(note.audioPath!);
          try {
            final resolved = await AudioHelper.resolveAudioPath(note.audioPath!, baseDir);
            final targetPath = resolved ?? note.audioPath!;
            final file = File(targetPath);
            if (await file.exists() && await file.length() > 0) {
              final bytes = await file.readAsBytes();
              audioPayloads[note.id] = base64Encode(bytes);
              audioFilesCount++;
              totalAudioBytes += bytes.length;
            }
          } catch (_) {}
        }
      }
    }

    return {
      'app': 'NoteFlow',
      'app_identifier': 'com.noteflow.app',
      'version': 1,
      'backup_version': 2,
      'created_at': now.toIso8601String(),
      'theme_mode': themeMode,
      'stats': {
        'notes_count': notes.length,
        'folders_count': folders.length,
        'tags_count': tags.length,
        'recordings_count': recordings.length,
        'has_audio': audioFilesCount > 0,
        'audio_files_count': audioFilesCount,
        'total_audio_bytes': totalAudioBytes,
      },
      'folders': folders.map((f) => f.toMap()).toList(),
      'tags': tags.map((t) => t.toMap()).toList(),
      'notes': notes.map((n) => n.toMap()).toList(),
      'voice_recordings': recordings.map((r) => r.toMap()).toList(),
      'audio_payloads': audioPayloads,
    };
  }

  /// Creates a complete, atomic, offline .noteflow backup file.
  /// Writes data with atomic staging and safe renaming.
  Future<File> createBackupArchive({
    bool includeAudio = true,
    String? customName,
    bool compress = false,
    void Function(double progress, String status)? onProgress,
  }) async {
    onProgress?.call(0.1, 'Gathering notes and folders...');
    final now = DateTime.now();
    final payload = await exportBackupPayload(includeAudio: includeAudio);

    onProgress?.call(0.5, 'Serializing backup package...');
    final jsonString = jsonEncode(payload);

    final backupDir = await getBackupDirectory();
    final String fileName;
    if (customName != null && customName.trim().isNotEmpty) {
      final clean = customName.trim();
      fileName = clean.endsWith('.noteflow') || clean.endsWith('.json')
          ? clean
          : '$clean.noteflow';
    } else {
      final stamp = '${now.year.toString().padLeft(4, '0')}'
          '${now.month.toString().padLeft(2, '0')}'
          '${now.day.toString().padLeft(2, '0')}_'
          '${now.hour.toString().padLeft(2, '0')}'
          '${now.minute.toString().padLeft(2, '0')}'
          '${now.second.toString().padLeft(2, '0')}';
      fileName = 'noteflow_backup_$stamp.noteflow';
    }

    final tempFile = File('${backupDir.path}/temp_${now.millisecondsSinceEpoch}.tmp');
    final finalFile = File('${backupDir.path}/$fileName');

    onProgress?.call(0.8, 'Writing backup file atomically...');
    if (compress) {
      final bytes = utf8.encode(jsonString);
      final compressedBytes = gzip.encode(bytes);
      await tempFile.writeAsBytes(compressedBytes, flush: true);
    } else {
      await tempFile.writeAsString(jsonString, flush: true);
    }

    if (await finalFile.exists()) {
      await finalFile.delete();
    }
    await tempFile.rename(finalFile.path);

    onProgress?.call(1.0, 'Backup created successfully');
    return finalFile;
  }

  /// Lists all saved .noteflow and .json backups in descending order of last modified.
  Future<List<File>> listLocalBackups() async {
    final backupDir = await getBackupDirectory();
    if (!await backupDir.exists()) return [];
    final entities = await backupDir.list().toList();
    final files = entities
        .whereType<File>()
        .where((f) =>
            f.path.endsWith('.noteflow') ||
            f.path.endsWith('.json') ||
            f.path.endsWith('.bak'))
        .toList();
    files.sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
    return files;
  }

  /// Deletes a local backup file safely.
  Future<void> deleteBackupFile(String filePath) async {
    final file = File(filePath);
    if (await file.exists()) {
      await file.delete();
    }
  }
}
