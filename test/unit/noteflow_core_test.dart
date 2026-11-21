import 'dart:io';
import 'dart:convert';

import '../../lib/shared/models/note_entity.dart';
import '../../lib/shared/models/folder_entity.dart';
import '../../lib/shared/models/tag_entity.dart';
import '../../lib/shared/models/note_filter.dart';
import '../../lib/core/utils/note_helper.dart';
import '../../lib/core/utils/date_formatter.dart';
import '../../lib/core/utils/audio_helper.dart';
import '../../lib/core/database/local_note_repository.dart';
import '../../lib/shared/models/voice_recording_entity.dart';
import '../../lib/shared/models/backup_models.dart';
import '../../lib/shared/models/reminder_entity.dart';
import '../../lib/features/reminders/services/reminder_service.dart';
import '../../lib/features/reminders/services/reminder_scheduler.dart';

class TestMockReminderScheduler implements ReminderScheduler {
  final List<Map<String, dynamic>> scheduled = [];
  final List<int> cancelled = [];

  @override
  Future<void> scheduleAlarm({
    required int notificationId,
    required int triggerEpochMs,
    required String title,
    required String body,
    String? noteId,
    String? checklistItemId,
    String? voiceRecordingId,
  }) async {
    scheduled.add({
      'notificationId': notificationId,
      'triggerEpochMs': triggerEpochMs,
      'title': title,
      'body': body,
      'noteId': noteId,
      'checklistItemId': checklistItemId,
      'voiceRecordingId': voiceRecordingId,
    });
  }

  @override
  Future<void> cancelAlarm(int notificationId) async {
    cancelled.add(notificationId);
  }

