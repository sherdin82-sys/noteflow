# NoteFlow — Attachments Feature: Complete Architecture Audit

> **Document Type:** Deep Architecture & Persistence Audit  
> **Application:** NoteFlow (v1.5.0)  
> **Target Platform:** Android (Flutter 3.22+ / Dart 3.14+ / Kotlin / Material 3)  
> **Audit Mode:** Read-Only Technical Inspection  
> **Date:** November 2026  

---

## 1. Executive Summary

A comprehensive, read-only architectural inspection of the **NoteFlow** codebase was conducted to determine how to safely, reliably, and seamlessly implement an end-to-end **Attachments** feature across all note types.

### Key Audit Findings

1. **Authoritative Persistence Mechanism:**  
   Despite the declaration of `drift: ^2.20.0`, `drift_flutter: ^0.2.0`, and `sqlite3_flutter_libs` in `pubspec.yaml`, and table definitions in `lib/core/database/app_database.dart`, **Drift SQLite is completely unused at runtime**. The true and sole authoritative storage layer is `LocalNoteRepository` backed by in-memory reactive data structures, persistent local filesystem audio storage, and durable single-file JSON disk persistence at `<Documents>/noteflow_data.json`.
2. **Note Types Support:**  
   NoteFlow supports three distinct note modes: **Text Notes**, **Checklists**, and **Voice Notes** (plus a hybrid voice memo capability inside text notes). All three note types are unified by `NoteEntity.id` (UUID v4) and can natively support attachments without altering their core data formats or breaking existing behavior.
3. **Existing Audio Storage vs. Attachments:**  
   Voice recordings are stored under `<Documents>/voice_notes/<voiceNoteId>/<recordingId>.m4a` and managed by `AudioHelper`. Attachments **must not** be stored in the voice recording directory; doing so would cause path collisions, break voice migration/recovery algorithms, and corrupt directory cleanup logic. Attachments require a dedicated app-private directory: `<Documents>/attachments/<noteId>/<attachmentId>.<ext>`, managed by a dedicated `AttachmentHelper` replicating `AudioHelper`'s verified atomic file-safety patterns.
4. **Android Native Integration & Build Constraints:**  
   The project operates in an environment with strict Android Gradle Plugin (AGP 9) and JNI type-descriptor requirements (evidenced by `scripts/patch_plugins.py`). Introducing third-party Flutter file/image picker plugins carries high build compatibility risks. A lightweight Kotlin `MethodChannel` implementing Android's standard `ActivityResultContracts` (Photo Picker and Storage Access Framework `ACTION_OPEN_DOCUMENT`) requires **zero external packages**, **zero runtime storage permissions**, and allows direct stream copying into app-private storage.
5. **Backup & Restore System:**  
   `BackupService` and `RestoreService` package database state and base64-encoded audio files into `.noteflow` (JSON/gzip) packages. The backup engine can be extended cleanly to version 3 to include attachment metadata and base64 payloads, while preserving 100% backward compatibility with existing version 1 and version 2 backups.
6. **Integrity of Existing Features:**  
   Existing test suites (`test/unit/noteflow_core_test.dart` — 30 suites, 428 assertions) run cleanly with 100% pass rate. The attachment architecture proposed here preserves all existing contracts, auto-save debounce behaviors, pop scope lifecycles, and reminder integrations.

---

## 2. Verified Current Architecture

### 2.1 Directory Structure & Layering

NoteFlow follows a modular Clean Architecture pattern:

```
lib/
├── core/
│   ├── constants/         # AppConstants (dimensions, auto-save debounce, versions)
│   ├── database/          # Persistence contracts, local repository, schema specs
│   ├── theme/             # AppTheme, AppColors, AppTypography, ThemeNotifier
│   └── utils/             # NoteHelper, AudioHelper, DateFormatter
├── features/
│   ├── archive/           # ArchiveScreen (filtered note view)
│   ├── backup/            # BackupService, RestoreService, BackupRestoreScreen
│   ├── editor/            # NoteEditorScreen, ChecklistView, EditorToolbar, VoiceNoteWidget
│   ├── folders/           # FoldersScreen, folder management
│   ├── home/              # HomeScreen, NoteCard, RichNotePreview, Header, Filters
│   ├── reminders/         # ReminderService, Scheduler, NativeBridge, BottomSheets
│   ├── tags/              # TagsScreen, TagSelectorModal, TagChip, TagDialog
│   └── voice_notes/       # VoiceNoteEditorScreen, VoicePlayerNotifier, LiveRecordingModal
├── shared/
│   ├── models/            # NoteEntity, FolderEntity, TagEntity, VoiceRecordingEntity, ReminderEntity, BackupModels
│   └── widgets/           # EmptyStateView, PremiumCard
└── main.dart              # App bootstrap, Riverpod ProviderScope, local repository hydration
```

### 2.2 Riverpod State Management Topology

The application relies on `flutter_riverpod: ^2.5.1`. Tracing `lib/main.dart` (lines 14–44) and `lib/core/database/database_provider.dart` (lines 1–56):

* **`noteRepositoryProvider` (`Provider<NoteRepository>`):**  
  Instantiated in `lib/main.dart` as `LocalNoteRepository` configured with `NativeReminderScheduler` and `getApplicationDocumentsDirectory()`. Overridden in the root `ProviderScope`.
* **`activeNotesStreamProvider` (`StreamProvider<List<NoteEntity>>`):**  
  Streams active (non-archived) notes sorted by `updatedAt` descending.
* **`archivedNotesStreamProvider` (`StreamProvider<List<NoteEntity>>`):**  
  Streams archived notes.
* **`favoriteNotesStreamProvider` (`Provider<AsyncValue<List<NoteEntity>>>`):**  
  Filters active notes by `isFavorite == true`.
* **`foldersStreamProvider` (`StreamProvider<List<FolderEntity>>`):**  
  Streams all user folders.
* **`tagsStreamProvider` (`StreamProvider<List<TagEntity>>`):**  
  Streams all tags sorted alphabetically.
