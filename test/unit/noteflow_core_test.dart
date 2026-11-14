import 'dart:io';
import '../../lib/shared/models/note_entity.dart';
import '../../lib/shared/models/folder_entity.dart';
import '../../lib/core/utils/note_helper.dart';
import '../../lib/core/utils/date_formatter.dart';
import '../../lib/core/database/local_note_repository.dart';

void expect(bool condition, String message) {
  if (!condition) {
    stderr.writeln('FAILED: $message');
    exit(1);
  }
}

Future<void> main() async {
  stdout.writeln('Running NoteFlow Unit Tests...');

  // Test 1: NoteEntity serialization & copyWith
  final now = DateTime.now();
  final note = NoteEntity(
    id: 'test-1',
    title: 'Test Note',
    content: 'Hello World',
    folderId: 'f-1',
    isPinned: true,
    isArchived: false,
    isChecklist: false,
    colorIndex: 2,
    createdAt: now,
    updatedAt: now,
  );

  final map = note.toMap();
  expect(map['id'] == 'test-1', 'ID matches');
  expect(map['title'] == 'Test Note', 'Title matches');
  expect(map['is_pinned'] == 1, 'is_pinned mapped to 1');

  final restored = NoteEntity.fromMap(map);
  expect(restored.id == note.id, 'Restored ID matches');
  expect(restored.title == note.title, 'Restored title matches');
  expect(restored.isPinned == true, 'Restored isPinned matches');

  final copied = note.copyWith(title: 'Updated Title', isPinned: false);
  expect(copied.title == 'Updated Title', 'Copied title updated');
  expect(copied.isPinned == false, 'Copied isPinned updated');
  expect(copied.id == 'test-1', 'Copied ID unchanged');

  // Test 2: NoteHelper
  final plainText = NoteHelper.extractPlainText('Simple plain text note');
  expect(plainText == 'Simple plain text note', 'Plain text extraction');

  final jsonDelta = '[{"insert":"Hello "},{"insert":"World\\n"}]';
  final extractedDelta = NoteHelper.extractPlainText(jsonDelta);
  expect(extractedDelta.contains('Hello World'), 'Delta JSON extraction');

  final words = NoteHelper.wordCount('Three simple words');
  expect(words == 3, 'Word count is 3');

  // Test 3: DateFormatter
  final smartNow = DateFormatter.formatSmart(DateTime.now());
  expect(smartNow == 'Just now', 'Smart now format');

  // Test 4: LocalNoteRepository CRUD & Reactive Streams
  final repo = LocalNoteRepository(seedDemoData: true);

  final initialNote = await repo.getNoteById('note-welcome');
  expect(initialNote != null, 'Welcome note seeded');
  expect(initialNote!.isPinned == true, 'Welcome note is pinned');

  // Test pin toggle
  await repo.togglePin('note-welcome');
  final unpinned = await repo.getNoteById('note-welcome');
  expect(unpinned!.isPinned == false, 'Note unpinned successfully');

  // Test archive toggle
  await repo.toggleArchive('note-welcome');
  final archived = await repo.getNoteById('note-welcome');
  expect(archived!.isArchived == true, 'Note archived successfully');

  // Test save new note
  final customNote = NoteEntity(
    id: 'custom-99',
    title: 'Custom Note',
    content: 'Content 99',
    createdAt: DateTime.now(),
    updatedAt: DateTime.now(),
  );
  await repo.saveNote(customNote);
  final fetchedCustom = await repo.getNoteById('custom-99');
  expect(fetchedCustom != null, 'Custom note saved');
  expect(fetchedCustom!.title == 'Custom Note', 'Custom note title matches');

  // Test delete note
  await repo.deleteNote('custom-99');
  final deletedCustom = await repo.getNoteById('custom-99');
  expect(deletedCustom == null, 'Custom note deleted');

  // Test folder management
  final folder = FolderEntity(
    id: 'f-test',
    name: 'Research',
    colorHex: '0xFF10B981',
    iconName: 'book',
    createdAt: DateTime.now(),
  );
  await repo.saveFolder(folder);
  await repo.deleteFolder('f-test');

  repo.dispose();

  stdout.writeln('ALL NOTEFLOW UNIT TESTS PASSED SUCCESSFULLY! ✓');
}
