import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/utils/note_helper.dart';
import '../../../../core/database/database_provider.dart';
import '../../../../shared/models/note_entity.dart';
import '../../../../shared/models/folder_entity.dart';
import 'widgets/color_tint_picker.dart';
import 'widgets/editor_toolbar.dart';
import 'widgets/checklist_view.dart';
import 'widgets/note_stats_modal.dart';

class NoteEditorScreen extends ConsumerStatefulWidget {
  final String? noteId;
  final NoteEntity? initialNote;
  final String? initialFolderId;
  final bool isChecklist;

  const NoteEditorScreen({
    super.key,
    this.noteId,
    this.initialNote,
    this.initialFolderId,
    this.isChecklist = false,
  });

  @override
  ConsumerState<NoteEditorScreen> createState() => _NoteEditorScreenState();
}

class _NoteEditorScreenState extends ConsumerState<NoteEditorScreen> {
  late final TextEditingController _titleController;
  late final TextEditingController _contentController;
  Timer? _autoSaveTimer;

  late NoteEntity _currentNote;
  bool _isLoading = false;
  bool _isSaving = false;
  String _saveStatus = 'Saved locally';
  final _uuid = const Uuid();

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();

    if (widget.initialNote != null) {
      var note = widget.initialNote!;
      if (NoteHelper.isDeltaContent(note.content)) {
        final isChecklist = note.isChecklist || NoteHelper.isChecklistContent(note.content);
        note = note.copyWith(
          content: NoteHelper.formatForEditor(note.content),
          isChecklist: isChecklist,
        );
      }
      _currentNote = note;
      _isLoading = false;
    } else if (widget.noteId == null) {
      _currentNote = _createDefaultNote(now);
      _isLoading = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ref.read(noteRepositoryProvider).saveNote(_currentNote);
        }
      });
    } else {
      _isLoading = true;
      _initExistingNote();
    }

    _titleController = TextEditingController(text: _isLoading ? '' : _currentNote.title);
    _contentController = TextEditingController(
      text: _isLoading ? '' : NoteHelper.formatForEditor(_currentNote.content),
    );
  }

  Future<void> _initExistingNote() async {
    final repo = ref.read(noteRepositoryProvider);
    final existing = await repo.getNoteById(widget.noteId!);
    if (existing != null) {
      var note = existing;
      if (NoteHelper.isDeltaContent(note.content)) {
        final isChecklist = note.isChecklist || NoteHelper.isChecklistContent(note.content);
        note = note.copyWith(
          content: NoteHelper.formatForEditor(note.content),
          isChecklist: isChecklist,
        );
        // Persist cleaned note immediately so raw Delta JSON is sanitized in database
        await repo.saveNote(note);
      }
      _currentNote = note;
    } else {
      _currentNote = _createDefaultNote(DateTime.now());
    }
    _titleController.text = _currentNote.title;
    _contentController.text = NoteHelper.formatForEditor(_currentNote.content);
    if (mounted) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  NoteEntity _createDefaultNote(DateTime now) {
    return NoteEntity(
      id: widget.noteId ?? _uuid.v4(),
      title: '',
      content: widget.isChecklist ? '[ ] ' : '',
      folderId: widget.initialFolderId,
      isPinned: false,
      isArchived: false,
      isChecklist: widget.isChecklist,
      colorIndex: 0,
      createdAt: now,
      updatedAt: now,
    );
  }

  @override
  void dispose() {
    _autoSaveTimer?.cancel();
    // Flush any pending save synchronously before disposing
    _saveNoteImmediate();
    _titleController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  void _triggerAutoSave() {
    setState(() {
      _isSaving = true;
      _saveStatus = 'Saving...';
    });

    _autoSaveTimer?.cancel();
    _autoSaveTimer = Timer(AppConstants.autoSaveDebounce, () {
      _saveNoteImmediate();
    });
  }

  Future<void> _saveNoteImmediate() async {
    _autoSaveTimer?.cancel();
    final updated = _currentNote.copyWith(
      title: _titleController.text,
      content: _contentController.text,
      updatedAt: DateTime.now(),
    );

    _currentNote = updated;
    await ref.read(noteRepositoryProvider).saveNote(updated);

    if (mounted) {
      setState(() {
        _isSaving = false;
        _saveStatus = 'Saved locally';
      });
    }
  }

  void _showFolderSelector(List<FolderEntity> folders) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppConstants.radiusLarge)),
      ),
      builder: (bottomContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: AppConstants.paddingMedium),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  child: Text(
                    'Assign to Folder',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.folder_off_outlined),
                  title: const Text('No Folder'),
                  trailing: _currentNote.folderId == null
                      ? const Icon(Icons.check, color: AppColors.primary)
                      : null,
                  onTap: () {
                    setState(() {
                      _currentNote = _currentNote.copyWith(clearFolder: true);
                    });
                    _triggerAutoSave();
                    Navigator.pop(bottomContext);
                  },
                ),
                for (final folder in folders)
                  ListTile(
                    leading: const Icon(Icons.folder_outlined),
                    title: Text(folder.name),
                    trailing: _currentNote.folderId == folder.id
                        ? const Icon(Icons.check, color: AppColors.primary)
                        : null,
                    onTap: () {
                      setState(() {
                        _currentNote = _currentNote.copyWith(folderId: folder.id);
                      });
                      _triggerAutoSave();
                      Navigator.pop(bottomContext);
                    },
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showStats() {
    // Sync note content before displaying stats
    _currentNote = _currentNote.copyWith(
      title: _titleController.text,
      content: _contentController.text,
    );

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppConstants.radiusLarge)),
      ),
      builder: (_) => NoteStatsModal(note: _currentNote),
    );
  }

  void _copyToClipboard() {
    final full = '${_titleController.text}\n\n${_contentController.text}'.trim();
    Clipboard.setData(ClipboardData(text: full));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Note copied to clipboard')),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colorList = isDark ? AppColors.darkNoteColors : AppColors.lightNoteColors;
    final backgroundColor = _currentNote.colorIndex < colorList.length
        ? colorList[_currentNote.colorIndex]
        : (isDark ? AppColors.darkBackground : AppColors.lightBackground);

    final primaryTextColor = isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary;
    final secondaryTextColor = isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary;

    final foldersAsync = ref.watch(foldersStreamProvider);
    final folders = foldersAsync.value ?? [];
    final currentFolder = folders.where((f) => f.id == _currentNote.folderId).firstOrNull;

    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) {
          _saveNoteImmediate();
        }
      },
      child: Scaffold(
        backgroundColor: backgroundColor,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: () async {
              await _saveNoteImmediate();
              if (mounted) Navigator.pop(context);
            },
          ),
          title: Row(
            children: [
              // Auto-save status indicator (100% offline local persistence)
              Icon(
                _isSaving ? Icons.sync_rounded : Icons.offline_pin_outlined,
                size: 15,
                color: _isSaving ? AppColors.pinColor : AppColors.accent,
              ),
              const SizedBox(width: 6),
              Text(
                _saveStatus,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: secondaryTextColor,
                ),
              ),
            ],
          ),
          actions: [
            // Pin toggle
            IconButton(
              icon: Icon(
                _currentNote.isPinned ? Icons.push_pin : Icons.push_pin_outlined,
                color: _currentNote.isPinned ? AppColors.pinColor : secondaryTextColor,
              ),
              tooltip: _currentNote.isPinned ? 'Unpin Note' : 'Pin Note',
              onPressed: () {
                setState(() {
                  _currentNote = _currentNote.copyWith(isPinned: !_currentNote.isPinned);
                });
                _triggerAutoSave();
              },
            ),

            // More Options Menu
            PopupMenuButton<String>(
              icon: Icon(Icons.more_vert, color: secondaryTextColor),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppConstants.radiusMedium),
              ),
              onSelected: (val) async {
                switch (val) {
                  case 'checklist':
                    setState(() {
                      _currentNote = _currentNote.copyWith(isChecklist: !_currentNote.isChecklist);
                    });
                    _triggerAutoSave();
                    break;
                  case 'folder':
                    _showFolderSelector(folders);
                    break;
                  case 'stats':
                    _showStats();
                    break;
                  case 'copy':
                    _copyToClipboard();
                    break;
                  case 'archive':
                    await ref.read(noteRepositoryProvider).toggleArchive(_currentNote.id);
                    if (mounted) Navigator.pop(context);
                    break;
                  case 'delete':
                    await ref.read(noteRepositoryProvider).deleteNote(_currentNote.id);
                    if (mounted) Navigator.pop(context);
                    break;
                }
              },
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: 'checklist',
                  child: Row(
                    children: [
                      Icon(
                        _currentNote.isChecklist ? Icons.notes_rounded : Icons.checklist_rounded,
                        size: 18,
                      ),
                      const SizedBox(width: 10),
                      Text(_currentNote.isChecklist ? 'Convert to Plain Text' : 'Convert to Checklist'),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'folder',
                  child: Row(
                    children: const [
                      Icon(Icons.folder_outlined, size: 18),
                      SizedBox(width: 10),
                      Text('Assign Folder'),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'stats',
                  child: Row(
                    children: const [
                      Icon(Icons.analytics_outlined, size: 18),
                      SizedBox(width: 10),
                      Text('Note Info & Stats'),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'copy',
                  child: Row(
                    children: const [
                      Icon(Icons.copy_rounded, size: 18),
                      SizedBox(width: 10),
                      Text('Copy Note Text'),
                    ],
                  ),
                ),
                const PopupMenuDivider(),
                PopupMenuItem(
                  value: 'archive',
                  child: Row(
                    children: const [
                      Icon(Icons.archive_outlined, size: 18),
                      SizedBox(width: 10),
                      Text('Archive Note'),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'delete',
                  child: Row(
                    children: const [
                      Icon(Icons.delete_outline, size: 18, color: AppColors.danger),
                      SizedBox(width: 10),
                      Text('Delete Note', style: TextStyle(color: AppColors.danger)),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),

        body: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: AppConstants.paddingMedium),
                children: [
                  // Folder Chip Badge (if assigned)
                  if (currentFolder != null) ...[
                    Align(
                      alignment: Alignment.centerLeft,
                      child: ActionChip(
                        avatar: const Icon(Icons.folder_outlined, size: 14),
                        label: Text(currentFolder.name),
                        onPressed: () => _showFolderSelector(folders),
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],

                  // Title Text Field
                  TextField(
                    controller: _titleController,
                    style: AppTypography.displayMedium(primaryTextColor),
                    decoration: InputDecoration(
                      hintText: 'Title',
                      hintStyle: AppTypography.displayMedium(
                        isDark ? AppColors.darkTextTertiary : AppColors.lightTextTertiary,
                      ),
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      filled: false,
                      contentPadding: EdgeInsets.zero,
                    ),
                    onChanged: (_) => _triggerAutoSave(),
                  ),

                  const SizedBox(height: 12),

                  // Body Content: Checklist or Rich-text markdown
                  if (_currentNote.isChecklist)
                    ChecklistView(
                      rawContent: _contentController.text,
                      onContentChanged: (newText) {
                        _contentController.text = newText;
                        _triggerAutoSave();
                      },
                    )
                  else
                    TextField(
                      controller: _contentController,
                      maxLines: null,
                      keyboardType: TextInputType.multiline,
                      style: AppTypography.bodyLarge(primaryTextColor),
                      decoration: InputDecoration(
                        hintText: 'Start writing thoughts, tasks, or paste markdown...',
                        hintStyle: AppTypography.bodyLarge(
                          isDark ? AppColors.darkTextTertiary : AppColors.lightTextTertiary,
                        ),
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        filled: false,
                        contentPadding: EdgeInsets.zero,
                      ),
                      onChanged: (_) => _triggerAutoSave(),
                    ),

                  const SizedBox(height: 40),
                ],
              ),
            ),

            // Bottom Controls Bar: auto-collapses color tint when keyboard is visible to maximize editor canvas
            Builder(
              builder: (context) {
                final isKeyboardOpen = MediaQuery.of(context).viewInsets.bottom > 0;
                return SafeArea(
                  top: false,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (!isKeyboardOpen)
                        ColorTintPicker(
                          selectedIndex: _currentNote.colorIndex,
                          onSelectColor: (idx) {
                            setState(() {
                              _currentNote = _currentNote.copyWith(colorIndex: idx);
                            });
                            _triggerAutoSave();
                          },
                        ),
                      if (!_currentNote.isChecklist)
                        EditorToolbar(
                          controller: _contentController,
                          onChanged: _triggerAutoSave,
                        ),
                    ],
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
