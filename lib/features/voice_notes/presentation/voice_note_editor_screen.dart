import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/database/database_provider.dart';
import '../../../../shared/models/note_entity.dart';
import '../../../../shared/models/folder_entity.dart';
import '../../../../shared/models/voice_recording_entity.dart';
import '../../tags/presentation/widgets/tag_chip.dart';
import '../../tags/presentation/widgets/tag_selector_modal.dart';
import '../../editor/presentation/widgets/color_tint_picker.dart';
import 'controllers/voice_player_controller.dart';
import 'widgets/live_recording_modal.dart';
import 'widgets/voice_recording_tile.dart';
import '../../reminders/providers/reminder_providers.dart';
import '../../reminders/presentation/widgets/reminder_bottom_sheet.dart';
import '../../reminders/presentation/widgets/reminder_chip.dart';
import '../../../../shared/models/attachment_entity.dart';
import '../../attachments/presentation/widgets/attachment_section.dart';
import '../../attachments/presentation/widgets/attachment_preview_dialog.dart';
import '../../attachments/services/attachment_native_bridge.dart';

class VoiceNoteEditorScreen extends ConsumerStatefulWidget {
  final String? noteId;
  final NoteEntity? initialNote;
  final String? initialFolderId;

  const VoiceNoteEditorScreen({
    super.key,
    this.noteId,
    this.initialNote,
    this.initialFolderId,
  });

  @override
  ConsumerState<VoiceNoteEditorScreen> createState() =>
      _VoiceNoteEditorScreenState();
}

class _VoiceNoteEditorScreenState extends ConsumerState<VoiceNoteEditorScreen> {
  late final TextEditingController _titleController;
  final FocusNode _titleFocusNode = FocusNode();
  Timer? _autoSaveTimer;

  late NoteEntity _currentNote;
  bool _isLoading = false;
  bool _isSaving = false;
  bool _isDeleted = false;
  bool _isNotePersisted = false;
  bool _isImportingAttachments = false;
  String _saveStatus = 'Saved locally';

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();

    if (widget.initialNote != null) {
      _currentNote = widget.initialNote!.copyWith(isVoiceNote: true);
      _isLoading = false;
      _isNotePersisted = true;
    } else if (widget.noteId == null) {
      _currentNote = NoteEntity(
        id: const Uuid().v4(),
        title: '',
        content: '',
        folderId: widget.initialFolderId,
        isPinned: false,
        isArchived: false,
        isChecklist: false,
        isVoiceNote: true,
        voiceMode: 'list',
        colorIndex: 0,
        createdAt: now,
        updatedAt: now,
      );
      _isLoading = false;
      _isNotePersisted = false;
    } else {
      _isLoading = true;
      _isNotePersisted = true;
      _initExistingNote();
    }

