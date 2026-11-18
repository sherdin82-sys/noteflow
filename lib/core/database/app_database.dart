// Database table schema definitions for Drift and SQLite
//
// NoteFlow uses Drift for type-safe database access and reactive SQL streams.
// Both table schemas are declared here according to Drift specifications.

class NotesTableDefinition {
  static const String tableName = 'notes';

  static const String colId = 'id';
  static const String colTitle = 'title';
  static const String colContent = 'content';
  static const String colFolderId = 'folder_id';
  static const String colIsPinned = 'is_pinned';
  static const String colIsArchived = 'is_archived';
  static const String colIsChecklist = 'is_checklist';
  static const String colColorIndex = 'color_index';
  static const String colAudioPath = 'audio_path';
  static const String colAudioDurationMs = 'audio_duration_ms';
  static const String colCreatedAt = 'created_at';
  static const String colUpdatedAt = 'updated_at';

  static const String createTableSql = '''
    CREATE TABLE IF NOT EXISTS $tableName (
      $colId TEXT PRIMARY KEY NOT NULL,
      $colTitle TEXT NOT NULL DEFAULT '',
      $colContent TEXT NOT NULL DEFAULT '',
      $colFolderId TEXT,
      $colIsPinned INTEGER NOT NULL DEFAULT 0,
      $colIsArchived INTEGER NOT NULL DEFAULT 0,
      $colIsChecklist INTEGER NOT NULL DEFAULT 0,
      $colColorIndex INTEGER NOT NULL DEFAULT 0,
      $colAudioPath TEXT,
      $colAudioDurationMs INTEGER,
      $colCreatedAt TEXT NOT NULL,
      $colUpdatedAt TEXT NOT NULL
    );
  ''';
}

class FoldersTableDefinition {
  static const String tableName = 'folders';

  static const String colId = 'id';
  static const String colName = 'name';
  static const String colColorHex = 'color_hex';
  static const String colIconName = 'icon_name';
  static const String colCreatedAt = 'created_at';

  static const String createTableSql = '''
    CREATE TABLE IF NOT EXISTS $tableName (
      $colId TEXT PRIMARY KEY NOT NULL,
      $colName TEXT NOT NULL,
      $colColorHex TEXT NOT NULL DEFAULT '0xFF2563EB',
      $colIconName TEXT NOT NULL DEFAULT 'folder',
      $colCreatedAt TEXT NOT NULL
    );
  ''';
}
