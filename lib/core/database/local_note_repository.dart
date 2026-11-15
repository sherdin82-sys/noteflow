import 'dart:async';
import 'dart:convert';
import 'dart:io';
import '../../shared/models/note_entity.dart';
import '../../shared/models/folder_entity.dart';
import 'note_repository.dart';

class LocalNoteRepository implements NoteRepository {
  final List<NoteEntity> _notes = [];
  final List<FolderEntity> _folders = [];

  final _notesStreamController = StreamController<List<NoteEntity>>.broadcast();
  final _foldersStreamController = StreamController<List<FolderEntity>>.broadcast();

  final bool _seedDemoData;
  final bool _enableDiskPersistence;
  final String? _customStoragePath;
  final Future<String> Function()? _directoryProvider;
  File? _resolvedFile;
  bool _initialized = false;
  String _themeMode = 'dark';

  String get themeMode => _themeMode;

  Future<void> setThemeMode(String mode) async {
    _themeMode = mode;
    await _saveToDisk();
  }

  LocalNoteRepository({
    bool seedDemoData = true,
    bool enableDiskPersistence = true,
    String? customStoragePath,
    Future<String> Function()? directoryProvider,
  })  : _seedDemoData = seedDemoData,
        _enableDiskPersistence = enableDiskPersistence,
        _customStoragePath = customStoragePath,
        _directoryProvider = directoryProvider {
    if (_seedDemoData) {
      _seedInitialData();
    }
  }

  Future<void> init() async {
    if (_initialized) return;
    if (!_enableDiskPersistence) {
      _initialized = true;
      return;
    }

    try {
      final file = await _getStorageFile();
      if (file != null && await file.exists()) {
        final content = await file.readAsString();
        if (content.trim().isNotEmpty) {
          final data = jsonDecode(content) as Map<String, dynamic>;
          if (data.containsKey('theme_mode')) {
            _themeMode = data['theme_mode'] as String? ?? 'dark';
          }
          final rawFolders = data['folders'] as List<dynamic>? ?? [];
          final rawNotes = data['notes'] as List<dynamic>? ?? [];

          _folders.clear();
          for (final f in rawFolders) {
            _folders.add(FolderEntity.fromMap(Map<String, dynamic>.from(f as Map)));
          }

          _notes.clear();
          for (final n in rawNotes) {
            _notes.add(NoteEntity.fromMap(Map<String, dynamic>.from(n as Map)));
          }

          _initialized = true;
          _emitNotes();
          _emitFolders();
          return;
        }
      }

      // If file didn't exist or was empty, seed demo data and save to disk
      if (_seedDemoData && _notes.isNotEmpty) {
        await _saveToDisk();
      }
    } catch (_) {
      // In case of error (e.g. non-Flutter test environment), maintain in-memory state
    }
    _initialized = true;
  }

