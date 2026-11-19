import 'dart:io';
import '../../shared/models/note_entity.dart';
import '../../shared/models/folder_entity.dart';
import '../../shared/models/voice_recording_entity.dart';
import '../../shared/models/backup_models.dart';

export '../../shared/models/backup_models.dart';

abstract class NoteRepository {
  /// Stream of all active or archived notes
  Stream<List<NoteEntity>> watchNotes({bool includeArchived = false, String? folderId});

  /// Get note by ID
  Future<NoteEntity?> getNoteById(String id);

  /// Upsert a note (insert or update)
  Future<void> saveNote(NoteEntity note);

  /// Delete note permanently
  Future<void> deleteNote(String id);

  /// Toggle pin status
  Future<void> togglePin(String id);

  /// Toggle archive status
  Future<void> toggleArchive(String id);

  /// Stream of folders
  Stream<List<FolderEntity>> watchFolders();

  /// Create or update folder
  Future<void> saveFolder(FolderEntity folder);

  /// Delete folder
  Future<void> deleteFolder(String id);

  /// Stream of voice recordings for a specific voice note
  Stream<List<VoiceRecordingEntity>> watchVoiceRecordings(String voiceNoteId);

  /// Get list of voice recordings for a specific voice note
  Future<List<VoiceRecordingEntity>> getVoiceRecordings(String voiceNoteId);

  /// Create or update a voice recording
  Future<void> saveVoiceRecording(VoiceRecordingEntity recording);

  /// Delete a single voice recording and its local audio file
  Future<void> deleteVoiceRecording(String recordingId);

  /// Reorder voice recordings by updating their sort orders
  Future<void> reorderVoiceRecordings(String voiceNoteId, List<String> orderedIds);

  /// Toggle the completion state of a voice recording (Checklist mode)
  Future<void> toggleVoiceRecordingCompletion(String recordingId);

  /// Export complete backup payload
  Future<Map<String, dynamic>> exportBackupPayload({bool includeAudio = true});

  /// Create a backup file in the local backups directory
  Future<File> createBackupFile({bool includeAudio = true, String? customName});

  /// List local backup files found in the backups directory
  Future<List<File>> listLocalBackups();

  /// Inspect a backup file or JSON string to get preview information
  Future<BackupPreview> inspectBackup(String jsonStringOrFilePath);

  /// Restore notes, folders, and recordings from backup data
  Future<void> restoreBackup(
    String jsonStringOrFilePath, {
    required RestoreStrategy strategy,
  });

  /// Delete a local backup file
  Future<void> deleteBackupFile(String filePath);
}