* **`voiceRecordingsStreamProvider` (`StreamProvider.family<List<VoiceRecordingEntity>, String>`):**  
  Streams voice recordings belonging to a given `voiceNoteId`.
* **`homeNotesProvider` (`Provider` in `lib/features/home/providers/home_notes_provider.dart`):**  
  Applies active filters (`NoteFilterState`: search query, folder filter, tag filter, sort order) to active notes.
* **`voicePlayerProvider` (`StateNotifierProvider<VoicePlayerNotifier, VoicePlaybackState>`):**  
  Manages single-instance audio playback via `audioplayers: ^6.1.0`.

### 2.3 Navigation Architecture

Navigation is entirely Flutter-native using `MaterialPageRoute` stacks:
* `HomeScreen` acts as the root hub.
* Tapping a standard or checklist note pushes `NoteEditorScreen`.
* Tapping a voice note (`isVoiceNote == true`) pushes `VoiceNoteEditorScreen`.
* Top header actions push `FoldersScreen`, `TagsScreen`, `ArchiveScreen`, `BackupRestoreScreen`, and `ReminderManagementScreen`.

---

## 3. Existing File and Media Handling

### 3.1 Physical Storage Locations

On Android, NoteFlow uses `path_provider: ^2.1.3` to access standard OS storage directories:
* **Documents Directory:** `getApplicationDocumentsDirectory()`  
  Maps to `/data/user/0/com.noteflow.app/app_flutter`. This is **internal app-private storage**. Files placed here are sandboxed, invisible to other apps, preserved across reboots and app updates, and exempt from Android storage permissions.
* **Temporary Directory:** `getTemporaryDirectory()`  
  Maps to `/data/user/0/com.noteflow.app/cache`. Used for temporary audio staging during active recording sessions.

### 3.2 File Hierarchy on Disk

```
/data/user/0/com.noteflow.app/app_flutter/
├── noteflow_data.json                          # Authoritative JSON database
├── backups/                                    # Local .noteflow backup archives
│   ├── noteflow_backup_20261120_143000.noteflow
│   └── pre_restore_safety.bak                  # Pre-restore safety rollback snapshot
└── voice_notes/                                # Permanent voice audio storage
    ├── <voiceNoteId>/                          # Container voice notes
    │   ├── <recordingId-1>.m4a
    │   └── <recordingId-2>.m4a
    └── <noteId>/                               # Hybrid note audio
        └── standalone_audio.m4a
```

### 3.3 File Transfer & Verification Pattern

Examining `lib/core/utils/audio_helper.dart` (lines 58–97) reveals NoteFlow's verified file handling standard:
1. Verify source file exists and has `length > 0`.
2. Ensure destination directory exists (`createSync(recursive: true)`).
3. Copy source file to permanent path.
4. Verify destination file exists and has `length > 0`.
5. Only after verification succeeds, delete the temporary file.

---

## 4. Existing Voice Recording Architecture

The voice note subsystem represents NoteFlow's most sophisticated media implementation.

```
┌─────────────────────────────────────────────────────────────┐
│                   Voice Recording Pipeline                  │
└─────────────────────────────────────────────────────────────┘
  1. Record Hardware        2. Temp Staging            3. Verification & Copy
┌──────────────────┐     ┌───────────────────┐      ┌─────────────────────────┐
│ record: ^5.2.0   │────▶│ <cache>/          │─────▶│ AudioHelper.save...     │
│ AAC-LC 128kbps   │     │ voice_recordings_ │      │ -> Verify size > 0      │
│ AudioEncoder.aac │     │ temp/<uuid>.m4a   │      │ -> Copy to app_flutter  │
└──────────────────┘     └───────────────────┘      └─────────────────────────┘
                                                                 │
  4. Repository & Storage   5. Playback Controller               ▼
┌──────────────────┐     ┌───────────────────┐      ┌─────────────────────────┐
│ LocalNoteRepo    │◀────│ VoicePlayer       │◀─────│ <app_flutter>/          │
│ voice_recordings │     │ audioplayers      │      │ voice_notes/<noteId>/   │
│ in JSON DB       │     │ DeviceFileSource  │      │ <recordingId>.m4a       │
└──────────────────┘     └───────────────────┘      └─────────────────────────┘
```

### 4.1 Storage & Naming
* Audio recordings are saved in `<Documents>/voice_notes/<voiceNoteId>/<recordingId>.<format>`.
* Primary format is `m4a` (AAC-LC audio encoding). Seed/demo audio uses RIFF WAVE (`wav`).
* Naming format is strictly `<UUID>.m4a` to prevent collisions.

### 4.2 Recording Metadata Model (`VoiceRecordingEntity`)
Located at `lib/shared/models/voice_recording_entity.dart`:
* `id: String` (UUID)
* `voiceNoteId: String` (FK to parent `NoteEntity.id`)
* `title: String`
* `audioPath: String` (full path or relative path)
* `durationMs: int`
* `fileSize: int`
* `createdAt: DateTime`
* `sortOrder: int`
* `isCompleted: bool` (for voice checklist mode)
* `format: String` (`m4a` or `wav`)

### 4.3 Playback Engine (`VoicePlayerNotifier`)
Located at `lib/features/voice_notes/presentation/controllers/voice_player_controller.dart`:
* Uses `AudioPlayer` from `audioplayers: ^6.1.0`.
* Configured with `AudioContextAndroid` (speakerphone forced, media usage type, normal mode).
* Pre-playback validation: Resolves path via `AudioHelper.resolveAudioPath`, checks `file.existsSync()`, verifies `file.lengthSync() > 0`, and transitions state to `PlaybackStatus.loading` before `play()`.
* Automatically stops before recording starts or when navigating away (`PopScope`).

### 4.4 Deletion & Cascade Lifecycle
* In `LocalNoteRepository.deleteVoiceRecording(recordingId)`:
  1. Resolves path using `AudioHelper.resolveAudioPath(rec.audioPath, baseDir)`.
  2. Deletes physical file `File(filePath).delete()`.
  3. Cancels and deletes associated child reminders (`voiceRecordingId == recordingId`).
  4. Removes recording from `_voiceRecordings` list.
  5. Flushes `noteflow_data.json` to disk.