    _titleController =
        TextEditingController(text: _isLoading ? '' : _currentNote.title);
  }

  Future<void> _initExistingNote() async {
    final note =
        await ref.read(noteRepositoryProvider).getNoteById(widget.noteId!);
    if (mounted) {
      if (note != null) {
        setState(() {
          _currentNote = note.copyWith(isVoiceNote: true);
          _titleController.text = _currentNote.title;
          _isLoading = false;
        });
      } else {
        Navigator.pop(context);
      }
    }
  }

  @override
  void dispose() {
    _autoSaveTimer?.cancel();
    _titleController.dispose();
    _titleFocusNode.dispose();
    ref.read(voicePlayerProvider.notifier).stop();
    super.dispose();
  }

  void _triggerAutoSave() {
    if (_isDeleted) return;
    setState(() {
      _isSaving = true;
      _saveStatus = 'Saving...';
    });

    _autoSaveTimer?.cancel();
    _autoSaveTimer = Timer(const Duration(milliseconds: 600), () {
      _saveNoteImmediate();
    });
  }

  Future<void> _saveNoteImmediate() async {
    if (_isDeleted) return;

    final title = _titleController.text.trim();
    final recordings = await ref
        .read(noteRepositoryProvider)
        .getVoiceRecordings(_currentNote.id);
    final attachments =
        await ref.read(noteRepositoryProvider).getAttachments(_currentNote.id);

    // If never persisted, title is empty, and no recordings or attachments, do not save an orphan note
    if (!_isNotePersisted &&
        title.isEmpty &&
        recordings.isEmpty &&
        attachments.isEmpty) {
      if (mounted) {
        setState(() {
          _isSaving = false;
          _saveStatus = 'Saved locally';
        });
      }
      return;
    }

    // Compute total audio duration and store recording titles in content for search indexing
    int totalMs = 0;
    final titles = <String>[];
    for (final r in recordings) {
      totalMs += r.durationMs;
      if (r.title.trim().isNotEmpty) {
        titles.add(r.title.trim());
      }
    }

    final updated = _currentNote.copyWith(
      title: _titleController.text,
      content: titles.join('\n'),
      isVoiceNote: true,
      audioDurationMs: totalMs,
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

  void _toggleMode(String newMode) {
    if (_currentNote.voiceMode == newMode) return;
    setState(() {
      _currentNote = _currentNote.copyWith(voiceMode: newMode);
    });
    _triggerAutoSave();
  }

  void _showColorPicker() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppConstants.radiusLarge)),
      ),
      builder: (bottomContext) => SafeArea(
        child: Padding(
          padding:
              const EdgeInsets.symmetric(vertical: AppConstants.paddingMedium),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: Text(
                  'Note Accent Color',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
              ),
              ColorTintPicker(
                selectedIndex: _currentNote.colorIndex,
                onSelectColor: (idx) {
                  setState(() {
                    _currentNote = _currentNote.copyWith(colorIndex: idx);
                  });
                  _triggerAutoSave();
                  Navigator.pop(bottomContext);
                },
              ),
            ],
          ),
        ),
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
      builder: (bottomContext) => SafeArea(
        child: Padding(
          padding:
              const EdgeInsets.symmetric(vertical: AppConstants.paddingMedium),
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
      ),
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

  Future<void> _archiveNote() async {
    _autoSaveTimer?.cancel();
    _isDeleted = true;

    final updated = _currentNote.copyWith(
      title: _titleController.text,
      isArchived: true,
      isPinned: false,
      updatedAt: DateTime.now(),
    );

    _currentNote = updated;
    await ref.read(noteRepositoryProvider).saveNote(updated);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Voice Note archived')),
      );
      Navigator.pop(context);
    }
  }

  void _confirmDelete() {
    final noteTitle = _titleController.text.trim().isNotEmpty
        ? _titleController.text.trim()
        : 'Voice Note';

    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppConstants.radiusMedium),
        ),
        title: const Text('Delete Voice Note'),
        content: Text(
          'Are you sure you want to delete "$noteTitle" and all its audio recordings permanently?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () async {
              _isDeleted = true;
              _autoSaveTimer?.cancel();
              // Stop playback
              ref.read(voicePlayerProvider.notifier).stop();

              if (_isNotePersisted) {
                await ref
                    .read(noteRepositoryProvider)
                    .deleteNote(_currentNote.id);
              }
              if (dialogCtx.mounted) Navigator.pop(dialogCtx);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                      content: Text('Voice Note deleted permanently')),
                );
                Navigator.pop(context);
              }
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  Future<void> _openRecordingModal(int currentCount) async {
    // 1. Stop any currently playing audio so it does not conflict with recording hardware
    ref.read(voicePlayerProvider.notifier).stop();

    // 2. If note is not saved to repository yet, persist it now so child SQLite foreign key is valid
    if (!_isNotePersisted) {
      final title = _titleController.text.trim();
      final noteToPersist = _currentNote.copyWith(
        title: title.isEmpty ? 'Voice Note' : title,
        updatedAt: DateTime.now(),
      );
      _currentNote = noteToPersist;
      _isNotePersisted = true;
      if (title.isEmpty) {
        _titleController.text = 'Voice Note';
      }
      await ref.read(noteRepositoryProvider).saveNote(noteToPersist);
    }

    if (!mounted) return;

    final result = await showModalBottomSheet<VoiceRecordingEntity>(
      context: context,
      isScrollControlled: true,
      useSafeArea: false,
      backgroundColor: Colors.transparent,
      enableDrag: true,
      isDismissible: true,
      builder: (_) => LiveRecordingModal(
        voiceNoteId: _currentNote.id,
        nextSortOrder: currentCount,
      ),
    );

    if (result != null && mounted) {
      await ref.read(noteRepositoryProvider).saveVoiceRecording(result);
      await _saveNoteImmediate();
    }
  }

  Future<void> _pickAttachments() async {
    if (_isImportingAttachments) return;

    // 1. Mandatory Pre-persistence: If draft note has not been saved to disk,
    // synchronously save it before importing child attachments so the parent note exists.
    if (!_isNotePersisted) {
      final title = _titleController.text.trim();
      final noteToPersist = _currentNote.copyWith(
        title: title.isEmpty ? 'Voice Note' : title,
        updatedAt: DateTime.now(),
      );
      _currentNote = noteToPersist;
      _isNotePersisted = true;
      if (title.isEmpty) {
        _titleController.text = 'Voice Note';
      }
      await ref.read(noteRepositoryProvider).saveNote(noteToPersist);
    }

    setState(() => _isImportingAttachments = true);
    try {
      final bridge = AttachmentNativeBridge();
      final result = await bridge.pickAttachments();
      if (result.isCancelled) return;

      final repo = ref.read(noteRepositoryProvider);
      int successCount = 0;
      for (final item in result.successfulItems) {
        if (item.stagingPath != null) {
          try {
            final saved = await repo.importAndSaveAttachment(
              stagingPath: item.stagingPath!,
              originalName: item.originalName,
              noteId: _currentNote.id,
              mimeType: item.mimeType,
            );
            if (saved != null) {
              successCount++;
            }
          } catch (e) {
            debugPrint('Failed to save attachment ${item.originalName}: $e');
          }
        }
      }

      if (mounted && successCount > 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'Added $successCount ${successCount == 1 ? 'attachment' : 'attachments'}'),
            duration: const Duration(seconds: 2),
          ),
        );
      }

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
          SnackBar(content: Text('Error selecting attachments: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isImportingAttachments = false);
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

  PopupMenuItem<String> _buildMenuSectionHeader(
    String title,
    Color textColor,
  ) {
    return PopupMenuItem<String>(
      enabled: false,
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.0,
          color: textColor,
        ),
      ),
    );
  }

  PopupMenuItem<String> _buildMenuItem({
    required String value,
    required IconData icon,
    required String label,
    Color? iconColor,
    Color? textColor,
  }) {
    return PopupMenuItem<String>(
      value: value,
      height: 42,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Icon(icon, size: 20, color: iconColor),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: textColor,
              ),
              overflow: TextOverflow.ellipsis,
            ),
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
    final primaryTextColor =
        isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary;
    final secondaryTextColor =
        isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary;
    final tertiaryTextColor =
        isDark ? AppColors.darkTextTertiary : AppColors.lightTextTertiary;

    final foldersAsync = ref.watch(foldersStreamProvider);
    final recordingsAsync =
        ref.watch(voiceRecordingsStreamProvider(_currentNote.id));
    final tagsAsync = ref.watch(tagsStreamProvider);
    final allTags = tagsAsync.value ?? [];
    final noteTags =
        allTags.where((t) => _currentNote.tagIds.contains(t.id)).toList();
    final currentFolder = (foldersAsync.value ?? [])
        .where((f) => f.id == _currentNote.folderId)
        .firstOrNull;

    final isChecklistMode = _currentNote.voiceMode == 'checklist';

    final reminder = ref.watch(noteReminderProvider(_currentNote.id));
    final hasReminder = reminder != null;

    // Background tint color
    final colorList =
        isDark ? AppColors.darkNoteColors : AppColors.lightNoteColors;
    final tintColor = _currentNote.colorIndex < colorList.length
        ? colorList[_currentNote.colorIndex]
        : (isDark ? AppColors.darkBackground : AppColors.lightBackground);

    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) {
          // Stop playback when leaving screen
          ref.read(voicePlayerProvider.notifier).stop();
          _saveNoteImmediate();
        }
      },
      child: Scaffold(
        backgroundColor: tintColor,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded),
            tooltip: 'Back',
            onPressed: () {
              ref.read(voicePlayerProvider.notifier).stop();
              _saveNoteImmediate();
              Navigator.pop(context);
            },
          ),
          title: Row(
            mainAxisSize: MainAxisSize.min,
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
            PopupMenuButton<String>(
              icon: Icon(Icons.more_vert_rounded, color: secondaryTextColor),
              tooltip: 'More options',
              elevation: 4,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppConstants.radiusMedium),
                side: BorderSide(
                  color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
                  width: 1.0,
                ),
              ),
              color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
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
                  case 'pin':
                    setState(() {
                      _currentNote = _currentNote.copyWith(
                          isPinned: !_currentNote.isPinned);
                    });
                    _triggerAutoSave();
                    break;
                  case 'folder':
                    _showFolderSelector(foldersAsync.value ?? []);
                    break;
                  case 'color':
                    _showColorPicker();
                    break;
                  case 'record':
                    final count = (recordingsAsync.value ?? []).length;
                    _openRecordingModal(count);
                    break;
                  case 'attach':
                    _pickAttachments();
                    break;
                  case 'mode':
                    _toggleMode(isChecklistMode ? 'list' : 'checklist');
                    break;
                  case 'reminder':
                    await _saveNoteImmediate();
                    if (!context.mounted) return;
                    final title = _titleController.text.trim().isNotEmpty
                        ? _titleController.text.trim()
                        : 'Voice Note Reminder';
                    ReminderBottomSheet.show(
                      context: context,
                      noteId: _currentNote.id,
                      defaultTitle: title,
                      existingReminder: reminder,
                    );
                    break;
                  case 'archive':
                    _archiveNote();
                    break;
                  case 'delete':
                    _confirmDelete();
                    break;
                }
              },
              itemBuilder: (context) => [
                _buildMenuSectionHeader('Organization', tertiaryTextColor),
                _buildMenuItem(
                  value: 'favorite',
                  icon: _currentNote.isFavorite
                      ? Icons.star_rounded
                      : Icons.star_outline_rounded,
                  label: _currentNote.isFavorite
                      ? 'Remove from favorites'
                      : 'Add to favorites',
                  iconColor: _currentNote.isFavorite
                      ? Colors.amber
                      : secondaryTextColor,
                ),
                _buildMenuItem(
                  value: 'tags',
                  icon: _currentNote.tagIds.isNotEmpty
                      ? Icons.label_rounded
                      : Icons.label_outline_rounded,
                  label: _currentNote.tagIds.isNotEmpty
                      ? 'Manage tags'
                      : 'Add tags',
                  iconColor: _currentNote.tagIds.isNotEmpty
                      ? AppColors.primary
                      : secondaryTextColor,
                ),
                _buildMenuItem(
                  value: 'pin',
                  icon: _currentNote.isPinned
                      ? Icons.push_pin_rounded
                      : Icons.push_pin_outlined,
                  label: _currentNote.isPinned ? 'Unpin note' : 'Pin note',
                  iconColor: _currentNote.isPinned
                      ? AppColors.pinColor
                      : secondaryTextColor,
                ),
                _buildMenuItem(
                  value: 'folder',
                  icon: currentFolder != null
                      ? Icons.folder_rounded
                      : Icons.folder_outlined,
                  label: currentFolder != null
                      ? 'Folder: ${currentFolder.name}'
                      : 'Assign folder',
                  iconColor: currentFolder != null
                      ? AppColors.primary
                      : secondaryTextColor,
                ),
                _buildMenuItem(
                  value: 'color',
                  icon: Icons.palette_outlined,
                  label: 'Note color',
                  iconColor: secondaryTextColor,
                ),
                const PopupMenuDivider(height: 1),
                _buildMenuSectionHeader('Add Content', tertiaryTextColor),
                _buildMenuItem(
                  value: 'record',
                  icon: Icons.mic_rounded,
                  label: 'Record audio',
                  iconColor: AppColors.primary,
                ),
                _buildMenuItem(
                  value: 'attach',
                  icon: Icons.attach_file_rounded,
                  label: 'Add attachment',
                  iconColor: secondaryTextColor,
                ),
                _buildMenuItem(
                  value: 'mode',
                  icon: isChecklistMode
                      ? Icons.format_list_bulleted_rounded
                      : Icons.checklist_rounded,
                  label: isChecklistMode
                      ? 'Switch to list mode'
                      : 'Switch to checklist mode',
                  iconColor: secondaryTextColor,
                ),
                const PopupMenuDivider(height: 1),
                _buildMenuSectionHeader('Scheduling', tertiaryTextColor),
                _buildMenuItem(
                  value: 'reminder',
                  icon: hasReminder
                      ? Icons.alarm_on_rounded
                      : Icons.alarm_add_rounded,
                  label: hasReminder ? 'Edit reminder' : 'Set reminder',
                  iconColor:
                      hasReminder ? AppColors.primary : secondaryTextColor,
                ),
                const PopupMenuDivider(height: 1),
                _buildMenuSectionHeader('More Actions', tertiaryTextColor),
                _buildMenuItem(
                  value: 'archive',
                  icon: Icons.archive_outlined,
                  label: 'Archive note',
                  iconColor: secondaryTextColor,
                ),
                _buildMenuItem(
                  value: 'delete',
                  icon: Icons.delete_outline_rounded,
                  label: 'Delete note',
                  iconColor: AppColors.danger,
                  textColor: AppColors.danger,
                ),
              ],
            ),
          ],
        ),

        body: Column(
          children: [
            // Top Section: Title & Mode Switcher
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Folder & Tags Wrap
                  if (currentFolder != null || noteTags.isNotEmpty) ...[
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        if (currentFolder != null)
                          ActionChip(
                            avatar: const Icon(Icons.folder_outlined, size: 14),
                            label: Text(currentFolder.name),
                            visualDensity: VisualDensity.compact,
                            onPressed: () =>
                                _showFolderSelector(foldersAsync.value ?? []),
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
                    const SizedBox(height: 8),
                  ],

                  // Title TextField
                  TextField(
                    controller: _titleController,
                    focusNode: _titleFocusNode,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: primaryTextColor,
                    ),
                    decoration: InputDecoration(
                      hintText: 'Voice Note Title...',
                      hintStyle: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w600,
                        color: secondaryTextColor.withAlpha(140),
                      ),
                      border: InputBorder.none,
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
                                      : 'Voice Note Reminder';
                              ReminderBottomSheet.show(
                                context: context,
                                noteId: _currentNote.id,
                                defaultTitle: title,
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

                  // Mode Selector Tabs (List Mode vs Checklist Mode)
                  Row(
                    children: [
                      SegmentedButton<String>(
                        segments: const [
                          ButtonSegment<String>(
                            value: 'list',
                            label: Text('List'),
                            icon: Icon(Icons.format_list_bulleted_rounded,
                                size: 16),
                          ),
                          ButtonSegment<String>(
                            value: 'checklist',
                            label: Text('Checklist'),
                            icon: Icon(Icons.checklist_rounded, size: 16),
                          ),
                        ],
                        selected: {_currentNote.voiceMode},
                        onSelectionChanged: (Set<String> newSelection) {
                          _toggleMode(newSelection.first);
                        },
                        style: const ButtonStyle(
                          visualDensity: VisualDensity.compact,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                      ),
                      const Spacer(),
                      recordingsAsync.when(
                        data: (recordings) => Text(
                          '${recordings.length} ${recordings.length == 1 ? 'recording' : 'recordings'}',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: secondaryTextColor,
                          ),
                        ),
                        loading: () => const SizedBox.shrink(),
                        error: (_, __) => const SizedBox.shrink(),
                      ),
                    ],
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
                ],
              ),
            ),

            const Divider(height: 1),

            // Recording List or Empty State
            Expanded(
              child: recordingsAsync.when(
                data: (recordings) {
                  if (recordings.isEmpty) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 64,
                              height: 64,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: AppColors.primary
                                    .withAlpha(isDark ? 30 : 15),
                              ),
                              child: const Icon(
                                Icons.mic_none_rounded,
                                size: 32,
                                color: AppColors.primary,
                              ),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'No Audio Recordings Yet',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: primaryTextColor,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Tap "Record Audio" below to add audio memos to this Voice Note.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 13,
                                color: secondaryTextColor,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }

                  return ReorderableListView.builder(
                    padding: const EdgeInsets.only(
                      left: 14,
                      right: 14,
                      top: 10,
                      bottom: 80,
                    ),
                    itemCount: recordings.length,
                    onReorder: (oldIndex, newIndex) {
                      if (oldIndex < newIndex) {
                        newIndex -= 1;
                      }
                      final items = List<VoiceRecordingEntity>.from(recordings);
                      final moved = items.removeAt(oldIndex);
                      items.insert(newIndex, moved);

                      final orderedIds = items.map((r) => r.id).toList();
                      ref.read(noteRepositoryProvider).reorderVoiceRecordings(
                            _currentNote.id,
                            orderedIds,
                          );
                    },
                    itemBuilder: (context, index) {
                      final recording = recordings[index];
                      return VoiceRecordingTile(
                        key: ValueKey(recording.id),
                        recording: recording,
                        isChecklistMode: isChecklistMode,
                        onToggleComplete: () {
                          ref
                              .read(noteRepositoryProvider)
                              .toggleVoiceRecordingCompletion(recording.id);
                        },
                        onRename: (newTitle) {
                          ref.read(noteRepositoryProvider).saveVoiceRecording(
                                recording.copyWith(title: newTitle),
                              );
                        },
                        onDelete: () {
                          ref
                              .read(noteRepositoryProvider)
                              .deleteVoiceRecording(recording.id);
                        },
                        dragHandle: ReorderableDragStartListener(
                          index: index,
                          child: Padding(
                            padding: const EdgeInsets.all(4),
                            child: Icon(
                              Icons.drag_indicator_rounded,
                              size: 18,
                              color: secondaryTextColor.withAlpha(120),
                            ),
                          ),
                        ),
                      );
                    },
                  );
                },
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) =>
                    Center(child: Text('Error loading recordings: $e')),
              ),
            ),
          ],
        ),

        // Prominent Record Button at Bottom
        floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
        floatingActionButton: recordingsAsync.when(
          data: (recordings) => FloatingActionButton.extended(
            elevation: 4,
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            icon: const Icon(Icons.mic_rounded, size: 22),
            label: const Text(
              'Record Audio',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            onPressed: () => _openRecordingModal(recordings.length),
          ),
          loading: () => const SizedBox.shrink(),
          error: (_, __) => const SizedBox.shrink(),
        ),
      ),
    );
  }
}
