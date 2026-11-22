import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/utils/note_helper.dart';
import '../../../../core/database/database_provider.dart';
import '../../../../shared/models/note_entity.dart';
import '../../../../shared/models/folder_entity.dart';
import '../../tags/presentation/widgets/tag_chip.dart';
import '../../tags/presentation/widgets/tag_selector_modal.dart';
import 'widgets/color_tint_picker.dart';
import 'widgets/editor_toolbar.dart';
import 'widgets/checklist_view.dart';
import 'widgets/note_stats_modal.dart';
import 'widgets/voice_note_widget.dart';
import '../../reminders/providers/reminder_providers.dart';
import '../../reminders/presentation/widgets/reminder_bottom_sheet.dart';
import '../../reminders/presentation/widgets/reminder_chip.dart';
import '../../attachments/presentation/widgets/attachment_section.dart';
import '../../attachments/presentation/widgets/attachment_preview_dialog.dart';
import '../../attachments/services/attachment_native_bridge.dart';
import '../../../shared/models/attachment_entity.dart';

class NoteEditorScreen extends ConsumerStatefulWidget {
  final String? noteId;
  final NoteEntity? initialNote;
  final String? initialFolderId;
  final bool isChecklist;
  final bool isVoiceNote;

  const NoteEditorScreen({
    super.key,
    this.noteId,
    this.initialNote,
    this.initialFolderId,
    this.isChecklist = false,
    this.isVoiceNote = false,
  });

  @override
  ConsumerState<NoteEditorScreen> createState() => _NoteEditorScreenState();
}

class _NoteEditorScreenState extends ConsumerState<NoteEditorScreen> {
  late final TextEditingController _titleController;
  final FocusNode _titleFocusNode = FocusNode();
  late QuillController _quillController;
  final FocusNode _editorFocusNode = FocusNode();
  final ScrollController _editorScrollController = ScrollController();
  Timer? _autoSaveTimer;

  late NoteEntity _currentNote;
  bool _isLoading = false;
  bool _isSaving = false;
  bool _isDeleted = false;
  bool _isNotePersisted = false;
  bool _showAudioRecorder = false;
  bool _isImportingAttachments = false;
  String _saveStatus = 'Saved locally';
  final _uuid = const Uuid();

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();

    _showAudioRecorder =
        widget.isVoiceNote || (widget.initialNote?.hasAudio ?? false);

    if (widget.initialNote != null) {
      _currentNote = widget.initialNote!;
      _initQuillController(_currentNote.content);
      _isLoading = false;
      _isNotePersisted = true;
    } else if (widget.noteId == null) {
      _currentNote = _createDefaultNote(now);
      _initQuillController(_currentNote.content);
      _isLoading = false;
      _isNotePersisted = false;
    } else {
      _isLoading = true;
      _isNotePersisted = true;
      _initExistingNote();
    }

    _titleController =
        TextEditingController(text: _isLoading ? '' : _currentNote.title);

    // Auto-focus Body Editor for new rich text notes to immediately open soft keyboard (skip for voice notes to avoid blocking audio recorder)
    if (!_isNotePersisted && !widget.isChecklist && !widget.isVoiceNote) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _quillController.updateSelection(
          const TextSelection.collapsed(offset: 0),
          ChangeSource.local,
        );
        _editorFocusNode.requestFocus();

