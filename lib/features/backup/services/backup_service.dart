import 'dart:convert';
import 'dart:io';
import 'package:archive/archive_io.dart';
import '../../../core/utils/audio_helper.dart';
import '../../../core/utils/attachment_helper.dart';
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
  /// Produces a Version 3 ZIP container archive containing manifest.json,
  /// raw voice notes, and attachments, eliminating base64 memory overhead.
  Future<File> createBackupArchive({
    bool includeAudio = true,
    bool includeAttachments = true,
    String? customName,
    bool compress = true,
    void Function(double progress, String status)? onProgress,
  }) async {
    onProgress?.call(0.1, 'Gathering notes, voice memos, and attachments...');
    final now = DateTime.now();
    final baseDir = await getBaseDirectory();

    final folders = repository.getAllFolders();
    final tags = repository.getAllTags();
    final notes = repository.getAllNotes();
    final recordings = repository.getAllVoiceRecordings();
    final reminders = repository.getAllReminders();
    final attachments = repository.getAllAttachments();
    final themeMode = repository.themeMode;

    onProgress?.call(0.3, 'Building backup manifest...');
    final manifestPayload = {
      'app': 'NoteFlow',
      'app_identifier': 'com.noteflow.app',
      'version': 3,
      'backup_version': 3,
      'created_at': now.toIso8601String(),
      'theme_mode': themeMode,
      'stats': {
        'notes_count': notes.length,
        'folders_count': folders.length,
        'tags_count': tags.length,
        'recordings_count': recordings.length,
        'reminders_count': reminders.length,
        'has_audio': includeAudio && recordings.isNotEmpty,
        'audio_files_count': includeAudio ? recordings.length : 0,
        'attachments_count': includeAttachments ? attachments.length : 0,
      },
      'folders': folders.map((f) => f.toMap()).toList(),
      'tags': tags.map((t) => t.toMap()).toList(),
      'notes': notes.map((n) => n.toMap()).toList(),
      'voice_recordings': recordings.map((r) => r.toMap()).toList(),
      'reminders': reminders.map((r) => r.toMap()).toList(),
      'attachments': includeAttachments ? attachments.map((a) => a.toMap()).toList() : [],
    };

    final backupDir = await getBackupDirectory();
    final String fileName;
    if (customName != null && customName.trim().isNotEmpty) {
      final clean = customName.trim();
      fileName = clean.endsWith('.noteflow') || clean.endsWith('.zip')
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

    onProgress?.call(0.5, 'Packaging ZIP archive...');
    final encoder = ZipFileEncoder();
    encoder.create(tempFile.path);

    // 1. Add manifest.json
    final manifestBytes = utf8.encode(jsonEncode(manifestPayload));
    encoder.addArchiveFile(ArchiveFile('manifest.json', manifestBytes.length, manifestBytes));

    // 2. Add raw voice recordings
    if (includeAudio && baseDir != null) {
      for (final rec in recordings) {
        if (rec.audioPath.isNotEmpty) {
          try {
            final resolved = await AudioHelper.resolveAudioPath(rec.audioPath, baseDir);
            final targetPath = resolved ?? rec.audioPath;
            final f = File(targetPath);
            if (await f.exists()) {
              final ext = rec.format.isNotEmpty ? rec.format : 'm4a';
              await encoder.addFile(f, 'voice_notes/${rec.id}.$ext');
            }
          } catch (_) {}
        }
      }
    }

    // 3. Add raw attachments
    if (includeAttachments && baseDir != null) {
      for (final att in attachments) {
        try {
          final absPath = AttachmentHelper.resolveAndVerifyPath(
            relativePath: att.relativePath,
            documentsBasePath: baseDir,
          );
          final f = File(absPath);
          if (await f.exists()) {
            await encoder.addFile(f, att.relativePath);
          }
        } catch (_) {}
      }
    }

    await encoder.close();

    onProgress?.call(0.9, 'Finalizing backup archive...');
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
