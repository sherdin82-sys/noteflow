import 'dart:async';
import 'dart:convert';
import 'dart:io';
import '../../shared/models/note_entity.dart';
import '../../shared/models/folder_entity.dart';
import '../../shared/models/voice_recording_entity.dart';
import '../utils/audio_helper.dart';
import '../utils/attachment_helper.dart';
import '../utils/per_note_mutex.dart';
import '../utils/attachment_journal.dart';
import 'note_repository.dart';
import '../../features/backup/services/backup_service.dart';
import '../../features/backup/services/restore_service.dart';
import '../../features/reminders/services/reminder_scheduler.dart';

class LocalNoteRepository implements NoteRepository {
  final List<NoteEntity> _notes = [];
  final List<FolderEntity> _folders = [];
  final List<TagEntity> _tags = [];
  final List<VoiceRecordingEntity> _voiceRecordings = [];
  final List<ReminderEntity> _reminders = [];
  final List<AttachmentEntity> _attachments = [];
  final List<String> _processedActionIds = [];

  final PerNoteMutex _noteMutex = PerNoteMutex();
  final PerNoteMutex _dbWriteMutex = PerNoteMutex();

  PerNoteMutex get noteMutex => _noteMutex;
  PerNoteMutex get dbWriteMutex => _dbWriteMutex;

  int _nextNotificationId = 1000;
  bool _isDataRecoveryMode = false;
  String? _dataRecoveryError;

  bool get isDataRecoveryMode => _isDataRecoveryMode;
  String? get dataRecoveryError => _dataRecoveryError;

  final _notesStreamController = StreamController<List<NoteEntity>>.broadcast();
  final _foldersStreamController =
      StreamController<List<FolderEntity>>.broadcast();
  final _tagsStreamController = StreamController<List<TagEntity>>.broadcast();
  final _recordingsStreamController =
      StreamController<List<VoiceRecordingEntity>>.broadcast();
  final _remindersStreamController =
      StreamController<List<ReminderEntity>>.broadcast();
  final _attachmentsStreamController =
      StreamController<List<AttachmentEntity>>.broadcast();

  final bool _seedDemoData;
  final bool _enableDiskPersistence;
  final String? _customStoragePath;
  final Future<String> Function()? _directoryProvider;
  final ReminderScheduler reminderScheduler;
  File? _resolvedFile;
  bool _initialized = false;
  String _themeMode = 'dark';

  String get themeMode => _themeMode;

  Future<void> setThemeMode(String mode) async {
    _themeMode = mode;
    await _saveToDisk();
  }

  LocalNoteRepository({
    bool seedDemoData = true,
    bool enableDiskPersistence = true,
    String? customStoragePath,
    Future<String> Function()? directoryProvider,
    this.reminderScheduler = const NoOpReminderScheduler(),
  })  : _seedDemoData = seedDemoData,
        _enableDiskPersistence = enableDiskPersistence,
        _customStoragePath = customStoragePath,
        _directoryProvider = directoryProvider {
    if (_seedDemoData) {
      _seedInitialData();
    }
  }

  Future<void> init() async {
    if (_initialized) return;
    if (!_enableDiskPersistence) {
      _initialized = true;
      return;
    }

    try {
      String? baseDir;
      if (_directoryProvider != null) {
        baseDir = await _directoryProvider!();
      } else if (_customStoragePath != null) {
        baseDir = File(_customStoragePath!).parent.path;
      }
      if (baseDir != null) {
        await _runPreInitRestoreRecovery(baseDir);
      }

      final file = await _getStorageFile();
      if (file == null) {
        _initialized = true;
        return;
      }

      final bakFile = File('${file.path}.bak');
      final tmpFile = File('${file.path}.tmp');

      Map<String, dynamic>? data;

      Future<Map<String, dynamic>?> tryLoadJson(File candidate) async {
        try {
          if (!await candidate.exists()) return null;
          final len = await candidate.length();
          if (len <= 0) return null;
          final content = await candidate.readAsString();
          if (content.trim().isEmpty) return null;
          final decoded = jsonDecode(content);
          if (decoded is Map<String, dynamic> &&
              (decoded.containsKey('notes') ||
                  decoded.containsKey('reminders') ||
                  decoded.containsKey('folders'))) {
            return decoded;
          }
        } catch (_) {}
        return null;
      }

      // 1. Try primary storage file
      data = await tryLoadJson(file);

      // 2. Fallback to .tmp file if primary missing or corrupt
      if (data == null && await tmpFile.exists()) {
        data = await tryLoadJson(tmpFile);
        if (data != null) {
          try {
            await tmpFile.copy(file.path);
          } catch (_) {}
        }
      }

      // 3. Fallback to .bak file if primary and tmp failed
      if (data == null && await bakFile.exists()) {
        data = await tryLoadJson(bakFile);
        if (data != null) {
          try {
            await bakFile.copy(file.path);
          } catch (_) {}
        }
      }

      final bool primaryExisted = await file.exists();
      final bool tmpExisted = await tmpFile.exists();
      final bool bakExisted = await bakFile.exists();
      final bool anyFileExisted = primaryExisted || tmpExisted || bakExisted;

      if (data == null && anyFileExisted) {
        // Files existed on disk but were unreadable or corrupt!
        // Preserve corrupt files as noteflow_data.json.corrupt.<timestamp>
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        if (primaryExisted) {
          try {
            await file.copy('${file.path}.corrupt.$timestamp');
          } catch (_) {}
        }

        // Enter Safe Data Recovery Mode - NEVER SILENTLY SEED DEMO DATA
        _notes.clear();
        _folders.clear();
        _tags.clear();
        _voiceRecordings.clear();
        _reminders.clear();
        _attachments.clear();
        _isDataRecoveryMode = true;
        _dataRecoveryError =
            'Unable to read note data. Please restore from a backup or contact support.';
        _initialized = true;
        _emitNotes();
        _emitFolders();
        _emitTags();
        _emitRecordings();
        _emitReminders();
        _emitAttachments();
        return;
      }

      if (data != null) {
        if (data.containsKey('theme_mode')) {
          _themeMode = data['theme_mode'] as String? ?? 'dark';
        }
        final rawFolders = data['folders'] as List<dynamic>? ?? [];
        final rawTags = data['tags'] as List<dynamic>? ?? [];
        final rawNotes = data['notes'] as List<dynamic>? ?? [];
        final rawRecordings =
            data['voice_recordings'] as List<dynamic>? ?? [];

        _folders.clear();
        for (final f in rawFolders) {
          _folders
              .add(FolderEntity.fromMap(Map<String, dynamic>.from(f as Map)));
        }

        _tags.clear();
        for (final t in rawTags) {
          _tags.add(TagEntity.fromMap(Map<String, dynamic>.from(t as Map)));
        }

        _notes.clear();
        for (final n in rawNotes) {
          _notes.add(NoteEntity.fromMap(Map<String, dynamic>.from(n as Map)));
        }

        _voiceRecordings.clear();
        for (final r in rawRecordings) {
          _voiceRecordings.add(VoiceRecordingEntity.fromMap(
              Map<String, dynamic>.from(r as Map)));
        }

        if (data.containsKey('next_notification_id')) {
          _nextNotificationId = data['next_notification_id'] as int? ?? 1000;
        }
        final rawReminders = data['reminders'] as List<dynamic>? ?? [];
        _reminders.clear();
        for (final r in rawReminders) {
          _reminders.add(
              ReminderEntity.fromMap(Map<String, dynamic>.from(r as Map)));
        }

        final rawAttachments = data['attachments'] as List<dynamic>? ?? [];
        _attachments.clear();
        for (final a in rawAttachments) {
          if (a is Map) {
            _attachments
                .add(AttachmentEntity.fromMap(Map<String, dynamic>.from(a)));
          }
        }

        if (data.containsKey('processed_action_ids')) {
          final rawActionIds =
              data['processed_action_ids'] as List<dynamic>? ?? [];
          _processedActionIds.clear();
          for (final id in rawActionIds) {
            if (id is String && id.trim().isNotEmpty) {
              _processedActionIds.add(id.trim());
            }
          }
        }

        await _ensureSampleAudioFiles();

        try {
          String? baseDir;
          if (_directoryProvider != null) {
            baseDir = await _directoryProvider!();
          } else if (_customStoragePath != null) {
            baseDir = File(_customStoragePath!).parent.path;
          }
          if (baseDir != null) {
            await _runStartupRecovery(baseDir);
          }
        } catch (_) {}

        _initialized = true;
        _emitNotes();
        _emitFolders();
        _emitTags();
        _emitRecordings();
        _emitReminders();
        _emitAttachments();
        return;
      }

      // If file didn't exist or was empty, seed demo data and save to disk
      await _ensureSampleAudioFiles();
      try {
        String? baseDir;
        if (_directoryProvider != null) {
          baseDir = await _directoryProvider!();
        } else if (_customStoragePath != null) {
          baseDir = File(_customStoragePath!).parent.path;
        }
        if (baseDir != null) {
          await _runStartupRecovery(baseDir);
        }
      } catch (_) {}
      if (_seedDemoData && _notes.isNotEmpty) {
        await _saveToDisk();
      }
    } catch (_) {
      // In case of error (e.g. non-Flutter test environment), maintain in-memory state
    }
    _initialized = true;
  }