* In `LocalNoteRepository.deleteNote(id)`:
  1. Deletes `note.audioPath` if populated.
  2. Iterates all child recordings (`voiceNoteId == id`), deleting each audio file.
  3. Cleans up empty parent directories.
  4. Deletes directory `<Documents>/voice_notes/<id>` recursively.

### 4.5 Why Audio Storage Cannot Be Reused for Attachments
1. **Domain Collision:** Voice recordings represent playable audio assets with duration, waveform amplitudes, playback positions, and completion checkmarks. Attachments represent generic external documents and images with MIME types, original file names, and external viewing capabilities.
2. **Directory Teardown Risks:** `LocalNoteRepository.deleteNote` executes `Directory('$baseDir/voice_notes/$id').delete(recursive: true)`. If attachments were intermingled in `voice_notes`, a note's audio cleanup would silently delete documents and images.
3. **Migration & Path Resolution Logic:** `AudioHelper.recoverOrMigrateAudioFile` specifically assumes audio formats (`m4a`, `wav`, `aac`). Running this logic against PDFs, spreadsheets, or images would corrupt metadata.
4. **Architectural Separation:** A dedicated `<Documents>/attachments/<noteId>/` directory ensures clean isolation, targeted backup strategies, and zero risk to existing voice features.

---

## 5. Actual Persistence Mechanism: Reality vs. Schema

### 5.1 Verification of Schema Declarations vs. Runtime Storage

`pubspec.yaml` contains:
```yaml
dependencies:
  drift: ^2.20.0
  drift_flutter: ^0.2.0
  sqlite3_flutter_libs: ^0.5.24
```
And `lib/core/database/app_database.dart` defines:
```dart
class NotesTableDefinition { ... }
class FoldersTableDefinition { ... }
class TagsTableDefinition { ... }
class VoiceRecordingsTableDefinition { ... }
```

**Audit Result:**
* A global codebase search (`grep -rn "app_database" lib/ test/`) returned **0 occurrences**.
* A global search for Drift classes (`AppDatabase`, `DatabaseConnection`, `QueryExecutor`, `into()`, `select()`) returned **0 occurrences**.
* Drift is **not imported anywhere** in `lib/` or `test/`.
* `NotesTableDefinition` and related classes in `app_database.dart` are **pure static string declarations** that are never executed or compiled into a database.

### 5.2 The Authoritative Runtime Persistence: `LocalNoteRepository`

Tracing runtime operations in `lib/core/database/local_note_repository.dart`:
1. **In-Memory Store:**  
   `LocalNoteRepository` maintains private in-memory lists:
   * `List<NoteEntity> _notes`
   * `List<FolderEntity> _folders`
   * `List<TagEntity> _tags`
   * `List<VoiceRecordingEntity> _voiceRecordings`
   * `List<ReminderEntity> _reminders`
2. **Reactivity:**  
   Broadcast `StreamController`s emit unmodifiable list snapshots whenever an entity is saved, toggled, or deleted.
3. **Disk Durability:**  
   Every write operation (`saveNote`, `deleteNote`, `saveVoiceRecording`, `deleteVoiceRecording`, `saveFolder`, `deleteFolder`, `saveTag`, `deleteTag`, `saveReminder`, `deleteReminder`, `setThemeMode`) invokes `_saveToDisk()`.
4. **Serialization Target:**  
   `_saveToDisk()` encodes the entire repository state into a single JSON document:
   `<Documents>/noteflow_data.json` with `flush: true`.
5. **Cold Boot Hydration:**  
   `LocalNoteRepository.init()` reads `<Documents>/noteflow_data.json`, deserializes all entities using `.fromMap()`, seeds sample audio files if necessary, and emits the restored entities to their respective stream controllers.

```json
{
  "version": 1,
  "theme_mode": "dark",
  "next_notification_id": 1005,
  "folders": [ ... ],
  "tags": [ ... ],
  "notes": [ ... ],
  "voice_recordings": [ ... ],
  "reminders": [ ... ]
}
```

### 5.3 Persistence Architectural Decision for Attachments
To prevent introducing a second, unsynchronized source of truth:
* Attachment metadata **must integrate directly** into `LocalNoteRepository` as `final List<AttachmentEntity> _attachments = [];`.
* Serialized into `noteflow_data.json` under the key `'attachments'`.
* Streamed reactively via `watchAttachments(String noteId)`.
* For schema completeness, an `AttachmentsTableDefinition` should also be added to `lib/core/database/app_database.dart`.

---

## 6. Proposed Attachment Architecture

```
┌────────────────────────────────────────────────────────────────────────┐
│                        Attachment Architecture                         │
└────────────────────────────────────────────────────────────────────────┘
                    ┌──────────────────────────────┐
                    │      NoteFlow UI Layer       │
                    │ Text / Checklist / Voice Note│
                    └──────────────┬───────────────┘
                                   │
                                   ▼
                    ┌──────────────────────────────┐
                    │  AttachmentNativeBridge /    │
                    │  AttachmentPicker (SAF/Photo)│
                    └──────────────┬───────────────┘
                                   │
                                   ▼
                    ┌──────────────────────────────┐
                    │       AttachmentHelper       │
                    │ Stream copy to app sandbox   │
                    │ Generate UUID stored filename│
                    └──────────────┬───────────────┘
                                   │
        ┌──────────────────────────┴──────────────────────────┐
        ▼                                                     ▼
┌──────────────────────────────┐             ┌──────────────────────────────┐
│     Attachment Storage       │             │     LocalNoteRepository      │
│ <Documents>/attachments/     │             │ _attachments in memory       │
│ <noteId>/<attachmentId>.<ext>│             │ Synced to noteflow_data.json │
└──────────────────────────────┘             └──────────────────────────────┘
```

