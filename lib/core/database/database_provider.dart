import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'note_repository.dart';
import 'local_note_repository.dart';
import '../../shared/models/note_entity.dart';
import '../../shared/models/folder_entity.dart';
import '../../shared/models/tag_entity.dart';
import '../../shared/models/voice_recording_entity.dart';
import '../../features/reminders/services/reminder_native_bridge.dart';

/// Provider for the singleton NoteRepository
final noteRepositoryProvider = Provider<NoteRepository>((ref) {
  final repo = LocalNoteRepository(
    seedDemoData: true,
    reminderScheduler: const NativeReminderScheduler(),
  );
  ref.onDispose(() {
    (repo as dynamic).dispose?.call();
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

/// Reactive stream of favorite notes
final favoriteNotesStreamProvider = Provider<AsyncValue<List<NoteEntity>>>((ref) {
  final activeNotesAsync = ref.watch(activeNotesStreamProvider);
  return activeNotesAsync.whenData((notes) => notes.where((n) => n.isFavorite).toList());
});

/// Reactive stream of all folders
final foldersStreamProvider = StreamProvider<List<FolderEntity>>((ref) {
  final repo = ref.watch(noteRepositoryProvider);
  return repo.watchFolders();
});

/// Reactive stream of all tags
final tagsStreamProvider = StreamProvider<List<TagEntity>>((ref) {
  final repo = ref.watch(noteRepositoryProvider);
  return repo.watchTags();
});

/// Reactive stream of voice recordings for a specific voice note
final voiceRecordingsStreamProvider = StreamProvider.family<List<VoiceRecordingEntity>, String>((ref, voiceNoteId) {
  final repo = ref.watch(noteRepositoryProvider);
  return repo.watchVoiceRecordings(voiceNoteId);
});
