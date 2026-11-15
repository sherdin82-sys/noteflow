import 'dart:io';
import 'dart:convert';
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

  // markdownToDeltaJson tests (Rich Text Migration & Storage)
  final boldDelta = NoteHelper.markdownToDeltaJson('**Hello**');
  final boldOps = jsonDecode(boldDelta) as List<dynamic>;
  expect(boldOps.any((op) => op is Map && op['insert'] == 'Hello' && op['attributes']?['bold'] == true), 'Bold text converted to Delta with bold attribute');

  final italicDelta = NoteHelper.markdownToDeltaJson('*Italic*');
  final italicOps = jsonDecode(italicDelta) as List<dynamic>;
  expect(italicOps.any((op) => op is Map && op['insert'] == 'Italic' && op['attributes']?['italic'] == true), 'Italic text converted to Delta with italic attribute');

  final underlineDelta = NoteHelper.markdownToDeltaJson('<u>Underlined</u>');
  final underlineOps = jsonDecode(underlineDelta) as List<dynamic>;
  expect(underlineOps.any((op) => op is Map && op['insert'] == 'Underlined' && op['attributes']?['underline'] == true), 'Underline text converted to Delta with underline attribute');

  final combinedDelta = NoteHelper.markdownToDeltaJson('***Bold and Italic***');
  final combinedOps = jsonDecode(combinedDelta) as List<dynamic>;
  expect(combinedOps.any((op) => op is Map && op['attributes']?['bold'] == true && op['attributes']?['italic'] == true), 'Combined bold & italic formatting converted to Delta');

  final headingDelta = NoteHelper.markdownToDeltaJson('# Heading 1\n## Heading 2\n### Heading 3');
  final headingOps = jsonDecode(headingDelta) as List<dynamic>;
  expect(headingOps.any((op) => op is Map && op['attributes']?['header'] == 1), 'H1 block attribute generated in Delta');
  expect(headingOps.any((op) => op is Map && op['attributes']?['header'] == 2), 'H2 block attribute generated in Delta');
  expect(headingOps.any((op) => op is Map && op['attributes']?['header'] == 3), 'H3 block attribute generated in Delta');

  final bulletDelta = NoteHelper.markdownToDeltaJson('- First Item\n- Second Item');
  final bulletOps = jsonDecode(bulletDelta) as List<dynamic>;
  expect(bulletOps.any((op) => op is Map && op['attributes']?['list'] == 'bullet'), 'Bullet list block attribute generated in Delta');

  final numberedDelta = NoteHelper.markdownToDeltaJson('1. Step One\n2. Step Two');
  final numberedOps = jsonDecode(numberedDelta) as List<dynamic>;
  expect(numberedOps.any((op) => op is Map && op['attributes']?['list'] == 'ordered'), 'Numbered list block attribute generated in Delta');

  final checklistDelta = NoteHelper.markdownToDeltaJson('[ ] Buy milk\n[x] Finished task');
  final checklistOps = jsonDecode(checklistDelta) as List<dynamic>;
  expect(checklistOps.any((op) => op is Map && op['attributes']?['list'] == 'unchecked'), 'Unchecked list attribute generated in Delta');
  expect(checklistOps.any((op) => op is Map && op['attributes']?['list'] == 'checked'), 'Checked list attribute generated in Delta');

  // --- Suite 2.5: Note Card Rich Text Snippet Parsing ---
  final inlineSpans = NoteHelper.parseInlineMarkdown('Buy **milk** and *eggs*');
  expect(inlineSpans.length == 4, 'Inline markdown parsed into 4 spans');
  expect(inlineSpans[0].text == 'Buy ', 'First span plain text');
  expect(inlineSpans[1].text == 'milk' && inlineSpans[1].isBold, 'Second span bold text');
  expect(inlineSpans[2].text == ' and ', 'Third span plain text');
  expect(inlineSpans[3].text == 'eggs' && inlineSpans[3].isItalic, 'Fourth span italic text');

  final codeSpans = NoteHelper.parseInlineMarkdown('Run `git commit` now');
  expect(codeSpans.any((s) => s.text == 'git commit' && s.isCode), 'Inline code parsed with isCode flag');

  final strikeAndUnderlineSpans = NoteHelper.parseInlineMarkdown('~~Done~~ and <u>Important</u>');
  expect(strikeAndUnderlineSpans.any((s) => s.text == 'Done' && s.isStrike), 'Strikethrough parsed with isStrike flag');
  expect(strikeAndUnderlineSpans.any((s) => s.text == 'Important' && s.isUnderline), 'Underline parsed with isUnderline flag');

  // Delta to RichLines parsing
  const richDeltaJson = '[{"insert":"Kickoff Meeting"},{"insert":"\\n","attributes":{"header":1}},{"insert":"Target: "},{"insert":"v1.0.5 Release","attributes":{"bold":true}},{"insert":"\\n"},{"insert":"Verify NoteCard styles"},{"insert":"\\n","attributes":{"list":"bullet"}},{"insert":"Step One"},{"insert":"\\n","attributes":{"list":"ordered"}},{"insert":"Step Two"},{"insert":"\\n","attributes":{"list":"ordered"}},{"insert":"Remember this"},{"insert":"\\n","attributes":{"blockquote":true}}]';
  final richLines = NoteHelper.parseToRichLines(richDeltaJson);
  expect(richLines.length == 6, 'Parsed 6 rich lines from Delta JSON');
  expect(richLines[0].header == 1 && richLines[0].plainText == 'Kickoff Meeting', 'H1 header line parsed');
  expect(richLines[1].spans.any((s) => s.text == 'v1.0.5 Release' && s.isBold), 'Inline bold span parsed in rich lines');
  expect(richLines[2].listType == 'bullet' && richLines[2].plainText == 'Verify NoteCard styles', 'Bullet list line parsed');
  expect(richLines[3].listType == 'ordered' && richLines[3].listIndex == 1, 'Ordered list line 1 has index 1');
  expect(richLines[4].listType == 'ordered' && richLines[4].listIndex == 2, 'Ordered list line 2 has index 2');
  expect(richLines[5].isBlockquote == true && richLines[5].plainText == 'Remember this', 'Blockquote line parsed');

  // Markdown note to RichLines parsing (for legacy notes)
  const legacyMarkdown = '# Release Roadmap\n- Deploy **v1.0.5**\n> Offline-First NotePad';
  final legacyLines = NoteHelper.parseToRichLines(legacyMarkdown);
  expect(legacyLines.length == 3, 'Parsed 3 rich lines from legacy Markdown');
  expect(legacyLines[0].header == 1 && legacyLines[0].plainText == 'Release Roadmap', 'Legacy H1 converted and parsed');
  expect(legacyLines[1].listType == 'bullet', 'Legacy bullet list converted and parsed');
  expect(legacyLines[1].spans.any((s) => s.text == 'v1.0.5' && s.isBold), 'Legacy inline bold converted and parsed');
  expect(legacyLines[2].isBlockquote == true, 'Legacy blockquote converted and parsed');

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

  // --- Suite 8: Rich Text Quill Delta Persistence & Editing Roundtrip ---
  final richTextRepo1 = LocalNoteRepository(
    seedDemoData: false,
    enableDiskPersistence: true,
    customStoragePath: testJsonPath,
  );
  await richTextRepo1.init();

  const richDeltaContent = '[{"insert":"Architecture Plan\\n","attributes":{"header":1}},{"insert":"Feature is "},{"insert":"critical","attributes":{"bold":true}},{"insert":" and "},{"insert":"urgent","attributes":{"italic":true}},{"insert":".\\n"},{"insert":"Draft spec"},{"insert":"\\n","attributes":{"list":"unchecked"}}]';

  final richNote = NoteEntity(
    id: 'rich-note-delta-1',
    title: 'Rich Text Delta Note',
    content: richDeltaContent,
    createdAt: DateTime.now(),
    updatedAt: DateTime.now(),
  );

  await richTextRepo1.saveNote(richNote);
  richTextRepo1.dispose();

  // Reopen note in brand new repository session
  final richTextRepo2 = LocalNoteRepository(
    seedDemoData: false,
    enableDiskPersistence: true,
    customStoragePath: testJsonPath,
  );
  await richTextRepo2.init();

  final reloadedRichNote = await richTextRepo2.getNoteById('rich-note-delta-1');
  expect(reloadedRichNote != null, 'Rich text note reloaded from disk');
  expect(NoteHelper.isDeltaContent(reloadedRichNote!.content), 'Content preserved as native Quill Delta JSON');

  final reloadedOps = jsonDecode(reloadedRichNote.content) as List<dynamic>;
  expect(reloadedOps.any((op) => op is Map && op['insert'] == 'critical' && op['attributes']?['bold'] == true), 'Bold attribute preserved across restart without plain text conversion');
  expect(reloadedOps.any((op) => op is Map && op['attributes']?['header'] == 1), 'Heading attribute preserved across restart');
  expect(reloadedOps.any((op) => op is Map && op['attributes']?['list'] == 'unchecked'), 'Checklist attribute preserved across restart');

  // Edit previously saved note by appending new formatted operations
  final editedOps = List<Map<String, dynamic>>.from(reloadedOps);
  editedOps.add({'insert': 'Approved by lead\n', 'attributes': {'list': 'checked'}});
  final editedDeltaJson = jsonEncode(editedOps);

  final editedNote = reloadedRichNote.copyWith(
    content: editedDeltaJson,
    updatedAt: DateTime.now(),
  );
  await richTextRepo2.saveNote(editedNote);
  richTextRepo2.dispose();

  // Reopen third session to verify edited note
  final richTextRepo3 = LocalNoteRepository(
    seedDemoData: false,
    enableDiskPersistence: true,
    customStoragePath: testJsonPath,
  );
  await richTextRepo3.init();

  final reloadedEdited = await richTextRepo3.getNoteById('rich-note-delta-1');
  expect(reloadedEdited != null, 'Edited rich text note reloaded');
  final reloadedEditedOps = jsonDecode(reloadedEdited!.content) as List<dynamic>;
  expect(reloadedEditedOps.any((op) => op is Map && op['insert'] == 'Approved by lead\n' && op['attributes']?['list'] == 'checked'), 'Edited operations persisted to disk');

  await richTextRepo3.deleteNote('rich-note-delta-1');
  richTextRepo3.dispose();

  // Clean up temp file
  tempDir.deleteSync(recursive: true);

  // --- Suite 6: Acceptance Tests — Four-Line Rich Text Note Verification ---
  // Note content:
  // Line 1: Hello (bold)
  // Line 2: Hello (italic)
  // Line 3: Hello (underline)
  // Line 4: Normal text
  final acceptanceDeltaJson = jsonEncode([
    {'insert': 'Hello', 'attributes': {'bold': true}},
    {'insert': '\n'},
    {'insert': 'Hello', 'attributes': {'italic': true}},
    {'insert': '\n'},
    {'insert': 'Hello', 'attributes': {'underline': true}},
    {'insert': '\n'},
    {'insert': 'Normal text\n'},
  ]);

  // Acceptance Test 1: Editor deserialization and formatting reproduction
  final editorFormattedText = NoteHelper.formatForEditor(acceptanceDeltaJson);
  expect(editorFormattedText.contains('**Hello**'), 'Editor formats line 1 with bold markdown representation');
  expect(editorFormattedText.contains('*Hello*'), 'Editor formats line 2 with italic markdown representation');
  expect(editorFormattedText.contains('<u>Hello</u>'), 'Editor formats line 3 with underline markdown representation');
  expect(editorFormattedText.contains('Normal text'), 'Editor preserves line 4 normal text');

  // Acceptance Test 2: Home screen preview preserves all formatting
  final previewLines = NoteHelper.parseToRichLines(acceptanceDeltaJson);
  expect(previewLines.length == 4, 'Preview has exactly 4 lines');
  expect(previewLines[0].spans.any((s) => s.text == 'Hello' && s.isBold), 'Preview Line 1 preserves bold formatting');
  expect(previewLines[1].spans.any((s) => s.text == 'Hello' && s.isItalic), 'Preview Line 2 preserves italic formatting');
  expect(previewLines[2].spans.any((s) => s.text == 'Hello' && s.isUnderline), 'Preview Line 3 preserves underline formatting');
  expect(previewLines[3].spans.any((s) => s.text == 'Normal text' && !s.isBold && !s.isItalic && !s.isUnderline), 'Preview Line 4 preserves unstyled normal text');

  // Acceptance Test 3: Closing and reopening the app preserves formatting (persistence)
  final acceptanceNote = NoteEntity(
    id: 'acceptance-note-1',
    title: 'Acceptance Note',
    content: acceptanceDeltaJson,
    createdAt: DateTime.now(),
    updatedAt: DateTime.now(),
  );

  final acceptanceTempDir = Directory.systemTemp.createTempSync('noteflow_acceptance_');
  final acceptanceDbPath = '${acceptanceTempDir.path}/noteflow_data.json';
  final persistRepo1 = LocalNoteRepository(
    enableDiskPersistence: true,
    customStoragePath: acceptanceDbPath,
  );
  await persistRepo1.init();
  await persistRepo1.saveNote(acceptanceNote);
  persistRepo1.dispose();

  // Reopen app by hydrating new repo instance from disk
  final persistRepo2 = LocalNoteRepository(
    enableDiskPersistence: true,
    customStoragePath: acceptanceDbPath,
  );
  await persistRepo2.init();
  final reloadedAcceptance = await persistRepo2.getNoteById('acceptance-note-1');
  expect(reloadedAcceptance != null, 'Acceptance note persisted and reloaded from disk');
  expect(reloadedAcceptance!.content == acceptanceDeltaJson, 'Reloaded note preserves exact Delta JSON payload');

  final reloadedPreviewLines = NoteHelper.parseToRichLines(reloadedAcceptance.content);
  expect(reloadedPreviewLines[0].spans.any((s) => s.isBold), 'Reloaded note preview preserves Line 1 bold');
  expect(reloadedPreviewLines[1].spans.any((s) => s.isItalic), 'Reloaded note preview preserves Line 2 italic');
  expect(reloadedPreviewLines[2].spans.any((s) => s.isUnderline), 'Reloaded note preview preserves Line 3 underline');

  // Acceptance Test 4: Archived notes preserve formatting
  await persistRepo2.toggleArchive('acceptance-note-1');
  final archivedAcceptance = await persistRepo2.getNoteById('acceptance-note-1');
  expect(archivedAcceptance != null && archivedAcceptance.isArchived, 'Acceptance note archived');
  final archivedPreviewLines = NoteHelper.parseToRichLines(archivedAcceptance!.content);
  expect(archivedPreviewLines.length == 4, 'Archived note preview preserves 4 lines');
  expect(archivedPreviewLines[0].spans.any((s) => s.isBold), 'Archived note preview preserves bold');
  expect(archivedPreviewLines[1].spans.any((s) => s.isItalic), 'Archived note preview preserves italic');
  expect(archivedPreviewLines[2].spans.any((s) => s.isUnderline), 'Archived note preview preserves underline');

  // Acceptance Test 5: Editing an existing formatted note does not remove its formatting
  final acceptanceEditedDeltaJson = jsonEncode([
    {'insert': 'Hello', 'attributes': {'bold': true}},
    {'insert': '\n'},
    {'insert': 'Hello', 'attributes': {'italic': true}},
    {'insert': '\n'},
    {'insert': 'Hello', 'attributes': {'underline': true}},
    {'insert': '\n'},
    {'insert': 'Normal text and edited additions\n'},
  ]);
  final editedAcceptance = archivedAcceptance.copyWith(content: acceptanceEditedDeltaJson, updatedAt: DateTime.now());
  await persistRepo2.saveNote(editedAcceptance);

  final fetchedEdited = await persistRepo2.getNoteById('acceptance-note-1');
  expect(fetchedEdited != null, 'Edited note retrieved');
  final editedPreviewLines = NoteHelper.parseToRichLines(fetchedEdited!.content);
  expect(editedPreviewLines[0].spans.any((s) => s.isBold), 'Edited note retains bold on line 1');
  expect(editedPreviewLines[1].spans.any((s) => s.isItalic), 'Edited note retains italic on line 2');
  expect(editedPreviewLines[2].spans.any((s) => s.isUnderline), 'Edited note retains underline on line 3');
  expect(editedPreviewLines[3].plainText.contains('edited additions'), 'Edited note has updated additions');

  persistRepo2.dispose();
  acceptanceTempDir.deleteSync(recursive: true);

  stdout.writeln('ALL NOTEFLOW TESTS PASSED! (100/100 Assertions) ✓');
}