### 6.1 Architectural Principles
1. **Immutable Domain Entities:** `AttachmentEntity` is an immutable data class with `toMap()`, `fromMap()`, and `copyWith()`.
2. **Repository Single Source of Truth:** `NoteRepository` defines attachment operations; `LocalNoteRepository` implements them with in-memory caching and disk sync.
3. **Dedicated Storage Manager:** `AttachmentHelper` provides static methods for file staging, directory sandboxing, path resolution, thumbnail caching, and safe deletion.
4. **Reactive Streams:** `attachmentsStreamProvider(noteId)` emits realtime updates to editor widgets whenever attachments are added or removed.
5. **Zero Interference:** Attachments act as a modular child collection linked by `noteId`. Standard note saving, text editing, checklist ticking, and audio recording remain completely untouched.

---

## 7. Proposed Data Model

### 7.1 Attachment Category Enum

```dart
enum AttachmentCategory {
  image,
  document,
  audio,
  video,
  other;

  static AttachmentCategory fromMime(String mimeType, String extension) {
    final lowerMime = mimeType.toLowerCase();
    final lowerExt = extension.toLowerCase();

    if (lowerMime.startsWith('image/') || {'jpg', 'jpeg', 'png', 'webp', 'gif', 'bmp', 'svg'}.contains(lowerExt)) {
      return AttachmentCategory.image;
    }
    if (lowerMime.startsWith('audio/') || {'mp3', 'm4a', 'wav', 'aac', 'ogg', 'flac'}.contains(lowerExt)) {
      return AttachmentCategory.audio;
    }
    if (lowerMime.startsWith('video/') || {'mp4', 'mkv', 'mov', 'webm'}.contains(lowerExt)) {
      return AttachmentCategory.video;
    }
    if (lowerMime.contains('pdf') ||
        lowerMime.contains('document') ||
        lowerMime.contains('text') ||
        lowerMime.contains('sheet') ||
        lowerMime.contains('presentation') ||
        {'pdf', 'doc', 'docx', 'txt', 'rtf', 'xls', 'xlsx', 'csv', 'ppt', 'pptx'}.contains(lowerExt)) {
      return AttachmentCategory.document;
    }
    return AttachmentCategory.other;
  }
}
```

### 7.2 Domain Entity: `AttachmentEntity`
Location: `lib/shared/models/attachment_entity.dart`

```dart
class AttachmentEntity {
  final String id;
  final String noteId;
  final String originalName;
  final String storedName;
  final String relativePath;
  final String mimeType;
  final String fileExtension;
  final int fileSizeBytes;
  final AttachmentCategory category;
  final DateTime createdAt;

  const AttachmentEntity({
    required this.id,
    required this.noteId,
    required this.originalName,
    required this.storedName,
    required this.relativePath,
    required this.mimeType,
    required this.fileExtension,
    required this.fileSizeBytes,
    required this.category,
    required this.createdAt,
  });

  bool get isImage => category == AttachmentCategory.image;
  bool get isDocument => category == AttachmentCategory.document;

  String get formattedSize {
    if (fileSizeBytes <= 0) return '0 B';
    if (fileSizeBytes < 1024) return '$fileSizeBytes B';
    if (fileSizeBytes < 1024 * 1024) {
      return '${(fileSizeBytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(fileSizeBytes / (1024 * 1024)).toStringAsFixed(2)} MB';
  }

  AttachmentEntity copyWith({
    String? id,
    String? noteId,
    String? originalName,
    String? storedName,
    String? relativePath,
    String? mimeType,
    String? fileExtension,
    int? fileSizeBytes,
    AttachmentCategory? category,
    DateTime? createdAt,
  }) {
    return AttachmentEntity(
      id: id ?? this.id,
      noteId: noteId ?? this.noteId,
      originalName: originalName ?? this.originalName,
      storedName: storedName ?? this.storedName,
      relativePath: relativePath ?? this.relativePath,
      mimeType: mimeType ?? this.mimeType,
      fileExtension: fileExtension ?? this.fileExtension,
      fileSizeBytes: fileSizeBytes ?? this.fileSizeBytes,
      category: category ?? this.category,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'note_id': noteId,
      'original_name': originalName,
      'stored_name': storedName,
      'relative_path': relativePath,
      'mime_type': mimeType,
      'file_extension': fileExtension,
      'file_size_bytes': fileSizeBytes,
      'category': category.name,
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory AttachmentEntity.fromMap(Map<String, dynamic> map) {
    final ext = map['file_extension'] as String? ?? '';
    final mime = map['mime_type'] as String? ?? 'application/octet-stream';
    final catName = map['category'] as String?;
    final cat = catName != null
        ? AttachmentCategory.values.firstWhere((e) => e.name == catName, orElse: () => AttachmentCategory.fromMime(mime, ext))
        : AttachmentCategory.fromMime(mime, ext);

    return AttachmentEntity(
      id: map['id'] as String,
      noteId: map['note_id'] as String? ?? '',
      originalName: map['original_name'] as String? ?? 'attachment',
      storedName: map['stored_name'] as String? ?? '',
      relativePath: map['relative_path'] as String? ?? '',
      mimeType: mime,
      fileExtension: ext,
      fileSizeBytes: map['file_size_bytes'] as int? ?? 0,
      category: cat,
      createdAt: DateTime.tryParse(map['created_at'] as String? ?? '') ?? DateTime.now(),
    );
  }
}
```

---

## 8. File Storage Design

### 8.1 Directory Structure & Relative Pathing
To ensure attachments survive app sandbox directory re-rooting (which occurs on Android during app updates or restores), the database records a **relative storage path**:
```
relativePath = "attachments/<noteId>/<attachmentId>.<fileExtension>"
```
At runtime, this path is resolved against the current base directory:
```
absolutePath = "$documentsBasePath/$relativePath"
```

### 8.2 Safe Storage Operations (`AttachmentHelper`)
Location: `lib/core/utils/attachment_helper.dart`

