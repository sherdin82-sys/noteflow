import '../../shared/models/note_entity.dart';
import '../../shared/models/folder_entity.dart';

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
}
