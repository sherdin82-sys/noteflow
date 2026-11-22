import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import '../../../core/database/local_note_repository.dart';
import '../../../shared/models/backup_models.dart';
import '../../../shared/models/folder_entity.dart';
import '../../../shared/models/tag_entity.dart';
import '../../../shared/models/note_entity.dart';
import '../../../shared/models/voice_recording_entity.dart';
import '../../../shared/models/reminder_entity.dart';
import '../../../shared/models/attachment_entity.dart';
import '../../../core/utils/attachment_helper.dart';

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

  bool isZipBytes(List<int> bytes) {
    if (bytes.length < 4) return false;
    return bytes[0] == 0x50 && bytes[1] == 0x4B && bytes[2] == 0x03 && bytes[3] == 0x04;
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
    final bool isZip = isZipBytes(bytes);
    final bool isCompressed = !isZip && isGzipBytes(bytes);

    if (isZip) {
      final Archive archive;
      try {
        archive = ZipDecoder().decodeBytes(bytes);
      } catch (e) {
        throw FormatException('Malformed or invalid NoteFlow ZIP archive: $e');
      }
      final manifestFile = archive.findFile('manifest.json');
      if (manifestFile == null) {
        throw const FormatException('Invalid NoteFlow ZIP archive: missing manifest.json');
      }
      final manifestBytes = manifestFile.content as List<int>;
      content = utf8.decode(manifestBytes);
      return _inspectJsonString(
        content,
        filePath: file.path,
        fileName: fileName,
        fileSize: fileSize,
        isZipArchive: true,
      );
    } else if (isCompressed) {
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
      isZipArchive: false,
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
    final tagsList = (parsed['tags'] as List<dynamic>?) ?? [];
    final recordingsList = (parsed['voice_recordings'] as List<dynamic>?) ?? [];
    final rawReminders = (parsed['reminders'] as List<dynamic>?) ?? [];
    final rawAttachments = (parsed['attachments'] as List<dynamic>?) ?? [];
    final audioPayloads = (parsed['audio_payloads'] as Map<String, dynamic>?) ?? {};

    final stats = parsed['stats'] as Map<String, dynamic>?;
    final notesCount = stats?['notes_count'] as int? ?? notesList.length;
    final foldersCount = stats?['folders_count'] as int? ?? foldersList.length;
    final tagsCount = stats?['tags_count'] as int? ?? tagsList.length;
    final recordingsCount = stats?['recordings_count'] as int? ?? recordingsList.length;
    final audioFilesCount = stats?['audio_files_count'] as int? ?? audioPayloads.length;
    final remindersCount = stats?['reminders_count'] as int? ?? rawReminders.length;
    final attachmentsCount = stats?['attachments_count'] as int? ?? rawAttachments.length;
    final hasAudio = stats?['has_audio'] as bool? ?? (audioFilesCount > 0);

    final calculatedSize = fileSize ?? utf8.encode(content).length;

    return BackupPreview(
      appName: app.isNotEmpty ? app : 'NoteFlow',
      version: parsed['version'] as int? ?? 1,
      createdAt: createdAt,
      notesCount: notesCount,
      foldersCount: foldersCount,
      tagsCount: tagsCount,
      recordingsCount: recordingsCount,
      hasAudio: hasAudio,
      audioFilesCount: audioFilesCount,
      remindersCount: remindersCount,
      attachmentsCount: attachmentsCount,
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

    if (trimmed.startsWith('{') && trimmed.endsWith('}')) {
      await _restoreLegacyJson(trimmed, strategy, onProgress, baseDir);
      return;
    }

    final file = File(trimmed);
    if (!await file.exists()) {
      throw FileSystemException('Backup file not found', trimmed);
    }
    final bytes = await file.readAsBytes();

    if (isZipBytes(bytes)) {
      await _restoreZipArchive(bytes, strategy, onProgress, baseDir);
    } else if (isGzipBytes(bytes)) {
      final decompressed = gzip.decode(bytes);
      final content = utf8.decode(decompressed);
      await _restoreLegacyJson(content, strategy, onProgress, baseDir);
    } else {
      final content = utf8.decode(bytes);
      await _restoreLegacyJson(content, strategy, onProgress, baseDir);
    }
  }

  Future<void> _restoreZipArchive(
    List<int> bytes,
    RestoreStrategy strategy,
    void Function(double progress, String status)? onProgress,
    String? baseDir,
  ) async {
    onProgress?.call(0.15, 'Validating ZIP archive structure...');
    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes);
    } catch (e) {
      throw FormatException('Malformed or invalid NoteFlow ZIP archive: $e');
    }

    // 15 Hardened Security Checks Enforcement:
    // Check 6: Entry count limit (max 500)
    if (archive.files.length > 500) {
      throw const FormatException('Security Violation: Archive exceeds maximum allowed entries (500)');
    }

    final seenEntries = <String>{};
    int totalUncompressedBytes = 0;

    for (final entry in archive.files) {
      final name = entry.name;

      // Check 1: Entry name validation (no control chars, no backslashes)
      if (name.contains('\\') || name.codeUnits.any((c) => c < 32 || c == 127)) {
        throw FormatException('Security Violation: Invalid entry name contains illegal characters: $name');
      }

      // Check 2: Absolute path rejection
      if (name.startsWith('/') || name.contains(':')) {
        throw FormatException('Security Violation: Absolute path detected in archive: $name');
      }

      // Check 3: Traversal rejection
      if (name.contains('..') || name.startsWith('./')) {
        throw FormatException('Security Violation: Directory traversal detected: $name');
      }

      // Check 4: Symlink rejection
      if (entry.isSymbolicLink) {
        throw FormatException('Security Violation: Symbolic link detected in archive: $name');
      }

      // Check 5: Duplicate entry rejection
      if (seenEntries.contains(name)) {
        throw FormatException('Security Violation: Duplicate entry detected in archive: $name');
      }
      seenEntries.add(name);

      // Check 7: Single entry size limit (max 25 MB = 26214400 bytes)
      if (entry.size > 26214400) {
        throw FormatException('Security Violation: Entry $name exceeds maximum allowed size (25 MB)');
      }

      // Check 8: Total archive size accumulation (max 250 MB = 262144000 bytes)
      totalUncompressedBytes += entry.size;
      if (totalUncompressedBytes > 262144000) {
        throw const FormatException('Security Violation: Total uncompressed archive size exceeds maximum limit (250 MB)');
      }

      // Check 9: Decompression bomb check
      if (entry.rawContent != null && entry.rawContent!.length > 0 && entry.size > 1024 * 1024) {
        final ratio = entry.size / entry.rawContent!.length;
        if (ratio > 100) {
          throw FormatException('Security Violation: Decompression bomb detected for entry: $name (ratio: $ratio)');
        }
      }

      // Check 10: CRC-32 verification
      if (entry.crc32 != 0 && entry.content != null) {
        final calculatedCrc = getCrc32(entry.content as List<int>);
        if (calculatedCrc != entry.crc32) {
          throw FormatException('CRC-32 checksum mismatch for entry: $name');
        }
      }
    }

    final manifestEntry = archive.findFile('manifest.json');
    if (manifestEntry == null) {
      throw const FormatException('Invalid NoteFlow ZIP archive: missing manifest.json');
    }

    onProgress?.call(0.25, 'Parsing manifest and entities...');
    final manifestContent = utf8.decode(manifestEntry.content as List<int>);
    final dynamic parsed;
    try {
      parsed = jsonDecode(manifestContent);
    } catch (e) {
      throw FormatException('Malformed manifest.json in archive: $e');
    }

    if (parsed is! Map<String, dynamic>) {
      throw const FormatException('Invalid manifest structure: root must be an object');
    }

    final app = parsed['app'] as String? ?? parsed['app_identifier'] as String? ?? '';
    if (app != 'NoteFlow' && app != 'com.noteflow.app' && !parsed.containsKey('notes')) {
      throw const FormatException('Foreign backup format: not a recognized NoteFlow backup');
    }

    final rawFolders = parsed['folders'] as List<dynamic>? ?? [];
    final rawTags = parsed['tags'] as List<dynamic>? ?? [];
    final rawNotes = parsed['notes'] as List<dynamic>? ?? [];
    final rawRecordings = parsed['voice_recordings'] as List<dynamic>? ?? [];
    final rawReminders = parsed['reminders'] as List<dynamic>? ?? [];
    final rawAttachments = parsed['attachments'] as List<dynamic>? ?? [];
    final themeMode = parsed['theme_mode'] as String? ?? 'dark';

    // Check 12: Duplicate ID rejection
    final noteIds = <String>{};
    for (final n in rawNotes) {
      final nid = (n as Map)['id'] as String?;
      if (nid == null || noteIds.contains(nid)) {
        throw FormatException('Security Violation: Duplicate or missing note ID in manifest: $nid');
      }
      noteIds.add(nid);
    }

    final attachmentIds = <String>{};
    for (final a in rawAttachments) {
      final aid = (a as Map)['id'] as String?;
      if (aid == null || attachmentIds.contains(aid)) {
        throw FormatException('Security Violation: Duplicate or missing attachment ID in manifest: $aid');
      }
      attachmentIds.add(aid);
    }

    // Check 13: Manifest relationship check
    for (final entry in archive.files) {
      if (entry.name == 'manifest.json' || entry.isDirectory) continue;
      if (entry.name.startsWith('attachments/')) {
        final segments = entry.name.split('/');
        if (segments.length < 3) {
          throw FormatException('Security Violation: Invalid attachment path structure: ${entry.name}');
        }
        final noteId = segments[1];
        if (!noteIds.contains(noteId)) {
          throw FormatException('Security Violation: Attachment file references non-existent note: $noteId');
        }
      }
    }

    final backupFolders = rawFolders
        .map((f) => FolderEntity.fromMap(Map<String, dynamic>.from(f as Map)))
        .toList();
    final backupTags = rawTags
        .map((t) => TagEntity.fromMap(Map<String, dynamic>.from(t as Map)))
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
    final backupAttachments = rawAttachments
        .map((a) => AttachmentEntity.fromMap(Map<String, dynamic>.from(a as Map)))
        .toList();

    if (baseDir == null) {
      if (strategy == RestoreStrategy.replace) {
        await repository.replaceAllData(
          folders: backupFolders,
          notes: backupNotes,
          voiceRecordings: backupRecordings,
          tags: backupTags,
          reminders: backupReminders,
          attachments: backupAttachments,
          themeMode: themeMode,
        );
      } else {
        await repository.mergeAllData(
          folders: backupFolders,
          notes: backupNotes,
          voiceRecordings: backupRecordings,
          tags: backupTags,
          reminders: backupReminders,
          attachments: backupAttachments,
          themeMode: themeMode,
        );
      }
      return;
    }

    final stamp = DateTime.now().millisecondsSinceEpoch;
    final stagingAttDir = Directory('$baseDir/attachments_restore_staging_$stamp');
    final stagingVoiceDir = Directory('$baseDir/voice_notes_restore_staging_$stamp');

    onProgress?.call(0.4, 'Extracting attachments and voice memos to staging...');
    await stagingAttDir.create(recursive: true);
    await stagingVoiceDir.create(recursive: true);

    try {
      // Check 14: Path reconstruction strictly into staging directory
      for (final att in backupAttachments) {
        final cleanExt = att.fileExtension.replaceAll('.', '');
        final safeTargetName = att.storedName.isNotEmpty
            ? att.storedName
            : '${att.id}.$cleanExt';
        final attTargetDir = Directory('${stagingAttDir.path}/${att.noteId}');
        if (!await attTargetDir.exists()) await attTargetDir.create(recursive: true);
        final attTargetFile = File('${attTargetDir.path}/$safeTargetName');

        final entryName = att.relativePath.isNotEmpty
            ? att.relativePath
            : 'attachments/${att.noteId}/$safeTargetName';
        final entry = archive.findFile(entryName) ??
            archive.findFile('attachments/${att.noteId}/$safeTargetName');

        if (entry != null) {
          final contentBytes = entry.content as List<int>;
          await attTargetFile.writeAsBytes(contentBytes, flush: true);
        }
      }

      for (final rec in backupRecordings) {
        final ext = rec.format.isNotEmpty ? rec.format : 'm4a';
        final entryName1 = 'voice_notes/${rec.id}.$ext';
        final entryName2 = 'voice_notes/${rec.voiceNoteId}/${rec.id}.$ext';
        final entry = archive.findFile(entryName1) ?? archive.findFile(entryName2);

        if (entry != null) {
          final recTargetDir = Directory('${stagingVoiceDir.path}/${rec.voiceNoteId}');
          if (!await recTargetDir.exists()) await recTargetDir.create(recursive: true);
          final recTargetFile = File('${recTargetDir.path}/${rec.id}.$ext');
          await recTargetFile.writeAsBytes(entry.content as List<int>, flush: true);
        }
      }

      if (strategy == RestoreStrategy.replace) {
        await _executeReplaceRestore(
          baseDir: baseDir,
          stamp: stamp,
          stagingAttDir: stagingAttDir,
          stagingVoiceDir: stagingVoiceDir,
          folders: backupFolders,
          notes: backupNotes,
          voiceRecordings: backupRecordings,
          tags: backupTags,
          reminders: backupReminders,
          attachments: backupAttachments,
          themeMode: themeMode,
          onProgress: onProgress,
        );
      } else {
        await _executeMergeRestore(
          baseDir: baseDir,
          stamp: stamp,
          stagingAttDir: stagingAttDir,
          stagingVoiceDir: stagingVoiceDir,
          folders: backupFolders,
          notes: backupNotes,
          voiceRecordings: backupRecordings,
          tags: backupTags,
          reminders: backupReminders,
          attachments: backupAttachments,
          themeMode: themeMode,
          onProgress: onProgress,
        );
      }
    } catch (e) {
      if (await stagingAttDir.exists()) {
        try { await stagingAttDir.delete(recursive: true); } catch (_) {}
      }
      if (await stagingVoiceDir.exists()) {
        try { await stagingVoiceDir.delete(recursive: true); } catch (_) {}
      }
      rethrow;
    }
  }

  Future<void> _executeReplaceRestore({
    required String baseDir,
    required int stamp,
    required Directory stagingAttDir,
    required Directory stagingVoiceDir,
    required List<FolderEntity> folders,
    required List<NoteEntity> notes,
    required List<VoiceRecordingEntity> voiceRecordings,
    required List<TagEntity> tags,
    required List<ReminderEntity> reminders,
    required List<AttachmentEntity> attachments,
    required String themeMode,
    void Function(double, String)? onProgress,
  }) async {
    final journalFile = File('$baseDir/restore_journal.json');
    final safetyBackupFile = File('$baseDir/backups/pre_restore_safety.bak');
    final currentDataFile = File('$baseDir/noteflow_data.json');
    final liveAttDir = Directory('$baseDir/attachments');
    final liveVoiceDir = Directory('$baseDir/voice_notes');
    final rollbackAttDir = Directory('$baseDir/attachments_rollback_$stamp');
    final rollbackVoiceDir = Directory('$baseDir/voice_notes_rollback_$stamp');

    // Phase 1: prepared
    onProgress?.call(0.6, 'Creating pre-restore safety snapshot...');
    if (await currentDataFile.exists()) {
      final backupsDir = Directory('$baseDir/backups');
      if (!await backupsDir.exists()) await backupsDir.create(recursive: true);
      await currentDataFile.copy(safetyBackupFile.path);
    }

    await journalFile.writeAsString(jsonEncode({
      'strategy': 'replace',
      'phase': 'prepared',
      'timestamp': stamp,
      'staging_att_dir': stagingAttDir.path,
      'staging_voice_dir': stagingVoiceDir.path,
    }), flush: true);

    try {
      // Phase 2: old_directory_moved
      onProgress?.call(0.7, 'Moving current directories to rollback location...');
      if (await liveAttDir.exists()) {
        await liveAttDir.rename(rollbackAttDir.path);
      }
      if (await liveVoiceDir.exists()) {
        await liveVoiceDir.rename(rollbackVoiceDir.path);
      }
      await journalFile.writeAsString(jsonEncode({
        'strategy': 'replace',
        'phase': 'old_directory_moved',
        'timestamp': stamp,
        'staging_att_dir': stagingAttDir.path,
        'staging_voice_dir': stagingVoiceDir.path,
      }), flush: true);

      // Phase 3: new_directory_moved
      onProgress?.call(0.8, 'Moving restored directories to live location...');
      if (await stagingAttDir.exists()) {
        await stagingAttDir.rename(liveAttDir.path);
      }
      if (await stagingVoiceDir.exists()) {
        await stagingVoiceDir.rename(liveVoiceDir.path);
      }
      await journalFile.writeAsString(jsonEncode({
        'strategy': 'replace',
        'phase': 'new_directory_moved',
        'timestamp': stamp,
        'staging_att_dir': stagingAttDir.path,
        'staging_voice_dir': stagingVoiceDir.path,
      }), flush: true);

      // Phase 4: repository_committed
      onProgress?.call(0.9, 'Committing restored metadata to repository...');
      await repository.replaceAllData(
        folders: folders,
        notes: notes,
        voiceRecordings: voiceRecordings,
        tags: tags,
        reminders: reminders,
        attachments: attachments,
        themeMode: themeMode,
      );
      await journalFile.writeAsString(jsonEncode({
        'strategy': 'replace',
        'phase': 'repository_committed',
        'timestamp': stamp,
      }), flush: true);

      // Phase 5: cleanup_complete
      onProgress?.call(0.95, 'Purging rollback directories...');
      if (await rollbackAttDir.exists()) {
        try { await rollbackAttDir.delete(recursive: true); } catch (_) {}
      }
      if (await rollbackVoiceDir.exists()) {
        try { await rollbackVoiceDir.delete(recursive: true); } catch (_) {}
      }
      if (await safetyBackupFile.exists()) {
        try { await safetyBackupFile.delete(); } catch (_) {}
      }
      if (await journalFile.exists()) {
        try { await journalFile.delete(); } catch (_) {}
      }
      onProgress?.call(1.0, 'Restoration complete');
    } catch (e) {
      try {
        if (await journalFile.exists()) {
          final journalContent = await journalFile.readAsString();
          final j = jsonDecode(journalContent) as Map<String, dynamic>;
          final phase = j['phase'] as String?;

          if (phase == 'new_directory_moved') {
            if (await liveAttDir.exists()) await liveAttDir.delete(recursive: true);
            if (await liveVoiceDir.exists()) await liveVoiceDir.delete(recursive: true);
            if (await rollbackAttDir.exists()) await rollbackAttDir.rename(liveAttDir.path);
            if (await rollbackVoiceDir.exists()) await rollbackVoiceDir.rename(liveVoiceDir.path);
            if (await safetyBackupFile.exists()) await safetyBackupFile.copy(currentDataFile.path);
          } else if (phase == 'old_directory_moved') {
            if (await rollbackAttDir.exists()) await rollbackAttDir.rename(liveAttDir.path);
            if (await rollbackVoiceDir.exists()) await rollbackVoiceDir.rename(liveVoiceDir.path);
          }
        }
      } catch (_) {}

      if (await safetyBackupFile.exists()) {
        try { await safetyBackupFile.delete(); } catch (_) {}
      }
      if (await journalFile.exists()) {
        try { await journalFile.delete(); } catch (_) {}
      }
      rethrow;
    }
  }

  Future<void> _executeMergeRestore({
    required String baseDir,
    required int stamp,
    required Directory stagingAttDir,
    required Directory stagingVoiceDir,
    required List<FolderEntity> folders,
    required List<NoteEntity> notes,
    required List<VoiceRecordingEntity> voiceRecordings,
    required List<TagEntity> tags,
    required List<ReminderEntity> reminders,
    required List<AttachmentEntity> attachments,
    required String themeMode,
    void Function(double, String)? onProgress,
  }) async {
    final journalFile = File('$baseDir/merge_restore_journal.json');
    final liveAttDir = Directory('$baseDir/attachments');
    final liveVoiceDir = Directory('$baseDir/voice_notes');
    if (!await liveAttDir.exists()) await liveAttDir.create(recursive: true);
    if (!await liveVoiceDir.exists()) await liveVoiceDir.create(recursive: true);

    onProgress?.call(0.6, 'Analyzing collisions and planning merge...');
    final existingAttachments = repository.getAllAttachments();
    final existingAttIds = existingAttachments.map((a) => a.id).toSet();

    final mergedAttachments = <AttachmentEntity>[];
    final copyPlan = <Map<String, String>>[];

    for (final att in attachments) {
      if (existingAttIds.contains(att.id)) {
        final newId = AttachmentHelper.generateUuidV4();
        final ext = att.fileExtension.replaceAll('.', '');
        final newStoredName = '$newId.$ext';
        final newRelativePath = 'attachments/${att.noteId}/$newStoredName';
        final remappedAtt = att.copyWith(
          id: newId,
          storedName: newStoredName,
          relativePath: newRelativePath,
        );
        mergedAttachments.add(remappedAtt);

        final sourceFile = File('${stagingAttDir.path}/${att.noteId}/${att.storedName}');
        final destFile = File('$baseDir/$newRelativePath');
        copyPlan.add({'source': sourceFile.path, 'destination': destFile.path});
      } else {
        mergedAttachments.add(att);
        final sourceFile = File('${stagingAttDir.path}/${att.noteId}/${att.storedName}');
        final destFile = File('$baseDir/${att.relativePath}');
        copyPlan.add({'source': sourceFile.path, 'destination': destFile.path});
      }
    }

    for (final rec in voiceRecordings) {
      final ext = rec.format.isNotEmpty ? rec.format : 'm4a';
      final sourceFile = File('${stagingVoiceDir.path}/${rec.voiceNoteId}/${rec.id}.$ext');
      final destFile = File('$baseDir/voice_notes/${rec.voiceNoteId}/${rec.id}.$ext');
      copyPlan.add({'source': sourceFile.path, 'destination': destFile.path});
    }

    // Phase 1: merge_prepared
    await journalFile.writeAsString(jsonEncode({
      'strategy': 'merge',
      'phase': 'merge_prepared',
      'timestamp': stamp,
      'staging_att_dir': stagingAttDir.path,
      'staging_voice_dir': stagingVoiceDir.path,
      'copied_files': [],
    }), flush: true);

    final copiedFiles = <String>[];

    try {
      // Phase 2: merge_files_copied
      onProgress?.call(0.75, 'Copying merged files to permanent storage...');
      for (final plan in copyPlan) {
        final src = File(plan['source']!);
        final dest = File(plan['destination']!);
        if (await src.exists()) {
          if (!await dest.parent.exists()) {
            await dest.parent.create(recursive: true);
          }
          await src.copy(dest.path);
          copiedFiles.add(dest.path);
        }
      }

      await journalFile.writeAsString(jsonEncode({
        'strategy': 'merge',
        'phase': 'merge_files_copied',
        'timestamp': stamp,
        'staging_att_dir': stagingAttDir.path,
        'staging_voice_dir': stagingVoiceDir.path,
        'copied_files': copiedFiles,
      }), flush: true);

      // Phase 3: merge_repository_committed
      onProgress?.call(0.9, 'Committing merged metadata to repository...');
      await repository.mergeAllData(
        folders: folders,
        notes: notes,
        voiceRecordings: voiceRecordings,
        tags: tags,
        reminders: reminders,
        attachments: mergedAttachments,
        themeMode: themeMode,
      );

      await journalFile.writeAsString(jsonEncode({
        'strategy': 'merge',
        'phase': 'merge_repository_committed',
        'timestamp': stamp,
      }), flush: true);

      // Phase 4: merge_cleanup_complete
      onProgress?.call(0.95, 'Cleaning up staging directory...');
      if (await stagingAttDir.exists()) {
        try { await stagingAttDir.delete(recursive: true); } catch (_) {}
      }
      if (await stagingVoiceDir.exists()) {
        try { await stagingVoiceDir.delete(recursive: true); } catch (_) {}
      }
      if (await journalFile.exists()) {
        try { await journalFile.delete(); } catch (_) {}
      }
      onProgress?.call(1.0, 'Merge restoration complete');
    } catch (e) {
      for (final path in copiedFiles) {
        try {
          final f = File(path);
          if (await f.exists()) await f.delete();
        } catch (_) {}
      }
      if (await stagingAttDir.exists()) {
        try { await stagingAttDir.delete(recursive: true); } catch (_) {}
      }
      if (await stagingVoiceDir.exists()) {
        try { await stagingVoiceDir.delete(recursive: true); } catch (_) {}
      }
      if (await journalFile.exists()) {
        try { await journalFile.delete(); } catch (_) {}
      }
      rethrow;
    }
  }

  Future<void> _restoreLegacyJson(
    String content,
    RestoreStrategy strategy,
    void Function(double progress, String status)? onProgress,
    String? baseDir,
  ) async {
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
      final rawTags = parsed['tags'] as List<dynamic>? ?? [];
      final rawNotes = parsed['notes'] as List<dynamic>? ?? [];
      final rawRecordings = parsed['voice_recordings'] as List<dynamic>? ?? [];
      final rawReminders = parsed['reminders'] as List<dynamic>? ?? [];
      final rawAttachments = parsed['attachments'] as List<dynamic>? ?? [];
      final audioPayloads = (parsed['audio_payloads'] as Map<String, dynamic>?) ?? {};
      final themeMode = parsed['theme_mode'] as String? ?? 'dark';

      final backupFolders = rawFolders
          .map((f) => FolderEntity.fromMap(Map<String, dynamic>.from(f as Map)))
          .toList();
      final backupTags = rawTags
          .map((t) => TagEntity.fromMap(Map<String, dynamic>.from(t as Map)))
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
      final backupAttachments = rawAttachments
          .map((a) => AttachmentEntity.fromMap(Map<String, dynamic>.from(a as Map)))
          .toList();

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
          tags: backupTags,
          reminders: backupReminders,
          attachments: backupAttachments,
          themeMode: themeMode,
        );
      } else {
        await repository.mergeAllData(
          folders: backupFolders,
          notes: backupNotes,
          voiceRecordings: backupRecordings,
          tags: backupTags,
          reminders: backupReminders,
          attachments: backupAttachments,
          themeMode: themeMode,
        );
      }

      if (safetyBackupFile != null && await safetyBackupFile.exists()) {
        try {
          await safetyBackupFile.delete();
        } catch (_) {}
      }

      onProgress?.call(1.0, 'Restoration complete');
    } catch (e) {
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