        // When navigating from a sheet/route transition, re-verify focus once transition completes
        final modalRoute = ModalRoute.of(context);
        if (modalRoute != null &&
            modalRoute.animation != null &&
            !modalRoute.animation!.isCompleted) {
          void onRouteCompleted(AnimationStatus status) {
            if (status == AnimationStatus.completed) {
              modalRoute.animation?.removeStatusListener(onRouteCompleted);
              if (mounted && !_editorFocusNode.hasFocus) {
                _quillController.updateSelection(
                  const TextSelection.collapsed(offset: 0),
                  ChangeSource.local,
                );
                _editorFocusNode.requestFocus();
              }
            }
          }

          modalRoute.animation!.addStatusListener(onRouteCompleted);
        }
      });
    }
  }

  void _initQuillController(String rawContent) {
    List<dynamic> deltaOps;
    if (NoteHelper.isDeltaContent(rawContent)) {
      try {
        deltaOps = jsonDecode(rawContent) as List<dynamic>;
      } catch (_) {
        deltaOps = jsonDecode(NoteHelper.markdownToDeltaJson(rawContent))
            as List<dynamic>;
      }
    } else {
      // Legacy markdown or plain text note: explicitly convert to native Quill Delta
      deltaOps = jsonDecode(NoteHelper.markdownToDeltaJson(rawContent))
          as List<dynamic>;
    }

    try {
      final doc = Document.fromJson(deltaOps);
      _quillController = QuillController(
        document: doc,
        selection: const TextSelection.collapsed(offset: 0),
      );
    } catch (_) {
      _quillController = QuillController.basic();
    }

    _quillController.addListener(_onQuillChanged);
  }

  void _onQuillChanged() {
    _triggerAutoSave();
  }

  Future<void> _initExistingNote() async {
    final repo = ref.read(noteRepositoryProvider);
    final existing = await repo.getNoteById(widget.noteId!);
    if (existing != null) {
      _currentNote = existing;
      if (existing.hasAudio) {
        _showAudioRecorder = true;
      }
    } else {
      _currentNote = _createDefaultNote(DateTime.now());
    }

    _initQuillController(_currentNote.content);
    _titleController.text = _currentNote.title;

    if (mounted) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  NoteEntity _createDefaultNote(DateTime now) {
    final defaultContent = widget.isChecklist
        ? NoteHelper.markdownToDeltaJson('[ ] ')
        : jsonEncode([
            {'insert': '\n'}
          ]);

    return NoteEntity(
      id: widget.noteId ?? _uuid.v4(),
      title: '',
      content: defaultContent,
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
    if (!_isLoading && !_isDeleted) {
      _saveNoteImmediate();
    }
    _quillController.removeListener(_onQuillChanged);
    _quillController.dispose();
    _titleFocusNode.dispose();
    _titleController.dispose();
    _editorFocusNode.dispose();
    _editorScrollController.dispose();
    super.dispose();
  }

  void _triggerAutoSave() {
    if (!mounted || _isDeleted) return;
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
    if (_isDeleted) return;

    final title = _titleController.text.trim();
    final String contentToSave;
    if (_currentNote.isChecklist) {
      contentToSave = _currentNote.content;
    } else {
      contentToSave = jsonEncode(_quillController.document.toDelta().toJson());
    }

    final plainText = NoteHelper.extractPlainText(contentToSave).trim();

    // If this is a new note and both title and content are blank, check audio and attachments
    final attachments =
        await ref.read(noteRepositoryProvider).getAttachments(_currentNote.id);
    final hasAttachments = attachments.isNotEmpty;
    if (!_isNotePersisted &&
        title.isEmpty &&
        plainText.isEmpty &&
        !_currentNote.hasAudio &&
        !hasAttachments) {
      return;
    }

    final updated = _currentNote.copyWith(
      title: _titleController.text,
      content: contentToSave,
      updatedAt: DateTime.now(),
    );

    _currentNote = updated;
    _isNotePersisted = true;
    await ref.read(noteRepositoryProvider).saveNote(updated);

    if (mounted) {
      setState(() {
        _isSaving = false;
        _saveStatus = 'Saved locally';
      });
    }
  }

  Future<void> _pickAttachments() async {
    // 1. Synchronous pre-persistence: ensure draft note is persisted before adding child attachments
    await _saveNoteImmediate();

    setState(() {
      _isImportingAttachments = true;
    });

    try {
      final bridge = AttachmentNativeBridge();
      final result = await bridge.pickAttachments();

      if (result.isCancelled) {
        return;
      }

      final repo = ref.read(noteRepositoryProvider);

      // Import successful files
      for (final item in result.successfulItems) {
        if (item.stagingPath != null) {
          await repo.importAndSaveAttachment(
            stagingPath: item.stagingPath!,
            originalName: item.originalName,
            noteId: _currentNote.id,
            mimeType: item.mimeType,
          );
        }
      }

      // Inform user if any file failed or exceeded size limit
      if (result.failedItems.isNotEmpty && mounted) {
        final oversized =
            result.failedItems.where((f) => f.isSizeLimitExceeded).length;
        final msg = oversized > 0
            ? '$oversized file(s) exceeded the 25 MB size limit and were skipped.'
            : 'Some files could not be imported.';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to pick attachments: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isImportingAttachments = false;
        });
      }
    }
  }

  Future<void> _deleteAttachment(AttachmentEntity attachment) async {
    final repo = ref.read(noteRepositoryProvider);
    await repo.deleteAttachment(attachment.id);
  }

  void _confirmDeleteAttachment(AttachmentEntity attachment) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppConstants.radiusMedium),
        ),
        title: const Text('Remove Attachment?'),
        content: Text(
            'Are you sure you want to remove "${attachment.originalName}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.of(dialogContext).pop();
              await _deleteAttachment(attachment);
            },
            child: const Text(
              'Remove',
              style: TextStyle(
                  color: AppColors.danger, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  void _showFolderSelector(List<FolderEntity> folders) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppConstants.radiusLarge)),
      ),
      builder: (bottomContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(
                vertical: AppConstants.paddingMedium),
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
                        _currentNote =
                            _currentNote.copyWith(folderId: folder.id);
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

  Future<void> _showTagSelector() async {
    final updatedTagIds = await TagSelectorModal.show(
      context: context,
      selectedTagIds: _currentNote.tagIds,
    );
    if (updatedTagIds != null && mounted) {
      setState(() {
        _currentNote = _currentNote.copyWith(tagIds: updatedTagIds);
      });
      _triggerAutoSave();
    }
  }

  void _showStats() {
    _currentNote = _currentNote.copyWith(
      title: _titleController.text,
      content: jsonEncode(_quillController.document.toDelta().toJson()),
    );

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppConstants.radiusLarge)),
      ),
      builder: (_) => NoteStatsModal(note: _currentNote),
    );
  }

  void _copyToClipboard() {
    final plainText = _quillController.document.toPlainText().trim();
    final full = '${_titleController.text}\n\n$plainText'.trim();
    Clipboard.setData(ClipboardData(text: full));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Note copied to clipboard')),
    );
  }

  Future<void> _archiveCurrentNote() async {
    _autoSaveTimer?.cancel();
    _isDeleted =
        true; // Mark true so PopScope/dispose will not re-save unarchived state

    final title = _titleController.text.trim();
    final String contentToSave;
    if (_currentNote.isChecklist) {
      contentToSave = _currentNote.content;
    } else {
      contentToSave = jsonEncode(_quillController.document.toDelta().toJson());
    }

    final plainText = NoteHelper.extractPlainText(contentToSave).trim();

    // If new note and completely empty (and no audio), discard without saving to archive
    if (!_isNotePersisted &&
        title.isEmpty &&
        plainText.isEmpty &&
        !_currentNote.hasAudio) {
      if (mounted) Navigator.of(context).pop();
      return;
    }

    final updated = _currentNote.copyWith(
      title: _titleController.text,
      content: contentToSave,
      isArchived: true,
      isPinned: false, // Unpin on archive
      updatedAt: DateTime.now(),
    );

    _currentNote = updated;
    await ref.read(noteRepositoryProvider).saveNote(updated);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Note archived')),
      );
      Navigator.of(context).pop();
    }
  }

  void _confirmDelete() {
    final noteTitle = _titleController.text.trim().isNotEmpty
        ? _titleController.text.trim()
        : (_currentNote.title.isNotEmpty
            ? _currentNote.title
            : 'Untitled Note');

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppConstants.radiusMedium),
        ),
        title: const Text('Delete Note'),
        content:
            Text('Are you sure you want to permanently delete "$noteTitle"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.danger,
            ),
            onPressed: () async {
              _isDeleted = true;
              _autoSaveTimer?.cancel();
              if (_isNotePersisted) {
                await ref
                    .read(noteRepositoryProvider)
                    .deleteNote(_currentNote.id);
              }
              if (dialogContext.mounted) Navigator.pop(dialogContext);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Note deleted permanently')),
                );
                Navigator.of(context).pop();
              }
            },
            child: const Text('Delete'),
          ),
        ],
      ),
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
    final colorList =
        isDark ? AppColors.darkNoteColors : AppColors.lightNoteColors;
    final backgroundColor = _currentNote.colorIndex < colorList.length
        ? colorList[_currentNote.colorIndex]
        : (isDark ? AppColors.darkBackground : AppColors.lightBackground);

    final primaryTextColor =
        isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary;
    final secondaryTextColor =
        isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary;

    final foldersAsync = ref.watch(foldersStreamProvider);
    final folders = foldersAsync.value ?? [];
    final currentFolder =
        folders.where((f) => f.id == _currentNote.folderId).firstOrNull;

    final tagsAsync = ref.watch(tagsStreamProvider);
    final allTags = tagsAsync.value ?? [];
    final noteTags =
        allTags.where((t) => _currentNote.tagIds.contains(t.id)).toList();

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        if (!_isDeleted) {
          await _saveNoteImmediate();
        }
        if (mounted) {
          Navigator.of(context).pop();
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
              if (!_isDeleted) {
                await _saveNoteImmediate();
              }
              if (mounted) Navigator.of(context).pop();
            },
          ),
          title: Row(
            children: [
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
            IconButton(
              icon: Icon(
                _currentNote.isFavorite
                    ? Icons.star_rounded
                    : Icons.star_outline_rounded,
                color:
                    _currentNote.isFavorite ? Colors.amber : secondaryTextColor,
              ),
              tooltip:
                  _currentNote.isFavorite ? 'Unfavorite Note' : 'Favorite Note',
              onPressed: () {
                setState(() {
                  _currentNote = _currentNote.copyWith(
                      isFavorite: !_currentNote.isFavorite);
                });
                _triggerAutoSave();
              },
            ),
            IconButton(
              icon: Icon(
                _currentNote.tagIds.isNotEmpty
                    ? Icons.label_rounded
                    : Icons.label_outline_rounded,
                color: _currentNote.tagIds.isNotEmpty
                    ? AppColors.primary
                    : secondaryTextColor,
              ),
              tooltip: 'Assign Tags',
              onPressed: _showTagSelector,
            ),
            IconButton(
              icon: Icon(
                _currentNote.isPinned
                    ? Icons.push_pin
                    : Icons.push_pin_outlined,
                color: _currentNote.isPinned
                    ? AppColors.pinColor
                    : secondaryTextColor,
              ),
              tooltip: _currentNote.isPinned ? 'Unpin Note' : 'Pin Note',
              onPressed: () {
                setState(() {
                  _currentNote =
                      _currentNote.copyWith(isPinned: !_currentNote.isPinned);
                });
                _triggerAutoSave();
              },
            ),
            IconButton(
              icon: Icon(
                _currentNote.hasAudio
                    ? Icons.mic_rounded
                    : Icons.mic_none_rounded,
                color: _currentNote.hasAudio
                    ? AppColors.primary
                    : secondaryTextColor,
              ),
              tooltip: _currentNote.hasAudio
                  ? 'Voice Memo Attached'
                  : 'Record Voice Memo',
              onPressed: () {
                setState(() {
                  _showAudioRecorder = true;
                });
              },
            ),
            IconButton(
              icon: Icon(
                Icons.attach_file_rounded,
                color: secondaryTextColor,
              ),
              tooltip: 'Add Attachment',
              onPressed: _pickAttachments,
            ),
            Consumer(
              builder: (context, ref, _) {
                final rem = ref.watch(noteReminderProvider(_currentNote.id));
                final hasReminder = rem != null;

                return IconButton(
                  icon: Icon(
                    hasReminder
                        ? Icons.alarm_on_rounded
                        : Icons.alarm_add_rounded,
                    color: hasReminder ? AppColors.primary : secondaryTextColor,
                  ),
                  tooltip: hasReminder ? 'Edit Reminder' : 'Set Reminder',
                  onPressed: () async {
                    await _saveNoteImmediate();
                    if (!context.mounted) return;
                    final title = _titleController.text.trim().isNotEmpty
                        ? _titleController.text.trim()
                        : 'Note Reminder';
                    final preview =
                        NoteHelper.extractPlainText(_currentNote.content)
                            .trim();
                    ReminderBottomSheet.show(
                      context: context,
                      noteId: _currentNote.id,
                      defaultTitle: title,
                      defaultPreview: preview,
                      existingReminder: rem,
                    );
                  },
                );
              },
            ),
            PopupMenuButton<String>(
              icon: Icon(Icons.more_vert, color: secondaryTextColor),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppConstants.radiusMedium),
              ),
              onSelected: (val) async {
                switch (val) {
                  case 'favorite':
                    setState(() {
                      _currentNote = _currentNote.copyWith(
                          isFavorite: !_currentNote.isFavorite);
                    });
                    _triggerAutoSave();
                    break;
                  case 'tags':
                    _showTagSelector();
                    break;
                  case 'attach':
                    _pickAttachments();
                    break;
                  case 'voice':
                    setState(() {
                      _showAudioRecorder = true;
                    });
                    break;
                  case 'checklist':
                    final newIsChecklist = !_currentNote.isChecklist;
                    if (newIsChecklist) {
                      // Switching to checklist: sync latest Quill delta first
                      final currentDelta = jsonEncode(
                          _quillController.document.toDelta().toJson());
                      setState(() {
                        _currentNote = _currentNote.copyWith(
                            isChecklist: true, content: currentDelta);
                      });
                    } else {
                      // Switching to rich text: reinitialize Quill with current checklist content
                      _quillController.removeListener(_onQuillChanged);
                      _quillController.dispose();
                      _initQuillController(_currentNote.content);
                      setState(() {
                        _currentNote =
                            _currentNote.copyWith(isChecklist: false);
                      });
                    }
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
                    await _archiveCurrentNote();
                    break;
                  case 'delete':
                    _confirmDelete();
                    break;
                }
              },
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: 'favorite',
                  child: Row(
                    children: [
                      Icon(
                        _currentNote.isFavorite
                            ? Icons.star_rounded
                            : Icons.star_outline_rounded,
                        size: 18,
                        color: _currentNote.isFavorite ? Colors.amber : null,
                      ),
                      const SizedBox(width: 10),
                      Text(_currentNote.isFavorite
                          ? 'Remove from Favorites'
                          : 'Add to Favorites'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'tags',
                  child: Row(
                    children: [
                      Icon(Icons.label_outline_rounded, size: 18),
                      SizedBox(width: 10),
                      Text('Assign Tags'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'attach',
                  child: Row(
                    children: [
                      Icon(Icons.attach_file_rounded, size: 18),
                      SizedBox(width: 10),
                      Text('Add Attachment'),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'voice',
                  child: Row(
                    children: [
                      Icon(
                        _currentNote.hasAudio
                            ? Icons.mic_rounded
                            : Icons.mic_none_rounded,
                        size: 18,
                        color: _currentNote.hasAudio ? AppColors.primary : null,
                      ),
                      const SizedBox(width: 10),
                      Text(_currentNote.hasAudio
                          ? 'Voice Memo Attached'
                          : 'Record Voice Memo'),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'checklist',
                  child: Row(
                    children: [
                      Icon(
                        _currentNote.isChecklist
                            ? Icons.notes_rounded
                            : Icons.checklist_rounded,
                        size: 18,
                      ),
                      const SizedBox(width: 10),
                      Text(_currentNote.isChecklist
                          ? 'Convert to Rich Text'
                          : 'Convert to Checklist'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'folder',
                  child: Row(
                    children: [
                      Icon(Icons.folder_outlined, size: 18),
                      SizedBox(width: 10),
                      Text('Assign Folder'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'stats',
                  child: Row(
                    children: [
                      Icon(Icons.analytics_outlined, size: 18),
                      SizedBox(width: 10),
                      Text('Note Info & Stats'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'copy',
                  child: Row(
                    children: [
                      Icon(Icons.copy_rounded, size: 18),
                      SizedBox(width: 10),
                      Text('Copy Note Text'),
                    ],
                  ),
                ),
                const PopupMenuDivider(),
                const PopupMenuItem(
                  value: 'archive',
                  child: Row(
                    children: [
                      Icon(Icons.archive_outlined, size: 18),
                      SizedBox(width: 10),
                      Text('Archive Note'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'delete',
                  child: Row(
                    children: [
                      Icon(Icons.delete_outline,
                          size: 18, color: AppColors.danger),
                      SizedBox(width: 10),
                      Text('Delete Note',
                          style: TextStyle(color: AppColors.danger)),
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
                padding: const EdgeInsets.symmetric(
                    horizontal: AppConstants.paddingMedium),
                children: [
                  if (currentFolder != null || noteTags.isNotEmpty) ...[
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          if (currentFolder != null)
                            ActionChip(
                              avatar:
                                  const Icon(Icons.folder_outlined, size: 14),
                              label: Text(currentFolder.name),
                              visualDensity: VisualDensity.compact,
                              onPressed: () => _showFolderSelector(folders),
                            ),
                          for (final tag in noteTags)
                            TagChip(
                              tag: tag,
                              onDeleted: () {
                                setState(() {
                                  _currentNote = _currentNote.copyWith(
                                    tagIds: _currentNote.tagIds
                                        .where((id) => id != tag.id)
                                        .toList(),
                                  );
                                });
                                _triggerAutoSave();
                              },
                            ),
                          ActionChip(
                            avatar: const Icon(Icons.add, size: 14),
                            label: const Text('Add Tag',
                                style: TextStyle(fontSize: 12)),
                            visualDensity: VisualDensity.compact,
                            onPressed: _showTagSelector,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],

                  // Voice Note Player / Recorder Widget (Hybrid Note Header)
                  if (_currentNote.hasAudio ||
                      _showAudioRecorder ||
                      widget.isVoiceNote) ...[
                    VoiceNoteWidget(
                      audioPath: _currentNote.audioPath,
                      audioDurationMs: _currentNote.audioDurationMs,
                      autoStartRecording:
                          !_isNotePersisted && widget.isVoiceNote,
                      onAudioRecorded: (data) {
                        setState(() {
                          _currentNote = _currentNote.copyWith(
                            audioPath: data.audioPath,
                            audioDurationMs: data.durationMs,
                          );
                        });
                        _triggerAutoSave();
                      },
                      onAudioDeleted: () {
                        setState(() {
                          _currentNote =
                              _currentNote.copyWith(clearAudio: true);
                          _showAudioRecorder = false;
                        });
                        _triggerAutoSave();
                      },
                    ),
                    const SizedBox(height: 8),
                  ],

                  // Title Text Field
                  TextField(
                    controller: _titleController,
                    focusNode: _titleFocusNode,
                    textInputAction: TextInputAction.next,
                    onSubmitted: (_) {
                      if (!_currentNote.isChecklist) {
                        _editorFocusNode.requestFocus();
                      }
                    },
                    style: AppTypography.displayMedium(primaryTextColor),
                    decoration: InputDecoration(
                      hintText: 'Title',
                      hintStyle: AppTypography.displayMedium(
                        isDark
                            ? AppColors.darkTextTertiary
                            : AppColors.lightTextTertiary,
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

                  // Active Note Reminder Chip
                  Consumer(
                    builder: (context, ref, _) {
                      final rem =
                          ref.watch(noteReminderProvider(_currentNote.id));
                      if (rem == null) return const SizedBox.shrink();
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: ReminderChip(
                            reminder: rem,
                            onTap: () {
                              final title =
                                  _titleController.text.trim().isNotEmpty
                                      ? _titleController.text.trim()
                                      : 'Note Reminder';
                              final preview = NoteHelper.extractPlainText(
                                      _currentNote.content)
                                  .trim();
                              ReminderBottomSheet.show(
                                context: context,
                                noteId: _currentNote.id,
                                defaultTitle: title,
                                defaultPreview: preview,
                                existingReminder: rem,
                              );
                            },
                            onDelete: () {
                              ref
                                  .read(reminderServiceProvider)
                                  .deleteReminder(rem.id);
                            },
                          ),
                        ),
                      );
                    },
                  ),

                  // Attachments Strip (hidden when empty)
                  AttachmentSection(
                    noteId: _currentNote.id,
                    isImporting: _isImportingAttachments,
                    onAddAttachment: _pickAttachments,
                    onAttachmentTap: (attachment) {
                      AttachmentPreviewDialog.show(
                        context: context,
                        attachment: attachment,
                        onDelete: () => _deleteAttachment(attachment),
                      );
                    },
                    onAttachmentDelete: (attachment) {
                      _confirmDeleteAttachment(attachment);
                    },
                  ),

                  // Body Content: Checklist or Native Flutter Quill Editor
                  if (_currentNote.isChecklist)
                    ChecklistView(
                      noteId: _currentNote.id,
                      rawContent:
                          NoteHelper.formatForEditor(_currentNote.content),
                      autoFocus: !_isNotePersisted &&
                          (_currentNote.title.isEmpty &&
                              NoteHelper.extractPlainText(_currentNote.content)
                                  .isEmpty),
                      onContentChanged: (newText) {
                        final deltaJson =
                            NoteHelper.markdownToDeltaJson(newText);
                        _currentNote =
                            _currentNote.copyWith(content: deltaJson);
                        try {
                          final ops = jsonDecode(deltaJson) as List<dynamic>;
                          _quillController.removeListener(_onQuillChanged);
                          _quillController.document = Document.fromJson(ops);
                          _quillController.addListener(_onQuillChanged);
                        } catch (_) {}
                        _triggerAutoSave();
                      },
                    )
                  else
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: QuillEditor.basic(
                        controller: _quillController,
                        focusNode: _editorFocusNode,
                        scrollController: _editorScrollController,
                        config: QuillEditorConfig(
                          placeholder:
                              'Start writing thoughts, tasks, or format with toolbar...',
                          padding: EdgeInsets.zero,
                          autoFocus: !_isNotePersisted && !widget.isChecklist,
                          scrollable: false,
                          expands: false,
                          showCursor: true,
                        ),
                      ),
                    ),

                  const SizedBox(height: 40),
                ],
              ),
            ),

            // Bottom Controls Bar: auto-collapses color tint when keyboard is visible to maximize editor canvas
            Builder(
              builder: (context) {
                final isKeyboardOpen =
                    MediaQuery.of(context).viewInsets.bottom > 0;
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
                              _currentNote =
                                  _currentNote.copyWith(colorIndex: idx);
                            });
                            _triggerAutoSave();
                          },
                        ),
                      if (!_currentNote.isChecklist)
                        EditorToolbar(
                          controller: _quillController,
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