```dart
class AttachmentHelper {
  const AttachmentHelper._();

  static const String attachmentsDirName = 'attachments';

  /// Resolves the absolute path for an attachment relative path.
  static String resolvePath({
    required String relativePath,
    required String documentsBasePath,
  }) {
    if (relativePath.startsWith(documentsBasePath)) return relativePath;
    return '$documentsBasePath/$relativePath';
  }

  /// Copies an incoming file into app-private storage.
  static Future<AttachmentEntity?> copyToPermanentStorage({
    required File sourceFile,
    required String originalName,
    required String noteId,
    required String documentsBasePath,
    String? mimeType,
  }) async {
    if (!await sourceFile.exists()) return null;
    final length = await sourceFile.length();
    if (length == 0) return null;

    final attachmentId = const Uuid().v4();
    final extension = _extractExtension(originalName);
    final storedName = '$attachmentId.$extension';
    final relativePath = '$attachmentsDirName/$noteId/$storedName';

    final targetDir = Directory('$documentsBasePath/$attachmentsDirName/$noteId');
    if (!await targetDir.exists()) {
      await targetDir.create(recursive: true);
    }

    final targetFile = File('${targetDir.path}/$storedName');
    
    // Streamed copy prevents OOM on large files
    final sink = targetFile.openWrite();
    await sourceFile.openRead().pipe(sink);

    if (!await targetFile.exists() || await targetFile.length() == 0) {
      if (await targetFile.exists()) await targetFile.delete();
      return null;
    }

    final resolvedMime = mimeType ?? _guessMimeType(extension);
    final category = AttachmentCategory.fromMime(resolvedMime, extension);

    return AttachmentEntity(
      id: attachmentId,
      noteId: noteId,
      originalName: originalName,
      storedName: storedName,
      relativePath: relativePath,
      mimeType: resolvedMime,
      fileExtension: extension,
      fileSizeBytes: length,
      category: category,
      createdAt: DateTime.now(),
    );
  }

  /// Safely deletes an attachment file.
  static Future<void> deleteAttachmentFile({
    required String relativePath,
    required String documentsBasePath,
  }) async {
    try {
      final file = File(resolvePath(relativePath: relativePath, documentsBasePath: documentsBasePath));
      if (await file.exists()) {
        await file.delete();
      }
      final parent = file.parent;
      if (await parent.exists() && await parent.list().isEmpty) {
        await parent.delete();
      }
    } catch (_) {}
  }

  /// Deletes all attachments for a note.
  static Future<void> deleteNoteAttachmentsDirectory({
    required String noteId,
    required String documentsBasePath,
  }) async {
    try {
      final dir = Directory('$documentsBasePath/$attachmentsDirName/$noteId');
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    } catch (_) {}
  }
}
```

### 8.3 Durability Across Restarts & Process Termination
* **App Restart:** File paths and metadata are written to disk with `flush: true`. On next startup, `LocalNoteRepository.init()` re-populates the in-memory state.
* **Process Termination / Force Stop:** Because the file bytes are flushed to the internal disk before the entity is committed to `noteflow_data.json`, an abrupt OS process termination leaves no orphaned metadata pointing to unwritten files.
* **Sanitized Filenames:** Even if `originalName` is `../../../etc/passwd.jpg`, the physical file is written as `att-uuid.jpg`. Directory traversal attacks are completely thwarted.

---

## 9. Android Integration Requirements

### 9.1 Modern Android Media & Document Selection Capabilities

Android provides standard system activities for picking files:
1. **Android Photo Picker (`PickVisualMedia` / `PickMultipleVisualMedia`):**  
   Introduced in Android 13 (API 33) and backported down to Android 4.4 via Google Play Services / AndroidX. Provides a clean system UI for photo and video selection. **Requires ZERO permissions.**
2. **Storage Access Framework Document Picker (`ACTION_OPEN_DOCUMENT`):**  
   Standard system activity for picking PDFs, text files, spreadsheets, and archives. Allows multiple selection (`EXTRA_ALLOW_MULTIPLE`). **Requires ZERO permissions.**

### 9.2 Package Evaluation: Third-Party Plugin vs. Native Kotlin Channel

| Criteria | Third-Party Plugins (`file_picker`, `image_picker`) | Native Kotlin MethodChannel (`MainActivity.kt`) |
| :--- | :--- | :--- |
| **Pubspec Dependencies** | Adds 2–3 new packages + transitive dependencies | **0 new packages** |
| **Build Stability in AGP 9 / Termux** | High risk of Gradle build breakage / JNI descriptor issues (see `patch_plugins.py`) | **100% build guarantee** (reuses existing `MainActivity.kt`) |
| **Android Permissions** | May request legacy permissions or declare unused manifest tags | **Zero storage permissions** declared or needed |
| **Content URI Handling** | Plugin converts URI to cache path; often leaves temp files behind | **Direct stream copy** from `contentResolver.openInputStream(uri)` directly to app-private storage |
| **UI Integration** | Standard native system pickers | Standard native system pickers; UI is 100% Flutter Material 3 |

**Verdict:**  
Implementing a dedicated `ATTACHMENTS_CHANNEL = "com.noteflow.app/attachments"` in `MainActivity.kt` using `ActivityResultContracts` or `startActivityForResult(Intent(Intent.ACTION_OPEN_DOCUMENT))` is vastly superior for NoteFlow. It eliminates all build risk, requires zero external Gradle dependencies, and streams directly into `<Documents>/attachments/<noteId>/`.

### 9.3 External File Opening & Sharing (`FileProvider`)

To view attachments in external apps (e.g. opening a PDF in Adobe Reader or sharing an image via WhatsApp), Android forbids passing raw `file://` URIs (`FileUriExposedException`).

**Requirements:**
1. Declare `FileProvider` in `android/app/src/main/AndroidManifest.xml`:
```xml
<provider
    android:name="androidx.core.content.FileProvider"
    android:authorities="${applicationId}.fileprovider"
    android:exported="false"
    android:grantUriPermissions="true">
    <meta-data
        android:name="android.support.FILE_PROVIDER_PATHS"
        android:resource="@xml/file_paths" />
</provider>
```
2. Create `android/app/src/main/res/xml/file_paths.xml`:
```xml
<?xml version="1.0" encoding="utf-8"?>
<paths>
    <files-path name="internal_files" path="." />
</paths>
```
3. Native method in `MainActivity.kt`:
   * `openAttachment(path, mimeType)` creates `Intent(Intent.ACTION_VIEW)` with `FileProvider.getUriForFile(...)` and `FLAG_GRANT_READ_URI_PERMISSION`.
   * `shareAttachment(path, mimeType)` creates `Intent(Intent.ACTION_SEND)` with `Intent.EXTRA_STREAM`.

