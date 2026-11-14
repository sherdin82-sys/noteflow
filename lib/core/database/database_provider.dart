import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'note_repository.dart';
import 'local_note_repository.dart';
import '../../shared/models/note_entity.dart';
import '../../shared/models/folder_entity.dart';

/// Provider for the singleton NoteRepository
final noteRepositoryProvider = Provider<NoteRepository>((ref) {
  final repo = LocalNoteRepository(seedDemoData: true);
  ref.onDispose(() {
    if (repo is LocalNoteRepository) {
      repo.dispose();
    }
  });
  return repo;
});

/// Reactive stream of all active notes
final activeNotesStreamProvider = StreamProvider<List<NoteEntity>>((ref) {
  final repo = ref.watch(noteRepositoryProvider);
  return repo.watchNotes(includeArchived: false);
});

/// Reactive stream of archived notes
final archivedNotesStreamProvider = StreamProvider<List<NoteEntity>>((ref) {
  final repo = ref.watch(noteRepositoryProvider);
  return repo.watchNotes(includeArchived: true);
});

/// Reactive stream of all folders
final foldersStreamProvider = StreamProvider<List<FolderEntity>>((ref) {
  final repo = ref.watch(noteRepositoryProvider);
  return repo.watchFolders();
});