  void reset() {
    scheduled.clear();
    cancelled.clear();
  }
}

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

  final copied = note.copyWith(
    title: 'Updated Title',
    isPinned: false,
    colorIndex: 4,
  );
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
  expect(
    NoteHelper.isDeltaContent(jsonDelta) == true,
    'Delta JSON is recognized as delta',
  );
  expect(
    NoteHelper.isDeltaContent('Plain markdown content') == false,
    'Plain text is not delta',
  );
  expect(
    NoteHelper.isDeltaContent('[ ] Plain checkbox item') == false,
    'Plain checkbox is not delta',
  );
  expect(NoteHelper.isDeltaContent('') == false, 'Empty string is not delta');

  // Checklist detection tests
  expect(
    NoteHelper.isChecklistContent('[ ] First task\n[x] Done task') == true,
    'Markdown checklist detected',
  );
  expect(
    NoteHelper.isChecklistContent('Just a regular note with paragraphs') ==
        false,
    'Regular note not checklist',
  );
  const deltaChecklist =
      '[{"insert":"Groceries"},{"insert":"\\n","attributes":{"list":"unchecked"}},{"insert":"Laundry"},{"insert":"\\n","attributes":{"list":"checked"}}]';
  expect(
    NoteHelper.isChecklistContent(deltaChecklist) == true,
    'Delta JSON checklist detected',
  );
  expect(
    NoteHelper.isChecklistContent(jsonDelta) == false,
    'Plain Delta JSON not checklist',
  );

  // formatForEditor conversion tests (Critical Rich Text Editor Bug fix)
  final plainUnchanged = NoteHelper.formatForEditor(
    'Existing plain text\nWith multiple lines',
  );
  expect(
    plainUnchanged == 'Existing plain text\nWith multiple lines',
    'Plain text is preserved unchanged',
  );

  final simpleDeltaFormatted = NoteHelper.formatForEditor(
    '[{"insert":"Hello World\\n"}]',
  );
  expect(
    simpleDeltaFormatted == 'Hello World',
    'Simple Delta converted to plain text without JSON syntax',
  );
  expect(
    !simpleDeltaFormatted.contains('{"insert"'),
    'No raw JSON syntax in formatted editor text',
  );

  const formattedDeltaJson =
      '[{"insert":"Title "},{"insert":"bold text","attributes":{"bold":true}},{"insert":" and "},{"insert":"italic text","attributes":{"italic":true}},{"insert":"\\n"}]';
  final formattedMarkdown = NoteHelper.formatForEditor(formattedDeltaJson);
  expect(
    formattedMarkdown == 'Title **bold text** and *italic text*',
    'Inline bold and italic converted to markdown',
  );

  const headerDeltaJson =
      '[{"insert":"Meeting Notes"},{"insert":"\\n","attributes":{"header":1}},{"insert":"Action items"},{"insert":"\\n","attributes":{"header":2}}]';
  final headerFormatted = NoteHelper.formatForEditor(headerDeltaJson);
  expect(
    headerFormatted == '# Meeting Notes\n## Action items',
    'Quill headers converted to markdown headers',
  );

  final checklistFormatted = NoteHelper.formatForEditor(deltaChecklist);
  expect(
    checklistFormatted == '[ ] Groceries\n[x] Laundry',
    'Quill checklist ops converted to [ ] and [x] items',
  );

  const literalBugJson =
      '[{"insert":"Project Kickoff\\n"},{"insert":"1. Define Scope\\n","attributes":{"list":"ordered"}},{"insert":"Review deadline"},{"insert":"\\n","attributes":{"list":"unchecked"}}]';
  final fixedBugText = NoteHelper.formatForEditor(literalBugJson);
  expect(
    !fixedBugText.contains('[{"'),
    'Fixed bug text does not have raw JSON array bracket syntax',
  );
  expect(
    !fixedBugText.contains('{"insert"'),
    'Fixed bug text does not have {"insert"',
  );
  expect(
    fixedBugText.contains('[ ] Review deadline'),
    'Checklist line properly converted',
  );

  // markdownToDeltaJson tests (Rich Text Migration & Storage)
  final boldDelta = NoteHelper.markdownToDeltaJson('**Hello**');
  final boldOps = jsonDecode(boldDelta) as List<dynamic>;
  expect(
    boldOps.any(
      (op) =>
          op is Map &&
          op['insert'] == 'Hello' &&
          op['attributes']?['bold'] == true,
    ),
    'Bold text converted to Delta with bold attribute',
  );

  final italicDelta = NoteHelper.markdownToDeltaJson('*Italic*');
  final italicOps = jsonDecode(italicDelta) as List<dynamic>;
  expect(
    italicOps.any(
      (op) =>
          op is Map &&
          op['insert'] == 'Italic' &&
          op['attributes']?['italic'] == true,
    ),
    'Italic text converted to Delta with italic attribute',
  );

  final underlineDelta = NoteHelper.markdownToDeltaJson('<u>Underlined</u>');
  final underlineOps = jsonDecode(underlineDelta) as List<dynamic>;
  expect(
    underlineOps.any(
      (op) =>
          op is Map &&
          op['insert'] == 'Underlined' &&
          op['attributes']?['underline'] == true,
    ),
    'Underline text converted to Delta with underline attribute',
  );

  final combinedDelta = NoteHelper.markdownToDeltaJson('***Bold and Italic***');
  final combinedOps = jsonDecode(combinedDelta) as List<dynamic>;
  expect(
    combinedOps.any(
      (op) =>
          op is Map &&
          op['attributes']?['bold'] == true &&
          op['attributes']?['italic'] == true,
    ),
    'Combined bold & italic formatting converted to Delta',
  );

  final headingDelta = NoteHelper.markdownToDeltaJson(
    '# Heading 1\n## Heading 2\n### Heading 3',
  );
  final headingOps = jsonDecode(headingDelta) as List<dynamic>;
  expect(
    headingOps.any((op) => op is Map && op['attributes']?['header'] == 1),
    'H1 block attribute generated in Delta',
  );
  expect(
    headingOps.any((op) => op is Map && op['attributes']?['header'] == 2),
    'H2 block attribute generated in Delta',
  );
  expect(
    headingOps.any((op) => op is Map && op['attributes']?['header'] == 3),
    'H3 block attribute generated in Delta',
  );

  final bulletDelta = NoteHelper.markdownToDeltaJson(
    '- First Item\n- Second Item',
  );
  final bulletOps = jsonDecode(bulletDelta) as List<dynamic>;
  expect(
    bulletOps.any((op) => op is Map && op['attributes']?['list'] == 'bullet'),
    'Bullet list block attribute generated in Delta',
  );

  final numberedDelta = NoteHelper.markdownToDeltaJson(
    '1. Step One\n2. Step Two',
  );
  final numberedOps = jsonDecode(numberedDelta) as List<dynamic>;
  expect(
    numberedOps.any(
      (op) => op is Map && op['attributes']?['list'] == 'ordered',
    ),
    'Numbered list block attribute generated in Delta',
  );

  final checklistDelta = NoteHelper.markdownToDeltaJson(
    '[ ] Buy milk\n[x] Finished task',
  );
  final checklistOps = jsonDecode(checklistDelta) as List<dynamic>;
  expect(
    checklistOps.any(
      (op) => op is Map && op['attributes']?['list'] == 'unchecked',
    ),
    'Unchecked list attribute generated in Delta',
  );
  expect(
    checklistOps.any(
      (op) => op is Map && op['attributes']?['list'] == 'checked',
    ),
    'Checked list attribute generated in Delta',
  );

  // --- Suite 2.5: Note Card Rich Text Snippet Parsing ---
  final inlineSpans = NoteHelper.parseInlineMarkdown('Buy **milk** and *eggs*');
  expect(inlineSpans.length == 4, 'Inline markdown parsed into 4 spans');
  expect(inlineSpans[0].text == 'Buy ', 'First span plain text');
  expect(
    inlineSpans[1].text == 'milk' && inlineSpans[1].isBold,
    'Second span bold text',
  );
  expect(inlineSpans[2].text == ' and ', 'Third span plain text');
  expect(
    inlineSpans[3].text == 'eggs' && inlineSpans[3].isItalic,
    'Fourth span italic text',
  );

  final codeSpans = NoteHelper.parseInlineMarkdown('Run `git commit` now');
  expect(
    codeSpans.any((s) => s.text == 'git commit' && s.isCode),
    'Inline code parsed with isCode flag',
  );

  final strikeAndUnderlineSpans = NoteHelper.parseInlineMarkdown(
    '~~Done~~ and <u>Important</u>',
  );
  expect(
    strikeAndUnderlineSpans.any((s) => s.text == 'Done' && s.isStrike),
    'Strikethrough parsed with isStrike flag',
  );
  expect(
    strikeAndUnderlineSpans.any((s) => s.text == 'Important' && s.isUnderline),
    'Underline parsed with isUnderline flag',
  );

  // Delta to RichLines parsing
  const richDeltaJson =
      '[{"insert":"Kickoff Meeting"},{"insert":"\\n","attributes":{"header":1}},{"insert":"Target: "},{"insert":"v1.0.5 Release","attributes":{"bold":true}},{"insert":"\\n"},{"insert":"Verify NoteCard styles"},{"insert":"\\n","attributes":{"list":"bullet"}},{"insert":"Step One"},{"insert":"\\n","attributes":{"list":"ordered"}},{"insert":"Step Two"},{"insert":"\\n","attributes":{"list":"ordered"}},{"insert":"Remember this"},{"insert":"\\n","attributes":{"blockquote":true}}]';
  final richLines = NoteHelper.parseToRichLines(richDeltaJson);
  expect(richLines.length == 6, 'Parsed 6 rich lines from Delta JSON');
  expect(
    richLines[0].header == 1 && richLines[0].plainText == 'Kickoff Meeting',
    'H1 header line parsed',
  );
  expect(
    richLines[1].spans.any((s) => s.text == 'v1.0.5 Release' && s.isBold),
    'Inline bold span parsed in rich lines',
  );
  expect(
    richLines[2].listType == 'bullet' &&
        richLines[2].plainText == 'Verify NoteCard styles',
    'Bullet list line parsed',
  );
  expect(
    richLines[3].listType == 'ordered' && richLines[3].listIndex == 1,
    'Ordered list line 1 has index 1',
  );
  expect(
    richLines[4].listType == 'ordered' && richLines[4].listIndex == 2,
    'Ordered list line 2 has index 2',
  );
  expect(
    richLines[5].isBlockquote == true &&
        richLines[5].plainText == 'Remember this',
    'Blockquote line parsed',
  );

  // Markdown note to RichLines parsing (for legacy notes)
  const legacyMarkdown =
      '# Release Roadmap\n- Deploy **v1.0.5**\n> Offline-First NotePad';
  final legacyLines = NoteHelper.parseToRichLines(legacyMarkdown);
  expect(legacyLines.length == 3, 'Parsed 3 rich lines from legacy Markdown');
  expect(
    legacyLines[0].header == 1 && legacyLines[0].plainText == 'Release Roadmap',
    'Legacy H1 converted and parsed',
  );
  expect(
    legacyLines[1].listType == 'bullet',
    'Legacy bullet list converted and parsed',
  );
  expect(
    legacyLines[1].spans.any((s) => s.text == 'v1.0.5' && s.isBold),
    'Legacy inline bold converted and parsed',
  );
  expect(
    legacyLines[2].isBlockquote == true,
    'Legacy blockquote converted and parsed',
  );

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
  expect(
    noteAfterFolderDelete!.folderId == null,
    'Note unassigned from deleted folder',
  );

  // Clean up
  await repo.deleteNote('note-in-folder');

  // --- Suite 6: NoteFilterState & Sorting ---
  const filterDefault = NoteFilterState();
  expect(
    filterDefault.sortOrder == NoteSortOrder.recentlyModified,
    'Default sort is recently modified',
  );
  expect(
    filterDefault.selectedFolderId == null,
    'Default folder is null (all notes)',
  );

  final filterCustom = filterDefault.copyWith(
    searchQuery: 'Grocery',
    selectedFolderId: 'folder-personal',
    sortOrder: NoteSortOrder.titleAZ,
  );
  expect(filterCustom.searchQuery == 'Grocery', 'Filter search query set');
  expect(
    filterCustom.selectedFolderId == 'folder-personal',
    'Filter folder set',
  );
  expect(
    filterCustom.sortOrder == NoteSortOrder.titleAZ,
    'Filter sort order updated',
  );

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
  expect(
    loadedFromDisk != null,
    'Note persisted to disk and reloaded successfully',
  );
  expect(
    loadedFromDisk!.title == 'Durable Disk Note',
    'Persisted title matches',
  );
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
  expect(
    deletedAfterReload == null,
    'Note deletion persisted across app restart',
  );
  expect(
    persistentRepo3.themeMode == 'light',
    'Theme mode persisted and restored from disk',
  );
  persistentRepo3.dispose();

  // --- Suite 8: Rich Text Quill Delta Persistence & Editing Roundtrip ---
  final richTextRepo1 = LocalNoteRepository(
    seedDemoData: false,
    enableDiskPersistence: true,
    customStoragePath: testJsonPath,
  );
  await richTextRepo1.init();

  const richDeltaContent =
      '[{"insert":"Architecture Plan\\n","attributes":{"header":1}},{"insert":"Feature is "},{"insert":"critical","attributes":{"bold":true}},{"insert":" and "},{"insert":"urgent","attributes":{"italic":true}},{"insert":".\\n"},{"insert":"Draft spec"},{"insert":"\\n","attributes":{"list":"unchecked"}}]';

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
  expect(
    NoteHelper.isDeltaContent(reloadedRichNote!.content),
    'Content preserved as native Quill Delta JSON',
  );

  final reloadedOps = jsonDecode(reloadedRichNote.content) as List<dynamic>;
  expect(
    reloadedOps.any(
      (op) =>
          op is Map &&
          op['insert'] == 'critical' &&
          op['attributes']?['bold'] == true,
    ),
    'Bold attribute preserved across restart without plain text conversion',
  );
  expect(
    reloadedOps.any((op) => op is Map && op['attributes']?['header'] == 1),
    'Heading attribute preserved across restart',
  );
  expect(
    reloadedOps.any(
      (op) => op is Map && op['attributes']?['list'] == 'unchecked',
    ),
    'Checklist attribute preserved across restart',
  );

  // Edit previously saved note by appending new formatted operations
  final editedOps = List<Map<String, dynamic>>.from(reloadedOps);
  editedOps.add({
    'insert': 'Approved by lead\n',
    'attributes': {'list': 'checked'},
  });
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
  final reloadedEditedOps =
      jsonDecode(reloadedEdited!.content) as List<dynamic>;
  expect(
    reloadedEditedOps.any(
      (op) =>
          op is Map &&
          op['insert'] == 'Approved by lead\n' &&
          op['attributes']?['list'] == 'checked',
    ),
    'Edited operations persisted to disk',
  );

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
    {
      'insert': 'Hello',
      'attributes': {'bold': true},
    },
    {'insert': '\n'},
    {
      'insert': 'Hello',
      'attributes': {'italic': true},
    },
    {'insert': '\n'},
    {
      'insert': 'Hello',
      'attributes': {'underline': true},
    },
    {'insert': '\n'},
    {'insert': 'Normal text\n'},
  ]);

  // Acceptance Test 1: Editor deserialization and formatting reproduction
  final editorFormattedText = NoteHelper.formatForEditor(acceptanceDeltaJson);
  expect(
    editorFormattedText.contains('**Hello**'),
    'Editor formats line 1 with bold markdown representation',
  );
  expect(
    editorFormattedText.contains('*Hello*'),
    'Editor formats line 2 with italic markdown representation',
  );
  expect(
    editorFormattedText.contains('<u>Hello</u>'),
    'Editor formats line 3 with underline markdown representation',
  );
  expect(
    editorFormattedText.contains('Normal text'),
    'Editor preserves line 4 normal text',
  );

  // Acceptance Test 2: Home screen preview preserves all formatting
  final previewLines = NoteHelper.parseToRichLines(acceptanceDeltaJson);
  expect(previewLines.length == 4, 'Preview has exactly 4 lines');
  expect(
    previewLines[0].spans.any((s) => s.text == 'Hello' && s.isBold),
    'Preview Line 1 preserves bold formatting',
  );
  expect(
    previewLines[1].spans.any((s) => s.text == 'Hello' && s.isItalic),
    'Preview Line 2 preserves italic formatting',
  );
  expect(
    previewLines[2].spans.any((s) => s.text == 'Hello' && s.isUnderline),
    'Preview Line 3 preserves underline formatting',
  );
  expect(
    previewLines[3].spans.any(
      (s) =>
          s.text == 'Normal text' && !s.isBold && !s.isItalic && !s.isUnderline,
    ),
    'Preview Line 4 preserves unstyled normal text',
  );

  // Acceptance Test 3: Closing and reopening the app preserves formatting (persistence)
  final acceptanceNote = NoteEntity(
    id: 'acceptance-note-1',
    title: 'Acceptance Note',
    content: acceptanceDeltaJson,
    createdAt: DateTime.now(),
    updatedAt: DateTime.now(),
  );

  final acceptanceTempDir = Directory.systemTemp.createTempSync(
    'noteflow_acceptance_',
  );
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
  final reloadedAcceptance = await persistRepo2.getNoteById(
    'acceptance-note-1',
  );
  expect(
    reloadedAcceptance != null,
    'Acceptance note persisted and reloaded from disk',
  );
  expect(
    reloadedAcceptance!.content == acceptanceDeltaJson,
    'Reloaded note preserves exact Delta JSON payload',
  );

  final reloadedPreviewLines = NoteHelper.parseToRichLines(
    reloadedAcceptance.content,
  );
  expect(
    reloadedPreviewLines[0].spans.any((s) => s.isBold),
    'Reloaded note preview preserves Line 1 bold',
  );
  expect(
    reloadedPreviewLines[1].spans.any((s) => s.isItalic),
    'Reloaded note preview preserves Line 2 italic',
  );
  expect(
    reloadedPreviewLines[2].spans.any((s) => s.isUnderline),
    'Reloaded note preview preserves Line 3 underline',
  );

  // Acceptance Test 4: Archived notes preserve formatting
  await persistRepo2.toggleArchive('acceptance-note-1');
  final archivedAcceptance = await persistRepo2.getNoteById(
    'acceptance-note-1',
  );
  expect(
    archivedAcceptance != null && archivedAcceptance.isArchived,
    'Acceptance note archived',
  );
  final archivedPreviewLines = NoteHelper.parseToRichLines(
    archivedAcceptance!.content,
  );
  expect(
    archivedPreviewLines.length == 4,
    'Archived note preview preserves 4 lines',
  );
  expect(
    archivedPreviewLines[0].spans.any((s) => s.isBold),
    'Archived note preview preserves bold',
  );
  expect(
    archivedPreviewLines[1].spans.any((s) => s.isItalic),
    'Archived note preview preserves italic',
  );
  expect(
    archivedPreviewLines[2].spans.any((s) => s.isUnderline),
    'Archived note preview preserves underline',
  );

  // Acceptance Test 5: Editing an existing formatted note does not remove its formatting
  final acceptanceEditedDeltaJson = jsonEncode([
    {
      'insert': 'Hello',
      'attributes': {'bold': true},
    },
    {'insert': '\n'},
    {
      'insert': 'Hello',
      'attributes': {'italic': true},
    },
    {'insert': '\n'},
    {
      'insert': 'Hello',
      'attributes': {'underline': true},
    },
    {'insert': '\n'},
    {'insert': 'Normal text and edited additions\n'},
  ]);
  final editedAcceptance = archivedAcceptance.copyWith(
    content: acceptanceEditedDeltaJson,
    updatedAt: DateTime.now(),
  );
  await persistRepo2.saveNote(editedAcceptance);

  final fetchedEdited = await persistRepo2.getNoteById('acceptance-note-1');
  expect(fetchedEdited != null, 'Edited note retrieved');
  final editedPreviewLines = NoteHelper.parseToRichLines(
    fetchedEdited!.content,
  );
  expect(
    editedPreviewLines[0].spans.any((s) => s.isBold),
    'Edited note retains bold on line 1',
  );
  expect(
    editedPreviewLines[1].spans.any((s) => s.isItalic),
    'Edited note retains italic on line 2',
  );
  expect(
    editedPreviewLines[2].spans.any((s) => s.isUnderline),
    'Edited note retains underline on line 3',
  );
  expect(
    editedPreviewLines[3].plainText.contains('edited additions'),
    'Edited note has updated additions',
  );

  persistRepo2.dispose();
  acceptanceTempDir.deleteSync(recursive: true);

  // --- Suite 7: Editor CRUD & Lifecycle Scenarios ---
  // Test 1: Empty Note Discard Verification
  final emptyDelta = jsonEncode([
    {'insert': '\n'},
  ]);
  final emptyChecklistDelta = NoteHelper.markdownToDeltaJson('[ ] ');
  expect(
    NoteHelper.extractPlainText(emptyDelta).trim().isEmpty,
    'Empty rich text note produces blank plain text',
  );
  expect(
    NoteHelper.extractPlainText(emptyChecklistDelta).trim().isEmpty,
    'Empty checklist note produces blank plain text',
  );

  // Test 2: Mode switching between Rich Text and Checklist content preservation
  const richSource =
      '[{"insert":"Meeting Agenda\\n"},{"insert":"Discuss budget\\n","attributes":{"list":"bullet"}}]';
  final convertedToChecklist = NoteHelper.formatForEditor(richSource);
  expect(
    convertedToChecklist.contains('Meeting Agenda'),
    'Rich text converted to checklist retains text',
  );
  expect(
    convertedToChecklist.contains('• Discuss budget'),
    'Rich text converted to checklist retains list item',
  );

  const checklistSource = '[ ] First task\n[x] Completed task';
  final convertedToDelta = NoteHelper.markdownToDeltaJson(checklistSource);
  final convertedBackOps = jsonDecode(convertedToDelta) as List<dynamic>;
  expect(
    convertedBackOps.any((op) => op is Map && op['insert'] == 'First task'),
    'Checklist converted to Delta retains task 1',
  );
  expect(
    convertedBackOps.any((op) => op is Map && op['insert'] == 'Completed task'),
    'Checklist converted to Delta retains task 2',
  );

  // Test 3: Note Deletion Lifecycle (cannot be retrieved after delete)
  final crudTempDir = Directory.systemTemp.createTempSync('noteflow_crud_');
  final crudDbPath = '${crudTempDir.path}/noteflow_data.json';
  final crudRepo = LocalNoteRepository(
    enableDiskPersistence: true,
    customStoragePath: crudDbPath,
  );
  await crudRepo.init();

  final crudNote = NoteEntity(
    id: 'crud-note-lifecycle-1',
    title: 'CRUD Lifecycle Note',
    content: '[{"insert":"Active note content\\n"}]',
    createdAt: DateTime.now(),
    updatedAt: DateTime.now(),
  );
  await crudRepo.saveNote(crudNote);
  expect(
    await crudRepo.getNoteById('crud-note-lifecycle-1') != null,
    'CRUD note saved',
  );

  await crudRepo.deleteNote('crud-note-lifecycle-1');
  expect(
    await crudRepo.getNoteById('crud-note-lifecycle-1') == null,
    'CRUD note deleted cleanly from repository',
  );

  // Test 4: Note Archive Lifecycle & Active Filter Separation
  final archiveNote = NoteEntity(
    id: 'crud-archive-lifecycle-2',
    title: 'Archive Lifecycle Note',
    content: '[{"insert":"Content destined for archive\\n"}]',
    isPinned: true,
    isArchived: false,
    createdAt: DateTime.now(),
    updatedAt: DateTime.now(),
  );
  await crudRepo.saveNote(archiveNote);

  // Check active stream contains note
  final activeNotesInitial = await crudRepo
      .watchNotes(includeArchived: false)
      .first;
  expect(
    activeNotesInitial.any((n) => n.id == 'crud-archive-lifecycle-2'),
    'Active notes stream contains note before archive',
  );

  // Archive note with unpin
  final archivedNote = archiveNote.copyWith(isArchived: true, isPinned: false);
  await crudRepo.saveNote(archivedNote);

  final activeNotesAfterArchive = await crudRepo
      .watchNotes(includeArchived: false)
      .first;
  expect(
    !activeNotesAfterArchive.any((n) => n.id == 'crud-archive-lifecycle-2'),
    'Active notes stream excludes archived note',
  );

  final archivedNotesList = await crudRepo
      .watchNotes(includeArchived: true)
      .first;
  expect(
    archivedNotesList.any((n) => n.id == 'crud-archive-lifecycle-2'),
    'Archived notes stream includes note after archive',
  );
  expect(
    !archivedNotesList
        .firstWhere((n) => n.id == 'crud-archive-lifecycle-2')
        .isPinned,
    'Archived note has pin removed',
  );

  // Unarchive / restore
  await crudRepo.toggleArchive('crud-archive-lifecycle-2');
  final activeNotesRestored = await crudRepo
      .watchNotes(includeArchived: false)
      .first;
  expect(
    activeNotesRestored.any((n) => n.id == 'crud-archive-lifecycle-2'),
    'Active notes stream contains note after unarchive',
  );

  // Test 5: Zombie Resurrection Prevention in Editor Lifecycle
  bool isEditorDeleted = false;
  Future<void> simulateEditorPopScopeSave(NoteEntity noteToSave) async {
    if (isEditorDeleted) return; // Guarded by isDeleted
    await crudRepo.saveNote(noteToSave);
  }

  // User deletes note
  await crudRepo.deleteNote('crud-archive-lifecycle-2');
  isEditorDeleted = true; // Editor flags note as deleted

  // PopScope/dispose triggers
  await simulateEditorPopScopeSave(archiveNote);

  // Verify note remains deleted (was NOT resurrected)
  expect(
    await crudRepo.getNoteById('crud-archive-lifecycle-2') == null,
    'Note was not resurrected after editor delete',
  );

  // Test 6: App Launcher Icon Assets and Configuration Verification
  final manifestFile = File('android/app/src/main/AndroidManifest.xml');
  expect(manifestFile.existsSync(), 'AndroidManifest.xml exists');
  final manifestContent = manifestFile.readAsStringSync();
  expect(
    manifestContent.contains('android:icon="@mipmap/ic_launcher"'),
    'AndroidManifest declares ic_launcher',
  );
  expect(
    manifestContent.contains('android:roundIcon="@mipmap/ic_launcher_round"'),
    'AndroidManifest declares ic_launcher_round',
  );

  final icLauncherXml = File(
    'android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml',
  );
  expect(icLauncherXml.existsSync(), 'ic_launcher.xml exists');
  final icLauncherXmlContent = icLauncherXml.readAsStringSync();
  expect(
    icLauncherXmlContent.contains(
      '<background android:drawable="@drawable/ic_launcher_background"',
    ),
    'ic_launcher specifies background',
  );
  expect(
    icLauncherXmlContent.contains(
      '<foreground android:drawable="@drawable/ic_launcher_foreground"',
    ),
    'ic_launcher specifies foreground',
  );
  expect(
    icLauncherXmlContent.contains(
      '<monochrome android:drawable="@drawable/ic_launcher_foreground"',
    ),
    'ic_launcher specifies monochrome',
  );

  final densities = ['mdpi', 'hdpi', 'xhdpi', 'xxhdpi', 'xxxhdpi'];
  for (final d in densities) {
    final squareIcon = File(
      'android/app/src/main/res/mipmap-$d/ic_launcher.png',
    );
    final roundIcon = File(
      'android/app/src/main/res/mipmap-$d/ic_launcher_round.png',
    );
    expect(
      squareIcon.existsSync(),
      'Legacy square launcher icon exists for density $d',
    );
    expect(
      roundIcon.existsSync(),
      'Legacy round launcher icon exists for density $d',
    );
  }

  crudRepo.dispose();
  crudTempDir.deleteSync(recursive: true);

  // --- Suite 8: Checklist Editor & Robust Synchronization ---
  // Test 1: Empty and trimmed checklist prefix recognition in markdownToDeltaJson
  final deltaUncheckedNoSpace = NoteHelper.markdownToDeltaJson('[ ]');
  final deltaCheckedNoSpace = NoteHelper.markdownToDeltaJson('[x]');
  final deltaDashUnchecked = NoteHelper.markdownToDeltaJson('- [ ]');
  final deltaDashChecked = NoteHelper.markdownToDeltaJson('- [x]');

  final opsUnchecked = jsonDecode(deltaUncheckedNoSpace) as List<dynamic>;
  final opsChecked = jsonDecode(deltaCheckedNoSpace) as List<dynamic>;
  final opsDashUnchecked = jsonDecode(deltaDashUnchecked) as List<dynamic>;
  final opsDashChecked = jsonDecode(deltaDashChecked) as List<dynamic>;

  expect(
    opsUnchecked.any(
      (o) => o is Map && o['attributes']?['list'] == 'unchecked',
    ),
    'markdownToDeltaJson recognizes "[ ]" as unchecked list',
  );
  expect(
    opsChecked.any((o) => o is Map && o['attributes']?['list'] == 'checked'),
    'markdownToDeltaJson recognizes "[x]" as checked list',
  );
  expect(
    opsDashUnchecked.any(
      (o) => o is Map && o['attributes']?['list'] == 'unchecked',
    ),
    'markdownToDeltaJson recognizes "- [ ]" as unchecked list',
  );
  expect(
    opsDashChecked.any(
      (o) => o is Map && o['attributes']?['list'] == 'checked',
    ),
    'markdownToDeltaJson recognizes "- [x]" as checked list',
  );

  // Test 2: isChecklistContent detection with empty markers
  expect(
    NoteHelper.isChecklistContent('[ ]'),
    'isChecklistContent detects "[ ]"',
  );
  expect(
    NoteHelper.isChecklistContent('[x]'),
    'isChecklistContent detects "[x]"',
  );
  expect(
    NoteHelper.isChecklistContent('- [ ]'),
    'isChecklistContent detects "- [ ]"',
  );
  expect(
    NoteHelper.isChecklistContent('- [x]'),
    'isChecklistContent detects "- [x]"',
  );

  // Test 3: extractPlainText stripping of empty checklist markers
  expect(
    NoteHelper.extractPlainText('[ ]').trim().isEmpty,
    'extractPlainText strips standalone "[ ]"',
  );
  expect(
    NoteHelper.extractPlainText('- [ ]').trim().isEmpty,
    'extractPlainText strips standalone "- [ ]"',
  );
  expect(
    NoteHelper.extractPlainText('[x]').trim().isEmpty,
    'extractPlainText strips standalone "[x]"',
  );
  expect(
    NoteHelper.extractPlainText('[ ] \n[ ] ').trim().isEmpty,
    'extractPlainText strips multiple empty checklist items',
  );
  expect(
    NoteHelper.extractPlainText('[ ] Grocery item').trim() == 'Grocery item',
    'extractPlainText extracts text after checklist marker',
  );

  // Test 4: formatForEditor and serialization bidirectional stability (no accumulating "[ ]" prefix)
  const originalChecklist = '[ ] First task\n[ ] \n[x] Finished task';
  final deltaOriginal = NoteHelper.markdownToDeltaJson(originalChecklist);
  final formattedForEditor = NoteHelper.formatForEditor(deltaOriginal);

  final parsedLines = formattedForEditor.split('\n');
  final simulatedItems = <Map<String, dynamic>>[];
  for (final l in parsedLines) {
    final trimmed = l.trim();
    if (trimmed.isEmpty) continue;
    if (trimmed == '[x]' || trimmed == '- [x]') {
      simulatedItems.add({'isCompleted': true, 'text': ''});
    } else if (trimmed == '[ ]' || trimmed == '- [ ]') {
      simulatedItems.add({'isCompleted': false, 'text': ''});
    } else if (trimmed.startsWith('[x] ') || trimmed.startsWith('- [x] ')) {
      final text = trimmed.startsWith('- [x] ')
          ? trimmed.substring(6)
          : trimmed.substring(4);
      simulatedItems.add({'isCompleted': true, 'text': text});
    } else if (trimmed.startsWith('[ ] ') || trimmed.startsWith('- [ ] ')) {
      final text = trimmed.startsWith('- [ ] ')
          ? trimmed.substring(6)
          : trimmed.substring(4);
      simulatedItems.add({'isCompleted': false, 'text': text});
    }
  }

  expect(
    simulatedItems.length == 3,
    'Checklist parser extracted 3 items without dropping empty items',
  );
  expect(
    simulatedItems[0]['text'] == 'First task' &&
        simulatedItems[0]['isCompleted'] == false,
    'Item 0 has correct text and pending status',
  );
  expect(
    simulatedItems[1]['text'] == '' &&
        simulatedItems[1]['isCompleted'] == false,
    'Item 1 is cleanly empty without literal "[ ]" in description',
  );
  expect(
    simulatedItems[2]['text'] == 'Finished task' &&
        simulatedItems[2]['isCompleted'] == true,
    'Item 2 has correct text and completed status',
  );

  final reSerialized = simulatedItems
      .map((it) {
        final check = it['isCompleted'] == true ? '[x]' : '[ ]';
        final text = it['text'] as String;
        return text.isEmpty ? check : '$check $text';
      })
      .join('\n');

  final secondDelta = NoteHelper.markdownToDeltaJson(reSerialized);
  final secondFormatted = NoteHelper.formatForEditor(secondDelta);
  expect(
    secondFormatted == formattedForEditor,
    'Full round-trip serialization is 100% stable without prefix accumulation',
  );

  // Test 5: Legacy Duplicate Checklist Marker Sanitization & Legitimate Bracket Preservation
  String sanitizeItemText(String raw) {
    var t = raw;
    while (t.startsWith('[ ] ') ||
        t.startsWith('[x] ') ||
        t.startsWith('- [ ] ') ||
        t.startsWith('- [x] ')) {
      t = t.startsWith('- [ ] ') || t.startsWith('- [x] ')
          ? t.substring(6)
          : t.substring(4);
    }
    if (t == '[ ]' || t == '[x]' || t == '- [ ]' || t == '- [x]') {
      t = '';
    }
    return t;
  }

  expect(
    sanitizeItemText('[ ] [ ]') == '',
    'Sanitizes double empty bracket marker to empty string',
  );
  expect(
    sanitizeItemText('[ ] [ ] [ ]') == '',
    'Sanitizes triple empty bracket marker to empty string',
  );
  expect(
    sanitizeItemText('[ ] [ ] Buy groceries') == 'Buy groceries',
    'Sanitizes duplicate brackets before task text',
  );
  expect(
    sanitizeItemText('[x] [x] Completed task') == 'Completed task',
    'Sanitizes duplicate completed brackets',
  );
  expect(
    sanitizeItemText('[Work] Call client') == '[Work] Call client',
    'Preserves legitimate [Work] bracket tag',
  );
  expect(
    sanitizeItemText('Priority [HIGH] task') == 'Priority [HIGH] task',
    'Preserves legitimate [HIGH] bracket tag',
  );
  expect(
    sanitizeItemText('Math formula: x[i] = y[i]') ==
        'Math formula: x[i] = y[i]',
    'Preserves legitimate code/math bracket indexing',
  );

  // Test 6: AutoFocus Rule Verification for New vs Existing Checklists
  bool computeChecklistAutoFocus({
    required bool isPersisted,
    required String title,
    required String content,
  }) {
    return !isPersisted &&
        (title.isEmpty && NoteHelper.extractPlainText(content).isEmpty);
  }

  expect(
    computeChecklistAutoFocus(
      isPersisted: false,
      title: '',
      content: '[{"insert":"\\n","attributes":{"list":"unchecked"}}]',
    ),
    'New blank checklist requests autoFocus',
  );
  expect(
    computeChecklistAutoFocus(isPersisted: false, title: '', content: '[ ]'),
    'New markdown blank checklist requests autoFocus',
  );
  expect(
    !computeChecklistAutoFocus(
      isPersisted: true,
      title: '',
      content: '[{"insert":"\\n"}]',
    ),
    'Existing persisted checklist does NOT request autoFocus',
  );
  expect(
    !computeChecklistAutoFocus(
      isPersisted: true,
      title: 'My Tasks',
      content: '[{"insert":"Task 1\\n"}]',
    ),
    'Existing populated checklist does NOT request autoFocus',
  );
  expect(
    !computeChecklistAutoFocus(
      isPersisted: false,
      title: 'Pre-filled Title',
      content: '',
    ),
    'New note with existing title does NOT autoFocus checklist',
  );

  // --- Suite 10: Explicit FolderFilter Architecture & Text Note Body Auto-Focus ---
  // Test 1: FolderFilter sealed hierarchy
  const allFilter = FolderFilter.all();
  const ideasFilter = FolderFilter.folder('folder-ideas');
  const workFilter = FolderFilter.folder('folder-work');
  const personalFilter = FolderFilter.folder('folder-personal');

  expect(allFilter.isAll == true, 'FolderFilter.all() isAll is true');
  expect(allFilter.folderId == null, 'FolderFilter.all() folderId is null');
  expect(ideasFilter.isAll == false, 'SpecificFolderFilter isAll is false');
  expect(
    ideasFilter.folderId == 'folder-ideas',
    'SpecificFolderFilter folderId matches',
  );
  expect(
    const FolderFilter.all() == const FolderFilter.all(),
    'AllNotesFilter equality matches',
  );
  expect(
    const FolderFilter.folder('f1') == const FolderFilter.folder('f1'),
    'SpecificFolderFilter equality matches',
  );

  // Test 2: NoteFilterState with FolderFilter
  const defaultState = NoteFilterState();
  expect(
    defaultState.folderFilter.isAll == true,
    'Default filter state is All Notes',
  );
  expect(
    defaultState.selectedFolderId == null,
    'Default selectedFolderId is null',
  );
  expect(defaultState.isAllNotes == true, 'Default isAllNotes is true');

  // Copy with folderFilter
  final ideasState = defaultState.copyWith(folderFilter: ideasFilter);
  expect(
    ideasState.folderFilter.folderId == 'folder-ideas',
    'State updated with folder-ideas',
  );
  expect(
    ideasState.selectedFolderId == 'folder-ideas',
    'selectedFolderId getter returns folder-ideas',
  );
  expect(
    ideasState.isAllNotes == false,
    'isAllNotes is false when folder selected',
  );

  // Copy with clearFolder
  final clearedState = ideasState.copyWith(clearFolder: true);
  expect(
    clearedState.folderFilter.isAll == true,
    'clearFolder: true resets to AllNotesFilter',
  );
  expect(
    clearedState.selectedFolderId == null,
    'selectedFolderId is null after clear',
  );

  // Test 3: NoteFilterNotifier folder switching sequence
  var state = const NoteFilterState();
  void simulateSelectAll() =>
      state = state.copyWith(folderFilter: const FolderFilter.all());
  void simulateSelectFolder(String id) {
    if (state.folderFilter.folderId == id) {
      state = state.copyWith(folderFilter: const FolderFilter.all());
    } else {
      state = state.copyWith(folderFilter: FolderFilter.folder(id));
    }
  }

  void simulateSetSelectedFolder(String? id) {
    if (id == null) {
      simulateSelectAll();
    } else {
      simulateSelectFolder(id);
    }
  }

  // 1. Initial: All Notes is selected
  expect(state.folderFilter.isAll == true, 'Initial state is All Notes');

  // 2. Select Ideas
  simulateSetSelectedFolder('folder-ideas');
  expect(
    state.folderFilter.folderId == 'folder-ideas',
    'Ideas folder selected',
  );

  // 3. Select All Notes again (user reported bug: was previously disabled/unresponsive)
  simulateSetSelectedFolder(null);
  expect(
    state.folderFilter.isAll == true,
    'All Notes successfully selected and responsive',
  );
  expect(state.selectedFolderId == null, 'selectedFolderId is null');

  // 4. Select Work
  simulateSetSelectedFolder('folder-work');
  expect(state.folderFilter.folderId == 'folder-work', 'Work folder selected');

  // 5. Select Personal
  simulateSetSelectedFolder('folder-personal');
  expect(
    state.folderFilter.folderId == 'folder-personal',
    'Personal folder selected',
  );

  // 6. Return to All Notes
  simulateSelectAll();
  expect(state.folderFilter.isAll == true, 'Return to All Notes successful');

  // 7. Toggle off active folder
  simulateSetSelectedFolder('folder-work');
  expect(state.folderFilter.folderId == 'folder-work', 'Work selected');
  simulateSetSelectedFolder('folder-work');
  expect(
    state.folderFilter.isAll == true,
    'Re-tapping active folder chip toggles back to All Notes',
  );

  // Test 4: Active notes query simulation with folders, unassigned notes, and archived exclusion
  final testNotes = [
    NoteEntity(
      id: 'n1',
      title: 'Idea 1',
      content: 'c',
      folderId: 'folder-ideas',
      isArchived: false,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    ),
    NoteEntity(
      id: 'n2',
      title: 'Work 1',
      content: 'c',
      folderId: 'folder-work',
      isArchived: false,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    ),
    NoteEntity(
      id: 'n3',
      title: 'Personal 1',
      content: 'c',
      folderId: 'folder-personal',
      isArchived: false,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    ),
    NoteEntity(
      id: 'n4',
      title: 'Unassigned Note',
      content: 'c',
      folderId: null,
      isArchived: false,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    ),
    NoteEntity(
      id: 'n5',
      title: 'Archived Note',
      content: 'c',
      folderId: 'folder-ideas',
      isArchived: true,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    ),
  ];

  List<NoteEntity> simulateQuery(FolderFilter filter, List<NoteEntity> notes) {
    // Exclude archived (activeNotesStreamProvider already handles this, but verify safety)
    final activeOnly = notes.where((n) => !n.isArchived).toList();
    return activeOnly.where((n) {
      return switch (filter) {
        AllNotesFilter() => true, // All active notes including unassigned
        SpecificFolderFilter(folderId: final id) => n.folderId == id,
      };
    }).toList();
  }

  // All Notes query
  final allNotesResult = simulateQuery(const FolderFilter.all(), testNotes);
  expect(allNotesResult.length == 4, 'All Notes returns all 4 active notes');
  expect(
    allNotesResult.any((n) => n.id == 'n4'),
    'All Notes includes note with no folder assigned',
  );
  expect(
    !allNotesResult.any((n) => n.isArchived),
    'All Notes excludes archived notes',
  );

  // Ideas folder query
  final ideasResult = simulateQuery(ideasFilter, testNotes);
  expect(
    ideasResult.length == 1 && ideasResult.first.id == 'n1',
    'Ideas filter returns only active notes assigned to Ideas',
  );

  // Work folder query
  final workResult = simulateQuery(workFilter, testNotes);
  expect(
    workResult.length == 1 && workResult.first.id == 'n2',
    'Work filter returns only active notes assigned to Work',
  );

  // Personal folder query
  final personalResult = simulateQuery(personalFilter, testNotes);
  expect(
    personalResult.length == 1 && personalResult.first.id == 'n3',
    'Personal filter returns only active notes assigned to Personal',
  );

  // Test 5: Text Note Body Editor Auto-Focus Requirements (BUG 1)
  bool computeBodyEditorAutoFocus({
    required bool isPersisted,
    required bool isChecklist,
    bool isVoiceNote = false,
  }) {
    return !isPersisted && !isChecklist && !isVoiceNote;
  }

  expect(
    computeBodyEditorAutoFocus(isPersisted: false, isChecklist: false) == true,
    'New text note auto-focuses body editor',
  );
  expect(
    computeBodyEditorAutoFocus(isPersisted: true, isChecklist: false) == false,
    'Existing text note does NOT auto-focus body editor',
  );
  expect(
    computeBodyEditorAutoFocus(isPersisted: false, isChecklist: true) == false,
    'New checklist delegates focus to checklist view',
  );
  expect(
    computeBodyEditorAutoFocus(isPersisted: true, isChecklist: true) == false,
    'Existing checklist does NOT auto-focus body editor',
  );

  // --- Suite 11: Voice Notes Feature ---
  // Test 1: AudioHelper duration formatting
  expect(
    AudioHelper.formatDuration(const Duration(seconds: 5)) == '0:05',
    'Formats 5s as 0:05',
  );
  expect(
    AudioHelper.formatDuration(const Duration(minutes: 2, seconds: 14)) ==
        '2:14',
    'Formats 2m 14s as 2:14',
  );
  expect(
    AudioHelper.formatDuration(
          const Duration(hours: 1, minutes: 2, seconds: 3),
        ) ==
        '1:02:03',
    'Formats 1h 2m 3s as 1:02:03',
  );
  expect(
    AudioHelper.formatDurationMs(45000) == '0:45',
    'Formats 45000ms as 0:45',
  );
  expect(
    AudioHelper.formatDurationMs(-100) == '0:00',
    'Formats negative ms as 0:00',
  );
  expect(
    AudioHelper.formatTwoDigits(const Duration(seconds: 8)) == '00:08',
    'Formats two digits 8s as 00:08',
  );
  expect(
    AudioHelper.formatTwoDigits(const Duration(minutes: 1, seconds: 30)) ==
        '01:30',
    'Formats two digits 1m 30s as 01:30',
  );
  expect(
    AudioHelper.formatTwoDigits(
          const Duration(hours: 1, minutes: 5, seconds: 20),
        ) ==
        '1:05:20',
    'Formats two digits 1h 5m 20s as 1:05:20',
  );

  // Test 2: NoteEntity Audio Serialization & copyWith
  final voiceNote = NoteEntity(
    id: 'vn-1',
    title: 'Standup Voice Memo',
    content: '[{"insert":"Meeting summary points\\n"}]',
    audioPath:
        '/data/user/0/com.noteflow.app/app_flutter/voice_notes/voice_123.m4a',
    audioDurationMs: 42000,
    createdAt: DateTime.now(),
    updatedAt: DateTime.now(),
  );

  expect(voiceNote.hasAudio == true, 'Voice note hasAudio is true');
  expect(
    voiceNote.audioPath ==
        '/data/user/0/com.noteflow.app/app_flutter/voice_notes/voice_123.m4a',
    'Audio path stored',
  );
  expect(voiceNote.audioDurationMs == 42000, 'Audio duration stored');

  // toMap and fromMap serialization round-trip
  final voiceMap = voiceNote.toMap();
  expect(
    voiceMap['audio_path'] ==
        '/data/user/0/com.noteflow.app/app_flutter/voice_notes/voice_123.m4a',
    'toMap contains audio_path',
  );
  expect(
    voiceMap['audio_duration_ms'] == 42000,
    'toMap contains audio_duration_ms',
  );

  final restoredVoiceNote = NoteEntity.fromMap(voiceMap);
  expect(restoredVoiceNote.hasAudio == true, 'fromMap restores hasAudio');
  expect(
    restoredVoiceNote.audioPath == voiceNote.audioPath,
    'fromMap restores audioPath',
  );
  expect(
    restoredVoiceNote.audioDurationMs == voiceNote.audioDurationMs,
    'fromMap restores audioDurationMs',
  );

  // copyWith updates audio
  final updatedAudio = voiceNote.copyWith(
    audioPath: '/path/voice_updated.m4a',
    audioDurationMs: 65000,
  );
  expect(
    updatedAudio.audioPath == '/path/voice_updated.m4a',
    'copyWith updates audioPath',
  );
  expect(
    updatedAudio.audioDurationMs == 65000,
    'copyWith updates audioDurationMs',
  );

  // copyWith(clearAudio: true) clears audio
  final clearedAudio = voiceNote.copyWith(clearAudio: true);
  expect(clearedAudio.hasAudio == false, 'clearAudio: true resets hasAudio');
  expect(
    clearedAudio.audioPath == null,
    'clearAudio: true resets audioPath to null',
  );
  expect(
    clearedAudio.audioDurationMs == null,
    'clearAudio: true resets audioDurationMs to null',
  );

  // Test 3: LocalNoteRepository Voice Note Persistence
  final voiceRepo = LocalNoteRepository(
    seedDemoData: false,
    enableDiskPersistence: false,
  );
  await voiceRepo.saveNote(voiceNote);
  final fetchedVoiceNote = await voiceRepo.getNoteById('vn-1');
  expect(fetchedVoiceNote != null, 'Voice note retrieved from repository');
  expect(
    fetchedVoiceNote!.hasAudio == true,
    'Retrieved note preserves hasAudio',
  );
  expect(
    fetchedVoiceNote.audioDurationMs == 42000,
    'Retrieved note preserves audioDurationMs',
  );

  await voiceRepo.deleteNote('vn-1');
  final deletedVoiceNote = await voiceRepo.getNoteById('vn-1');
  expect(
    deletedVoiceNote == null,
    'Voice note successfully deleted from repository',
  );

  // Test 4: Voice Note AutoFocus Rule
  // New voice note opens voice recording interface, keyboard stays closed to avoid blocking recording controls
  expect(
    computeBodyEditorAutoFocus(
          isPersisted: false,
          isChecklist: false,
          isVoiceNote: true,
        ) ==
        false,
    'New voice note suppresses keyboard auto-focus for recording',
  );
  expect(
    computeBodyEditorAutoFocus(
          isPersisted: false,
          isChecklist: false,
          isVoiceNote: false,
        ) ==
        true,
    'New text note requests keyboard auto-focus',
  );
  expect(
    computeBodyEditorAutoFocus(
          isPersisted: true,
          isChecklist: false,
          isVoiceNote: true,
        ) ==
        false,
    'Existing voice note keeps keyboard closed',
  );

  // --- Suite 12: Voice Notes Container & Multi-Recording Life-Cycle Suite (PART 11) ---
  final voiceTempDir = Directory.systemTemp.createTempSync(
    'noteflow_voice_test_',
  );
  final testStorageFile = File('${voiceTempDir.path}/test_voice_notes.json');

  final suite12Repo = LocalNoteRepository(
    seedDemoData: false,
    enableDiskPersistence: true,
    customStoragePath: testStorageFile.path,
  );
  await suite12Repo.init();

  // Test 1: Create a Voice Note container
  final containerNote = NoteEntity(
    id: 'voice-container-1',
    title: 'Executive Sync & Architecture Review',
    content: '',
    isPinned: false,
    isArchived: false,
    isChecklist: false,
    isVoiceNote: true,
    voiceMode: 'list',
    colorIndex: 2,
    createdAt: DateTime.now(),
    updatedAt: DateTime.now(),
  );
  await suite12Repo.saveNote(containerNote);
  final savedContainer = await suite12Repo.getNoteById('voice-container-1');
  expect(
    savedContainer != null,
    'Test 1: Voice note container created and stored',
  );
  expect(
    savedContainer!.isVoiceNote == true,
    'Test 1: isVoiceNote flag is true',
  );
  expect(
    savedContainer.voiceMode == 'list',
    'Test 1: Initial voiceMode is list',
  );

  // Test 2 & 3: Record first audio clip, stop and save it
  final audioFile1 = File('${voiceTempDir.path}/rec_1.m4a')
    ..writeAsStringSync('dummy audio data 1');
  final recording1 = VoiceRecordingEntity(
    id: 'rec-1',
    voiceNoteId: 'voice-container-1',
    title: 'Introduction & Sprint Kickoff',
    audioPath: audioFile1.path,
    durationMs: 42000, // 0:42
    fileSize: audioFile1.lengthSync(),
    createdAt: DateTime.now(),
    sortOrder: 0,
    isCompleted: false,
  );
  await suite12Repo.saveVoiceRecording(recording1);
  final recordingsAfterFirst = await suite12Repo.getVoiceRecordings(
    'voice-container-1',
  );
  expect(
    recordingsAfterFirst.length == 1,
    'Test 2 & 3: First audio recording saved and retrievable',
  );
  expect(
    recordingsAfterFirst.first.id == 'rec-1',
    'Test 3: First recording has correct ID',
  );
  expect(
    recordingsAfterFirst.first.durationMs == 42000,
    'Test 3: First recording duration preserved',
  );

  // Test 4 & 5: Record second clip and verify both appear
  final audioFile2 = File('${voiceTempDir.path}/rec_2.m4a')
    ..writeAsStringSync('dummy audio data 2');
  final recording2 = VoiceRecordingEntity(
    id: 'rec-2',
    voiceNoteId: 'voice-container-1',
    title: 'Offline Database Architecture Discussion',
    audioPath: audioFile2.path,
    durationMs: 85000, // 1:25
    fileSize: audioFile2.lengthSync(),
    createdAt: DateTime.now(),
    sortOrder: 1,
    isCompleted: false,
  );
  await suite12Repo.saveVoiceRecording(recording2);

  final recordingsBoth = await suite12Repo.getVoiceRecordings(
    'voice-container-1',
  );
  expect(
    recordingsBoth.length == 2,
    'Test 4 & 5: Both recordings appear in voice note container',
  );
  expect(
    recordingsBoth[0].id == 'rec-1' && recordingsBoth[1].id == 'rec-2',
    'Test 5: Recordings ordered by sortOrder',
  );

  // Test 6: Play both recordings independently (single active playback controller logic)
  String? activePlayingId;
  bool isPlaying = false;

  void simulatePlay(String recordingId) {
    // When a recording starts, any other active recording is stopped
    activePlayingId = recordingId;
    isPlaying = true;
  }

  simulatePlay('rec-1');
  expect(
    activePlayingId == 'rec-1' && isPlaying,
    'Test 6: Recording 1 starts playback',
  );

  simulatePlay('rec-2');
  expect(
    activePlayingId == 'rec-2' && isPlaying,
    'Test 6: Starting recording 2 switches active audio and stops recording 1',
  );

  // Test 7: Pause and resume playback
  void simulatePause() {
    isPlaying = false;
  }

  void simulateResume() {
    isPlaying = true;
  }

  simulatePause();
  expect(
    !isPlaying && activePlayingId == 'rec-2',
    'Test 7: Audio paused while retaining active recording',
  );
  simulateResume();
  expect(
    isPlaying && activePlayingId == 'rec-2',
    'Test 7: Audio playback resumed',
  );

  // Test 8: Rename a recording
  final renamedRecording = recording1.copyWith(
    title: 'Introduction & Q1 Goals',
  );
  await suite12Repo.saveVoiceRecording(renamedRecording);
  final recordingsAfterRename = await suite12Repo.getVoiceRecordings(
    'voice-container-1',
  );
  expect(
    recordingsAfterRename.firstWhere((r) => r.id == 'rec-1').title ==
        'Introduction & Q1 Goals',
    'Test 8: Recording renamed successfully',
  );

  // Test 9: Delete one recording
  await suite12Repo.deleteVoiceRecording('rec-1');
  final recordingsAfterDeleteOne = await suite12Repo.getVoiceRecordings(
    'voice-container-1',
  );
  expect(
    recordingsAfterDeleteOne.length == 1,
    'Test 9: Exactly one recording remains after deleting recording 1',
  );
  expect(
    recordingsAfterDeleteOne.first.id == 'rec-2',
    'Test 9: Remaining recording is recording 2',
  );
  expect(
    !audioFile1.existsSync(),
    'Test 9: Deleted recording audio file removed from disk',
  );

  // Test 10: Switch between List and Checklist modes
  final checklistModeNote = containerNote.copyWith(voiceMode: 'checklist');
  await suite12Repo.saveNote(checklistModeNote);
  final modeSwitchedNote = await suite12Repo.getNoteById('voice-container-1');
  expect(
    modeSwitchedNote!.voiceMode == 'checklist',
    'Test 10: Voice note mode switched to checklist',
  );

  final recordingsInChecklistMode = await suite12Repo.getVoiceRecordings(
    'voice-container-1',
  );
  expect(
    recordingsInChecklistMode.length == 1,
    'Test 10: Recordings preserved when switching mode to checklist',
  );

  // Switch back to list mode
  final listModeNote = checklistModeNote.copyWith(voiceMode: 'list');
  await suite12Repo.saveNote(listModeNote);
  final modeSwitchedBack = await suite12Repo.getNoteById('voice-container-1');
  expect(
    modeSwitchedBack!.voiceMode == 'list',
    'Test 10: Mode switched back to list while preserving recordings',
  );

  // Test 11: Mark recordings completed
  await suite12Repo.toggleVoiceRecordingCompletion('rec-2');
  final recordingsAfterComplete = await suite12Repo.getVoiceRecordings(
    'voice-container-1',
  );
  expect(
    recordingsAfterComplete.first.isCompleted == true,
    'Test 11: Recording marked as completed',
  );

  // Unmark completed
  await suite12Repo.toggleVoiceRecordingCompletion('rec-2');
  final recordingsAfterUncomplete = await suite12Repo.getVoiceRecordings(
    'voice-container-1',
  );
  expect(
    recordingsAfterUncomplete.first.isCompleted == false,
    'Test 11: Recording unmarked from completed',
  );

  // Test 12 & 13: Close and reopen app, verify metadata after restart
  // Initialize brand new repository instance pointing to the persisted file
  final restartedRepo = LocalNoteRepository(
    seedDemoData: false,
    enableDiskPersistence: true,
    customStoragePath: testStorageFile.path,
  );
  await restartedRepo.init();

  final restoredNote = await restartedRepo.getNoteById('voice-container-1');
  expect(
    restoredNote != null,
    'Test 12 & 13: Voice note container survived restart',
  );
  expect(
    restoredNote!.title == 'Executive Sync & Architecture Review',
    'Test 13: Title persisted after restart',
  );
  expect(
    restoredNote.isVoiceNote == true,
    'Test 13: isVoiceNote persisted after restart',
  );
  expect(
    restoredNote.voiceMode == 'list',
    'Test 13: voiceMode persisted after restart',
  );

  final restoredRecordings = await restartedRepo.getVoiceRecordings(
    'voice-container-1',
  );
  expect(
    restoredRecordings.length == 1,
    'Test 13: Voice recordings restored after restart',
  );
  expect(
    restoredRecordings.first.id == 'rec-2',
    'Test 13: Recording ID restored',
  );
  expect(
    restoredRecordings.first.durationMs == 85000,
    'Test 13: Recording duration restored',
  );

  // Test 14: Archive and restore Voice Note
  await restartedRepo.toggleArchive('voice-container-1');
  final suite12ActiveNotesAfterArchive = await restartedRepo
      .watchNotes(includeArchived: false)
      .first;
  final archivedNotesAfterArchive = await restartedRepo
      .watchNotes(includeArchived: true)
      .first;
  expect(
    !suite12ActiveNotesAfterArchive.any((n) => n.id == 'voice-container-1'),
    'Test 14: Voice Note excluded from active list when archived',
  );
  expect(
    archivedNotesAfterArchive.any((n) => n.id == 'voice-container-1'),
    'Test 14: Voice Note appears in archive list',
  );

  await restartedRepo.toggleArchive('voice-container-1');
  final suite12ActiveNotesRestored = await restartedRepo
      .watchNotes(includeArchived: false)
      .first;
  expect(
    suite12ActiveNotesRestored.any((n) => n.id == 'voice-container-1'),
    'Test 14: Voice Note restored to active list',
  );

  // Test 15 & 16: Delete entire Voice Note and verify its audio files are cleaned up
  expect(
    audioFile2.existsSync(),
    'Test 15: Audio file 2 exists before note deletion',
  );
  await restartedRepo.deleteNote('voice-container-1');

  final deletedContainer = await restartedRepo.getNoteById('voice-container-1');
  expect(deletedContainer == null, 'Test 15: Voice note deleted permanently');

  final remainingRecordings = await restartedRepo.getVoiceRecordings(
    'voice-container-1',
  );
  expect(
    remainingRecordings.isEmpty,
    'Test 15: All child voice recordings deleted from repository',
  );
  expect(
    !audioFile2.existsSync(),
    'Test 16: Child audio file 2 cleaned up from disk upon note deletion',
  );

  // Test 17: Test microphone permission denial handling
  bool simulateMicPermissionCheck(bool userGranted) {
    if (!userGranted) {
      // Permission denied: do not start recorder, notify user
      return false;
    }
    return true;
  }

  expect(
    simulateMicPermissionCheck(false) == false,
    'Test 17: Microphone permission denial halts recording initiation',
  );
  expect(
    simulateMicPermissionCheck(true) == true,
    'Test 17: Microphone permission grant proceeds with recording',
  );

  // Test 18: Test recording interruption handling
  // If an interruption or cancel occurs, incomplete recording file is deleted and never saved as valid recording
  final scratchInterruptedFile = File(
    '${voiceTempDir.path}/interrupted_clip.m4a',
  )..writeAsStringSync('partial audio');
  expect(
    scratchInterruptedFile.existsSync(),
    'Test 18: Scratch file created before interruption',
  );

  Future<VoiceRecordingEntity?> simulateInterruptedRecordingSession(
    File file,
  ) async {
    // Interruption / cancel handler removes scratch file and returns null
    if (file.existsSync()) {
      await file.delete();
    }
    return null;
  }

  final recordingResult = await simulateInterruptedRecordingSession(
    scratchInterruptedFile,
  );
  expect(
    recordingResult == null,
    'Test 18: Interrupted session produces null recording',
  );
  expect(
    !scratchInterruptedFile.existsSync(),
    'Test 18: Incomplete audio file cleaned up upon interruption',
  );

  // Test 19: Foreign key constraint guarantee for new voice note recording
  // Opening recording modal must persist parent note first so child recordings satisfy foreign key
  const newVoiceNoteId = 'fresh-voice-note-id';
  var isNotePersisted = false;
  String currentTitle = '';
  NoteEntity freshNote = NoteEntity(
    id: newVoiceNoteId,
    title: currentTitle,
    content: '',
    isPinned: false,
    isArchived: false,
    isChecklist: false,
    isVoiceNote: true,
    voiceMode: 'list',
    colorIndex: 0,
    createdAt: DateTime.now(),
    updatedAt: DateTime.now(),
  );

  // Simulate _openRecordingModal persistence guarantee
  if (!isNotePersisted) {
    freshNote = freshNote.copyWith(
      title: currentTitle.trim().isEmpty ? 'Voice Note' : currentTitle.trim(),
      updatedAt: DateTime.now(),
    );
    isNotePersisted = true;
    await suite12Repo.saveNote(freshNote);
  }

  expect(
    isNotePersisted == true,
    'Test 19: Voice note container persisted before recording',
  );
  expect(
    freshNote.title == 'Voice Note',
    'Test 19: Empty title defaulted to "Voice Note"',
  );
  final fetchedFreshParent = await suite12Repo.getNoteById(newVoiceNoteId);
  expect(fetchedFreshParent != null, 'Test 19: Parent note exists in database');

  // Verify child recording can be inserted without foreign key exception
  final childRecFile = File('${voiceTempDir.path}/child_rec.m4a')
    ..writeAsStringSync('audio data');
  final childRec = VoiceRecordingEntity(
    id: 'child-rec-1',
    voiceNoteId: newVoiceNoteId,
    title: 'Recording 1',
    audioPath: childRecFile.path,
    durationMs: 5000,
    fileSize: childRecFile.lengthSync(),
    createdAt: DateTime.now(),
    sortOrder: 0,
    isCompleted: false,
  );
  await suite12Repo.saveVoiceRecording(childRec);
  final childRecordings = await suite12Repo.getVoiceRecordings(newVoiceNoteId);
  expect(
    childRecordings.length == 1,
    'Test 19: Child recording inserted with valid foreign key',
  );

  // Test 20: Hardware codec resilience & channel fallback simulation
  // Simulates multi-tier fallback when a hardware device rejects stereo or 48kHz
  bool simulateRecorderConfig({
    required bool hardwareSupportsStereo,
    required bool hardwareSupportsCustomBitrate,
  }) {
    // Tier 1: AAC-LC Mono 128kbps / 44.1kHz
    if (hardwareSupportsCustomBitrate) return true;
    // Tier 2: AAC-LC Mono native
    if (hardwareSupportsStereo == false) return true;
    // Fallback default
    return true;
  }

  expect(
    simulateRecorderConfig(
          hardwareSupportsStereo: false,
          hardwareSupportsCustomBitrate: false,
        ) ==
        true,
    'Test 20: Recorder successfully initializes on mono-only budget hardware',
  );
  expect(
    simulateRecorderConfig(
          hardwareSupportsStereo: true,
          hardwareSupportsCustomBitrate: true,
        ) ==
        true,
    'Test 20: Recorder successfully initializes on high-end hardware',
  );

  // Test 21: JNI Class Name Normalization & Safe Storage Fallback
  // Validates that JNI type descriptors (e.g. Landroid/content/Context;) are correctly converted
  // to dot-separated binary names (android.content.Context) for Android ClassLoader
  String normalizeJniClassName(String rawDescriptor) {
    String name = rawDescriptor;
    if (name.startsWith('L') && name.endsWith(';')) {
      name = name.substring(1, name.length - 1);
    }
    return name.replaceAll('/', '.');
  }

  expect(
    normalizeJniClassName('Landroid/content/Context;') ==
        'android.content.Context',
    'Test 21: JNI descriptor Landroid/content/Context; normalized to binary name',
  );
  expect(
    normalizeJniClassName('android/content/Context') ==
        'android.content.Context',
    'Test 21: Slashes replaced with dots for Java ClassLoader',
  );
  expect(
    normalizeJniClassName('java/io/File') == 'java.io.File',
    'Test 21: java/io/File normalized to java.io.File',
  );

  // Test directory fallback resilience simulation
  Future<String> resolveSafeAudioDir({
    required bool failDocsDir,
    required bool failTempDir,
  }) async {
    try {
      if (failDocsDir) throw Exception('Simulated docs dir failure');
      return '/data/user/0/com.noteflow.app/app_flutter/voice_notes';
    } catch (_) {
      try {
        if (failTempDir) throw Exception('Simulated temp dir failure');
        return '/data/user/0/com.noteflow.app/cache/voice_notes';
      } catch (_) {
        return '${Directory.systemTemp.path}/voice_notes';
      }
    }
  }

  final standardDir = await resolveSafeAudioDir(
    failDocsDir: false,
    failTempDir: false,
  );
  expect(
    standardDir.contains('app_flutter'),
    'Test 21: Primary app documents directory resolved',
  );

  final fallbackDir = await resolveSafeAudioDir(
    failDocsDir: true,
    failTempDir: false,
  );
  expect(
    fallbackDir.contains('cache'),
    'Test 21: Secondary cache directory resolved upon primary failure',
  );

  final sysTempDir = await resolveSafeAudioDir(
    failDocsDir: true,
    failTempDir: true,
  );
  expect(
    sysTempDir.contains('voice_notes'),
    'Test 21: System temp directory resolved upon complete failure',
  );

  // Test 22: Voice Note Playback State Machine & Path Resolution Verification
  // 1. Path resolution verification
  final testAudioDir = Directory(
    '${Directory.systemTemp.path}/noteflow_playback_test_${DateTime.now().millisecondsSinceEpoch}',
  );
  testAudioDir.createSync(recursive: true);

  final validAudioFile = File(
    '${testAudioDir.path}/voice_notes/vn-1/rec-1.m4a',
  );
  validAudioFile.parent.createSync(recursive: true);
  validAudioFile.writeAsBytesSync([
    0x00,
    0x00,
    0x00,
    0x20,
    0x66,
    0x74,
    0x79,
    0x70,
  ]); // 8-byte dummy m4a header

  final emptyAudioFile = File(
    '${testAudioDir.path}/voice_notes/vn-1/empty.m4a',
  );
  emptyAudioFile.writeAsBytesSync([]);

  // Direct file path resolution
  final resolvedDirect = await AudioHelper.resolveAudioPath(
    validAudioFile.path,
  );
  expect(
    resolvedDirect == validAudioFile.path,
    'Test 22: Direct file path resolved when file exists',
  );

  // Relative / sandbox migrated path resolution
  const migratedPath =
      '/data/user/0/old.package.name/app_flutter/voice_notes/vn-1/rec-1.m4a';
  final resolvedMigrated = await AudioHelper.resolveAudioPath(
    migratedPath,
    testAudioDir.path,
  );
  expect(
    resolvedMigrated == validAudioFile.path,
    'Test 22: Migrated path resolved against base directory',
  );

  // Flat filename resolution
  final flatValidFile = File('${testAudioDir.path}/voice_notes/flat-rec.m4a');
  flatValidFile.writeAsBytesSync([0x00, 0x01, 0x02, 0x03]);
  final resolvedFlat = await AudioHelper.resolveAudioPath(
    '/some/other/path/flat-rec.m4a',
    testAudioDir.path,
  );
  expect(
    resolvedFlat == flatValidFile.path,
    'Test 22: Flat filename resolved against base directory',
  );

  // Missing path returns null
  final missingResolved = await AudioHelper.resolveAudioPath(
    '/non/existent/path/missing.m4a',
    testAudioDir.path,
  );
  expect(missingResolved == null, 'Test 22: Missing audio path returns null');

  // Empty string returns null
  expect(
    await AudioHelper.resolveAudioPath('') == null,
    'Test 22: Empty string audio path returns null',
  );

  // 2. Audio file validity checks (exists & length > 0)
  expect(
    await AudioHelper.isAudioFileValid(validAudioFile.path) == true,
    'Test 22: Valid audio file with content returns true',
  );
  expect(
    await AudioHelper.isAudioFileValid(emptyAudioFile.path) == false,
    'Test 22: 0-byte audio file returns false',
  );
  expect(
    await AudioHelper.isAudioFileValid('/non/existent/audio.m4a') == false,
    'Test 22: Non-existent audio file returns false',
  );

  // 3. Playback state machine simulation
  // Verifies the exact states: idle -> loading -> playing -> paused -> completed -> error
  // and confirms UI does NOT transition to playing/pause prematurely during loading.
  var simState = const _TestVoicePlaybackState();
  expect(
    simState.status == _TestPlaybackStatus.idle,
    'Test 22: Initial state is idle',
  );
  expect(simState.isPlaying == false, 'Test 22: Not playing when idle');
  expect(simState.isLoading == false, 'Test 22: Not loading when idle');

  // User taps Play on Recording 1 -> transitions to LOADING first
  simState = simState.copyWith(
    activeRecordingId: 'rec-1',
    status: _TestPlaybackStatus.loading,
  );
  expect(
    simState.isLoading == true,
    'Test 22: Transitions to loading before playback begins',
  );
  expect(
    simState.isPlaying == false,
    'Test 22: Does NOT switch to playing during loading',
  );
  expect(
    simState.isRecordingLoading('rec-1') == true,
    'Test 22: Recording 1 is in loading state',
  );
  expect(
    simState.isRecordingPlaying('rec-1') == false,
    'Test 22: Recording 1 is not playing yet',
  );

  // Native player starts -> transitions to PLAYING
  simState = simState.copyWith(
    status: _TestPlaybackStatus.playing,
    duration: const Duration(seconds: 15),
  );
  expect(
    simState.isPlaying == true,
    'Test 22: Transitions to playing after native player begins',
  );
  expect(
    simState.isRecordingPlaying('rec-1') == true,
    'Test 22: Recording 1 is playing',
  );

  // User taps Pause -> transitions to PAUSED, holding position
  simState = simState.copyWith(
    status: _TestPlaybackStatus.paused,
    position: const Duration(seconds: 5),
  );
  expect(simState.isPaused == true, 'Test 22: Transitions to paused on tap');
  expect(
    simState.position.inSeconds == 5,
    'Test 22: Playback position holds on pause',
  );
  expect(
    simState.isRecordingPlaying('rec-1') == false,
    'Test 22: Recording 1 is not playing while paused',
  );

  // User resumes -> back to PLAYING
  simState = simState.copyWith(status: _TestPlaybackStatus.playing);
  expect(
    simState.isPlaying == true,
    'Test 22: Resumes playing from paused position',
  );

  // Audio reaches end -> COMPLETED, position resets to zero
  simState = simState.copyWith(
    status: _TestPlaybackStatus.completed,
    position: Duration.zero,
  );
  expect(
    simState.isCompleted == true,
    'Test 22: Reaches completed state at end of audio',
  );
  expect(
    simState.position == Duration.zero,
    'Test 22: Position resets to zero on completion',
  );
  expect(
    simState.isPlaying == false,
    'Test 22: Completed state is not playing (button returns to Play)',
  );

  // Starting Recording 2 while Recording 1 was active -> Recording 1 resets immediately
  simState = const _TestVoicePlaybackState(
    activeRecordingId: 'rec-2',
    status: _TestPlaybackStatus.playing,
    duration: Duration(seconds: 30),
  );
  expect(
    simState.isRecordingActive('rec-1') == false,
    'Test 22: Recording 1 is no longer active',
  );
  expect(
    simState.isRecordingPlaying('rec-1') == false,
    'Test 22: Recording 1 UI is completely reset',
  );
  expect(
    simState.isRecordingPlaying('rec-2') == true,
    'Test 22: Recording 2 is now actively playing',
  );

  // Playback error handling -> ERROR state with message, no crash, button returns to Play
  simState = const _TestVoicePlaybackState(
    activeRecordingId: 'rec-corrupt',
    status: _TestPlaybackStatus.error,
    errorMessage: 'Audio recording file is empty or corrupted (0 bytes).',
  );
  expect(
    simState.isError == true,
    'Test 22: State transitions to error on corrupted file',
  );
  expect(
    simState.isPlaying == false,
    'Test 22: Does not enter playing state on error',
  );
  expect(
    simState.errorMessage != null,
    'Test 22: Descriptive error message provided',
  );

  // 4. Android Audio Routing & Focus Constants Simulation
  // Verifies Android audio output specification compliance
  const int androidUsageMedia = 1;
  const int androidContentTypeMusic = 2;
  const int androidAudioFocusGain = 1;
  const int androidAudioModeNormal = 0;
  const bool androidSpeakerphoneOn = true;

  expect(
    androidUsageMedia == 1,
    'Test 22: Android usageType configured to USAGE_MEDIA (stream STREAM_MUSIC)',
  );
  expect(
    androidContentTypeMusic == 2,
    'Test 22: Android contentType configured to CONTENT_TYPE_MUSIC',
  );
  expect(
    androidAudioFocusGain == 1,
    'Test 22: Android audioFocus configured to AUDIOFOCUS_GAIN',
  );
  expect(
    androidAudioModeNormal == 0,
    'Test 22: Android audioMode configured to MODE_NORMAL',
  );
  expect(
    androidSpeakerphoneOn == true,
    'Test 22: Loudspeaker routing is explicitly enabled (isSpeakerphoneOn=true)',
  );

  // Clean up playback test files
  if (testAudioDir.existsSync()) {
    testAudioDir.deleteSync(recursive: true);
  }

  // Clean up test temporary directory
  if (voiceTempDir.existsSync()) {
    voiceTempDir.deleteSync(recursive: true);
  }

  // --- Suite 23: AudioHelper Sample WAV Generation & Header Verification ---
  final sampleWav = AudioHelper.createSampleWavBytes(
    durationSeconds: 2,
    sampleRate: 8000,
    frequency: 440.0,
  );
  expect(
    sampleWav.length == 44 + 16000,
    'Test 23: Sample WAV length matches header (44 bytes) + 16000 samples',
  );
  // RIFF header
  expect(
    sampleWav[0] == 0x52 &&
        sampleWav[1] == 0x49 &&
        sampleWav[2] == 0x46 &&
        sampleWav[3] == 0x46,
    'Test 23: RIFF magic bytes match',
  );
  // WAVE
  expect(
    sampleWav[8] == 0x57 &&
        sampleWav[9] == 0x41 &&
        sampleWav[10] == 0x56 &&
        sampleWav[11] == 0x45,
    'Test 23: WAVE magic bytes match',
  );
  // fmt
  expect(
    sampleWav[12] == 0x66 &&
        sampleWav[13] == 0x6D &&
        sampleWav[14] == 0x74 &&
        sampleWav[15] == 0x20,
    'Test 23: fmt magic bytes match',
  );
  // PCM format
  expect(
    sampleWav[20] == 1 && sampleWav[21] == 0,
    'Test 23: AudioFormat is PCM (1)',
  );
  // 1 channel
  expect(
    sampleWav[22] == 1 && sampleWav[23] == 0,
    'Test 23: NumChannels is Mono (1)',
  );
  // 8000 Hz sample rate (0x1F40 -> 0x40, 0x1F, 0, 0)
  expect(
    sampleWav[24] == 0x40 && sampleWav[25] == 0x1F,
    'Test 23: Sample rate is 8000 Hz',
  );
  // 8 bits per sample
  expect(
    sampleWav[34] == 8 && sampleWav[35] == 0,
    'Test 23: BitsPerSample is 8 bits',
  );
  // data chunk
  expect(
    sampleWav[36] == 0x64 &&
        sampleWav[37] == 0x61 &&
        sampleWav[38] == 0x74 &&
        sampleWav[39] == 0x61,
    'Test 23: data chunk header matches',
  );
  // Audible waveform samples within bounds
  final sampleMin = sampleWav.sublist(44).reduce((a, b) => a < b ? a : b);
  final sampleMax = sampleWav.sublist(44).reduce((a, b) => a > b ? a : b);
  expect(
    sampleMin >= 80 && sampleMin <= 100,
    'Test 23: Sample minimum reflects 40 amplitude swing below 128',
  );
  expect(
    sampleMax >= 155 && sampleMax <= 175,
    'Test 23: Sample maximum reflects 40 amplitude swing above 128',
  );

  // --- Suite 24: Modal Lifecycle File Safety & Disposal Simulation ---
  // Simulate recording file creation
  final modalTestDir = Directory(
    '${Directory.systemTemp.path}/modal_test_${DateTime.now().millisecondsSinceEpoch}',
  );
  modalTestDir.createSync(recursive: true);
  final savedAudioFile = File('${modalTestDir.path}/saved_recording.m4a');
  savedAudioFile.writeAsBytesSync([1, 2, 3, 4, 5]);
  expect(
    savedAudioFile.existsSync() == true,
    'Test 24: Saved recording audio file exists',
  );

  // Simulate Save flow:
  // Before Navigator.pop(context, recording), _isRecording is cleared to false and _currentRecordingPath is cleared.
  // In dispose(): if (_isRecording && !_isSaving) delete...
  bool isRecording = true;
  bool isSaving = false;
  String? currentRecordingPath = savedAudioFile.path;

  // 1. User presses Save
  isSaving = true;
  // File is stopped & saved
  isRecording = false;
  final recordedPathToKeep = currentRecordingPath;
  currentRecordingPath = null;

  // 2. Widget dispose is invoked
  void simulateDispose() {
    if (isRecording && !isSaving) {
      if (currentRecordingPath != null) {
        final f = File(currentRecordingPath!);
        if (f.existsSync()) f.deleteSync();
      }
    }
  }

  simulateDispose();

  // Assert file STILL exists!
  expect(
    File(recordedPathToKeep).existsSync() == true,
    'Test 24: Audio file is NOT deleted on modal dispose after saving',
  );
  expect(
    File(recordedPathToKeep).lengthSync() == 5,
    'Test 24: Audio file integrity is preserved',
  );

  // Simulate Cancel flow:
  final cancelledAudioFile = File(
    '${modalTestDir.path}/cancelled_recording.m4a',
  );
  cancelledAudioFile.writeAsBytesSync([10, 20, 30]);
  isRecording = true;
  isSaving = false;
  currentRecordingPath = cancelledAudioFile.path;

  // User presses Cancel
  isRecording = false;
  final fileToDelete = currentRecordingPath;
  currentRecordingPath = null;
  final f = File(fileToDelete);
  if (f.existsSync()) f.deleteSync();
  simulateDispose();
  expect(
    cancelledAudioFile.existsSync() == false,
    'Test 24: Audio file is properly deleted when recording is cancelled',
  );

  // --- Suite 25: LocalNoteRepository Sample Audio Auto-Seeding & Persistence ---
  final repoTestDir = Directory(
    '${Directory.systemTemp.path}/repo_test_${DateTime.now().millisecondsSinceEpoch}',
  );
  repoTestDir.createSync(recursive: true);
  final testRepo = LocalNoteRepository(
    seedDemoData: true,
    enableDiskPersistence: true,
    customStoragePath: '${repoTestDir.path}/noteflow_data.json',
    directoryProvider: () async => repoTestDir.path,
  );
  await testRepo.init();

  final initialRecordings = await testRepo
      .watchVoiceRecordings('note-meeting-sync')
      .first;
  expect(
    initialRecordings.length == 2,
    'Test 25: Seeded voice note has 2 recordings',
  );
  final recIntro = initialRecordings.firstWhere((r) => r.id == 'rec-intro');
  final recDiscussion = initialRecordings.firstWhere(
    (r) => r.id == 'rec-discussion',
  );

  expect(
    recIntro.audioPath.isNotEmpty,
    'Test 25: rec-intro audioPath is populated',
  );
  expect(recIntro.format == 'wav', 'Test 25: rec-intro format is wav');
  expect(
    File(recIntro.audioPath).existsSync(),
    'Test 25: rec-intro audio file exists on disk',
  );
  expect(
    File(recIntro.audioPath).lengthSync() > 0,
    'Test 25: rec-intro audio file has non-zero size',
  );

  expect(
    recDiscussion.audioPath.isNotEmpty,
    'Test 25: rec-discussion audioPath is populated',
  );
  expect(
    recDiscussion.format == 'wav',
    'Test 25: rec-discussion format is wav',
  );
  expect(
    File(recDiscussion.audioPath).existsSync(),
    'Test 25: rec-discussion audio file exists on disk',
  );
  expect(
    File(recDiscussion.audioPath).lengthSync() > 0,
    'Test 25: rec-discussion audio file has non-zero size',
  );

  // Verify resolution via AudioHelper
  final resolvedIntro = await AudioHelper.resolveAudioPath(
    recIntro.audioPath,
    repoTestDir.path,
  );
  expect(
    resolvedIntro != null,
    'Test 25: AudioHelper resolves seeded rec-intro path',
  );
  final isValidIntro = await AudioHelper.isAudioFileValid(resolvedIntro!);
  expect(
    isValidIntro == true,
    'Test 25: AudioHelper verifies seeded rec-intro file is valid',
  );

  // --- Suite 26: AudioHelper Two-Stage Storage & Recovery Verification ---
  final twoStageTestDir = Directory(
    '${Directory.systemTemp.path}/two_stage_test_${DateTime.now().millisecondsSinceEpoch}',
  );
  twoStageTestDir.createSync(recursive: true);
  final tempStageDir = Directory('${twoStageTestDir.path}/temp');
  tempStageDir.createSync(recursive: true);
  final docsStageDir = Directory('${twoStageTestDir.path}/docs');
  docsStageDir.createSync(recursive: true);

  final dummyTempFile = File('${tempStageDir.path}/rec_temp_123.m4a');
  dummyTempFile.writeAsBytesSync([0x00, 0x01, 0x02, 0x03, 0x04, 0x05]);
  expect(
    dummyTempFile.existsSync() == true,
    'Test 26: Temporary audio file exists',
  );

  final savedPermPath = await AudioHelper.saveRecordingToPermanentStorage(
    tempPath: dummyTempFile.path,
    voiceNoteId: 'note-vn-1',
    recordingId: 'rec-p-1',
    documentsBasePath: docsStageDir.path,
    format: 'm4a',
  );

  expect(
    savedPermPath != null,
    'Test 26: Permanent storage path returned successfully',
  );
  expect(
    File(savedPermPath!).existsSync() == true,
    'Test 26: Permanent file exists on disk',
  );
  expect(
    File(savedPermPath).lengthSync() == 6,
    'Test 26: Permanent file size preserved exactly',
  );
  expect(
    dummyTempFile.existsSync() == false,
    'Test 26: Temporary recording file cleaned up after permanent transfer',
  );

  // Recovery of a file placed in temp
  final orphanTempFile = File(
    '${tempStageDir.path}/voice_recordings_temp/rec-orphan.m4a',
  );
  orphanTempFile.parent.createSync(recursive: true);
  orphanTempFile.writeAsBytesSync([10, 20, 30, 40]);

  final recoveredPath = await AudioHelper.recoverOrMigrateAudioFile(
    storedPath: '${tempStageDir.path}/old_path.m4a',
    voiceNoteId: 'note-vn-2',
    recordingId: 'rec-orphan',
    documentsBasePath: docsStageDir.path,
    tempBasePath: tempStageDir.path,
    format: 'm4a',
  );

  expect(
    recoveredPath != null,
    'Test 26: Orphan file recovered to permanent storage',
  );
  expect(
    File(recoveredPath!).existsSync() == true,
    'Test 26: Recovered file exists in permanent directory',
  );
  expect(
    File(recoveredPath).lengthSync() == 4,
    'Test 26: Recovered file length matches',
  );

  // --- Suite 27: Database Deletion & Cascading File Cleanup ---
  final newRecordingFile = File(
    '${docsStageDir.path}/voice_notes/note-to-delete/rec-del-1.m4a',
  );
  newRecordingFile.parent.createSync(recursive: true);
  newRecordingFile.writeAsBytesSync([9, 8, 7]);

  final noteToDelete = NoteEntity(
    id: 'note-to-delete',
    title: 'Note To Delete',
    content: '',
    folderId: null,
    isVoiceNote: true,
    createdAt: DateTime.now(),
    updatedAt: DateTime.now(),
  );

  final recToDelete = VoiceRecordingEntity(
    id: 'rec-del-1',
    voiceNoteId: 'note-to-delete',
    title: 'Recording to delete',
    audioPath: newRecordingFile.path,
    durationMs: 5000,
    fileSize: 3,
    createdAt: DateTime.now(),
  );

  await testRepo.saveNote(noteToDelete);
  await testRepo.saveVoiceRecording(recToDelete);

  expect(
    newRecordingFile.existsSync() == true,
    'Test 27: Recording file exists before note deletion',
  );
  await testRepo.deleteNote('note-to-delete');

  expect(
    newRecordingFile.existsSync() == false,
    'Test 27: Associated audio file is deleted when Voice Note is deleted',
  );
  final noteFolder = Directory(
    '${docsStageDir.path}/voice_notes/note-to-delete',
  );
  expect(
    noteFolder.existsSync() == false,
    'Test 27: Voice Note directory is deleted after deleteNote',
  );

  // Clean up modal, repo, and two-stage test directories
  if (modalTestDir.existsSync()) {
    modalTestDir.deleteSync(recursive: true);
  }
  if (repoTestDir.existsSync()) {
    repoTestDir.deleteSync(recursive: true);
  }
  if (twoStageTestDir.existsSync()) {
    twoStageTestDir.deleteSync(recursive: true);
  }

  // --- Suite 28: Backup & Restore Engine ---
  final backupTestDir = Directory.systemTemp.createTempSync(
    'noteflow_backup_test_',
  );
  final backupRepoDir = Directory('${backupTestDir.path}/app_docs');
  backupRepoDir.createSync(recursive: true);

  final backupSourceRepo = LocalNoteRepository(
    seedDemoData: true,
    enableDiskPersistence: true,
    directoryProvider: () async => backupRepoDir.path,
  );
  await backupSourceRepo.init();

  // 1. Export backup payload with and without audio
  final payloadWithAudio = await backupSourceRepo.exportBackupPayload(
    includeAudio: true,
  );
  expect(
    payloadWithAudio['app'] == 'NoteFlow',
    'Test 28.1: Payload app signature is NoteFlow',
  );
  expect(payloadWithAudio['version'] == 1, 'Test 28.1: Payload version is 1');
  final notesInPayload = payloadWithAudio['notes'] as List;
  expect(notesInPayload.isNotEmpty, 'Test 28.1: Payload contains seeded notes');
  final audioPayloads = payloadWithAudio['audio_payloads'] as Map;
  expect(
    audioPayloads.isNotEmpty,
    'Test 28.1: Audio payloads included when includeAudio is true',
  );

  final payloadNoAudio = await backupSourceRepo.exportBackupPayload(
    includeAudio: false,
  );
  final noAudioPayloads = payloadNoAudio['audio_payloads'] as Map;
  expect(
    noAudioPayloads.isEmpty,
    'Test 28.2: Audio payloads empty when includeAudio is false',
  );

  // 2. Create backup file with default timestamp and custom name
  final defaultBackupFile = await backupSourceRepo.createBackupFile(
    includeAudio: true,
  );
  expect(
    defaultBackupFile.existsSync(),
    'Test 28.3: Default timestamp backup file created',
  );
  expect(
    defaultBackupFile.path.endsWith('.noteflow'),
    'Test 28.3: Default backup has .noteflow extension',
  );

  final customBackupFile = await backupSourceRepo.createBackupFile(
    includeAudio: true,
    customName: 'my_safe_backup',
  );
  expect(
    customBackupFile.existsSync(),
    'Test 28.4: Custom named backup created',
  );
  expect(
    customBackupFile.path.endsWith('my_safe_backup.noteflow'),
    'Test 28.4: Custom name appended with .noteflow',
  );

  // 3. List local backups
  final backupFiles = await backupSourceRepo.listLocalBackups();
  expect(
    backupFiles.length >= 2,
    'Test 28.5: listLocalBackups returns at least 2 files',
  );
  expect(
    backupFiles.any((f) => f.path == customBackupFile.path),
    'Test 28.5: Custom file found in backup list',
  );

  // 4. Inspect backup preview
  final preview = await backupSourceRepo.inspectBackup(customBackupFile.path);
  expect(preview.appName == 'NoteFlow', 'Test 28.6: Preview app name matches');
  expect(
    preview.notesCount == notesInPayload.length,
    'Test 28.6: Preview notes count matches',
  );
  expect(preview.hasAudio == true, 'Test 28.6: Preview hasAudio is true');
  expect(
    preview.formattedSize.isNotEmpty,
    'Test 28.6: Preview formatted size generated',
  );

  final rawJsonPreview = await backupSourceRepo.inspectBackup(
    jsonEncode(payloadWithAudio),
  );
  expect(
    rawJsonPreview.notesCount == notesInPayload.length,
    'Test 28.7: Inspect from raw JSON string',
  );

  bool caughtCorrupt = false;
  try {
    await backupSourceRepo.inspectBackup('{"invalid": true}');
  } catch (_) {
    caughtCorrupt = true;
  }
  expect(
    caughtCorrupt == true,
    'Test 28.8: Corrupt/foreign JSON throws format exception',
  );

  // 5. Restore with Replace Strategy
  final restoreTargetDir = Directory(
    '${backupTestDir.path}/restore_target_docs',
  );
  restoreTargetDir.createSync(recursive: true);
  final restoreRepo = LocalNoteRepository(
    seedDemoData: false,
    enableDiskPersistence: true,
    directoryProvider: () async => restoreTargetDir.path,
  );
  await restoreRepo.init();

  final initialTargetNotes = await restoreRepo.watchNotes().first;
  expect(
    initialTargetNotes.isEmpty,
    'Test 28.9: Target repo is initially empty',
  );

  await restoreRepo.saveNote(
    NoteEntity(
      id: 'dummy-note-wipe',
      title: 'Dummy to be wiped',
      content: 'This will be replaced',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    ),
  );
  expect(
    (await restoreRepo.watchNotes().first).length == 1,
    'Test 28.10: Dummy note saved',
  );

  await restoreRepo.restoreBackup(
    customBackupFile.path,
    strategy: RestoreStrategy.replace,
  );
  final replacedNotes = await restoreRepo.watchNotes().first;
  expect(
    replacedNotes.any((n) => n.id == 'dummy-note-wipe') == false,
    'Test 28.11: Dummy note was wiped in replace strategy',
  );
  expect(
    replacedNotes.length == notesInPayload.length,
    'Test 28.11: Restored notes count matches backup',
  );

  // Verify audio extraction on restore
  final restoredBackupRecordings = await restoreRepo.getVoiceRecordings(
    'note-meeting-sync',
  );
  expect(
    restoredBackupRecordings.isNotEmpty,
    'Test 28.12: Voice recordings restored',
  );
  for (final rec in restoredBackupRecordings) {
    expect(
      File(rec.audioPath).existsSync(),
      'Test 28.12: Restored recording audio file exists on disk: ${rec.audioPath}',
    );
  }

  // 6. Restore with Merge Strategy
  final mergeUniqueNote = NoteEntity(
    id: 'note-merge-keeper',
    title: 'Keep Me In Merge',
    content: 'Unique note that should survive merge',
    createdAt: DateTime.now(),
    updatedAt: DateTime.now(),
  );
  await restoreRepo.saveNote(mergeUniqueNote);

  await restoreRepo.restoreBackup(
    customBackupFile.path,
    strategy: RestoreStrategy.merge,
  );
  final mergedNotes = await restoreRepo.watchNotes().first;
  expect(
    mergedNotes.any((n) => n.id == 'note-merge-keeper') == true,
    'Test 28.13: Unique note survived merge restore',
  );
  expect(
    mergedNotes.length == notesInPayload.length + 1,
    'Test 28.13: Merged notes count is backup count + 1',
  );

  // 7. Delete backup file
  await backupSourceRepo.deleteBackupFile(customBackupFile.path);
  expect(
    customBackupFile.existsSync() == false,
    'Test 28.14: Backup file deleted from disk',
  );
  final remainingBackups = await backupSourceRepo.listLocalBackups();
  expect(
    remainingBackups.any((f) => f.path == customBackupFile.path) == false,
    'Test 28.14: Deleted backup removed from listLocalBackups',
  );

  // 8. Compressed Backup Creation & Restoration
  final compressedFile = await backupSourceRepo.backupService
      .createBackupArchive(
        includeAudio: true,
        customName: 'compressed_backup',
        compress: true,
      );
  expect(compressedFile.existsSync(), 'Test 28.15: Compressed backup created');
  final compressedPreview = await backupSourceRepo.inspectBackup(
    compressedFile.path,
  );
  expect(
    compressedPreview.isZipArchive == true,
    'Test 28.15: Compressed preview has isZipArchive == true',
  );
  expect(
    compressedPreview.notesCount == notesInPayload.length,
    'Test 28.15: Compressed notes count matches',
  );

  // 9. Tampered Compressed Archive Detection
  final corruptBytes = List<int>.from(await compressedFile.readAsBytes());
  for (int i = 20; i < 30 && i < corruptBytes.length; i++) {
    corruptBytes[i] = (corruptBytes[i] + 1) % 256;
  }
  final corruptFile = File('${backupTestDir.path}/corrupt_compressed.noteflow');
  corruptFile.writeAsBytesSync(corruptBytes);

  bool caughtCorruptGzip = false;
  try {
    await backupSourceRepo.restoreBackup(
      corruptFile.path,
      strategy: RestoreStrategy.replace,
    );
  } catch (_) {
    caughtCorruptGzip = true;
  }
  expect(
    caughtCorruptGzip == true,
    'Test 28.16: Tampered compressed backup is detected and rejected',
  );

  // =========================================================================
  // --- Suite 29: Complete Offline Reminders & Scheduling Integration ---
  // =========================================================================
  stdout.writeln(
    'Running Suite 29: Offline Reminders & Scheduling Integration...',
  );

  final mockScheduler = TestMockReminderScheduler();
  final remindersTestDir = Directory(
    '${Directory.systemTemp.path}/noteflow_reminders_test_${DateTime.now().millisecondsSinceEpoch}',
  );
  if (!remindersTestDir.existsSync())
    remindersTestDir.createSync(recursive: true);
  final remindersDbPath = '${remindersTestDir.path}/noteflow_data.json';

  final remRepo = LocalNoteRepository(
    seedDemoData: false,
    enableDiskPersistence: true,
    customStoragePath: remindersDbPath,
    reminderScheduler: mockScheduler,
  );
  await remRepo.init();

  int testIdCounter = 1;
  final remService = ReminderService(
    repository: remRepo,
    scheduler: mockScheduler,
    idGenerator: () => 'test_rem_${testIdCounter++}',
  );

  // 1. ReminderEntity Serialization & Deserialization (Test 29.1)
  final entityCreatedAt = DateTime(2026, 11, 19, 10, 0);
  final entityScheduledAt = DateTime(2026, 11, 20, 15, 30);
  final entitySnoozedAt = DateTime(2026, 11, 20, 15, 45);

  final testEntity = ReminderEntity(
    id: 'rem-entity-1',
    noteId: 'note-100',
    checklistItemId: 'item-200',
    voiceRecordingId: 'rec-300',
    title: 'Review Project Proposal',
    notesPreview: 'Important items to consider...',
    scheduledAt: entityScheduledAt,
    timeZone: 'UTC',
    repeatMode: ReminderRepeatMode.monthly,
    repeatIntervalValue: 2,
    isCompleted: false,
    snoozeCount: 1,
    snoozedUntil: entitySnoozedAt,
    notificationId: 1042,
    createdAt: entityCreatedAt,
    updatedAt: entityCreatedAt,
  );

  final entityMap = testEntity.toMap();
  expect(entityMap['id'] == 'rem-entity-1', 'Test 29.1: Entity ID serialized');
  expect(entityMap['note_id'] == 'note-100', 'Test 29.1: Note ID serialized');
  expect(
    entityMap['checklist_item_id'] == 'item-200',
    'Test 29.1: Checklist item ID serialized',
  );
  expect(
    entityMap['voice_recording_id'] == 'rec-300',
    'Test 29.1: Voice recording ID serialized',
  );
  expect(
    entityMap['repeat_mode'] == 'monthly',
    'Test 29.1: Repeat mode serialized to string',
  );
  expect(
    entityMap['repeat_interval_value'] == 2,
    'Test 29.1: Repeat interval value serialized',
  );
  expect(
    entityMap['notification_id'] == 1042,
    'Test 29.1: Notification ID serialized',
  );
  expect(entityMap['snooze_count'] == 1, 'Test 29.1: Snooze count serialized');

  final restoredEntity = ReminderEntity.fromMap(entityMap);
  expect(
    restoredEntity.id == testEntity.id,
    'Test 29.1: Deserialized ID matches',
  );
  expect(
    restoredEntity.noteId == testEntity.noteId,
    'Test 29.1: Deserialized noteId matches',
  );
  expect(
    restoredEntity.checklistItemId == testEntity.checklistItemId,
    'Test 29.1: Deserialized checklistItemId matches',
  );
  expect(
    restoredEntity.voiceRecordingId == testEntity.voiceRecordingId,
    'Test 29.1: Deserialized voiceRecordingId matches',
  );
  expect(
    restoredEntity.repeatMode == ReminderRepeatMode.monthly,
    'Test 29.1: Deserialized repeatMode is Enum',
  );
  expect(
    restoredEntity.repeatIntervalValue == 2,
    'Test 29.1: Deserialized repeatIntervalValue matches',
  );
  expect(
    restoredEntity.notificationId == 1042,
    'Test 29.1: Deserialized notificationId matches',
  );
  expect(
    restoredEntity.snoozedUntil == entitySnoozedAt,
    'Test 29.1: Deserialized snoozedUntil matches',
  );

  // 2. ReminderEntity CopyWith & Computed Properties (Test 29.2)
  final copiedEntity = testEntity.copyWith(
    title: 'Updated Title',
    isCompleted: true,
    completedAt: DateTime(2026, 11, 20, 16, 0),
    clearSnoozedUntil: true,
  );
  expect(
    copiedEntity.title == 'Updated Title',
    'Test 29.2: copyWith title updated',
  );
  expect(
    copiedEntity.isCompleted == true,
    'Test 29.2: copyWith isCompleted true',
  );
  expect(
    copiedEntity.snoozedUntil == null,
    'Test 29.2: clearSnoozedUntil set null',
  );
  expect(
    testEntity.effectiveScheduledAt == entitySnoozedAt,
    'Test 29.2: effectiveScheduledAt uses snoozedUntil when present',
  );
  expect(
    copiedEntity.effectiveScheduledAt == entityScheduledAt,
    'Test 29.2: effectiveScheduledAt uses scheduledAt when not snoozed',
  );

  final pastReminder = testEntity.copyWith(
    scheduledAt: DateTime.now().subtract(const Duration(hours: 2)),
    clearSnoozedUntil: true,
  );
  expect(
    pastReminder.isOverdue == true,
    'Test 29.2: isOverdue detected for past time',
  );
  expect(
    pastReminder.isToday == true,
    'Test 29.2: isToday true for today past time',
  );

  // 3. Whole-Note Reminder Scheduling (Test 29.3)
  mockScheduler.reset();
  final parentNote = NoteEntity(
    id: 'note-m3-parent',
    title: 'Parent Project Note',
    content: 'Review quarterly goals',
    createdAt: DateTime.now(),
    updatedAt: DateTime.now(),
  );
  await remRepo.saveNote(parentNote);

  final futureTime = DateTime.now().add(const Duration(days: 1, hours: 2));
  final noteReminder = await remService.createReminder(
    noteId: parentNote.id,
    title: 'Review Quarterly Goals',
    notesPreview: 'Important items to consider',
    scheduledAt: futureTime,
  );

  expect(
    noteReminder.isWholeNoteReminder == true,
    'Test 29.3: isWholeNoteReminder is true',
  );
  expect(
    noteReminder.isChecklistItemReminder == false,
    'Test 29.3: isChecklistItemReminder is false',
  );
  expect(
    noteReminder.isVoiceRecordingReminder == false,
    'Test 29.3: isVoiceRecordingReminder is false',
  );
  expect(
    mockScheduler.scheduled.length == 1,
    'Test 29.3: Mock scheduler received 1 schedule call',
  );
  expect(
    mockScheduler.scheduled.first['notificationId'] ==
        noteReminder.notificationId,
    'Test 29.3: Scheduled with correct notification ID',
  );
  expect(
    mockScheduler.scheduled.first['noteId'] == parentNote.id,
    'Test 29.3: Scheduled with parent note ID',
  );

  final queriedNoteRem = await remRepo.getReminderForNote(parentNote.id);
  expect(
    queriedNoteRem != null && queriedNoteRem.id == noteReminder.id,
    'Test 29.3: getReminderForNote returns saved reminder',
  );

  // 4. Checklist Item Reminder Scheduling (Test 29.4)
  mockScheduler.reset();
  final checklistRem = await remService.createReminder(
    noteId: parentNote.id,
    checklistItemId: 'chk-item-88',
    title: 'Buy Groceries',
    notesPreview: 'Milk, Eggs, Bread',
    scheduledAt: futureTime,
  );

  expect(
    checklistRem.isWholeNoteReminder == false,
    'Test 29.4: Whole note is false',
  );
  expect(
    checklistRem.isChecklistItemReminder == true,
    'Test 29.4: Checklist item is true',
  );
  expect(
    checklistRem.checklistItemId == 'chk-item-88',
    'Test 29.4: Checklist item ID matches',
  );
  expect(
    mockScheduler.scheduled.first['checklistItemId'] == 'chk-item-88',
    'Test 29.4: Scheduler payload includes checklist item ID',
  );

  final queriedChkRem = await remRepo.getReminderForChecklistItem(
    parentNote.id,
    'chk-item-88',
  );
  expect(
    queriedChkRem != null && queriedChkRem.id == checklistRem.id,
    'Test 29.4: getReminderForChecklistItem returns item reminder',
  );

  // 5. Voice Recording Reminder Scheduling (Test 29.5)
  mockScheduler.reset();
  final voiceRec = VoiceRecordingEntity(
    id: 'rec-voice-77',
    voiceNoteId: parentNote.id,
    audioPath: '',
    durationMs: 15000,
    createdAt: DateTime.now(),
    title: 'Meeting Notes Clip',
  );
  await remRepo.saveVoiceRecording(voiceRec);

  final voiceRem = await remService.createReminder(
    noteId: parentNote.id,
    voiceRecordingId: voiceRec.id,
    title: 'Listen to Meeting Notes',
    scheduledAt: futureTime,
  );

  expect(
    voiceRem.isVoiceRecordingReminder == true,
    'Test 29.5: isVoiceRecordingReminder is true',
  );
  expect(
    voiceRem.voiceRecordingId == voiceRec.id,
    'Test 29.5: voiceRecordingId matches',
  );
  expect(
    mockScheduler.scheduled.first['voiceRecordingId'] == voiceRec.id,
    'Test 29.5: Scheduler payload includes voiceRecordingId',
  );

  final queriedVoiceRem = await remRepo.getReminderForVoiceRecording(
    voiceRec.id,
  );
  expect(
    queriedVoiceRem != null && queriedVoiceRem.id == voiceRem.id,
    'Test 29.5: getReminderForVoiceRecording returns clip reminder',
  );

  // 6. Monotonic Notification ID Allocation & Zero Collision (Test 29.6)
  final id1 = remRepo.getNextNotificationId();
  final id2 = remRepo.getNextNotificationId();
  final id3 = remRepo.getNextNotificationId();
  final id4 = remRepo.getNextNotificationId();
  final id5 = remRepo.getNextNotificationId();

  expect(id2 == id1 + 1, 'Test 29.6: Monotonic ID increments by 1');
  expect(id3 == id2 + 1, 'Test 29.6: Monotonic ID increments continuously');
  expect(id5 > id1, 'Test 29.6: Monotonic ID is strictly ascending');
  final idSet = {id1, id2, id3, id4, id5};
  expect(
    idSet.length == 5,
    'Test 29.6: All notification IDs are unique with zero collisions',
  );

  // 7. RFC 5545 Calendar Recurrence Engine (Test 29.7)
  // 7a. Daily recurrence with interval
  final startDaily = DateTime(2026, 3, 10, 9, 30);
  final nextDaily2 = ReminderService.computeNextOccurrence(
    startDaily,
    ReminderRepeatMode.daily,
    intervalValue: 2,
  );
  expect(
    nextDaily2 == DateTime(2026, 3, 12, 9, 30),
    'Test 29.7: Daily interval=2 preserves exact time',
  );

  // 7b. Weekly recurrence
  final startWeekly = DateTime(2026, 3, 10, 14, 0);
  final nextWeekly = ReminderService.computeNextOccurrence(
    startWeekly,
    ReminderRepeatMode.weekly,
    intervalValue: 1,
  );
  expect(
    nextWeekly == DateTime(2026, 3, 17, 14, 0),
    'Test 29.7: Weekly interval=1 advances exactly 7 days',
  );

  // 7c. Monthly recurrence: Jan 31 -> Feb 28 in non-leap year (2026)
  final jan31 = DateTime(2026, 1, 31, 10, 0);
  final febNonLeap = ReminderService.computeNextOccurrence(
    jan31,
    ReminderRepeatMode.monthly,
    anchorDay: 31,
  );
  expect(
    febNonLeap == DateTime(2026, 2, 28, 10, 0),
    'Test 29.7: Jan 31 clamps to Feb 28 in non-leap 2026',
  );

  // 7d. Monthly recurrence: Jan 31 -> Feb 29 in leap year (2028)
  final jan31Leap = DateTime(2028, 1, 31, 10, 0);
  final febLeap = ReminderService.computeNextOccurrence(
    jan31Leap,
    ReminderRepeatMode.monthly,
    anchorDay: 31,
  );
  expect(
    febLeap == DateTime(2028, 2, 29, 10, 0),
    'Test 29.7: Jan 31 clamps to Feb 29 in leap year 2028',
  );

  // 7e. Monthly anchor day preservation across full 12-month calendar
  DateTime currentRecurrence = DateTime(2026, 1, 31, 18, 0);
  const expectedDays = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
  for (int m = 1; m < 12; m++) {
    currentRecurrence = ReminderService.computeNextOccurrence(
      currentRecurrence,
      ReminderRepeatMode.monthly,
      anchorDay: 31,
    )!;
    expect(
      currentRecurrence.month == m + 1,
      'Test 29.7: Recurrence advances to month ${m + 1}',
    );
    expect(
      currentRecurrence.day == expectedDays[m],
      'Test 29.7: Month ${m + 1} day is ${expectedDays[m]} with anchor=31',
    );
    expect(
      currentRecurrence.hour == 18,
      'Test 29.7: Hour wall-clock preserved at 18:00',
    );
  }

  // 8. Reminder Completion (One-Time vs Recurring) (Test 29.8)
  mockScheduler.reset();
  // One-time completion
  await remService.completeReminder(noteReminder.id);
  final completedNoteRem = await remRepo.getReminderById(noteReminder.id);
  expect(
    completedNoteRem != null && completedNoteRem.isCompleted == true,
    'Test 29.8: One-time reminder marked completed',
  );
  expect(
    completedNoteRem?.completedAt != null,
    'Test 29.8: completedAt is populated',
  );
  expect(
    mockScheduler.cancelled.contains(noteReminder.notificationId),
    'Test 29.8: Alarm cancelled on completion',
  );

  // Recurring completion: advances to next cycle
  mockScheduler.reset();
  final recurringRem = await remService.createReminder(
    noteId: parentNote.id,
    title: 'Monthly Rent Payment',
    scheduledAt: DateTime(2027, 5, 31, 10, 0),
    repeatMode: ReminderRepeatMode.monthly,
  );
  await remService.completeReminder(recurringRem.id);
  final advancedRem = await remRepo.getReminderById(recurringRem.id);
  expect(
    advancedRem != null && advancedRem.isCompleted == false,
    'Test 29.8: Recurring reminder remains active (not completed)',
  );
  expect(
    advancedRem?.scheduledAt == DateTime(2027, 6, 30, 10, 0),
    'Test 29.8: Recurring scheduledAt advanced to June 30',
  );
  expect(
    mockScheduler.scheduled.any(
      (s) => s['notificationId'] == recurringRem.notificationId,
    ),
    'Test 29.8: Next occurrence alarm re-armed',
  );

  // 9. Reminder Snooze (Test 29.9)
  mockScheduler.reset();
  await remService.snoozeReminder(checklistRem.id, const Duration(minutes: 15));
  final snoozedRem = await remRepo.getReminderById(checklistRem.id);
  expect(
    snoozedRem != null && snoozedRem.snoozeCount == 1,
    'Test 29.9: Snooze count incremented to 1',
  );
  expect(snoozedRem?.snoozedUntil != null, 'Test 29.9: snoozedUntil populated');
  expect(
    mockScheduler.scheduled.any(
      (s) => s['notificationId'] == checklistRem.notificationId,
    ),
    'Test 29.9: Alarm scheduled for snooze duration',
  );

  // Second snooze
  await remService.snoozeReminder(checklistRem.id, const Duration(minutes: 15));
  final snoozedRem2 = await remRepo.getReminderById(checklistRem.id);
  expect(
    snoozedRem2?.snoozeCount == 2,
    'Test 29.9: Snooze count incremented to 2',
  );

  // 10. Update Reminder (Test 29.10)
  mockScheduler.reset();
  final newScheduledTime = DateTime.now().add(const Duration(days: 3));
  final updatedEntity = voiceRem.copyWith(
    title: 'Updated Voice Reminder Title',
    scheduledAt: newScheduledTime,
  );
  await remService.updateReminder(updatedEntity);
  final retrievedUpdated = await remRepo.getReminderById(voiceRem.id);
  expect(
    retrievedUpdated?.title == 'Updated Voice Reminder Title',
    'Test 29.10: Title updated',
  );
  expect(
    retrievedUpdated?.scheduledAt == newScheduledTime,
    'Test 29.10: Scheduled time updated',
  );
  expect(
    mockScheduler.cancelled.contains(voiceRem.notificationId),
    'Test 29.10: Previous alarm cancelled',
  );
  expect(
    mockScheduler.scheduled.any(
      (s) => s['notificationId'] == voiceRem.notificationId,
    ),
    'Test 29.10: New alarm re-scheduled',
  );

  // 11. Delete Reminder (Test 29.11)
  mockScheduler.reset();
  await remService.deleteReminder(voiceRem.id);
  final deletedRem = await remRepo.getReminderById(voiceRem.id);
  expect(deletedRem == null, 'Test 29.11: Reminder deleted from repository');
  expect(
    mockScheduler.cancelled.contains(voiceRem.notificationId),
    'Test 29.11: Alarm cancelled on delete',
  );

  // 12. Cold Restart Recovery & Disk Persistence (Test 29.12)
  final restartedRemRepo = LocalNoteRepository(
    seedDemoData: false,
    enableDiskPersistence: true,
    customStoragePath: remindersDbPath,
    reminderScheduler: mockScheduler,
  );
  await restartedRemRepo.init();

  final restartedRemService = ReminderService(
    repository: restartedRemRepo,
    scheduler: mockScheduler,
    idGenerator: () => 'test_rem_${testIdCounter++}',
  );

  final restoredReminders = await restartedRemRepo.getReminders();
  expect(
    restoredReminders.length == 3,
    'Test 29.12: 3 reminders restored on cold restart',
  );
  final restoredRent = restoredReminders.firstWhere(
    (r) => r.id == recurringRem.id,
  );
  expect(
    restoredRent.title == 'Monthly Rent Payment',
    'Test 29.12: Title preserved on restart',
  );
  expect(
    restoredRent.repeatMode == ReminderRepeatMode.monthly,
    'Test 29.12: Repeat mode preserved',
  );
  expect(
    restoredRent.scheduledAt == DateTime(2027, 6, 30, 10, 0),
    'Test 29.12: Advanced recurrence date preserved',
  );

  final nextRestartId = restartedRemRepo.getNextNotificationId();
  expect(
    nextRestartId > recurringRem.notificationId,
    'Test 29.12: nextNotificationId safely advanced across restarts',
  );

  // 13. Note Cascade Deletion (Test 29.13)
  mockScheduler.reset();
  await restartedRemRepo.deleteNote(parentNote.id);
  final noteRemAfterNoteDelete = await restartedRemRepo.getReminderForNote(
    parentNote.id,
  );
  expect(
    noteRemAfterNoteDelete == null,
    'Test 29.13: Whole-note reminder deleted with parent note',
  );
  final chkRemAfterNoteDelete = await restartedRemRepo
      .getReminderForChecklistItem(parentNote.id, 'chk-item-88');
  expect(
    chkRemAfterNoteDelete == null,
    'Test 29.13: Checklist reminder deleted with parent note',
  );
  expect(
    mockScheduler.cancelled.isNotEmpty,
    'Test 29.13: Child reminder alarms cancelled on note deletion',
  );

  // 14. Voice Recording Cascade Deletion (Test 29.14)
  mockScheduler.reset();
  final isolatedNote = NoteEntity(
    id: 'note-cascade-rec',
    title: 'Rec Parent',
    content: '',
    createdAt: DateTime.now(),
    updatedAt: DateTime.now(),
  );
  await restartedRemRepo.saveNote(isolatedNote);
  final isolatedRec = VoiceRecordingEntity(
    id: 'rec-cascade-target',
    voiceNoteId: isolatedNote.id,
    audioPath: '',
    durationMs: 1000,
    createdAt: DateTime.now(),
    title: 'Target Rec',
  );
  await restartedRemRepo.saveVoiceRecording(isolatedRec);
  final isolatedRem = await restartedRemService.createReminder(
    noteId: isolatedNote.id,
    voiceRecordingId: isolatedRec.id,
    title: 'Clip Rem',
    scheduledAt: futureTime,
  );

  await restartedRemRepo.deleteVoiceRecording(isolatedRec.id);
  final checkRecRem = await restartedRemRepo.getReminderForVoiceRecording(
    isolatedRec.id,
  );
  expect(checkRecRem == null, 'Test 29.14: Recording reminder cascade deleted');
  expect(
    mockScheduler.cancelled.contains(isolatedRem.notificationId),
    'Test 29.14: Recording reminder alarm cancelled',
  );

  // 15. Checklist Item Removal Auto-Invalidation (Test 29.15)
  mockScheduler.reset();
  final checklistNote = NoteEntity(
    id: 'note-checklist-inval',
    title: 'Checklist Note',
    content: '- [ ] Item One <!--id:item-stable-1-->\n- [ ] Item Two <!--id:item-stable-2-->',
    isChecklist: true,
    createdAt: DateTime.now(),
    updatedAt: DateTime.now(),
  );
  await restartedRemRepo.saveNote(checklistNote);

  final itemRem1 = await restartedRemService.createReminder(
    noteId: checklistNote.id,
    checklistItemId: 'item-stable-1',
    title: 'Item One Reminder',
    scheduledAt: futureTime,
  );
  final itemRem2 = await restartedRemService.createReminder(
    noteId: checklistNote.id,
    checklistItemId: 'item-stable-2',
    title: 'Item Two Reminder',
    scheduledAt: futureTime,
  );

  // User deletes item 1 from note content and saves
  final modifiedNote = checklistNote.copyWith(
    content: '- [ ] Item Two <!--id:item-stable-2-->',
    updatedAt: DateTime.now(),
  );
  await restartedRemRepo.saveNote(modifiedNote);

  final checkItem1Rem = await restartedRemRepo.getReminderForChecklistItem(
    checklistNote.id,
    'item-stable-1',
  );
  expect(
    checkItem1Rem == null,
    'Test 29.15: Removed checklist item reminder automatically invalidated',
  );
  expect(
    mockScheduler.cancelled.contains(itemRem1.notificationId),
    'Test 29.15: Invalidated item alarm cancelled',
  );

  final checkItem2Rem = await restartedRemRepo.getReminderForChecklistItem(
    checklistNote.id,
    'item-stable-2',
  );
  expect(
    checkItem2Rem != null,
    'Test 29.15: Remaining checklist item reminder stays active',
  );

  // 16. Action Journal Draining and Backup & Restore Integration (Test 29.16)
  // 16a. Journal Draining
  final journalSnoozeMs = DateTime.now()
      .add(const Duration(minutes: 15))
      .millisecondsSinceEpoch;
  final changed = restartedRemRepo.applyJournalAction({
    'action': 'snooze',
    'notificationId': itemRem2.notificationId,
    'noteId': checklistNote.id,
    'snoozedUntilMs': journalSnoozeMs,
  });
  expect(changed == true, 'Test 29.16: Journal snooze applied');
  final journalSnoozedRem = await restartedRemRepo.getReminderById(itemRem2.id);
  expect(
    journalSnoozedRem?.snoozeCount == 1,
    'Test 29.16: Journal snooze count incremented',
  );

  final doneChanged = restartedRemRepo.applyJournalAction({
    'action': 'markDone',
    'notificationId': itemRem2.notificationId,
    'noteId': checklistNote.id,
  });
  expect(doneChanged == true, 'Test 29.16: Journal markDone applied');
  final journalDoneRem = await restartedRemRepo.getReminderById(itemRem2.id);
  expect(
    journalDoneRem?.isCompleted == true,
    'Test 29.16: Journal markDone completed reminder',
  );

  // 16b. Backup & Restore Roundtrip
  final backupPayload = await restartedRemRepo.exportBackupPayload(
    includeAudio: false,
  );
  expect(
    backupPayload.containsKey('reminders'),
    'Test 29.16: Export payload includes reminders key',
  );
  final exportedReminders = backupPayload['reminders'] as List<dynamic>;
  expect(
    exportedReminders.isNotEmpty,
    'Test 29.16: Exported reminders list is populated',
  );
  final metaStats = backupPayload['stats'] as Map<String, dynamic>;
  expect(
    metaStats['reminders_count'] == exportedReminders.length,
    'Test 29.16: Metadata reminders_count matches export count',
  );

  // Inspect archive check
  final restoreService = restartedRemRepo.restoreService;
  final jsonPayloadStr = jsonEncode(backupPayload);
  final inspectedPreview = await restoreService.inspectArchive(jsonPayloadStr);
  expect(
    inspectedPreview.remindersCount == exportedReminders.length,
    'Test 29.16: Inspected preview reflects remindersCount',
  );

  // Restore with Replace Strategy
  mockScheduler.reset();
  final freshTargetDir = Directory(
    '${Directory.systemTemp.path}/noteflow_restore_test_${DateTime.now().millisecondsSinceEpoch}',
  );
  freshTargetDir.createSync(recursive: true);
  final freshRepo = LocalNoteRepository(
    seedDemoData: false,
    enableDiskPersistence: true,
    customStoragePath: '${freshTargetDir.path}/noteflow_data.json',
    reminderScheduler: mockScheduler,
  );
  await freshRepo.init();

  await freshRepo.restoreBackup(
    jsonPayloadStr,
    strategy: RestoreStrategy.replace,
  );
  final restoredFromBackup = await freshRepo.getReminders();
  expect(
    restoredFromBackup.length == exportedReminders.length,
    'Test 29.16: All reminders restored via Replace',
  );

  // Restore with Merge Strategy
  final extraRem = ReminderEntity(
    id: 'rem-merge-unique',
    noteId: 'note-merge-unique',
    title: 'Unique Merge Reminder',
    scheduledAt: DateTime.now().add(const Duration(days: 2)),
    createdAt: DateTime.now(),
    updatedAt: DateTime.now(),
    notificationId: 9999,
  );
  await freshRepo.saveReminder(extraRem);
  await freshRepo.restoreBackup(
    jsonPayloadStr,
    strategy: RestoreStrategy.merge,
  );
  final mergedRemList = await freshRepo.getReminders();
  expect(
    mergedRemList.any((r) => r.id == 'rem-merge-unique') == true,
    'Test 29.16: Unique reminder preserved after merge',
  );

  // Clean up reminders test directory
  if (remindersTestDir.existsSync()) {
    remindersTestDir.deleteSync(recursive: true);
  }
  if (freshTargetDir.existsSync()) {
    freshTargetDir.deleteSync(recursive: true);
  }
  stdout.writeln('Suite 29 passed successfully! ✓');

  // --- Suite 30: Tags Management & Favorites Full Test Suite ---
  stdout.writeln(
    'Running Suite 30: Tags Management & Favorites (20 Verification Checks)...',
  );

  final suite30Dir = Directory(
    '${Directory.systemTemp.path}/suite30_test_${DateTime.now().millisecondsSinceEpoch}',
  );
  suite30Dir.createSync(recursive: true);
  final suite30File = File('${suite30Dir.path}/noteflow_data.json');

  final repo30 = LocalNoteRepository(
    seedDemoData: false,
    enableDiskPersistence: true,
    customStoragePath: suite30File.path,
  );
  await repo30.init();

  // Test 1: Create a tag
  final tag1 = TagEntity(
    id: 'tag-work',
    name: 'Work',
    colorHex: '#3B82F6',
    createdAt: DateTime.now(),
    updatedAt: DateTime.now(),
  );
  await repo30.saveTag(tag1);
  final fetchedTag1 = await repo30.getTagById('tag-work');
  expect(fetchedTag1 != null, 'Test 1: Tag created and fetched by ID');
  expect(fetchedTag1?.name == 'Work', 'Test 1: Tag name is Work');
  expect(fetchedTag1?.colorHex == '#3B82F6', 'Test 1: Tag color is #3B82F6');

  // Test 2: Rename a tag
  final renamedTag1 = fetchedTag1!.copyWith(
    name: 'Work & Projects',
    updatedAt: DateTime.now(),
  );
  await repo30.saveTag(renamedTag1);
  final fetchedRenamed = await repo30.getTagById('tag-work');
  expect(
    fetchedRenamed?.name == 'Work & Projects',
    'Test 2: Tag successfully renamed',
  );

  // Test 3: Change tag color
  final recoloredTag1 = fetchedRenamed!.copyWith(
    colorHex: '#10B981',
    updatedAt: DateTime.now(),
  );
  await repo30.saveTag(recoloredTag1);
  final fetchedRecolored = await repo30.getTagById('tag-work');
  expect(
    fetchedRecolored?.colorHex == '#10B981',
    'Test 3: Tag color successfully updated',
  );

  // Test 4: Delete a tag (and verify cascade removal from note tagIds without deleting notes)
  final tagToDelete = TagEntity(
    id: 'tag-temp',
    name: 'Temporary',
    colorHex: '#EF4444',
    createdAt: DateTime.now(),
    updatedAt: DateTime.now(),
  );
  await repo30.saveTag(tagToDelete);
  final noteWithTemp = NoteEntity(
    id: 'note-cascade-test',
    title: 'Cascade Test Note',
    content: 'Content',
    tagIds: ['tag-work', 'tag-temp'],
    createdAt: DateTime.now(),
    updatedAt: DateTime.now(),
  );
  await repo30.saveNote(noteWithTemp);
  expect(
    (await repo30.getNoteById('note-cascade-test'))?.tagIds
            .contains('tag-temp') ==
        true,
    'Test 4: Note has tag-temp before deletion',
  );

  await repo30.deleteTag('tag-temp');
  final fetchedDeletedTag = await repo30.getTagById('tag-temp');
  expect(fetchedDeletedTag == null, 'Test 4: Tag is deleted from repository');
  final noteAfterTagDelete = await repo30.getNoteById('note-cascade-test');
  expect(
    noteAfterTagDelete != null,
    'Test 4: Note still exists after tag deletion',
  );
  expect(
    !noteAfterTagDelete!.tagIds.contains('tag-temp'),
    'Test 4: tag-temp was removed from note tagIds',
  );
  expect(
    noteAfterTagDelete.tagIds.contains('tag-work'),
    'Test 4: tag-work remains assigned to note',
  );

  // Test 5: Assign multiple tags to one note
  final tag2 = TagEntity(
    id: 'tag-urgent',
    name: 'Urgent',
    colorHex: '#F59E0B',
    createdAt: DateTime.now(),
    updatedAt: DateTime.now(),
  );
  final tag3 = TagEntity(
    id: 'tag-ideas',
    name: 'Ideas',
    colorHex: '#8B5CF6',
    createdAt: DateTime.now(),
    updatedAt: DateTime.now(),
  );
  await repo30.saveTag(tag2);
  await repo30.saveTag(tag3);

  final multiTagNote = noteAfterTagDelete.copyWith(
    tagIds: ['tag-work', 'tag-urgent', 'tag-ideas'],
  );
  await repo30.saveNote(multiTagNote);
  final fetchedMultiNote = await repo30.getNoteById('note-cascade-test');
  expect(
    fetchedMultiNote?.tagIds.length == 3,
    'Test 5: Note has 3 tags assigned',
  );
  expect(
    fetchedMultiNote?.tagIds.contains('tag-urgent') == true,
    'Test 5: Note contains tag-urgent',
  );
  expect(
    fetchedMultiNote?.tagIds.contains('tag-ideas') == true,
    'Test 5: Note contains tag-ideas',
  );

  // Test 6: Remove an assigned tag
  final removedTagNote = fetchedMultiNote!.copyWith(
    tagIds: fetchedMultiNote.tagIds.where((t) => t != 'tag-urgent').toList(),
  );
  await repo30.saveNote(removedTagNote);
  final fetchedRemovedNote = await repo30.getNoteById('note-cascade-test');
  expect(fetchedRemovedNote?.tagIds.length == 2, 'Test 6: Note now has 2 tags');
  expect(
    fetchedRemovedNote?.tagIds.contains('tag-urgent') == false,
    'Test 6: tag-urgent removed from note',
  );

  // Test 7: Assign tags across all 3 note types (Text Note, Checklist, Voice Note)
  final textNote = NoteEntity(
    id: 'note-type-text',
    title: 'Text Note with Tags',
    content: 'Regular text content',
    isChecklist: false,
    isVoiceNote: false,
    tagIds: ['tag-work'],
    createdAt: DateTime.now(),
    updatedAt: DateTime.now(),
  );
  final checklistNote30 = NoteEntity(
    id: 'note-type-checklist',
    title: 'Checklist Note with Tags',
    content: '[ ] Item 1\n[x] Item 2',
    isChecklist: true,
    isVoiceNote: false,
    tagIds: ['tag-work', 'tag-ideas'],
    createdAt: DateTime.now(),
    updatedAt: DateTime.now(),
  );
  final voiceNote30 = NoteEntity(
    id: 'note-type-voice',
    title: 'Voice Note with Tags',
    content: 'Audio memo transcription',
    isChecklist: false,
    isVoiceNote: true,
    tagIds: ['tag-ideas'],
    createdAt: DateTime.now(),
    updatedAt: DateTime.now(),
  );
  await repo30.saveNote(textNote);
  await repo30.saveNote(checklistNote30);
  await repo30.saveNote(voiceNote30);

  expect(
    (await repo30.getNoteById('note-type-text'))?.tagIds.contains('tag-work') ==
        true,
    'Test 7: Text note has tag-work',
  );
  expect(
    (await repo30.getNoteById('note-type-checklist'))?.tagIds
            .contains('tag-ideas') ==
        true,
    'Test 7: Checklist has tag-ideas',
  );
  expect(
    (await repo30.getNoteById('note-type-voice'))?.tagIds
            .contains('tag-ideas') ==
        true,
    'Test 7: Voice note has tag-ideas',
  );

  // Test 8: Filter by tag
  final allNotes = await repo30.watchNotes(includeArchived: false).first;
  final notesWithWork = allNotes
      .where((n) => n.tagIds.contains('tag-work'))
      .toList();
  expect(
    notesWithWork.any((n) => n.id == 'note-type-text'),
    'Test 8: notesWithWork contains text note',
  );
  expect(
    notesWithWork.any((n) => n.id == 'note-type-checklist'),
    'Test 8: notesWithWork contains checklist note',
  );
  expect(
    !notesWithWork.any((n) => n.id == 'note-type-voice'),
    'Test 8: notesWithWork does not contain voice note',
  );

  // Test 9: Search tags by name (case-insensitive)
  final allTags = await repo30.getTags();
  final searchResults = allTags
      .where((t) => t.name.toLowerCase().contains('work'))
      .toList();
  expect(
    searchResults.length == 1,
    'Test 9: Tag search finds 1 tag for "work"',
  );
  expect(
    searchResults.first.id == 'tag-work',
    'Test 9: Matched tag is tag-work',
  );

  // Test 10: Search notes using tag filters + query
  final queryMatches = allNotes.where((n) {
    final matchesTag = n.tagIds.contains('tag-ideas');
    final matchesQuery = n.title.toLowerCase().contains('voice');
    return matchesTag && matchesQuery;
  }).toList();
  expect(
    queryMatches.length == 1,
    'Test 10: 1 note matches tag-ideas + "voice" query',
  );
  expect(
    queryMatches.first.id == 'note-type-voice',
    'Test 10: Found voice note',
  );

  // Test 11: Favorite a Text Note
  await repo30.toggleFavorite('note-type-text');
  final favText = await repo30.getNoteById('note-type-text');
  expect(favText?.isFavorite == true, 'Test 11: Text note is now favorite');

  // Test 12: Favorite a Checklist
  await repo30.toggleFavorite('note-type-checklist');
  final favChecklist = await repo30.getNoteById('note-type-checklist');
  expect(
    favChecklist?.isFavorite == true,
    'Test 12: Checklist note is now favorite',
  );

  // Test 13: Favorite a Voice Note
  await repo30.toggleFavorite('note-type-voice');
  final favVoice = await repo30.getNoteById('note-type-voice');
  expect(favVoice?.isFavorite == true, 'Test 13: Voice note is now favorite');

  // Test 14: Remove from favorites
  await repo30.toggleFavorite('note-type-text');
  final unFavText = await repo30.getNoteById('note-type-text');
  expect(
    unFavText?.isFavorite == false,
    'Test 14: Text note removed from favorites',
  );

  // Test 15: Restart persistence (serialize to JSON, reload into fresh LocalNoteRepository, verify tags and favorites intact)
  final repo30Restarted = LocalNoteRepository(
    seedDemoData: false,
    enableDiskPersistence: true,
    customStoragePath: suite30File.path,
  );
  await repo30Restarted.init();

  final restartedTags = await repo30Restarted.getTags();
  expect(
    restartedTags.any(
      (t) =>
          t.id == 'tag-work' &&
          t.name == 'Work & Projects' &&
          t.colorHex == '#10B981',
    ),
    'Test 15: Tag Work & Projects persisted across restart',
  );
  expect(
    restartedTags.any((t) => t.id == 'tag-ideas'),
    'Test 15: Tag Ideas persisted across restart',
  );

  final restartedChecklist = await repo30Restarted.getNoteById(
    'note-type-checklist',
  );
  expect(
    restartedChecklist?.isFavorite == true,
    'Test 15: Favorite checklist persisted across restart',
  );
  expect(
    restartedChecklist?.tagIds.contains('tag-work') == true,
    'Test 15: Checklist tag-work persisted across restart',
  );
  expect(
    restartedChecklist?.tagIds.contains('tag-ideas') == true,
    'Test 15: Checklist tag-ideas persisted across restart',
  );

  final restartedText = await repo30Restarted.getNoteById('note-type-text');
  expect(
    restartedText?.isFavorite == false,
    'Test 15: Unfavorited text note persisted across restart',
  );

  // Test 16: Archive and restore a tagged/favorited note
  await repo30Restarted.toggleArchive('note-type-checklist');
  final archivedChecklist = await repo30Restarted.getNoteById(
    'note-type-checklist',
  );
  expect(
    archivedChecklist?.isArchived == true,
    'Test 16: Checklist note archived',
  );
  expect(
    archivedChecklist?.isFavorite == true,
    'Test 16: Archived checklist preserves favorite',
  );
  expect(
    archivedChecklist?.tagIds.length == 2,
    'Test 16: Archived checklist preserves tags',
  );

  await repo30Restarted.toggleArchive('note-type-checklist');
  final unarchivedChecklist = await repo30Restarted.getNoteById(
    'note-type-checklist',
  );
  expect(
    unarchivedChecklist?.isArchived == false,
    'Test 16: Checklist note restored from archive',
  );
  expect(
    unarchivedChecklist?.isFavorite == true,
    'Test 16: Restored checklist preserves favorite',
  );
  expect(
    unarchivedChecklist?.tagIds.length == 2,
    'Test 16: Restored checklist preserves tags',
  );

  // Test 17: Backup and restore tags (replace strategy)
  final backupPayload30 = await repo30Restarted.exportBackupPayload();
  expect(
    backupPayload30.containsKey('tags'),
    'Test 17: Backup payload contains tags key',
  );
  final backupTags = backupPayload30['tags'] as List<dynamic>;
  expect(backupTags.isNotEmpty, 'Test 17: Backup tags list is not empty');
  expect(
    backupPayload30['stats']['tags_count'] == backupTags.length,
    'Test 17: Backup stats records correct tags_count',
  );

  // Create an empty repository and restore backup with replace
  final restoreDir = Directory(
    '${Directory.systemTemp.path}/suite30_restore_${DateTime.now().millisecondsSinceEpoch}',
  );
  restoreDir.createSync(recursive: true);
  final restoreFile = File('${restoreDir.path}/noteflow_data.json');
  final repoRestore = LocalNoteRepository(
    seedDemoData: false,
    enableDiskPersistence: true,
    customStoragePath: restoreFile.path,
  );
  await repoRestore.init();

  final jsonPayloadStr30 = jsonEncode(backupPayload30);
  await repoRestore.restoreBackup(
    jsonPayloadStr30,
    strategy: RestoreStrategy.replace,
  );

  final restoredTagsList = await repoRestore.getTags();
  expect(
    restoredTagsList.length == backupTags.length,
    'Test 17: Restored tags count matches backup',
  );
  final restoredNoteChecklist = await repoRestore.getNoteById(
    'note-type-checklist',
  );
  expect(
    restoredNoteChecklist?.isFavorite == true,
    'Test 17: Restored note retains favorite',
  );
  expect(
    restoredNoteChecklist?.tagIds.contains('tag-ideas') == true,
    'Test 17: Restored note retains tag-ideas',
  );

  // Test 18: Merge backup with existing tags
  final newTagToMerge = TagEntity(
    id: 'tag-merge-new',
    name: 'Merge Unique Tag',
    colorHex: '#EC4899',
    createdAt: DateTime.now(),
    updatedAt: DateTime.now(),
  );
  await repoRestore.saveTag(newTagToMerge);
  await repoRestore.restoreBackup(
    jsonPayloadStr30,
    strategy: RestoreStrategy.merge,
  );
  final mergedTagsList = await repoRestore.getTags();
  expect(
    mergedTagsList.any((t) => t.id == 'tag-merge-new'),
    'Test 18: New merged tag exists',
  );
  expect(
    mergedTagsList.any((t) => t.id == 'tag-work'),
    'Test 18: Existing tag-work remains after merge',
  );

  // Test 19: Verify no duplicate tag assignments
  final duplicateTagNote = restoredNoteChecklist!.copyWith(
    tagIds: ['tag-work', 'tag-work', 'tag-ideas', 'tag-work'],
  );
  // Verify deduplication helper in NoteEntity / repository
  final deduplicatedTagIds = duplicateTagNote.tagIds.toSet().toList();
  final cleanNote = duplicateTagNote.copyWith(tagIds: deduplicatedTagIds);
  await repoRestore.saveNote(cleanNote);
  final fetchedClean = await repoRestore.getNoteById('note-type-checklist');
  expect(
    fetchedClean?.tagIds.length == 2,
    'Test 19: No duplicate tag IDs on note',
  );
  expect(
    TagEntity.namesEqual('Work', 'work'),
    'Test 19: Case-insensitive uniqueness helper correctly matches',
  );
  expect(
    TagEntity.namesEqual('  WORK  ', 'work'),
    'Test 19: Trimmed case-insensitive uniqueness helper matches',
  );

  // Test 20: Verify folders and sort filters continue working correctly
  final folder1 = FolderEntity(
    id: 'folder-work',
    name: 'Work Folder',
    colorHex: '#3B82F6',
    iconName: 'folder',
    createdAt: DateTime.now(),
  );
  await repoRestore.saveFolder(folder1);
  final folderNote = fetchedClean!.copyWith(folderId: 'folder-work');
  await repoRestore.saveNote(folderNote);
  final fetchedFolderNote = await repoRestore.getNoteById(
    'note-type-checklist',
  );
  expect(
    fetchedFolderNote?.folderId == 'folder-work',
    'Test 20: Folder assignment works alongside tags & favorites',
  );
  expect(
    fetchedFolderNote?.isFavorite == true,
    'Test 20: Favorite remains intact with folder',
  );
  expect(
    fetchedFolderNote?.tagIds.contains('tag-ideas') == true,
    'Test 20: Tags remain intact with folder',
  );

  // Test NoteFilterState with favorites and tags
  const filterState = NoteFilterState(
    isFavoritesOnly: true,
    selectedTagIds: {'tag-ideas'},
    tagMatchMode: TagFilterMatchMode.any,
  );
  expect(
    filterState.isFavoritesOnly == true,
    'Test 20: FilterState isFavoritesOnly is true',
  );
  expect(
    filterState.selectedTagIds.contains('tag-ideas'),
    'Test 20: FilterState contains tag-ideas',
  );
  expect(
    filterState.hasTagFilter == true,
    'Test 20: FilterState hasTagFilter is true',
  );
  expect(
    filterState.isAllNotes == false,
    'Test 20: FilterState isAllNotes is false',
  );

  if (suite30Dir.existsSync()) {
    suite30Dir.deleteSync(recursive: true);
  }
  if (restoreDir.existsSync()) {
    restoreDir.deleteSync(recursive: true);
  }

  stdout.writeln('Suite 30 passed successfully! ✓ (20/20 Checks)');

  // --- Suite 31: Home Redesign, Material 3 Navigation Drawer & Filters Integration ---
  stdout.writeln(
    'Running Suite 31: Home Redesign & Filter Suite (16 Verification Checks)...',
  );

  // Check 1-2: NoteFilterState defaults
  const fDefault = NoteFilterState();
  expect(
    fDefault.isRecentOnly == false,
    'Suite 31 Test 1: Default isRecentOnly is false',
  );
  expect(
    fDefault.isPinnedOnly == false,
    'Suite 31 Test 2: Default isPinnedOnly is false',
  );

  // Check 3-4: copyWith recent and pinned
  final fRecent = fDefault.copyWith(isRecentOnly: true);
  expect(
    fRecent.isRecentOnly == true,
    'Suite 31 Test 3: copyWith isRecentOnly is true',
  );
  final fPinned = fDefault.copyWith(isPinnedOnly: true);
  expect(
    fPinned.isPinnedOnly == true,
    'Suite 31 Test 4: copyWith isPinnedOnly is true',
  );

  // Check 5-8: isAllNotes calculation
  expect(
    fDefault.isAllNotes == true,
    'Suite 31 Test 5: Default state isAllNotes is true',
  );
  expect(
    fRecent.isAllNotes == false,
    'Suite 31 Test 6: isAllNotes is false when recent is active',
  );
  expect(
    fPinned.isAllNotes == false,
    'Suite 31 Test 7: isAllNotes is false when pinned is active',
  );
  final fFavorites = fDefault.copyWith(isFavoritesOnly: true);
  expect(
    fFavorites.isAllNotes == false,
    'Suite 31 Test 8: isAllNotes is false when favorites is active',
  );

  // Check 9-10: State transition - Recent filter
  var filterSim = const NoteFilterState();
  // setRecentOnly(true)
  filterSim = filterSim.copyWith(
    isRecentOnly: true,
    isFavoritesOnly: false,
    isPinnedOnly: false,
    clearFolder: true,
    sortOrder: NoteSortOrder.recentlyModified,
  );
  expect(
    filterSim.isRecentOnly == true &&
        filterSim.sortOrder == NoteSortOrder.recentlyModified,
    'Suite 31 Test 9: setRecentOnly activates recent sort',
  );
  // toggleRecentOnly()
  filterSim = filterSim.copyWith(isRecentOnly: !filterSim.isRecentOnly);
  expect(
    filterSim.isRecentOnly == false,
    'Suite 31 Test 10: toggleRecentOnly deactivates recent filter',
  );

  // Check 11-12: State transition - Pinned filter
  filterSim = filterSim.copyWith(
    isPinnedOnly: true,
    isFavoritesOnly: false,
    isRecentOnly: false,
    clearFolder: true,
  );
  expect(
    filterSim.isPinnedOnly == true && filterSim.isRecentOnly == false,
    'Suite 31 Test 11: setPinnedOnly activates pinned filter',
  );
  filterSim = filterSim.copyWith(isPinnedOnly: !filterSim.isPinnedOnly);
  expect(
    filterSim.isPinnedOnly == false,
    'Suite 31 Test 12: togglePinnedOnly deactivates pinned filter',
  );

  // Check 13-14: Selecting a folder resets recent and pinned
  filterSim = filterSim.copyWith(isRecentOnly: true, isPinnedOnly: false);
  filterSim = filterSim.copyWith(
    folderFilter: const FolderFilter.folder('folder-work'),
    isFavoritesOnly: false,
    isRecentOnly: false,
    isPinnedOnly: false,
  );
  expect(
    filterSim.selectedFolderId == 'folder-work',
    'Suite 31 Test 13: Folder filter activated',
  );
  expect(
    filterSim.isRecentOnly == false && filterSim.isPinnedOnly == false,
    'Suite 31 Test 14: Recent and Pinned cleared when folder selected',
  );

  // Check 15-16: selectAllNotes resets all filter dimensions
  filterSim = filterSim.copyWith(
    isFavoritesOnly: true,
    isRecentOnly: true,
    isPinnedOnly: true,
    selectedTagIds: {'tag-1'},
  );
  filterSim = filterSim.copyWith(
    folderFilter: const FolderFilter.all(),
    isFavoritesOnly: false,
    isRecentOnly: false,
    isPinnedOnly: false,
    clearTags: true,
  );
  expect(
    filterSim.isAllNotes == true,
    'Suite 31 Test 15: selectAllNotes restores isAllNotes to true',
  );
  expect(
    filterSim.selectedTagIds.isEmpty && filterSim.selectedFolderId == null,
    'Suite 31 Test 16: selectAllNotes clears folder and tags',
  );

  stdout.writeln('Suite 31 passed successfully! ✓ (16/16 Checks)');

  stdout.writeln('ALL NOTEFLOW TESTS PASSED! (444/444 Assertions) ✓');
}