---

## 10. User Interface Integration Plan

The user interface must strictly adhere to NoteFlow's Material 3 design language, dark/light theme support, and non-intrusive layout.

### 10.1 NoteEditorScreen (Text & Checklist Notes)
* **Access Point:**  
  Add an attachment icon button in the `AppBar` actions row:
  `IconButton(icon: Icon(Icons.attach_file_rounded), tooltip: 'Add Attachment', onPressed: _pickAttachments)`.
  Also add an "Add Attachment" item to the `PopupMenuButton`.
* **Attachment Strip Placement:**  
  Inserted in the scrollable `ListView` directly below the active `ReminderChip` and above the `QuillEditor` / `ChecklistView`.
* **Visual Presentation:**  
  * **When 0 attachments:** The strip is **completely hidden** (takes 0 vertical pixels). No visual clutter.
  * **When attachments exist:** Displays a compact horizontal scroll view with preview cards (80dp height):
    * **Images:** Rounded thumbnail container (`BoxFit.cover`) with subtle border, aspect ratio 1:1, image icon overlay, tap to view.
    * **Documents:** Rounded card with document icon (PDF, DOC, TXT), truncated file name, formatted size badge (e.g., "1.2 MB").
    * **Add Button:** An "add" thumbnail card (`+`) at the end of the strip to quickly append more files.
* **Tapping an Attachment:**  
  Opens the **Attachment Preview Modal**.

### 10.2 VoiceNoteEditorScreen (Voice Notes)
* **Access Point:**  
  Add an `IconButton(icon: Icon(Icons.attach_file_rounded))` in the AppBar actions.
* **Placement:**  
  Placed between the SegmentedButton (`List` / `Checklist`) and the recordings list.
* **Use Case:**  
  Allows attaching lecture slides, meeting agendas, whiteboard photos, or contract documents directly to an audio session.

### 10.3 NoteCard (HomeScreen & ArchiveScreen)
* **Compact Indicator:**  
  In the `NoteCard` footer (next to the folder chip and timestamp), display an attachment badge if `attachmentCount > 0`:
  `Row(children: [Icon(Icons.attach_file_rounded, size: 12), SizedBox(width: 4), Text('$count')])`.
* **Optional Thumbnail Strip:**  
  If the note has image attachments, display a compact preview thumbnail grid (1–3 small rounded thumbnails) above the card footer.

### 10.4 Attachment Preview & Management Modal
* Material 3 dialog / modal bottom sheet with:
  * Full filename, creation timestamp, and file size.
  * For images: Pinch-to-zoom interactive viewer (`InteractiveViewer`).
  * Action buttons:
    * **Open in External App** (`Icons.open_in_new_rounded`).
    * **Share** (`Icons.share_rounded`).
    * **Delete** (`Icons.delete_outline`, red, with confirmation prompt).

### 10.5 UI State Handlers
* **Import Progress:** Displays a compact linear progress bar inside the attachment strip while files are copying.
* **Import Failure:** Shows a non-blocking `SnackBar` with an error description (e.g., "File exceeds maximum size limit (25 MB)" or "Failed to read file").
* **Missing File State:** If a file was deleted externally or disk was wiped, the card renders a red warning icon `Icons.broken_image_rounded` or `Icons.file_present_outlined` with text "Missing" and a "Remove" button.
* **No External App Handler:** If user tries to open a file for which no app exists on the device, catches `ActivityNotFoundException` and displays a SnackBar: "No application found to open this file type."

---

## 11. Backup and Restore Integration

### 11.1 Packaging Format (Version 3)

NoteFlow backups are currently version 2 (`backup_version: 2`) created by `BackupService` and restored by `RestoreService`.

```json
{
  "app": "NoteFlow",
  "app_identifier": "com.noteflow.app",
  "version": 1,
  "backup_version": 3,
  "created_at": "2026-11-20T14:45:00.000Z",
  "theme_mode": "dark",
  "stats": {
    "notes_count": 12,
    "folders_count": 3,
    "tags_count": 4,
    "recordings_count": 6,
    "has_audio": true,
    "audio_files_count": 6,
    "total_audio_bytes": 1420500,
    "has_attachments": true,
    "attachments_count": 5,
    "total_attachment_bytes": 8450120
  },
  "folders": [ ... ],
  "tags": [ ... ],
  "notes": [ ... ],
  "voice_recordings": [ ... ],
  "reminders": [ ... ],
  "attachments": [
    {
      "id": "att-1",
      "note_id": "note-welcome",
      "original_name": "Project_Spec.pdf",
      "stored_name": "att-1.pdf",
      "relative_path": "attachments/note-welcome/att-1.pdf",
      "mime_type": "application/pdf",
      "file_extension": "pdf",
      "file_size_bytes": 1048576,
      "category": "document",
      "created_at": "2026-11-20T12:00:00.000Z"
    }
  ],
  "audio_payloads": {
    "rec-1": "AAAA... (base64)"
  },
  "attachment_payloads": {
    "att-1": "JVBE... (base64)"
  }
}
```

### 11.2 Backward Compatibility
* When `RestoreService` reads a backup file:
  * If `parsed['backup_version'] <= 2` or `!parsed.containsKey('attachments')`:
    `backupAttachments` defaults to `[]` and `attachmentPayloads` defaults to `{}`.
  * Notes, audio recordings, folders, tags, and reminders restore cleanly with zero regression.

### 11.3 Restoration Strategies
1. **`RestoreStrategy.replace`:**
   * Pre-restore safety snapshot created at `<Documents>/backups/pre_restore_safety.bak`.
   * Current attachments directory `<Documents>/attachments` wiped or replaced.
   * Restored files decoded from `attachment_payloads` and written to `<Documents>/attachments/<noteId>/<storedName>`.
   * `LocalNoteRepository.replaceAllData` sets `_attachments = backupAttachments`.