  Future<File?> _getStorageFile() async {
    if (_resolvedFile != null) return _resolvedFile;
    if (_customStoragePath != null) {
      _resolvedFile = File(_customStoragePath);
      return _resolvedFile;
    }
    if (_directoryProvider != null) {
      try {
        final dirPath = await _directoryProvider();
        _resolvedFile = File('$dirPath/noteflow_data.json');
        return _resolvedFile;
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  Future<void> _saveToDisk() async {
    if (!_enableDiskPersistence) return;
    try {
      final file = await _getStorageFile();
      if (file == null) return;
      final payload = {
        'version': 1,
        'theme_mode': _themeMode,
        'folders': _folders.map((f) => f.toMap()).toList(),
        'notes': _notes.map((n) => n.toMap()).toList(),
      };
      await file.writeAsString(jsonEncode(payload), flush: true);
    } catch (_) {
      // Silent error fallback
    }
  }

  void _seedInitialData() {
    final now = DateTime.now();

    // Seed Folders
    _folders.addAll([
      FolderEntity(
        id: 'folder-ideas',
        name: 'Ideas',
        colorHex: '0xFF10B981', // Emerald
        iconName: 'lightbulb',
        createdAt: now.subtract(const Duration(days: 5)),
      ),
      FolderEntity(
        id: 'folder-work',
        name: 'Work',
        colorHex: '0xFF2563EB', // Cobalt
        iconName: 'briefcase',
        createdAt: now.subtract(const Duration(days: 4)),
      ),
      FolderEntity(
        id: 'folder-personal',
        name: 'Personal',
        colorHex: '0xFF8B5CF6', // Purple
        iconName: 'user',
        createdAt: now.subtract(const Duration(days: 3)),
      ),
    ]);

    // Seed Notes
    _notes.addAll([
      NoteEntity(
        id: 'note-welcome',
        title: 'Welcome to NoteFlow ✦',
        content:
            'NoteFlow is a modern, offline-first notepad crafted with Flutter, Drift SQLite, and Riverpod.\n\n'
            'Key features:\n'
            '• Pure offline persistence — zero cloud, zero tracking.\n'
            '• Rich-text editing with formatting & checklists.\n'
            '• Organize notes with custom folders & color tints.\n'
            '• Pin important notes to keep them accessible.\n'
            '• Instant search and smooth dark/light theme transitions.',
        folderId: 'folder-ideas',
        isPinned: true,
        isArchived: false,
        isChecklist: false,
        colorIndex: 1, // Soft emerald tint
        createdAt: now.subtract(const Duration(hours: 3)),
        updatedAt: now.subtract(const Duration(minutes: 10)),
      ),
      NoteEntity(
        id: 'note-groceries',
        title: 'Weekly Essentials & Tasks',
        content:
            '[x] Almond milk & Greek yogurt\n'
            '[x] Fresh sourdough bread\n'
            '[ ] Organic olive oil & balsamic vinegar\n'
            '[ ] Arabica coffee beans\n'
            '[ ] Fresh rosemary & thyme\n'
            '[ ] Review sprint retrospective notes',
        folderId: 'folder-personal',
        isPinned: true,
        isArchived: false,
        isChecklist: true,
        colorIndex: 4, // Warm amber tint
        createdAt: now.subtract(const Duration(days: 1)),
        updatedAt: now.subtract(const Duration(hours: 1)),
      ),
      NoteEntity(
        id: 'note-architecture',
        title: 'Offline-First Architecture Notes',
        content:
            'Drift SQLite serves as the single source of truth.\n\n'
            '1. All write operations commit immediately to local disk.\n'
            '2. Reactive queries emit updates to Riverpod providers.\n'
            '3. Clean Architecture separates domain entities from UI widgets.',
        folderId: 'folder-work',
        isPinned: false,
        isArchived: false,
        isChecklist: false,
        colorIndex: 2, // Soft blue tint
        createdAt: now.subtract(const Duration(days: 2)),
        updatedAt: now.subtract(const Duration(hours: 4)),
      ),
      NoteEntity(
        id: 'note-reading-list',
        title: 'Book Recommendations',
        content:
            '• Designing Data-Intensive Applications by Martin Kleppmann\n'
            '• Clean Architecture by Robert C. Martin\n'
            '• The Design of Everyday Things by Don Norman\n'
            '• Atomic Habits by James Clear',
        folderId: 'folder-personal',
        isPinned: false,
        isArchived: false,
        isChecklist: false,
        colorIndex: 3, // Lavender tint
        createdAt: now.subtract(const Duration(days: 4)),
        updatedAt: now.subtract(const Duration(days: 1)),
      ),
    ]);

    _emitNotes();
    _emitFolders();
  }

  void _emitNotes() {
    if (!_notesStreamController.isClosed) {
      // Sort by recently updated by default
      final sorted = List<NoteEntity>.from(_notes)
        ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      _notesStreamController.add(List.unmodifiable(sorted));
    }
  }

  void _emitFolders() {
    if (!_foldersStreamController.isClosed) {
      _foldersStreamController.add(List.unmodifiable(_folders));
    }
  }

  @override
  Stream<List<NoteEntity>> watchNotes({bool includeArchived = false, String? folderId}) async* {
    List<NoteEntity> filterNotes(List<NoteEntity> notes) {
      return notes.where((note) {
        if (!includeArchived && note.isArchived) return false;
        if (includeArchived && !note.isArchived) return false;
        if (folderId != null && note.folderId != folderId) return false;
        return true;
      }).toList();
    }

    final sorted = List<NoteEntity>.from(_notes)
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    yield filterNotes(sorted);
    yield* _notesStreamController.stream.map(filterNotes);
  }

  @override
  Future<NoteEntity?> getNoteById(String id) async {
    try {
      return _notes.firstWhere((n) => n.id == id);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> saveNote(NoteEntity note) async {
    final index = _notes.indexWhere((n) => n.id == note.id);
    if (index >= 0) {
      _notes[index] = note.copyWith(updatedAt: DateTime.now());
    } else {
      _notes.insert(0, note);
    }
    _emitNotes();
    await _saveToDisk();
  }

  @override
  Future<void> deleteNote(String id) async {
    _notes.removeWhere((n) => n.id == id);
    _emitNotes();
    await _saveToDisk();
  }

  @override
  Future<void> togglePin(String id) async {
    final index = _notes.indexWhere((n) => n.id == id);
    if (index >= 0) {
      final current = _notes[index];
      _notes[index] = current.copyWith(
        isPinned: !current.isPinned,
        updatedAt: DateTime.now(),
      );
      _emitNotes();
      await _saveToDisk();
    }
  }

  @override
  Future<void> toggleArchive(String id) async {
    final index = _notes.indexWhere((n) => n.id == id);
    if (index >= 0) {
      final current = _notes[index];
      _notes[index] = current.copyWith(
        isArchived: !current.isArchived,
        isPinned: false, // Unpin when archiving
        updatedAt: DateTime.now(),
      );
      _emitNotes();
      await _saveToDisk();
    }
  }

  @override
  Stream<List<FolderEntity>> watchFolders() async* {
    yield List.unmodifiable(_folders);
    yield* _foldersStreamController.stream;
  }

  @override
  Future<void> saveFolder(FolderEntity folder) async {
    final index = _folders.indexWhere((f) => f.id == folder.id);
    if (index >= 0) {
      _folders[index] = folder;
    } else {
      _folders.add(folder);
    }
    _emitFolders();
    await _saveToDisk();
  }

  @override
  Future<void> deleteFolder(String id) async {
    _folders.removeWhere((f) => f.id == id);
    // Unassign notes in this folder
    for (int i = 0; i < _notes.length; i++) {
      if (_notes[i].folderId == id) {
        _notes[i] = _notes[i].copyWith(clearFolder: true);
      }
    }
    _emitFolders();
    _emitNotes();
    await _saveToDisk();
  }

  void dispose() {
    _notesStreamController.close();
    _foldersStreamController.close();
  }
}