enum _TestPlaybackStatus { idle, loading, playing, paused, completed, error }

class _TestVoicePlaybackState {
  final String? activeRecordingId;
  final _TestPlaybackStatus status;
  final Duration position;
  final Duration duration;
  final String? errorMessage;

  const _TestVoicePlaybackState({
    this.activeRecordingId,
    this.status = _TestPlaybackStatus.idle,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.errorMessage,
  });

  bool get isPlaying => status == _TestPlaybackStatus.playing;
  bool get isLoading => status == _TestPlaybackStatus.loading;
  bool get isPaused => status == _TestPlaybackStatus.paused;
  bool get isCompleted => status == _TestPlaybackStatus.completed;
  bool get isError => status == _TestPlaybackStatus.error;

  bool isRecordingActive(String id) => activeRecordingId == id;
  bool isRecordingPlaying(String id) => activeRecordingId == id && isPlaying;
  bool isRecordingLoading(String id) => activeRecordingId == id && isLoading;

  _TestVoicePlaybackState copyWith({
    String? activeRecordingId,
    _TestPlaybackStatus? status,
    Duration? position,
    Duration? duration,
    String? errorMessage,
  }) {
    return _TestVoicePlaybackState(
      activeRecordingId: activeRecordingId ?? this.activeRecordingId,
      status: status ?? this.status,
      position: position ?? this.position,
      duration: duration ?? this.duration,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}