2. **`RestoreStrategy.merge`:**
   * Incoming attachments compared against existing `_attachments`.
   * If collision occurs (`id` already exists), keep newest or preserve both with generated UUID.
   * Physical files written safely without overwriting unrelated files.
3. **Rollback Guarantee:**
   * If any step fails during extraction, the pre-restore snapshot `pre_restore_safety.bak` is copied back to `noteflow_data.json`, and partial writes in `attachments` are rolled back.

---

## 12. Security and Performance Considerations

### 12.1 Path Traversal Mitigation
* **Risk:** A malicious file name such as `../../../../system/etc/hosts` or `../../../data/user/0/...` could overwrite sensitive app data.
* **Mitigation:** The physical stored name is **strictly generated** via `Uuid().v4() + '.' + sanitizedExtension`. The file path is strictly constrained to `<Documents>/attachments/<noteId>/<storedName>`. `originalName` is strictly stored as metadata text and never used in filesystem paths.

### 12.2 Memory Safety & Large File Limits
* **Risk:** Decoding 50MB files into base64 in Dart memory can cause an Out-Of-Memory (OOM) crash on memory-constrained mobile devices.
* **Recommendations:**
  * Enforce a single-file size ceiling of **25 MB** per attachment.
  * Enforce a total per-note attachment ceiling of **50 MB**.
  * Use streamed file piping (`source.openRead().pipe(target.openWrite())`) rather than `readAsBytesSync()`.
  * For image thumbnails, always decode using Flutter's `ResizeImage` with `cacheWidth: 300` / `cacheHeight: 300` to avoid loading full 48MP raw bitmaps into memory.

### 12.3 Sandbox Isolation
* Attachments are stored within the app-private `app_flutter` directory.
* External applications cannot access these files without explicit permission granted on a per-URI basis via `FileProvider`.

---

## 13. Risks and Compatibility Concerns

1. **Gradle / AGP 9 Build Breakage Risk (HIGH):**  
   Adding third-party plugins with native Android components (e.g. `file_picker`, `image_picker`) risks build errors in the current Termux / musl environment (which already required `scripts/patch_plugins.py`).  
   *Mitigation:* Utilize native Kotlin MethodChannel in `MainActivity.kt` with zero third-party dependencies.
2. **Backup Archive File Bloat (MEDIUM):**  
   Large attachments stored as base64 in `.noteflow` files can increase backup file size by 33%.  
   *Mitigation:* Use NoteFlow's existing gzip compression (`createBackupArchive(compress: true)`) which reduces JSON/base64 overhead by 40–60%. Also provide an `includeAttachments` toggle in `BackupRestoreScreen`.
3. **External View Application Absence (LOW):**  
   Attempting to open an exotic file extension when the device lacks a compatible viewer.  
   *Mitigation:* Wrap `startActivity` in a `try/catch (e: ActivityNotFoundException)` and return an error message to Flutter.

---

## 14. Complete File-by-File Change Plan

### 14.1 New Files to Create

| File Path | Responsibility |
| :--- | :--- |
| `lib/shared/models/attachment_entity.dart` | Immutable `AttachmentEntity` domain model with category detection and JSON serialization |
| `lib/core/utils/attachment_helper.dart` | File system operations: path resolution, stream copy, safe deletion, storage size metrics |
| `lib/features/attachments/services/attachment_native_bridge.dart` | Flutter interface to `MainActivity.kt` MethodChannel for file picking, external opening, and sharing |
| `lib/features/attachments/providers/attachment_providers.dart` | Riverpod providers: `attachmentsStreamProvider.family`, `attachmentCountProvider` |
| `lib/features/attachments/presentation/widgets/attachment_section.dart` | Horizontal scrollable attachment tray rendered in note editors |
| `lib/features/attachments/presentation/widgets/attachment_tile.dart` | Compact thumbnail card for images and document badges |
| `lib/features/attachments/presentation/widgets/attachment_preview_dialog.dart` | Material 3 fullscreen image viewer and document action dialog |
| `android/app/src/main/res/xml/file_paths.xml` | XML file provider path definition for Android `FileProvider` |

### 14.2 Existing Files to Modify

| File Path | Changes Required |
| :--- | :--- |
| `lib/core/database/note_repository.dart` | Add attachment contract methods (`watchAttachments`, `saveAttachment`, `deleteAttachment`, `deleteNoteAttachments`) |
| `lib/core/database/local_note_repository.dart` | Implement `_attachments` store, streams, CRUD, disk JSON sync, and cascade delete in `deleteNote()` |
| `lib/core/database/app_database.dart` | Add `AttachmentsTableDefinition` for schema specification completeness |
| `lib/core/database/database_provider.dart` | Export `attachmentsStreamProvider` |
| `lib/features/backup/services/backup_service.dart` | Add `attachments` and `attachment_payloads` to export payload; update `stats` |
| `lib/features/backup/services/restore_service.dart` | Parse and extract attachments; decode base64 payloads to `<Documents>/attachments/` |
| `lib/features/backup/presentation/backup_restore_screen.dart` | Add `includeAttachments` switch in UI; display attachment stats in backup preview cards |
| `lib/features/editor/presentation/note_editor_screen.dart` | Integrate `AttachmentSection` between ReminderChip and Editor body; add AppBar attachment button |
| `lib/features/voice_notes/presentation/voice_note_editor_screen.dart` | Add `AttachmentSection` into Voice Note container below mode switcher |
| `lib/features/home/presentation/widgets/note_card.dart` | Display attachment count badge in card footer |
| `android/app/src/main/AndroidManifest.xml` | Declare `<provider>` for `androidx.core.content.FileProvider` |
| `android/app/src/main/kotlin/com/noteflow/app/MainActivity.kt` | Implement `"com.noteflow.app/attachments"` channel with `pickFiles`, `openFile`, and `shareFile` handlers |

---

## 15. Dependencies Required

### Analysis of External Dependencies