  /// Deterministic crash recovery for Replace & Merge restore operations before loading database.
  Future<void> _runPreInitRestoreRecovery(String documentsBasePath) async {
    try {
      // 1. Check Replace Restore Journal
      final replaceJournalFile =
          File('$documentsBasePath/restore_journal.json');
      if (await replaceJournalFile.exists()) {
        try {
          final content = await replaceJournalFile.readAsString();
          final j = jsonDecode(content) as Map<String, dynamic>;
          final phase = j['phase'] as String?;

          final liveAttDir = Directory('$documentsBasePath/attachments');
          final liveVoiceDir = Directory('$documentsBasePath/voice_notes');
          final safetyBak =
              File('$documentsBasePath/backups/pre_restore_safety.bak');
          final dataFile = File('$documentsBasePath/noteflow_data.json');

          if (phase == 'prepared') {
            await _cleanStagingDirs(documentsBasePath);
            if (await safetyBak.exists()) await safetyBak.delete();
          } else if (phase == 'old_directory_moved') {
            await _restoreRollbackDirs(documentsBasePath);
            await _cleanStagingDirs(documentsBasePath);
            if (await safetyBak.exists()) await safetyBak.delete();
          } else if (phase == 'new_directory_moved') {
            if (await liveAttDir.exists()) {
              await liveAttDir.delete(recursive: true);
            }
            if (await liveVoiceDir.exists()) {
              await liveVoiceDir.delete(recursive: true);
            }
            await _restoreRollbackDirs(documentsBasePath);
            if (await safetyBak.exists()) {
              await safetyBak.copy(dataFile.path);
              await safetyBak.delete();
            }
            await _cleanStagingDirs(documentsBasePath);
          } else if (phase == 'repository_committed' ||
              phase == 'cleanup_complete') {
            await _purgeRollbackDirs(documentsBasePath);
            if (await safetyBak.exists()) await safetyBak.delete();
            await _cleanStagingDirs(documentsBasePath);
          }
        } catch (_) {}
        try {
          await replaceJournalFile.delete();
        } catch (_) {}
      }

      // 2. Check Merge Restore Journal
      final mergeJournalFile =
          File('$documentsBasePath/merge_restore_journal.json');
      if (await mergeJournalFile.exists()) {
        try {
          final content = await mergeJournalFile.readAsString();
          final j = jsonDecode(content) as Map<String, dynamic>;
          final phase = j['phase'] as String?;
          final copiedFiles =
              (j['copied_files'] as List<dynamic>?)?.cast<String>() ?? [];

          if (phase == 'merge_prepared') {
            await _cleanStagingDirs(documentsBasePath);
          } else if (phase == 'merge_files_copied') {
            for (final path in copiedFiles) {
              try {
                final f = File(path);
                if (await f.exists()) await f.delete();
              } catch (_) {}
            }
            await _cleanStagingDirs(documentsBasePath);
          } else if (phase == 'merge_repository_committed' ||
              phase == 'merge_cleanup_complete') {
            await _cleanStagingDirs(documentsBasePath);
          }
        } catch (_) {}
        try {
          await mergeJournalFile.delete();
        } catch (_) {}
      }

      await _cleanStagingDirs(documentsBasePath);
    } catch (_) {}
  }

  Future<void> _cleanStagingDirs(String basePath) async {
    try {
      final dir = Directory(basePath);
      if (await dir.exists()) {
        final entries = await dir.list().toList();
        for (final entry in entries) {
          if (entry is Directory) {
            final name = entry.path.split(Platform.pathSeparator).last;
            if (name.startsWith('attachments_restore_staging_') ||
                name.startsWith('voice_notes_restore_staging_')) {
              try {
                await entry.delete(recursive: true);
              } catch (_) {}
            }
          }
        }
      }
    } catch (_) {}
  }

  Future<void> _restoreRollbackDirs(String basePath) async {
    try {
      final dir = Directory(basePath);
      if (await dir.exists()) {
        final entries = await dir.list().toList();
        for (final entry in entries) {
          if (entry is Directory) {
            final name = entry.path.split(Platform.pathSeparator).last;
            if (name.startsWith('attachments_rollback_')) {
              final target = Directory('$basePath/attachments');
              if (!await target.exists()) {
                await entry.rename(target.path);
              }
            } else if (name.startsWith('voice_notes_rollback_')) {
              final target = Directory('$basePath/voice_notes');
              if (!await target.exists()) {
                await entry.rename(target.path);
              }
            }
          }
        }
      }
    } catch (_) {}
  }

  Future<void> _purgeRollbackDirs(String basePath) async {
    try {
      final dir = Directory(basePath);
      if (await dir.exists()) {
        final entries = await dir.list().toList();
        for (final entry in entries) {
          if (entry is Directory) {
            final name = entry.path.split(Platform.pathSeparator).last;
            if (name.startsWith('attachments_rollback_') ||
                name.startsWith('voice_notes_rollback_')) {
              try {
                await entry.delete(recursive: true);
              } catch (_) {}
            }
          }
        }
      }
    } catch (_) {}
  }

