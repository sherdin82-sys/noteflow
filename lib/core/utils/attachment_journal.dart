import 'dart:convert';
import 'dart:io';

/// Represents a single durable transaction or tombstone entry in `attachments_journal.json`.
class AttachmentJournalEntry {
  final String txId;
  final String type; // 'TOMBSTONE_NOTE', 'DELETE_ATTACHMENT', 'IMPORT_ATTACHMENT'
  final String noteId;
  final String? attachmentId;
  final String? relativePath;
  final String? stagingPath;
  final String state; // 'PENDING', 'COMMITTED', 'ABANDONED'
  final int timestamp;

  const AttachmentJournalEntry({
    required this.txId,
    required this.type,
    required this.noteId,
    this.attachmentId,
    this.relativePath,
    this.stagingPath,
    this.state = 'PENDING',
    required this.timestamp,
  });

  Map<String, dynamic> toMap() {
    return {
      'txId': txId,
      'type': type,
      'noteId': noteId,
      if (attachmentId != null) 'attachmentId': attachmentId,
      if (relativePath != null) 'relativePath': relativePath,
      if (stagingPath != null) 'stagingPath': stagingPath,
      'state': state,
      'timestamp': timestamp,
    };
  }

  factory AttachmentJournalEntry.fromMap(Map<String, dynamic> map) {
    return AttachmentJournalEntry(
      txId: map['txId'] as String? ?? '',
      type: map['type'] as String? ?? '',
      noteId: map['noteId'] as String? ?? '',
      attachmentId: map['attachmentId'] as String?,
      relativePath: map['relativePath'] as String?,
      stagingPath: map['stagingPath'] as String?,
      state: map['state'] as String? ?? 'PENDING',
      timestamp: map['timestamp'] as int? ?? DateTime.now().millisecondsSinceEpoch,
    );
  }
}

/// Manages durable recording, retrieval, and atomic persistence of attachment
/// transactions and note deletion tombstones in `<Documents>/attachments_journal.json`.
class AttachmentJournal {
  const AttachmentJournal._();

  static const String journalFileName = 'attachments_journal.json';

  static File _getJournalFile(String documentsBasePath) {
    return File('$documentsBasePath/$journalFileName');
  }

  /// Loads all current journal entries from disk.
  static Future<List<AttachmentJournalEntry>> loadEntries(String documentsBasePath) async {
    try {
      final file = _getJournalFile(documentsBasePath);
      if (!await file.exists()) return [];
      final content = await file.readAsString();
      if (content.trim().isEmpty) return [];
      final list = jsonDecode(content) as List<dynamic>;
      return list
          .map((item) => AttachmentJournalEntry.fromMap(Map<String, dynamic>.from(item as Map)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// Atomically writes journal entries using a temporary file and atomic rename.
  static Future<void> _writeEntries(String documentsBasePath, List<AttachmentJournalEntry> entries) async {
    try {
      final file = _getJournalFile(documentsBasePath);
      if (entries.isEmpty) {
        if (await file.exists()) {
          await file.delete();
        }
        return;
      }
      final tmpFile = File('${file.path}.tmp');
      final data = jsonEncode(entries.map((e) => e.toMap()).toList());
      await tmpFile.writeAsString(data, flush: true);
      await tmpFile.rename(file.path);
    } catch (_) {}
  }

  /// Records a committed tombstone for a note scheduled for deletion.
  static Future<void> recordTombstone({
    required String documentsBasePath,
    required String txId,
    required String noteId,
  }) async {
    final entries = await loadEntries(documentsBasePath);
    entries.removeWhere((e) => e.type == 'TOMBSTONE_NOTE' && e.noteId == noteId);
    entries.add(AttachmentJournalEntry(
      txId: txId,
      type: 'TOMBSTONE_NOTE',
      noteId: noteId,
      state: 'COMMITTED',
      timestamp: DateTime.now().millisecondsSinceEpoch,
    ));
    await _writeEntries(documentsBasePath, entries);
  }

  /// Removes a note deletion tombstone once note and attachments are fully deleted.
  static Future<void> removeTombstone({
    required String documentsBasePath,
    required String noteId,
  }) async {
    final entries = await loadEntries(documentsBasePath);
    entries.removeWhere((e) => e.type == 'TOMBSTONE_NOTE' && e.noteId == noteId);
    await _writeEntries(documentsBasePath, entries);
  }

  /// Checks if a note has an active tombstone recorded in the journal.
  static Future<bool> isNoteTombstoned({
    required String documentsBasePath,
    required String noteId,
  }) async {
    final entries = await loadEntries(documentsBasePath);
    return entries.any((e) => e.type == 'TOMBSTONE_NOTE' && e.noteId == noteId);
  }

  /// Records a pending attachment deletion.
  static Future<void> recordDeletePending({
    required String documentsBasePath,
    required String txId,
    required String noteId,
    required String attachmentId,
    required String relativePath,
  }) async {
    final entries = await loadEntries(documentsBasePath);
    entries.add(AttachmentJournalEntry(
      txId: txId,
      type: 'DELETE_ATTACHMENT',
      noteId: noteId,
      attachmentId: attachmentId,
      relativePath: relativePath,
      state: 'PENDING',
      timestamp: DateTime.now().millisecondsSinceEpoch,
    ));
    await _writeEntries(documentsBasePath, entries);
  }

  /// Records a pending attachment import.
  static Future<void> recordImportPending({
    required String documentsBasePath,
    required String txId,
    required String noteId,
    required String attachmentId,
    required String relativePath,
    required String stagingPath,
  }) async {
    final entries = await loadEntries(documentsBasePath);
    entries.add(AttachmentJournalEntry(
      txId: txId,
      type: 'IMPORT_ATTACHMENT',
      noteId: noteId,
      attachmentId: attachmentId,
      relativePath: relativePath,
      stagingPath: stagingPath,
      state: 'PENDING',
      timestamp: DateTime.now().millisecondsSinceEpoch,
    ));
    await _writeEntries(documentsBasePath, entries);
  }

  /// Removes a specific entry by its transaction ID.
  static Future<void> removeEntry({
    required String documentsBasePath,
    required String txId,
  }) async {
    final entries = await loadEntries(documentsBasePath);
    entries.removeWhere((e) => e.txId == txId);
    await _writeEntries(documentsBasePath, entries);
  }

  /// Completely clears all journal entries.
  static Future<void> clearJournal(String documentsBasePath) async {
    await _writeEntries(documentsBasePath, []);
  }
}
