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
import '../../editor/presentation/widgets/color_tint_picker.dart';
import 'controllers/voice_player_controller.dart';
import 'widgets/live_recording_modal.dart';
import 'widgets/voice_recording_tile.dart';

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
  ConsumerState<VoiceNoteEditorScreen> createState() => _VoiceNoteEditorScreenState();
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

    _titleController = TextEditingController(text: _isLoading ? '' : _currentNote.title);
  }

  Future<void> _initExistingNote() async {
    final note = await ref.read(noteRepositoryProvider).getNoteById(widget.noteId!);
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
    final recordings = await ref.read(noteRepositoryProvider).getVoiceRecordings(_currentNote.id);

    // If never persisted, title is empty and no recordings, do not save an orphan note
    if (!_isNotePersisted && title.isEmpty && recordings.isEmpty) {
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
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppConstants.radiusLarge)),
      ),
      builder: (bottomContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppConstants.paddingMedium),
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
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppConstants.radiusLarge)),
      ),
      builder: (bottomContext) => SafeArea(
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
      ),
    );
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
                await ref.read(noteRepositoryProvider).deleteNote(_currentNote.id);
              }
              if (dialogCtx.mounted) Navigator.pop(dialogCtx);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Voice Note deleted permanently')),
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
    // If note is not saved to repository yet, make sure it is persisted before adding child recordings
    if (!_isNotePersisted) {
      await _saveNoteImmediate();
    }

    if (!mounted) return;

    final result = await showModalBottomSheet<VoiceRecordingEntity>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
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

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryTextColor = isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary;
    final secondaryTextColor = isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary;

    final foldersAsync = ref.watch(foldersStreamProvider);
    final recordingsAsync = ref.watch(voiceRecordingsStreamProvider(_currentNote.id));

    final isChecklistMode = _currentNote.voiceMode == 'checklist';

    // Background tint color
    final colorList = isDark ? AppColors.darkNoteColors : AppColors.lightNoteColors;
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
            onPressed: () {
              ref.read(voicePlayerProvider.notifier).stop();
              _saveNoteImmediate();
              Navigator.pop(context);
            },
          ),
          title: Text(
            _isSaving ? _saveStatus : 'Voice Note',
            style: TextStyle(
              fontSize: 14,
              color: secondaryTextColor,
              fontWeight: FontWeight.normal,
            ),
          ),
          actions: [
            // Pin / Unpin
            IconButton(
              icon: Icon(
                _currentNote.isPinned ? Icons.push_pin : Icons.push_pin_outlined,
                color: _currentNote.isPinned ? AppColors.primary : secondaryTextColor,
              ),
              tooltip: _currentNote.isPinned ? 'Unpin' : 'Pin',
              onPressed: () {
                setState(() {
                  _currentNote = _currentNote.copyWith(isPinned: !_currentNote.isPinned);
                });
                _triggerAutoSave();
              },
            ),

            // Color Tint
            IconButton(
              icon: const Icon(Icons.palette_outlined),
              tooltip: 'Note Color',
              onPressed: _showColorPicker,
            ),

            // Folder Assignment
            IconButton(
              icon: Icon(
                _currentNote.folderId != null ? Icons.folder_rounded : Icons.folder_outlined,
                color: _currentNote.folderId != null ? AppColors.primary : secondaryTextColor,
              ),
              tooltip: 'Assign Folder',
              onPressed: () => _showFolderSelector(foldersAsync.value ?? []),
            ),

            // More Options Menu
            PopupMenuButton<String>(
              icon: Icon(Icons.more_vert_rounded, color: secondaryTextColor),
              onSelected: (val) {
                if (val == 'archive') {
                  _archiveNote();
                } else if (val == 'delete') {
                  _confirmDelete();
                }
              },
              itemBuilder: (ctx) => [
                const PopupMenuItem(
                  value: 'archive',
                  child: Row(
                    children: [
                      Icon(Icons.archive_outlined, size: 20),
                      SizedBox(width: 8),
                      Text('Archive Note'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'delete',
                  child: Row(
                    children: [
                      Icon(Icons.delete_outline_rounded, size: 20, color: AppColors.danger),
                      SizedBox(width: 8),
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
            // Top Section: Title & Mode Switcher
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
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

                  // Mode Selector Tabs (List Mode vs Checklist Mode)
                  Row(
                    children: [
                      SegmentedButton<String>(
                        segments: const [
                          ButtonSegment<String>(
                            value: 'list',
                            label: Text('List'),
                            icon: Icon(Icons.format_list_bulleted_rounded, size: 16),
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
                                color: AppColors.primary.withAlpha(isDark ? 30 : 15),
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
                          ref.read(noteRepositoryProvider).deleteVoiceRecording(recording.id);
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
                error: (e, _) => Center(child: Text('Error loading recordings: $e')),
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