  /// Strict 5-step startup recovery sequencing for crashes, tombstones, and orphans.
  Future<void> _runStartupRecovery(String documentsBasePath) async {
    try {
      final entries = await AttachmentJournal.loadEntries(documentsBasePath);
      if (entries.isEmpty) {
        await AttachmentHelper.reconcileAttachments(
          documentsBasePath: documentsBasePath,
          activeRelativePaths: _attachments.map((a) => a.relativePath).toList(),
        );
        return;
      }

      // Step 1 (Tombstones): Finish complete deletion of tombstoned notes
      final tombstones =
          entries.where((e) => e.type == 'TOMBSTONE_NOTE').toList();
      for (final tombstone in tombstones) {
        final noteId = tombstone.noteId;
        // Delete physical attachment folder
        await AttachmentHelper.deleteNoteAttachmentDirectory(
          noteId: noteId,
          documentsBasePath: documentsBasePath,
        );
        // Delete physical voice notes folder
        try {
          final audioDir = Directory('$documentsBasePath/voice_notes/$noteId');
          if (await audioDir.exists()) {
            await audioDir.delete(recursive: true);
          }
        } catch (_) {}

        // Remove from memory
        _attachments.removeWhere((a) => a.noteId == noteId);
        _voiceRecordings.removeWhere((r) => r.voiceNoteId == noteId);
        _reminders.removeWhere((rem) => rem.noteId == noteId);
        _notes.removeWhere((n) => n.id == noteId);

        // Clear tombstone entry from journal
        await AttachmentJournal.removeTombstone(
          documentsBasePath: documentsBasePath,
          noteId: noteId,
        );
      }

      if (tombstones.isNotEmpty) {
        await _saveToDisk();
      }

      // Step 2 (Pending Deletions): Complete pending file deletions
      final deletions =
          entries.where((e) => e.type == 'DELETE_ATTACHMENT').toList();
      for (final del in deletions) {
        if (del.relativePath != null) {
          try {
            await AttachmentHelper.deleteAttachmentFile(
              relativePath: del.relativePath!,
              documentsBasePath: documentsBasePath,
            );
          } catch (_) {}
        }
        await AttachmentJournal.removeEntry(
          documentsBasePath: documentsBasePath,
          txId: del.txId,
        );
      }

      // Step 3 (Pending Imports): Verify parent note status
      final imports =
          entries.where((e) => e.type == 'IMPORT_ATTACHMENT').toList();
      for (final imp in imports) {
        final noteExists = _notes.any((n) => n.id == imp.noteId);
        if (!noteExists) {
          // Parent note does not exist (was deleted/discarded): delete staged and permanent files
          if (imp.relativePath != null) {
            try {
              await AttachmentHelper.deleteAttachmentFile(
                relativePath: imp.relativePath!,
                documentsBasePath: documentsBasePath,
              );
            } catch (_) {}
          }
          if (imp.stagingPath != null) {
            try {
              final sf = File(imp.stagingPath!);
              if (await sf.exists()) await sf.delete();
            } catch (_) {}
          }
        } else {
          // Parent note exists: if metadata is missing from _attachments, resurrect it
          final metaExists = _attachments.any((a) => a.id == imp.attachmentId);
          if (!metaExists &&
              imp.relativePath != null &&
              imp.attachmentId != null) {
            final file = File('$documentsBasePath/${imp.relativePath!}');
            if (await file.exists()) {
              final size = await file.length();
              final ext =
                  file.path.contains('.') ? file.path.split('.').last : '';
              final mime = AttachmentHelper.inferMimeType(ext);
              final category = AttachmentCategory.fromMime(mime, ext);
              final restoredEntity = AttachmentEntity(
                id: imp.attachmentId!,
                noteId: imp.noteId,
                originalName: file.uri.pathSegments.last,
                storedName: file.uri.pathSegments.last,
                relativePath: imp.relativePath!,
                mimeType: mime,
                fileExtension: ext,
                fileSizeBytes: size,
                category: category,
                createdAt: DateTime.fromMillisecondsSinceEpoch(imp.timestamp),
              );
              _attachments.add(restoredEntity);
              await _saveToDisk();
            }
          }
        }
        await AttachmentJournal.removeEntry(
          documentsBasePath: documentsBasePath,
          txId: imp.txId,
        );
      }

      // Step 4 (Journal Purge): Clear any remaining stale journal entries
      await AttachmentJournal.clearJournal(documentsBasePath);

      // Step 5 (Orphan Reconciliation): Run orphan cleanup on disk
      await AttachmentHelper.reconcileAttachments(
        documentsBasePath: documentsBasePath,
        activeRelativePaths: _attachments.map((a) => a.relativePath).toList(),
      );
    } catch (_) {}
  }

  Future<void> _ensureSampleAudioFiles() async {
    String? baseDir;
    if (_directoryProvider != null) {
      try {
        baseDir = await _directoryProvider!();
      } catch (_) {}
    } else if (_customStoragePath != null) {
      baseDir = File(_customStoragePath!).parent.path;
    }
    if (baseDir == null) return;

    bool updated = false;
    for (int i = 0; i < _voiceRecordings.length; i++) {
      final rec = _voiceRecordings[i];
      if (rec.voiceNoteId == 'note-meeting-sync' || rec.audioPath.isEmpty) {
        final targetPath =
            '$baseDir/voice_notes/${rec.voiceNoteId}/${rec.id}.wav';
        final targetFile = File(targetPath);
        if (!targetFile.existsSync() || targetFile.lengthSync() == 0) {
          try {
            targetFile.parent.createSync(recursive: true);
            final freq = rec.id.contains('intro') ? 440.0 : 554.37;
            final durationSec = rec.durationMs > 0
                ? (rec.durationMs / 1000).clamp(3, 10).toInt()
                : 4;
            targetFile.writeAsBytesSync(
              AudioHelper.createSampleWavBytes(
                durationSeconds: durationSec,
                frequency: freq,
              ),
            );
          } catch (_) {}
        }
        if (rec.audioPath != targetFile.path && targetFile.existsSync()) {
          _voiceRecordings[i] = rec.copyWith(
            audioPath: targetFile.path,
            format: 'wav',
            fileSize: targetFile.lengthSync(),
          );
          updated = true;
        }
      } else {
        // Recovery & migration for existing user recordings
        final currentFile = File(rec.audioPath);
        if (!currentFile.existsSync() || currentFile.lengthSync() == 0) {
          final recovered = await AudioHelper.recoverOrMigrateAudioFile(
            storedPath: rec.audioPath,
            voiceNoteId: rec.voiceNoteId,
            recordingId: rec.id,
            documentsBasePath: baseDir,
            format: rec.format.isNotEmpty ? rec.format : 'm4a',
          );
          if (recovered != null && recovered != rec.audioPath) {
            final recoveredFile = File(recovered);
            _voiceRecordings[i] = rec.copyWith(
              audioPath: recovered,
              fileSize: recoveredFile.existsSync()
                  ? recoveredFile.lengthSync()
                  : rec.fileSize,
            );
            updated = true;
          }
        }
      }
    }
    if (updated) {
      await _saveToDisk();
    }
  }

