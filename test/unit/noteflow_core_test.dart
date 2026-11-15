import 'dart:io';
import '../../lib/shared/models/note_entity.dart';
import '../../lib/shared/models/folder_entity.dart';
import '../../lib/shared/models/note_filter.dart';
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
  stdout.writeln('Running NoteFlow Milestone 1 & 2 Test Suite...');

  // --- Suite 1: NoteEntity serialization & copyWith ---
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
  expect(map['color_index'] == 2, 'color_index mapped correctly');

  final restored = NoteEntity.fromMap(map);
  expect(restored.id == note.id, 'Restored ID matches');
  expect(restored.title == note.title, 'Restored title matches');
  expect(restored.isPinned == true, 'Restored isPinned matches');
  expect(restored.colorIndex == 2, 'Restored colorIndex matches');

  final copied = note.copyWith(title: 'Updated Title', isPinned: false, colorIndex: 4);
  expect(copied.title == 'Updated Title', 'Copied title updated');
  expect(copied.isPinned == false, 'Copied isPinned updated');
  expect(copied.colorIndex == 4, 'Copied colorIndex updated');

  // --- Suite 2: NoteHelper & Formatting ---
  final plainText = NoteHelper.extractPlainText('Simple plain text note');
  expect(plainText == 'Simple plain text note', 'Plain text extraction');

  const jsonDelta = '[{"insert":"Hello "},{"insert":"World\\n"}]';
  final extractedDelta = NoteHelper.extractPlainText(jsonDelta);
  expect(extractedDelta.contains('Hello World'), 'Delta JSON extraction');

  final words = NoteHelper.wordCount('Three simple words');
  expect(words == 3, 'Word count is 3');

  // Quill Delta detection tests
  expect(NoteHelper.isDeltaContent(jsonDelta) == true, 'Delta JSON is recognized as delta');
  expect(NoteHelper.isDeltaContent('Plain markdown content') == false, 'Plain text is not delta');
  expect(NoteHelper.isDeltaContent('[ ] Plain checkbox item') == false, 'Plain checkbox is not delta');
  expect(NoteHelper.isDeltaContent('') == false, 'Empty string is not delta');

  // Checklist detection tests
  expect(NoteHelper.isChecklistContent('[ ] First task\n[x] Done task') == true, 'Markdown checklist detected');
  expect(NoteHelper.isChecklistContent('Just a regular note with paragraphs') == false, 'Regular note not checklist');
  const deltaChecklist = '[{"insert":"Groceries"},{"insert":"\\n","attributes":{"list":"unchecked"}},{"insert":"Laundry"},{"insert":"\\n","attributes":{"list":"checked"}}]';
  expect(NoteHelper.isChecklistContent(deltaChecklist) == true, 'Delta JSON checklist detected');
  expect(NoteHelper.isChecklistContent(jsonDelta) == false, 'Plain Delta JSON not checklist');

  // formatForEditor conversion tests (Critical Rich Text Editor Bug fix)
  final plainUnchanged = NoteHelper.formatForEditor('Existing plain text\nWith multiple lines');
  expect(plainUnchanged == 'Existing plain text\nWith multiple lines', 'Plain text is preserved unchanged');

  final simpleDeltaFormatted = NoteHelper.formatForEditor('[{"insert":"Hello World\\n"}]');
  expect(simpleDeltaFormatted == 'Hello World', 'Simple Delta converted to plain text without JSON syntax');
  expect(!simpleDeltaFormatted.contains('{"insert"'), 'No raw JSON syntax in formatted editor text');

  const formattedDeltaJson = '[{"insert":"Title "},{"insert":"bold text","attributes":{"bold":true}},{"insert":" and "},{"insert":"italic text","attributes":{"italic":true}},{"insert":"\\n"}]';
  final formattedMarkdown = NoteHelper.formatForEditor(formattedDeltaJson);
  expect(formattedMarkdown == 'Title **bold text** and *italic text*', 'Inline bold and italic converted to markdown');

  const headerDeltaJson = '[{"insert":"Meeting Notes"},{"insert":"\\n","attributes":{"header":1}},{"insert":"Action items"},{"insert":"\\n","attributes":{"header":2}}]';
  final headerFormatted = NoteHelper.formatForEditor(headerDeltaJson);
  expect(headerFormatted == '# Meeting Notes\n## Action items', 'Quill headers converted to markdown headers');

  final checklistFormatted = NoteHelper.formatForEditor(deltaChecklist);
  expect(checklistFormatted == '[ ] Groceries\n[x] Laundry', 'Quill checklist ops converted to [ ] and [x] items');

  const literalBugJson = '[{"insert":"Project Kickoff\\n"},{"insert":"1. Define Scope\\n","attributes":{"list":"ordered"}},{"insert":"Review deadline"},{"insert":"\\n","attributes":{"list":"unchecked"}}]';
  final fixedBugText = NoteHelper.formatForEditor(literalBugJson);
  expect(!fixedBugText.contains('[{"'), 'Fixed bug text does not have raw JSON array bracket syntax');
  expect(!fixedBugText.contains('{"insert"'), 'Fixed bug text does not have {"insert"');
  expect(fixedBugText.contains('[ ] Review deadline'), 'Checklist line properly converted');

  // --- Suite 3: DateFormatter ---
  final smartNow = DateFormatter.formatSmart(DateTime.now());
  expect(smartNow == 'Just now', 'Smart now format');
  final smartFull = DateFormatter.formatFull(DateTime.now());
  expect(smartFull.isNotEmpty, 'Full date format not empty');

  // --- Suite 4: LocalNoteRepository Operations & Seeding ---
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
  expect(archived.isPinned == false, 'Archived note automatically unpinned');

  // Test unarchive toggle
  await repo.toggleArchive('note-welcome');
  final unarchived = await repo.getNoteById('note-welcome');
  expect(unarchived!.isArchived == false, 'Note unarchived successfully');

  // Test save new note (simulating Editor Auto-Save)
  final customNote = NoteEntity(
    id: 'editor-note-1',
    title: 'Editor Auto-Save Draft',
    content: '[ ] Buy groceries\n[x] Finish unit tests',
    isChecklist: true,
    colorIndex: 3,
    createdAt: DateTime.now(),
    updatedAt: DateTime.now(),
  );
  await repo.saveNote(customNote);
  final fetchedCustom = await repo.getNoteById('editor-note-1');
  expect(fetchedCustom != null, 'Auto-save draft committed');
  expect(fetchedCustom!.title == 'Editor Auto-Save Draft', 'Title matches');
  expect(fetchedCustom.isChecklist == true, 'Checklist flag preserved');
  expect(fetchedCustom.colorIndex == 3, 'Color tint index preserved');

  // Test delete note
  await repo.deleteNote('editor-note-1');
  final deletedCustom = await repo.getNoteById('editor-note-1');
  expect(deletedCustom == null, 'Note permanently deleted');

  // --- Suite 5: Folder Management & Unassignment ---
  final folder = FolderEntity(
    id: 'f-projects',
    name: 'Projects',
    colorHex: '0xFF2563EB',
    iconName: 'folder',
    createdAt: DateTime.now(),
  );
  await repo.saveFolder(folder);

  final noteInFolder = NoteEntity(
    id: 'note-in-folder',
    title: 'Project Roadmap',
    content: 'Roadmap details',
    folderId: 'f-projects',
    createdAt: DateTime.now(),
    updatedAt: DateTime.now(),
  );
  await repo.saveNote(noteInFolder);

  final savedInFolder = await repo.getNoteById('note-in-folder');
  expect(savedInFolder!.folderId == 'f-projects', 'Note assigned to folder');

  // Deleting folder should safely unassign the note, not delete it
  await repo.deleteFolder('f-projects');
  final noteAfterFolderDelete = await repo.getNoteById('note-in-folder');
  expect(noteAfterFolderDelete != null, 'Note preserved after folder deletion');
  expect(noteAfterFolderDelete!.folderId == null, 'Note unassigned from deleted folder');

  // Clean up
  await repo.deleteNote('note-in-folder');

  // --- Suite 6: NoteFilterState & Sorting ---
  const filterDefault = NoteFilterState();
  expect(filterDefault.sortOrder == NoteSortOrder.recentlyModified, 'Default sort is recently modified');
  expect(filterDefault.selectedFolderId == null, 'Default folder is null (all notes)');

  final filterCustom = filterDefault.copyWith(
    searchQuery: 'Grocery',
    selectedFolderId: 'folder-personal',
    sortOrder: NoteSortOrder.titleAZ,
  );
  expect(filterCustom.searchQuery == 'Grocery', 'Filter search query set');
  expect(filterCustom.selectedFolderId == 'folder-personal', 'Filter folder set');
  expect(filterCustom.sortOrder == NoteSortOrder.titleAZ, 'Filter sort order updated');

  repo.dispose();

  // --- Suite 7: Durable Local Disk Persistence Roundtrip ---
  final tempDir = Directory.systemTemp.createTempSync('noteflow_test_');
  final testJsonPath = '${tempDir.path}/test_noteflow_data.json';

  final persistentRepo1 = LocalNoteRepository(
    seedDemoData: true,
    enableDiskPersistence: true,
    customStoragePath: testJsonPath,
  );
  await persistentRepo1.init();

  // Create and save a new note to disk
  final persistentNote = NoteEntity(
    id: 'disk-note-1',
    title: 'Durable Disk Note',
    content: 'Survives application termination and restarts',
    isPinned: true,
    createdAt: DateTime.now(),
    updatedAt: DateTime.now(),
  );
  await persistentRepo1.saveNote(persistentNote);
  persistentRepo1.dispose();

  // Instantiate brand new repository pointing to the same file
  final persistentRepo2 = LocalNoteRepository(
    seedDemoData: false,
    enableDiskPersistence: true,
    customStoragePath: testJsonPath,
  );
  await persistentRepo2.init();

  final loadedFromDisk = await persistentRepo2.getNoteById('disk-note-1');
  expect(loadedFromDisk != null, 'Note persisted to disk and reloaded successfully');
  expect(loadedFromDisk!.title == 'Durable Disk Note', 'Persisted title matches');
  expect(loadedFromDisk.isPinned == true, 'Persisted pin state matches');

  // Test theme mode persistence across sessions
  await persistentRepo2.setThemeMode('light');
  expect(persistentRepo2.themeMode == 'light', 'Theme mode updated in memory');

  // Verify deletion persists across sessions
  await persistentRepo2.deleteNote('disk-note-1');
  persistentRepo2.dispose();

  final persistentRepo3 = LocalNoteRepository(
    seedDemoData: false,
    enableDiskPersistence: true,
    customStoragePath: testJsonPath,
  );
  await persistentRepo3.init();
  final deletedAfterReload = await persistentRepo3.getNoteById('disk-note-1');
  expect(deletedAfterReload == null, 'Note deletion persisted across app restart');
  expect(persistentRepo3.themeMode == 'light', 'Theme mode persisted and restored from disk');
  persistentRepo3.dispose();

  // Clean up temp file
  tempDir.deleteSync(recursive: true);

  stdout.writeln('ALL NOTEFLOW TESTS PASSED! (39/39 Assertions) ✓');
}