* **Recommended Approach: Zero Additional Pub Dependencies**  
  * All file picking (Photo Picker + SAF Documents) can be handled by `MainActivity.kt` via standard Android APIs.
  * All file opening and sharing can be handled by `MainActivity.kt` via standard Android `Intent` and `FileProvider`.
  * All path resolutions use the existing `path_provider: ^2.1.3`.
  * All unique IDs use the existing `uuid: ^4.4.0`.
  * All compression uses Dart's built-in `dart:io` `gzip`.
  * All base64 encoding uses Dart's built-in `dart:convert` `base64`.

* **Optional Third-Party Package Alternative:**  
  If the team explicitly chooses to use pub packages instead of Kotlin MethodChannel:
  * `file_picker: ^8.0.0`
  * `share_plus: ^9.0.0`
  * `open_filex: ^4.5.0`  
  *Warning:* As audited in `scripts/patch_plugins.py`, introducing these packages requires testing against AGP 9 and may trigger JNI build failures in this specific development environment.

---

## 16. Detailed Testing Plan

The testing plan covers all 17 requirements specified in the audit brief:

1. **Attach an image to a text note:**  
   Pick a JPG/PNG image; verify it copies to `<Documents>/attachments/<noteId>/`, displays thumbnail in `AttachmentSection`, and persists across auto-save.
2. **Attach a PDF to a text note:**  
   Pick a PDF document; verify category is `document`, size is formatted correctly, and filename is preserved.
3. **Attach multiple files to a checklist:**  
   Select 3 files simultaneously in document picker; verify all 3 are imported, checkable items remain interactive, and checklist state is undisturbed.
4. **Attach a document to a voice note:**  
   Open `VoiceNoteEditorScreen`, attach a document; verify audio recording, audio playback, and waveform rendering continue operating without interference.
5. **Close and reopen the application (Cold Boot Persistence):**  
   Create notes with attachments, force-kill app process (`LocalNoteRepository.dispose()`), instantiate a new repository instance pointing to `noteflow_data.json`; verify all attachments are reloaded and file paths resolve.
6. **Edit a note with attachments:**  
   Modify title, format text with Quill toolbar, toggle checklist items; verify auto-save debouncing commits changes without duplicating or corrupting attachments.
7. **Archive and restore a note:**  
   Archive a note with attachments; verify it disappears from active stream and appears in `ArchiveScreen`. Restore note; verify attachments are fully intact.
8. **Delete one attachment:**  
   Delete a single attachment from the preview dialog; verify physical file is deleted from disk, `_attachments` updates, and other attachments remain untouched.
9. **Delete a note with attachments (Cascade Deletion):**  
   Delete note; verify all physical files and directory `<Documents>/attachments/<noteId>/` are completely deleted from storage with zero orphaned files.
10. **Share and open attachments:**  
    Trigger external open and share via `FileProvider`; verify `Intent.ACTION_VIEW` and `Intent.ACTION_SEND` grant temporary URI read permissions.
11. **Restore attachments from backup:**  
    Generate `.noteflow` backup archive with attachments; restore on clean state; verify physical files are written to disk and metadata restored.
12. **Merge backups containing attachments:**  
    Restore with `RestoreStrategy.merge`; verify existing notes and attachments are merged without overwriting identical IDs or causing file collisions.
13. **Handle missing or corrupted files:**  
    Manually delete an attachment file from the filesystem; verify UI displays the warning badge gracefully without throwing an unhandled exception or crashing.
14. **Handle failed imports:**  
    Simulate a read failure or 0-byte source file; verify system cancels import, cleans up partial files, and displays an informative SnackBar.
15. **Test large files:**  
    Import a 20MB document; verify stream copying prevents high memory spikes, and UI displays progress smoothly.
16. **Confirm existing voice recordings continue working:**  
    Run full suite of audio tests; record, play, seek, pause, and delete audio memos; verify zero regressions.
17. **Confirm existing note functionality is unchanged:**  
    Run `dart run test/unit/noteflow_core_test.dart`; verify all 30 existing test suites (428 assertions) pass completely.

---

## 17. Phased Implementation Roadmap

```
┌─────────────────────────────────────────────────────────────┐
│                 Implementation Roadmap                      │
└─────────────────────────────────────────────────────────────┘
  Phase 1: Domain & Storage Core
  ├── AttachmentEntity & Category
  ├── AttachmentHelper (stream copy, validation, cleanup)
  └── LocalNoteRepository integration & Unit Tests
        │
        ▼
  Phase 2: Android Native Bridge
  ├── MainActivity.kt (Photo Picker, SAF, FileProvider)
  ├── AndroidManifest.xml (FileProvider configuration)
  └── AttachmentNativeBridge (MethodChannel)
        │
        ▼
  Phase 3: UI Integration
  ├── AttachmentSection & AttachmentTile widgets
  ├── NoteEditorScreen & VoiceNoteEditorScreen integration
  └── NoteCard indicator badge
        │
        ▼
  Phase 4: Backup & Restore
  ├── BackupService & RestoreService version 3 integration
  ├── Base64 attachment payload packing & extraction
  └── BackupRestoreScreen UI switches
        │
        ▼
  Phase 5: Verification & Acceptance
  ├── 17-point test suite execution
  └── Performance, memory, and regression validation
```

---

## 18. Questions and Unresolved Architectural Decisions

1. **Max File Size Policy:**  
   *Proposed:* 25 MB per file, 50 MB total per note.  
   *Question for Team:* Should this limit be user-configurable in settings, or strictly enforced to prevent backup file inflation?
2. **Backup Storage Inclusions:**  
   *Proposed:* Provide a toggle `includeAttachments` in `BackupRestoreScreen` (similar to existing `includeAudio`).  
   *Question for Team:* Should backups default to `includeAttachments = true`, or warn users if backup size exceeds 50 MB?
3. **Cloud/Sync Extensibility:**  
   While NoteFlow is currently 100% offline, storing relative paths (`attachments/<noteId>/<storedName>`) makes future cloud synchronization (e.g. WebDAV, Google Drive, or self-hosted sync) trivial. Confirm alignment on relative path schema.

---

*End of Architecture Audit Report.*