  Future<File?> _getStorageFile() async {
    if (_resolvedFile != null) return _resolvedFile;
    if (_customStoragePath != null) {
      _resolvedFile = File(_customStoragePath);
      return _resolvedFile;
    }
    if (_directoryProvider != null) {
      try {
        final dirPath = await _directoryProvider();
        _resolvedFile = File('$dirPath/noteflow_data.json');
        return _resolvedFile;
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  Future<void> _saveToDisk() async {
    if (!_enableDiskPersistence) return;
    if (_isDataRecoveryMode) {
      // In Data Recovery Mode, avoid overwriting disk until explicitly resolved or restored
      return;
    }
    await _dbWriteMutex.runLocked('__db_write__', () async {
      try {
        final file = await _getStorageFile();
        if (file == null) return;
        final payload = {
          'version': 1,
          'theme_mode': _themeMode,
          'next_notification_id': _nextNotificationId,
          'folders': _folders.map((f) => f.toMap()).toList(),
          'tags': _tags.map((t) => t.toMap()).toList(),
          'notes': _notes.map((n) => n.toMap()).toList(),
          'voice_recordings': _voiceRecordings.map((r) => r.toMap()).toList(),
          'reminders': _reminders.map((r) => r.toMap()).toList(),
          'attachments': _attachments.map((a) => a.toMap()).toList(),
          'processed_action_ids': _processedActionIds,
        };
        final jsonString = jsonEncode(payload);

        // 1. Write to noteflow_data.json.tmp (flush: true, file descriptor sync)
        final tmpFile = File('${file.path}.tmp');
        await tmpFile.writeAsString(jsonString, flush: true);

        // 2. Validate noteflow_data.json.tmp
        final tmpLength = await tmpFile.length();
        if (tmpLength <= 0) {
          throw StateError('Temporary save file length is zero');
        }
        final validatedContent = await tmpFile.readAsString();
        final validatedMap = jsonDecode(validatedContent);
        if (validatedMap is! Map<String, dynamic> ||
            !validatedMap.containsKey('notes') ||
            !validatedMap.containsKey('reminders')) {
          throw StateError(
              'Temporary save file validation failed: missing required root keys');
        }

        // 3. Maintain .bak fallback
        if (await file.exists() && await file.length() > 0) {
          final bakFile = File('${file.path}.bak');
          try {
            await file.copy(bakFile.path);
          } catch (_) {}
        }

        // 4. POSIX Atomic Rename (.tmp -> noteflow_data.json)
        await tmpFile.rename(file.path);
      } catch (_) {
        // Silent error fallback
      }
    });
  }

  void _seedInitialData() {
    final now = DateTime.now();

    // Seed Folders
    _folders.addAll([
      FolderEntity(
        id: 'folder-ideas',
        name: 'Ideas',
        colorHex: '0xFF10B981', // Emerald
        iconName: 'lightbulb',
        createdAt: now.subtract(const Duration(days: 5)),
      ),
      FolderEntity(
        id: 'folder-work',
        name: 'Work',
        colorHex: '0xFF2563EB', // Cobalt
        iconName: 'briefcase',
        createdAt: now.subtract(const Duration(days: 4)),
      ),
      FolderEntity(
        id: 'folder-personal',
        name: 'Personal',
        colorHex: '0xFF8B5CF6', // Purple
        iconName: 'user',
        createdAt: now.subtract(const Duration(days: 3)),
      ),
    ]);

    // Seed Tags
    _tags.addAll([
      TagEntity(
        id: 'tag-important',
        name: 'Important',
        colorHex: '0xFFEF4444', // Red/Rose
        createdAt: now.subtract(const Duration(days: 6)),
        updatedAt: now.subtract(const Duration(days: 6)),
      ),
      TagEntity(
        id: 'tag-work',
        name: 'Work',
        colorHex: '0xFF2563EB', // Cobalt
        createdAt: now.subtract(const Duration(days: 5)),
        updatedAt: now.subtract(const Duration(days: 5)),
      ),
      TagEntity(
        id: 'tag-ideas',
        name: 'Ideas',
        colorHex: '0xFF10B981', // Emerald
        createdAt: now.subtract(const Duration(days: 4)),
        updatedAt: now.subtract(const Duration(days: 4)),
      ),
      TagEntity(
        id: 'tag-personal',
        name: 'Personal',
        colorHex: '0xFF8B5CF6', // Purple
        createdAt: now.subtract(const Duration(days: 3)),
        updatedAt: now.subtract(const Duration(days: 3)),
      ),
    ]);

    // Seed Notes
    _notes.addAll([
      NoteEntity(
        id: 'note-welcome',
        title: 'Welcome to NoteFlow ✦',
        content:
            'NoteFlow is a modern, offline-first notepad crafted with Flutter, Drift SQLite, and Riverpod.\n\n'
            'Key features:\n'
            '• Pure offline persistence — zero cloud, zero tracking.\n'
            '• Rich-text editing with formatting & checklists.\n'
            '• Voice Notes container with independent audio recordings.\n'
            '• Organize notes with custom folders & color tints.\n'
            '• Pin important notes to keep them accessible.\n'
            '• Instant search and smooth dark/light theme transitions.',
        folderId: 'folder-ideas',
        isPinned: true,
        isArchived: false,
        isFavorite: true,
        isChecklist: false,
        isVoiceNote: false,
        colorIndex: 1, // Soft emerald tint
        tagIds: const ['tag-ideas', 'tag-important'],
        createdAt: now.subtract(const Duration(hours: 3)),
        updatedAt: now.subtract(const Duration(minutes: 10)),
      ),
      NoteEntity(
        id: 'note-groceries',
        title: 'Weekly Essentials & Tasks',
        content: '[x] Almond milk & Greek yogurt\n'
            '[x] Fresh sourdough bread\n'
            '[ ] Organic olive oil & balsamic vinegar\n'
            '[ ] Arabica coffee beans\n'
            '[ ] Fresh rosemary & thyme\n'
            '[ ] Review sprint retrospective notes',
        folderId: 'folder-personal',
        isPinned: true,
        isArchived: false,
        isFavorite: false,
        isChecklist: true,
        isVoiceNote: false,
        colorIndex: 4, // Warm amber tint
        tagIds: const ['tag-personal'],
        createdAt: now.subtract(const Duration(days: 1)),
        updatedAt: now.subtract(const Duration(hours: 1)),
      ),
      NoteEntity(
        id: 'note-architecture',
        title: 'Offline-First Architecture Notes',
        content: 'Drift SQLite serves as the single source of truth.\n\n'
            '1. All write operations commit immediately to local disk.\n'
            '2. Reactive queries emit updates to Riverpod providers.\n'
            '3. Clean Architecture separates domain entities from UI widgets.',
        folderId: 'folder-work',
        isPinned: false,
        isArchived: false,
        isFavorite: true,
        isChecklist: false,
        isVoiceNote: false,
        colorIndex: 2, // Soft blue tint
        tagIds: const ['tag-work'],
        createdAt: now.subtract(const Duration(days: 2)),
        updatedAt: now.subtract(const Duration(hours: 4)),
      ),
      NoteEntity(
        id: 'note-meeting-sync',
        title: 'Product Sync & Design Audio Memos',
        content: 'Meeting voice clips and action items',
        folderId: 'folder-work',
        isPinned: false,
        isArchived: false,
        isFavorite: false,
        isChecklist: false,
        isVoiceNote: true,
        voiceMode: 'list',
        colorIndex: 3, // Lavender tint
        tagIds: const ['tag-work', 'tag-ideas'],
        createdAt: now.subtract(const Duration(hours: 5)),
        updatedAt: now.subtract(const Duration(minutes: 45)),
      ),
    ]);

    // Seed Voice Recordings for note-meeting-sync
    _voiceRecordings.addAll([
      VoiceRecordingEntity(
        id: 'rec-intro',
        voiceNoteId: 'note-meeting-sync',
        title: 'Sprint 24 Goals & Timeline',
        audioPath: '',
        durationMs: 42000, // 0:42
        createdAt: now.subtract(const Duration(hours: 5)),
        sortOrder: 0,
        isCompleted: false,
      ),
      VoiceRecordingEntity(
        id: 'rec-discussion',
        voiceNoteId: 'note-meeting-sync',
        title: 'Offline Voice Storage Architecture',
        audioPath: '',
        durationMs: 84000, // 1:24
        createdAt: now.subtract(const Duration(hours: 4)),
        sortOrder: 1,
        isCompleted: true,
      ),
    ]);

    _emitNotes();
    _emitFolders();
    _emitTags();
    _emitRecordings();
  }

  void _emitTags() {
    if (!_tagsStreamController.isClosed) {
      final sorted = List<TagEntity>.from(_tags)
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      _tagsStreamController.add(List.unmodifiable(sorted));
    }
  }

  void _emitNotes() {
    if (!_notesStreamController.isClosed) {
      // Sort by recently updated by default
      final sorted = List<NoteEntity>.from(_notes)
        ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      _notesStreamController.add(List.unmodifiable(sorted));
    }
  }

  void _emitFolders() {
    if (!_foldersStreamController.isClosed) {
      _foldersStreamController.add(List.unmodifiable(_folders));
    }
  }

  void _emitRecordings() {
    if (!_recordingsStreamController.isClosed) {
      _recordingsStreamController.add(List.unmodifiable(_voiceRecordings));
    }
  }

  void _emitReminders() {
    if (!_remindersStreamController.isClosed) {
      _remindersStreamController.add(List.unmodifiable(_reminders));
    }
  }

  void _emitAttachments() {
    if (!_attachmentsStreamController.isClosed) {
      _attachmentsStreamController.add(List.unmodifiable(_attachments));
    }
  }

  int getNextNotificationId() {
    final id = _nextNotificationId++;
    _saveToDisk();
    return id;
  }

  List<String> get processedActionIds => List.unmodifiable(_processedActionIds);

  bool isActionProcessed(String actionId) {
    if (actionId.trim().isEmpty) return false;
    return _processedActionIds.contains(actionId.trim());
  }

  Future<void> recordProcessedActionId(String actionId) async {
    final clean = actionId.trim();
    if (clean.isEmpty) return;
    if (!_processedActionIds.contains(clean)) {
      _processedActionIds.add(clean);
      if (_processedActionIds.length > 500) {
        _processedActionIds.removeRange(0, _processedActionIds.length - 500);
      }
      await _saveToDisk();
    }
  }

  bool applyJournalAction(Map<String, dynamic> action) {
    return _applyJournalAction(action);
  }

  Future<void> applyJournalActions(List<Map<String, dynamic>> actions) async {
    bool changed = false;
    for (final a in actions) {
      if (_applyJournalAction(a)) {
        changed = true;
      }
    }
    if (changed) {
      await _saveToDisk();
      _emitReminders();
    }
  }

  bool _applyJournalAction(Map<String, dynamic> action) {
    final actionType = action['action'] as String?;
    final notificationId = action['notificationId'] as int? ?? -1;
    final noteId = action['noteId'] as String? ?? '';
    final idx = _reminders.indexWhere((r) =>
        r.notificationId == notificationId ||
        (noteId.isNotEmpty && r.noteId == noteId));
    if (idx < 0) return false;

    final rem = _reminders[idx];
    if (actionType == 'snooze') {
      final snoozedUntilMs = action['snoozedUntilMs'] as int?;
      final snoozedDate = snoozedUntilMs != null
          ? DateTime.fromMillisecondsSinceEpoch(snoozedUntilMs)
          : DateTime.now().add(const Duration(minutes: 15));
      _reminders[idx] = rem.copyWith(
        snoozeCount: rem.snoozeCount + 1,
        snoozedUntil: snoozedDate,
        updatedAt: DateTime.now(),
      );
      return true;
    } else if (actionType == 'markDone') {
      _reminders[idx] = rem.copyWith(
        isCompleted: true,
        completedAt: DateTime.now(),
        clearSnoozedUntil: true,
        updatedAt: DateTime.now(),
      );
      return true;
    }
    return false;
  }

  @override
  Stream<List<NoteEntity>> watchNotes(
      {bool includeArchived = false, String? folderId}) async* {
    List<NoteEntity> filterNotes(List<NoteEntity> notes) {
      return notes.where((note) {
        if (!includeArchived && note.isArchived) return false;
        if (includeArchived && !note.isArchived) return false;
        if (folderId != null && note.folderId != folderId) return false;
        return true;
      }).toList();
    }

    final sorted = List<NoteEntity>.from(_notes)
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    yield filterNotes(sorted);
    yield* _notesStreamController.stream.map(filterNotes);
  }

  @override
  Future<NoteEntity?> getNoteById(String id) async {
    try {
      return _notes.firstWhere((n) => n.id == id);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> saveNote(NoteEntity note) async {
    final index = _notes.indexWhere((n) => n.id == note.id);
    if (index >= 0) {
      _notes[index] = note.copyWith(updatedAt: DateTime.now());
    } else {
      _notes.insert(0, note);
    }
    _emitNotes();

    // Invalidate any checklist item reminders whose stable item tag was deleted from note content
    final checklistReminders = _reminders
        .where((r) => r.noteId == note.id && r.isChecklistItemReminder)
        .toList();
    if (checklistReminders.isNotEmpty) {
      final itemMatches = RegExp(r'<!--id:(.*?)-->').allMatches(note.content);
      final existingItemIds = itemMatches.map((m) => m.group(1)).toSet();
      bool changed = false;
      for (final rem in checklistReminders) {
        if (!existingItemIds.contains(rem.checklistItemId)) {
          try {
            reminderScheduler.cancelAlarm(rem.notificationId);
          } catch (_) {}
          _reminders.removeWhere((r) => r.id == rem.id);
          changed = true;
        }
      }
      if (changed) _emitReminders();
    }

    await _saveToDisk();
  }

  @override
  Future<void> deleteNote(String id) async {
    await _noteMutex.runLocked(id, () async {
      String? baseDir;
      if (_directoryProvider != null) {
        baseDir = await _directoryProvider!();
      } else if (_customStoragePath != null) {
        baseDir = File(_customStoragePath!).parent.path;
      }

      final txId = AttachmentHelper.generateUuidV4();

      // Write tombstone to journal BEFORE deleting metadata or files
      if (baseDir != null) {
        await AttachmentJournal.recordTombstone(
          documentsBasePath: baseDir,
          txId: txId,
          noteId: id,
        );
      }

      final note = await getNoteById(id);
      if (note?.audioPath != null) {
        try {
          final audioFile = File(note!.audioPath!);
          if (await audioFile.exists()) {
            await audioFile.delete();
          }
        } catch (_) {}
      }

      // Delete all child voice recordings and their local audio files
      final childRecordings =
          _voiceRecordings.where((r) => r.voiceNoteId == id).toList();
      for (final rec in childRecordings) {
        if (rec.audioPath.isNotEmpty) {
          try {
            final audioFile = File(rec.audioPath);
            if (await audioFile.exists()) {
              await audioFile.delete();
            }
            final parentDir = audioFile.parent;
            if (await parentDir.exists() && await parentDir.list().isEmpty) {
              await parentDir.delete(recursive: true);
            }
          } catch (_) {}
        }
      }
      _voiceRecordings.removeWhere((r) => r.voiceNoteId == id);
      _emitRecordings();

      // Delete all child reminders and cancel their native alarms
      final childReminders = _reminders.where((r) => r.noteId == id).toList();
      for (final rem in childReminders) {
        try {
          reminderScheduler.cancelAlarm(rem.notificationId);
        } catch (_) {}
      }
      _reminders.removeWhere((r) => r.noteId == id);
      _emitReminders();

      // Clean up dedicated note directories if they exist
      try {
        if (baseDir != null) {
          final noteAudioDir = Directory('$baseDir/voice_notes/$id');
          if (await noteAudioDir.exists()) {
            await noteAudioDir.delete(recursive: true);
          }
          await AttachmentHelper.deleteNoteAttachmentDirectory(
            noteId: id,
            documentsBasePath: baseDir,
          );
        }
      } catch (_) {}

      _attachments.removeWhere((a) => a.noteId == id);
      _emitAttachments();

      _notes.removeWhere((n) => n.id == id);
      _emitNotes();
      await _saveToDisk();

      // Clear the tombstone from the journal only AFTER noteflow_data.json is flushed
      if (baseDir != null) {
        await AttachmentJournal.removeTombstone(
          documentsBasePath: baseDir,
          noteId: id,
        );
      }
    });
  }

  @override
  Future<void> togglePin(String id) async {
    final index = _notes.indexWhere((n) => n.id == id);
    if (index >= 0) {
      final current = _notes[index];
      _notes[index] = current.copyWith(
        isPinned: !current.isPinned,
        updatedAt: DateTime.now(),
      );
      _emitNotes();
      await _saveToDisk();
    }
  }

  @override
  Future<void> toggleArchive(String id) async {
    final index = _notes.indexWhere((n) => n.id == id);
    if (index >= 0) {
      final current = _notes[index];
      _notes[index] = current.copyWith(
        isArchived: !current.isArchived,
        isPinned: false, // Unpin when archiving
        updatedAt: DateTime.now(),
      );
      _emitNotes();
      await _saveToDisk();
    }
  }

  @override
  Future<void> toggleFavorite(String id) async {
    final index = _notes.indexWhere((n) => n.id == id);
    if (index >= 0) {
      final current = _notes[index];
      _notes[index] = current.copyWith(
        isFavorite: !current.isFavorite,
        updatedAt: DateTime.now(),
      );
      _emitNotes();
      await _saveToDisk();
    }
  }

  @override
  Stream<List<FolderEntity>> watchFolders() async* {
    yield List.unmodifiable(_folders);
    yield* _foldersStreamController.stream;
  }

  @override
  Future<void> saveFolder(FolderEntity folder) async {
    final index = _folders.indexWhere((f) => f.id == folder.id);
    if (index >= 0) {
      _folders[index] = folder;
    } else {
      _folders.add(folder);
    }
    _emitFolders();
    await _saveToDisk();
  }

  @override
  Future<void> deleteFolder(String id) async {
    _folders.removeWhere((f) => f.id == id);
    // Unassign notes in this folder
    for (int i = 0; i < _notes.length; i++) {
      if (_notes[i].folderId == id) {
        _notes[i] = _notes[i].copyWith(clearFolder: true);
      }
    }
    _emitFolders();
    _emitNotes();
    await _saveToDisk();
  }

  // Tags CRUD
  @override
  Stream<List<TagEntity>> watchTags() async* {
    final sorted = List<TagEntity>.from(_tags)
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    yield List.unmodifiable(sorted);
    yield* _tagsStreamController.stream;
  }

  @override
  Future<List<TagEntity>> getTags() async {
    final sorted = List<TagEntity>.from(_tags)
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return List.unmodifiable(sorted);
  }

  @override
  Future<TagEntity?> getTagById(String id) async {
    try {
      return _tags.firstWhere((t) => t.id == id);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> saveTag(TagEntity tag) async {
    final index = _tags.indexWhere((t) => t.id == tag.id);
    if (index >= 0) {
      _tags[index] = tag.copyWith(updatedAt: DateTime.now());
    } else {
      _tags.add(tag);
    }
    _emitTags();
    await _saveToDisk();
  }

  @override
  Future<void> deleteTag(String id) async {
    _tags.removeWhere((t) => t.id == id);
    // Cascade removal of this tag from all notes
    bool notesModified = false;
    for (int i = 0; i < _notes.length; i++) {
      if (_notes[i].tagIds.contains(id)) {
        final updatedTags = List<String>.from(_notes[i].tagIds)..remove(id);
        _notes[i] = _notes[i].copyWith(tagIds: updatedTags);
        notesModified = true;
      }
    }
    _emitTags();
    if (notesModified) {
      _emitNotes();
    }
    await _saveToDisk();
  }

  // Voice Recordings CRUD
  @override
  Stream<List<VoiceRecordingEntity>> watchVoiceRecordings(
      String voiceNoteId) async* {
    List<VoiceRecordingEntity> getSorted() {
      final list = _voiceRecordings
          .where((r) => r.voiceNoteId == voiceNoteId)
          .toList()
        ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
      return list;
    }

    yield getSorted();
    yield* _recordingsStreamController.stream.map((_) => getSorted());
  }

  @override
  Future<List<VoiceRecordingEntity>> getVoiceRecordings(
      String voiceNoteId) async {
    final list = _voiceRecordings
        .where((r) => r.voiceNoteId == voiceNoteId)
        .toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    return list;
  }

  @override
  Future<void> saveVoiceRecording(VoiceRecordingEntity recording) async {
    final index = _voiceRecordings.indexWhere((r) => r.id == recording.id);
    if (index >= 0) {
      _voiceRecordings[index] = recording;
    } else {
      _voiceRecordings.add(recording);
    }
    _emitRecordings();
    await _saveToDisk();
  }

  @override
  Future<void> deleteVoiceRecording(String recordingId) async {
    final index = _voiceRecordings.indexWhere((r) => r.id == recordingId);
    if (index >= 0) {
      final rec = _voiceRecordings[index];
      if (rec.audioPath.isNotEmpty) {
        try {
          String? baseDir;
          if (_directoryProvider != null) {
            baseDir = await _directoryProvider!();
          } else if (_customStoragePath != null) {
            baseDir = File(_customStoragePath!).parent.path;
          }
          final resolved =
              await AudioHelper.resolveAudioPath(rec.audioPath, baseDir);
          final filePath = resolved ?? rec.audioPath;
          final file = File(filePath);
          if (await file.exists()) {
            await file.delete();
          }
        } catch (_) {}
      }
      _voiceRecordings.removeAt(index);
      _emitRecordings();

      // Cancel and remove any reminders targeting this recording
      final recReminders =
          _reminders.where((r) => r.voiceRecordingId == recordingId).toList();
      for (final rem in recReminders) {
        try {
          reminderScheduler.cancelAlarm(rem.notificationId);
        } catch (_) {}
      }
      _reminders.removeWhere((r) => r.voiceRecordingId == recordingId);
      _emitReminders();

      await _saveToDisk();
    }
  }

  @override
  Future<void> reorderVoiceRecordings(
      String voiceNoteId, List<String> orderedIds) async {
    for (int i = 0; i < orderedIds.length; i++) {
      final id = orderedIds[i];
      final index = _voiceRecordings
          .indexWhere((r) => r.id == id && r.voiceNoteId == voiceNoteId);
      if (index >= 0) {
        _voiceRecordings[index] =
            _voiceRecordings[index].copyWith(sortOrder: i);
      }
    }
    _emitRecordings();
    await _saveToDisk();
  }

  @override
  Future<void> toggleVoiceRecordingCompletion(String recordingId) async {
    final index = _voiceRecordings.indexWhere((r) => r.id == recordingId);
    if (index >= 0) {
      final current = _voiceRecordings[index];
      _voiceRecordings[index] =
          current.copyWith(isCompleted: !current.isCompleted);
      _emitRecordings();
      await _saveToDisk();
    }
  }

  BackupService get backupService => BackupService(repository: this);
  RestoreService get restoreService => RestoreService(repository: this);

  @override
  Future<String?> getBaseDirectory() async {
    if (_directoryProvider != null) {
      try {
        return await _directoryProvider!();
      } catch (_) {}
    } else if (_customStoragePath != null) {
      return File(_customStoragePath!).parent.path;
    }
    final file = await _getStorageFile();
    return file?.parent.path;
  }

  Future<Directory> getBackupDirectory() async {
    return backupService.getBackupDirectory();
  }

  List<NoteEntity> getAllNotes() => List.unmodifiable(_notes);
  List<FolderEntity> getAllFolders() => List.unmodifiable(_folders);
  List<TagEntity> getAllTags() => List.unmodifiable(_tags);
  List<VoiceRecordingEntity> getAllVoiceRecordings() =>
      List.unmodifiable(_voiceRecordings);
  List<ReminderEntity> getAllReminders() => List.unmodifiable(_reminders);
  List<AttachmentEntity> getAllAttachments() => List.unmodifiable(_attachments);

  Future<void> replaceAllData({
    required List<FolderEntity> folders,
    required List<NoteEntity> notes,
    required List<VoiceRecordingEntity> voiceRecordings,
    List<TagEntity>? tags,
    List<ReminderEntity>? reminders,
    List<AttachmentEntity>? attachments,
    String? themeMode,
  }) async {
    _isDataRecoveryMode = false;
    _dataRecoveryError = null;
    if (themeMode != null) _themeMode = themeMode;
    _folders.clear();
    _folders.addAll(folders);
    if (attachments != null) {
      _attachments.clear();
      _attachments.addAll(attachments);
    }
    if (tags != null) {
      _tags.clear();
      _tags.addAll(tags);
    }
    _notes.clear();
    _notes.addAll(notes);
    _voiceRecordings.clear();
    _voiceRecordings.addAll(voiceRecordings);
    if (reminders != null) {
      // Pre-cancel existing alarms before replacing data
      for (final rem in _reminders) {
        try {
          reminderScheduler.cancelAlarm(rem.notificationId);
        } catch (_) {}
      }
      _reminders.clear();
      _reminders.addAll(reminders);

      // Re-arm restored alarms if future and active
      final now = DateTime.now();
      for (final rem in reminders) {
        if (!rem.isCompleted && rem.effectiveScheduledAt.isAfter(now)) {
          try {
            reminderScheduler.scheduleAlarm(
              notificationId: rem.notificationId,
              triggerEpochMs: rem.effectiveScheduledAt.millisecondsSinceEpoch,
              title: rem.title,
              body: rem.notesPreview.isNotEmpty
                  ? rem.notesPreview
                  : 'Note Reminder',
              noteId: rem.noteId,
              checklistItemId: rem.checklistItemId,
              voiceRecordingId: rem.voiceRecordingId,
            );
          } catch (_) {}
        }
        if (rem.notificationId >= _nextNotificationId) {
          _nextNotificationId = rem.notificationId + 1;
        }
      }

      _emitReminders();
    }
    if (tags != null) _emitTags();
    if (attachments != null) _emitAttachments();
    _emitFolders();
    _emitNotes();
    _emitRecordings();
    await _saveToDisk();
  }

  Future<void> mergeAllData({
    required List<FolderEntity> folders,
    required List<NoteEntity> notes,
    required List<VoiceRecordingEntity> voiceRecordings,
    List<TagEntity>? tags,
    List<ReminderEntity>? reminders,
    List<AttachmentEntity>? attachments,
    String? themeMode,
  }) async {
    if (themeMode != null) _themeMode = themeMode;

    for (final bf in folders) {
      final idx = _folders.indexWhere((f) => f.id == bf.id);
      if (idx >= 0) {
        _folders[idx] = bf;
      } else {
        _folders.add(bf);
      }
    }

    if (tags != null) {
      for (final bt in tags) {
        final idx = _tags.indexWhere(
            (t) => t.id == bt.id || TagEntity.namesEqual(t.name, bt.name));
        if (idx >= 0) {
          _tags[idx] = bt;
        } else {
          _tags.add(bt);
        }
      }
    }

    for (final br in voiceRecordings) {
      final idx = _voiceRecordings.indexWhere((r) => r.id == br.id);
      if (idx >= 0) {
        _voiceRecordings[idx] = br;
      } else {
        _voiceRecordings.add(br);
      }
    }

    for (final bn in notes) {
      final idx = _notes.indexWhere((n) => n.id == bn.id);
      if (idx >= 0) {
        final mergedTagIds = {..._notes[idx].tagIds, ...bn.tagIds}.toList();
        final isFav = _notes[idx].isFavorite || bn.isFavorite;
        _notes[idx] = bn.copyWith(
          tagIds: mergedTagIds,
          isFavorite: isFav,
        );
      } else {
        _notes.add(bn);
      }
    }

    if (reminders != null) {
      final now = DateTime.now();
      for (final br in reminders) {
        final idx = _reminders.indexWhere((r) => r.id == br.id);
        if (idx >= 0) {
          _reminders[idx] = br;
        } else {
          _reminders.add(br);
        }

        if (!br.isCompleted && br.effectiveScheduledAt.isAfter(now)) {
          try {
            reminderScheduler.scheduleAlarm(
              notificationId: br.notificationId,
              triggerEpochMs: br.effectiveScheduledAt.millisecondsSinceEpoch,
              title: br.title,
              body: br.notesPreview.isNotEmpty
                  ? br.notesPreview
                  : 'Note Reminder',
              noteId: br.noteId,
              checklistItemId: br.checklistItemId,
              voiceRecordingId: br.voiceRecordingId,
            );
          } catch (_) {}
        }

        if (br.notificationId >= _nextNotificationId) {
          _nextNotificationId = br.notificationId + 1;
        }
      }
      _emitReminders();
    }

    if (attachments != null) {
      for (final ba in attachments) {
        final idx = _attachments.indexWhere((a) => a.id == ba.id);
        if (idx >= 0) {
          _attachments[idx] = ba;
        } else {
          _attachments.add(ba);
        }
      }
      _emitAttachments();
    }

    _emitFolders();
    _emitNotes();
    _emitRecordings();
    await _saveToDisk();
  }

  // Reminders Implementation
  @override
  Stream<List<ReminderEntity>> watchReminders() async* {
    yield List.unmodifiable(_reminders);
    yield* _remindersStreamController.stream;
  }

  @override
  Future<List<ReminderEntity>> getReminders() async {
    return List.unmodifiable(_reminders);
  }

  @override
  Future<ReminderEntity?> getReminderById(String id) async {
    try {
      return _reminders.firstWhere((r) => r.id == id);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<ReminderEntity?> getReminderForNote(String noteId) async {
    try {
      return _reminders
          .firstWhere((r) => r.noteId == noteId && r.isWholeNoteReminder);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<ReminderEntity?> getReminderForChecklistItem(
      String noteId, String checklistItemId) async {
    try {
      return _reminders.firstWhere(
          (r) => r.noteId == noteId && r.checklistItemId == checklistItemId);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<ReminderEntity?> getReminderForVoiceRecording(
      String voiceRecordingId) async {
    try {
      return _reminders
          .firstWhere((r) => r.voiceRecordingId == voiceRecordingId);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> saveReminder(ReminderEntity reminder) async {
    final idx = _reminders.indexWhere((r) => r.id == reminder.id);
    if (idx >= 0) {
      _reminders[idx] = reminder;
    } else {
      _reminders.add(reminder);
    }
    _emitReminders();
    await _saveToDisk();
  }

  @override
  Future<void> deleteReminder(String id) async {
    final rem = await getReminderById(id);
    if (rem != null) {
      try {
        reminderScheduler.cancelAlarm(rem.notificationId);
      } catch (_) {}
    }
    _reminders.removeWhere((r) => r.id == id);
    _emitReminders();
    await _saveToDisk();
  }

  @override
  Future<void> completeReminder(String id) async {
    final idx = _reminders.indexWhere((r) => r.id == id);
    if (idx >= 0) {
      final rem = _reminders[idx];
      try {
        reminderScheduler.cancelAlarm(rem.notificationId);
      } catch (_) {}
      _reminders[idx] = rem.copyWith(
        isCompleted: true,
        completedAt: DateTime.now(),
        clearSnoozedUntil: true,
        updatedAt: DateTime.now(),
      );
      _emitReminders();
      await _saveToDisk();
    }
  }

  @override
  Future<void> snoozeReminder(String id, Duration duration) async {
    final idx = _reminders.indexWhere((r) => r.id == id);
    if (idx >= 0) {
      final rem = _reminders[idx];
      final newTime = DateTime.now().add(duration);
      _reminders[idx] = rem.copyWith(
        snoozeCount: rem.snoozeCount + 1,
        snoozedUntil: newTime,
        updatedAt: DateTime.now(),
      );
      try {
        reminderScheduler.scheduleAlarm(
          notificationId: rem.notificationId,
          triggerEpochMs: newTime.millisecondsSinceEpoch,
          title: rem.title,
          body: rem.notesPreview.isNotEmpty
              ? rem.notesPreview
              : 'Note Reminder (Snoozed)',
          noteId: rem.noteId,
          checklistItemId: rem.checklistItemId,
          voiceRecordingId: rem.voiceRecordingId,
        );
      } catch (_) {}
      _emitReminders();
      await _saveToDisk();
    }
  }

  @override
  Future<Map<String, dynamic>> exportBackupPayload(
      {bool includeAudio = true}) async {
    final now = DateTime.now();
    final Map<String, String> audioPayloads = {};
    int audioFilesCount = 0;

    if (includeAudio) {
      final baseDir = await getBaseDirectory();
      for (final rec in _voiceRecordings) {
        if (rec.audioPath.isNotEmpty) {
          try {
            final resolved =
                await AudioHelper.resolveAudioPath(rec.audioPath, baseDir);
            final targetPath = resolved ?? rec.audioPath;
            final file = File(targetPath);
            if (await file.exists() && await file.length() > 0) {
              final bytes = await file.readAsBytes();
              audioPayloads[rec.id] = base64Encode(bytes);
              audioFilesCount++;
            }
          } catch (_) {}
        }
      }
      for (final note in _notes) {
        if (note.audioPath != null && note.audioPath!.isNotEmpty) {
          try {
            final resolved =
                await AudioHelper.resolveAudioPath(note.audioPath!, baseDir);
            final targetPath = resolved ?? note.audioPath!;
            final file = File(targetPath);
            if (await file.exists() && await file.length() > 0) {
              final bytes = await file.readAsBytes();
              audioPayloads[note.id] = base64Encode(bytes);
              audioFilesCount++;
            }
          } catch (_) {}
        }
      }
    }

    return {
      'app': 'NoteFlow',
      'version': 1,
      'backup_version': 2,
      'created_at': now.toIso8601String(),
      'theme_mode': _themeMode,
      'stats': {
        'notes_count': _notes.length,
        'folders_count': _folders.length,
        'tags_count': _tags.length,
        'recordings_count': _voiceRecordings.length,
        'reminders_count': _reminders.length,
        'has_audio': audioFilesCount > 0,
        'audio_files_count': audioFilesCount,
      },
      'folders': _folders.map((f) => f.toMap()).toList(),
      'tags': _tags.map((t) => t.toMap()).toList(),
      'notes': _notes.map((n) => n.toMap()).toList(),
      'voice_recordings': _voiceRecordings.map((r) => r.toMap()).toList(),
      'reminders': _reminders.map((r) => r.toMap()).toList(),
      'audio_payloads': audioPayloads,
    };
  }

  @override
  Future<File> createBackupFile(
      {bool includeAudio = true, String? customName}) async {
    return backupService.createBackupArchive(
      includeAudio: includeAudio,
      customName: customName,
    );
  }

  @override
  Future<List<File>> listLocalBackups() async {
    return backupService.listLocalBackups();
  }

  @override
  Future<BackupPreview> inspectBackup(String jsonStringOrFilePath) async {
    return restoreService.inspectArchive(jsonStringOrFilePath);
  }

  @override
  Future<void> restoreBackup(
    String jsonStringOrFilePath, {
    required RestoreStrategy strategy,
  }) async {
    await restoreService.restoreArchive(jsonStringOrFilePath,
        strategy: strategy);
  }

  @override
  Future<void> deleteBackupFile(String filePath) async {
    await backupService.deleteBackupFile(filePath);
  }

  // Attachments CRUD
  @override
  Stream<List<AttachmentEntity>> watchAttachments(String noteId) async* {
    List<AttachmentEntity> getForNote() {
      final list = _attachments.where((a) => a.noteId == noteId).toList()
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
      return List.unmodifiable(list);
    }

    yield getForNote();
    yield* _attachmentsStreamController.stream.map((_) => getForNote());
  }

  @override
  Future<List<AttachmentEntity>> getAttachments(String noteId) async {
    final list = _attachments.where((a) => a.noteId == noteId).toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return List.unmodifiable(list);
  }

  @override
  Future<AttachmentEntity?> getAttachmentById(String id) async {
    try {
      return _attachments.firstWhere((a) => a.id == id);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> saveAttachment(AttachmentEntity attachment) async {
    await _noteMutex.runLocked(attachment.noteId, () async {
      final index = _attachments.indexWhere((a) => a.id == attachment.id);
      if (index >= 0) {
        _attachments[index] = attachment;
      } else {
        _attachments.add(attachment);
      }
      _emitAttachments();
      await _saveToDisk();
    });
  }

  @override
  Future<void> deleteAttachment(String id) async {
    final index = _attachments.indexWhere((a) => a.id == id);
    if (index >= 0) {
      final attachment = _attachments[index];
      await _noteMutex.runLocked(attachment.noteId, () async {
        String? baseDir;
        if (_directoryProvider != null) {
          baseDir = await _directoryProvider!();
        } else if (_customStoragePath != null) {
          baseDir = File(_customStoragePath!).parent.path;
        }

        final txId = AttachmentHelper.generateUuidV4();
        if (baseDir != null) {
          await AttachmentJournal.recordDeletePending(
            documentsBasePath: baseDir,
            txId: txId,
            noteId: attachment.noteId,
            attachmentId: attachment.id,
            relativePath: attachment.relativePath,
          );
        }

        try {
          if (baseDir != null) {
            await AttachmentHelper.deleteAttachmentFile(
              relativePath: attachment.relativePath,
              documentsBasePath: baseDir,
            );
          }
        } catch (_) {}

        _attachments.removeWhere((a) => a.id == id);
        _emitAttachments();
        await _saveToDisk();

        if (baseDir != null) {
          await AttachmentJournal.removeEntry(
            documentsBasePath: baseDir,
            txId: txId,
          );
        }
      });
    }
  }

  @override
  Future<void> deleteAttachmentsForNote(String noteId) async {
    await _noteMutex.runLocked(noteId, () async {
      try {
        String? baseDir;
        if (_directoryProvider != null) {
          baseDir = await _directoryProvider!();
        } else if (_customStoragePath != null) {
          baseDir = File(_customStoragePath!).parent.path;
        }
        if (baseDir != null) {
          await AttachmentHelper.deleteNoteAttachmentDirectory(
            noteId: noteId,
            documentsBasePath: baseDir,
          );
        }
      } catch (_) {}
      _attachments.removeWhere((a) => a.noteId == noteId);
      _emitAttachments();
      await _saveToDisk();
    });
  }

  /// Atomically commits a staged attachment and persists its metadata,
  /// guarded by the per-note mutex and durable transaction journal.
  @override
  Future<AttachmentEntity?> importAndSaveAttachment({
    required String stagingPath,
    required String originalName,
    required String noteId,
    String? mimeType,
    String Function()? idGenerator,
  }) async {
    return _noteMutex.runLocked(noteId, () async {
      String? baseDir;
      if (_directoryProvider != null) {
        baseDir = await _directoryProvider!();
      } else if (_customStoragePath != null) {
        baseDir = File(_customStoragePath!).parent.path;
      }
      if (baseDir == null) return null;

      // 1. Verify note exists and is not tombstoned
      final noteExists = _notes.any((n) => n.id == noteId);
      final isTombstoned = await AttachmentJournal.isNoteTombstoned(
        documentsBasePath: baseDir,
        noteId: noteId,
      );
      if (!noteExists || isTombstoned) {
        try {
          final sf = File(stagingPath);
          if (await sf.exists()) await sf.delete();
        } catch (_) {}
        return null;
      }

      // 2. Record IMPORT_ATTACHMENT in journal
      final txId = idGenerator != null
          ? idGenerator()
          : AttachmentHelper.generateUuidV4();
      final rawExt =
          originalName.contains('.') ? originalName.split('.').last : '';
      final ext = AttachmentHelper.sanitizeExtension(rawExt);
      final storedName = ext.isNotEmpty ? '$txId.$ext' : txId;
      final relPath =
          '${AttachmentHelper.attachmentsDirName}/$noteId/$storedName';

      await AttachmentJournal.recordImportPending(
        documentsBasePath: baseDir,
        txId: txId,
        noteId: noteId,
        attachmentId: txId,
        relativePath: relPath,
        stagingPath: stagingPath,
      );

      // 3. Move file to permanent storage
      final entity = await AttachmentHelper.commitStagedAttachment(
        stagingPath: stagingPath,
        originalName: originalName,
        noteId: noteId,
        documentsBasePath: baseDir,
        mimeType: mimeType,
        idGenerator: () => txId,
      );

      if (entity == null) {
        await AttachmentJournal.removeEntry(
            documentsBasePath: baseDir, txId: txId);
        return null;
      }

      // 4. Double check note wasn't deleted while moving file
      final noteStillExists = _notes.any((n) => n.id == noteId);
      final noteNowTombstoned = await AttachmentJournal.isNoteTombstoned(
        documentsBasePath: baseDir,
        noteId: noteId,
      );
      if (!noteStillExists || noteNowTombstoned) {
        await AttachmentHelper.deleteAttachmentFile(
          relativePath: entity.relativePath,
          documentsBasePath: baseDir,
        );
        await AttachmentJournal.removeEntry(
            documentsBasePath: baseDir, txId: txId);
        return null;
      }

      // 5. Persist metadata
      final index = _attachments.indexWhere((a) => a.id == entity.id);
      if (index >= 0) {
        _attachments[index] = entity;
      } else {
        _attachments.add(entity);
      }
      _emitAttachments();
      await _saveToDisk();

      // 6. Purge journal entry
      await AttachmentJournal.removeEntry(
          documentsBasePath: baseDir, txId: txId);

      return entity;
    });
  }

  /// Checks if a note has an active tombstone recorded in the journal.
  Future<bool> isNoteTombstoned(String noteId) async {
    String? baseDir;
    if (_directoryProvider != null) {
      baseDir = await _directoryProvider!();
    } else if (_customStoragePath != null) {
      baseDir = File(_customStoragePath!).parent.path;
    }
    if (baseDir == null) return false;
    return AttachmentJournal.isNoteTombstoned(
      documentsBasePath: baseDir,
      noteId: noteId,
    );
  }

  void dispose() {
    _notesStreamController.close();
    _foldersStreamController.close();
    _tagsStreamController.close();
    _recordingsStreamController.close();
    _remindersStreamController.close();
    _attachmentsStreamController.close();
  }
}
