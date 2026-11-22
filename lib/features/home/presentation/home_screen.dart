import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_provider.dart';
import '../../../core/database/database_provider.dart';
import '../../../shared/models/note_entity.dart';
import '../../../shared/models/folder_entity.dart';
import '../../../shared/models/note_filter.dart';
import '../../../shared/widgets/empty_state_view.dart';
import '../providers/home_notes_provider.dart';
import 'widgets/home_navigation_drawer.dart';
import 'widgets/home_header.dart';
import 'widgets/folder_filter_bar.dart';
import 'widgets/tag_filter_bar.dart';
import 'widgets/note_card.dart';
import '../../editor/presentation/note_editor_screen.dart';
import '../../voice_notes/presentation/voice_note_editor_screen.dart';
import '../../archive/presentation/archive_screen.dart';
import '../../folders/presentation/folders_screen.dart';
import '../../tags/presentation/tags_screen.dart';
import '../../tags/presentation/widgets/tag_dialog.dart';
import '../../backup/presentation/backup_restore_screen.dart';
import '../../reminders/presentation/reminder_management_screen.dart';
import '../../reminders/services/reminder_native_bridge.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final TextEditingController _searchController = TextEditingController();
  final _uuid = const Uuid();
  StreamSubscription? _notificationTapSub;
  bool _isSearching = false;

  @override
  void initState() {
    super.initState();
    _initNotificationRouting();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkDataRecoveryMode();
    });
  }

  void _checkDataRecoveryMode() {
    final repo = ref.read(noteRepositoryProvider);
    if (repo.isDataRecoveryMode && mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          icon: const Icon(Icons.warning_amber_rounded, color: Colors.amber, size: 36),
          title: const Text('Data Recovery Mode'),
          content: Text(
            repo.dataRecoveryError ??
                'Unable to read note data. Please restore from a backup or contact support.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Dismiss'),
            ),
            FilledButton.icon(
              icon: const Icon(Icons.settings_backup_restore_rounded),
              label: const Text('Restore Backup'),
              onPressed: () {
                Navigator.pop(ctx);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const BackupRestoreScreen()),
                );
              },
            ),
          ],
        ),
      );
    }
  }

  void _initNotificationRouting() async {
    try {
      final initial =
          await ReminderNativeBridge.getInitialNotificationPayload();
      if (initial != null) {
        _dispatchNotificationPayload(initial);
      }

      _notificationTapSub = ReminderNativeBridge.onNotificationTapped.listen((
        payload,
      ) {
        if (!mounted) return;
        _dispatchNotificationPayload(payload);
      });
    } catch (_) {}
  }

  void _dispatchNotificationPayload(Map<String, dynamic> payload) {
    if (payload['action'] == 'open_overdue' || payload['initialTabIndex'] != null) {
      final tabIndex = (payload['initialTabIndex'] as num?)?.toInt() ?? 2;
      _navigateToReminders(initialTabIndex: tabIndex);
      return;
    }

    final noteId = payload['noteId'] as String?;
    if (noteId != null && noteId.isNotEmpty) {
      final checklistItemId = payload['checklistItemId'] as String?;
      final voiceRecordingId = payload['voiceRecordingId'] as String?;
      _handleNotificationDeepLink(
        noteId: noteId,
        checklistItemId: checklistItemId,
        voiceRecordingId: voiceRecordingId,
      );
    } else {
      _navigateToReminders();
    }
  }

  Future<void> _handleNotificationDeepLink({
    required String noteId,
    String? checklistItemId,
    String? voiceRecordingId,
  }) async {
    final repo = ref.read(noteRepositoryProvider);
    final note = await repo.getNoteById(noteId);

    if (!mounted) return;

    if (note == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Target note was deleted')),
      );
      return;
    }

    final targetRouteName = 'editor_$noteId';
    bool alreadyOnScreen = false;
    Navigator.of(context).popUntil((route) {
      if (route.settings.name == targetRouteName) {
        alreadyOnScreen = true;
        return true;
      }
      return route.isFirst;
    });

    if (alreadyOnScreen) {
      return;
    }

    _navigateToEditor(
      note: note,
      noteId: note.id,
      isChecklist: note.isChecklist,
      isVoiceNote: note.isVoiceNote,
      targetChecklistItemId: checklistItemId,
      targetVoiceRecordingId: voiceRecordingId,
    );
  }

  @override
  void dispose() {
    _notificationTapSub?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _navigateToEditor({
    NoteEntity? note,
    String? noteId,
    bool isChecklist = false,
    bool isVoiceNote = false,
    String? targetChecklistItemId,
    String? targetVoiceRecordingId,
  }) {
    final effectiveNoteId = note?.id ?? noteId;
    final filterState = ref.read(noteFilterProvider);
    final isVoice = isVoiceNote || (note?.isVoiceNote ?? false);
    final routeName =
        effectiveNoteId != null ? 'editor_$effectiveNoteId' : 'editor_new';

    if (isVoice) {
      Navigator.push(
        context,
        MaterialPageRoute(
          settings: RouteSettings(name: routeName),
          builder: (_) => VoiceNoteEditorScreen(
            noteId: effectiveNoteId,
            initialNote: note,
            initialFolderId: note?.folderId ?? filterState.selectedFolderId,
            targetVoiceRecordingId: targetVoiceRecordingId,
          ),
        ),
      );
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        settings: RouteSettings(name: routeName),
        builder: (_) => NoteEditorScreen(
          noteId: effectiveNoteId,
          initialNote: note,
          initialFolderId: note?.folderId ?? filterState.selectedFolderId,
          isChecklist: note?.isChecklist ?? isChecklist,
          isVoiceNote: note?.hasAudio ?? false,
          targetChecklistItemId: targetChecklistItemId,
        ),
      ),
    );
  }

  void _navigateToReminders({int initialTabIndex = 0}) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ReminderManagementScreen(initialTabIndex: initialTabIndex),
      ),
    );
  }

  void _showCreateFolderDialog() {
    final textController = TextEditingController();
    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppConstants.radiusMedium),
          ),
          title: const Text('New Folder'),
          content: TextField(
            controller: textController,
            autofocus: true,
            decoration: const InputDecoration(
              hintText: 'Folder name (e.g. Work, Journal)',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                final name = textController.text.trim();
                if (name.isNotEmpty) {
                  final newFolder = FolderEntity(
                    id: _uuid.v4(),
                    name: name,
                    colorHex: '0xFF2563EB',
                    iconName: 'folder',
                    createdAt: DateTime.now(),
                  );
                  await ref.read(noteRepositoryProvider).saveFolder(newFolder);
                }
                if (dialogContext.mounted) Navigator.pop(dialogContext);
              },
              child: const Text('Create'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final homeNotesAsync = ref.watch(homeNotesProvider);
    final foldersAsync = ref.watch(foldersStreamProvider);
    final tagsAsync = ref.watch(tagsStreamProvider);
    final filterState = ref.watch(noteFilterProvider);
    final filterNotifier = ref.read(noteFilterProvider.notifier);
    final repo = ref.read(noteRepositoryProvider);

    final folders = foldersAsync.value ?? [];
    final folderMap = {for (var f in folders) f.id: f};

    // Calculate active filter title & icon for app bar identity
    String? activeFilterTitle;
    IconData? activeFilterIcon;
    if (filterState.isFavoritesOnly) {
      activeFilterTitle = 'Favorites';
      activeFilterIcon = Icons.star_rounded;
    } else if (filterState.isRecentOnly) {
      activeFilterTitle = 'Recent';
      activeFilterIcon = Icons.schedule_rounded;
    } else if (filterState.isPinnedOnly) {
      activeFilterTitle = 'Pinned';
      activeFilterIcon = Icons.push_pin_rounded;
    } else if (filterState.selectedFolderId != null &&
        folderMap.containsKey(filterState.selectedFolderId)) {
      activeFilterTitle = folderMap[filterState.selectedFolderId]!.name;
      activeFilterIcon = Icons.folder_outlined;
    }

    return PopScope(
      canPop: !_isSearching,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_isSearching) {
          setState(() {
            _isSearching = false;
            _searchController.clear();
            filterNotifier.setSearchQuery('');
          });
        }
      },
      child: Scaffold(
        drawer: const HomeNavigationDrawer(),
        body: SafeArea(
          child: Column(
            children: [
              // Redesigned Top App Bar with Drawer Button, Identity, Search & Actions
              HomeHeader(
                searchController: _searchController,
                isSearching: _isSearching,
                onStartSearch: () => setState(() => _isSearching = true),
                onCloseSearch: () => setState(() {
                  _isSearching = false;
                  _searchController.clear();
                  filterNotifier.setSearchQuery('');
                }),
                isDark: isDark,
                currentSort: filterState.sortOrder,
                activeFilterTitle: activeFilterTitle,
                activeFilterIcon: activeFilterIcon,
                onSearchChanged: (query) =>
                    filterNotifier.setSearchQuery(query),
                onClearSearch: () {
                  _searchController.clear();
                  filterNotifier.setSearchQuery('');
                },
                onToggleTheme: () =>
                    ref.read(themeModeProvider.notifier).toggleTheme(),
                onOpenTags: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const TagsScreen()),
                ),
                onOpenFolders: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const FoldersScreen()),
                ),
                onOpenArchive: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const ArchiveScreen()),
                ),
                onOpenBackup: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const BackupRestoreScreen(),
                  ),
                ),
                onOpenReminders: _navigateToReminders,
                onSortChanged: (sort) => filterNotifier.setSortOrder(sort),
              ),

              const SizedBox(height: 6),

              // Quick Filter Bar (All Notes, Favorites, Recent, Folders, + Folder)
              foldersAsync.when(
                data: (folders) => FolderFilterBar(
                  folders: folders,
                  selectedFolderId: filterState.selectedFolderId,
                  isFavoritesSelected: filterState.isFavoritesOnly,
                  isRecentSelected: filterState.isRecentOnly,
                  onSelectFolder: (id) => filterNotifier.setSelectedFolder(id),
                  onSelectFavorites: () => filterNotifier.toggleFavoritesOnly(),
                  onSelectRecent: () => filterNotifier.toggleRecentOnly(),
                  onAddFolder: _showCreateFolderDialog,
                ),
                loading: () => const SizedBox(height: 34),
                error: (_, __) => const SizedBox(height: 34),
              ),

              // Compact Secondary Tag Filter Bar
              tagsAsync.when(
                data: (tags) => TagFilterBar(
                  tags: tags,
                  selectedTagIds: filterState.selectedTagIds,
                  matchMode: filterState.tagMatchMode,
                  onToggleTag: (id) => filterNotifier.toggleTag(id),
                  onClearTags: () => filterNotifier.clearTags(),
                  onToggleMatchMode: (m) => filterNotifier.setTagMatchMode(m),
                  onAddTag: () async {
                    final result = await TagDialog.show(
                      context: context,
                      allTags: tags,
                    );
                    if (result != null && mounted) {
                      await repo.saveTag(result);
                      filterNotifier.toggleTag(result.id);
                    }
                  },
                  onManageTags: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const TagsScreen()),
                  ),
                ),
                loading: () => const SizedBox.shrink(),
                error: (_, __) => const SizedBox.shrink(),
              ),

              const SizedBox(height: 10),

              // Main Note List View
              Expanded(
                child: homeNotesAsync.when(
                  data: (data) {
                    if (data.isEmpty) {
                      return _buildEmptyState(filterState);
                    }

                    return RefreshIndicator(
                      onRefresh: () async {
                        ref.invalidate(activeNotesStreamProvider);
                      },
                      child: ListView(
                        keyboardDismissBehavior:
                            ScrollViewKeyboardDismissBehavior.onDrag,
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppConstants.paddingMedium,
                          vertical: AppConstants.paddingSmall,
                        ),
                        children: [
                          // Pinned Section
                          if (data.pinnedNotes.isNotEmpty) ...[
                            _buildSectionHeader(
                              'PINNED',
                              isDark,
                              count: data.pinnedNotes.length,
                              icon: Icons.push_pin_rounded,
                            ),
                            const SizedBox(height: 8),
                            ...data.pinnedNotes.map(
                              (note) => Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: NoteCard(
                                  note: note,
                                  folder: note.folderId != null
                                      ? folderMap[note.folderId]
                                      : null,
                                  onTap: () => _navigateToEditor(note: note),
                                  onTogglePin: () => repo.togglePin(note.id),
                                  onToggleFavorite: () =>
                                      repo.toggleFavorite(note.id),
                                  onToggleArchive: () =>
                                      repo.toggleArchive(note.id),
                                  onDelete: () => _confirmDelete(note),
                                ),
                              ),
                            ),
                            const SizedBox(height: 14),
                          ],

                          // Other Notes Section
                          if (data.otherNotes.isNotEmpty) ...[
                            if (data.pinnedNotes.isNotEmpty)
                              _buildSectionHeader(
                                'NOTES',
                                isDark,
                                count: data.otherNotes.length,
                                icon: Icons.notes_rounded,
                              ),
                            const SizedBox(height: 8),
                            ...data.otherNotes.map(
                              (note) => Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: NoteCard(
                                  note: note,
                                  folder: note.folderId != null
                                      ? folderMap[note.folderId]
                                      : null,
                                  onTap: () => _navigateToEditor(note: note),
                                  onTogglePin: () => repo.togglePin(note.id),
                                  onToggleFavorite: () =>
                                      repo.toggleFavorite(note.id),
                                  onToggleArchive: () =>
                                      repo.toggleArchive(note.id),
                                  onDelete: () => _confirmDelete(note),
                                ),
                              ),
                            ),
                          ],

                          // Extra bottom padding for FAB clearance
                          const SizedBox(height: 110),
                        ],
                      ),
                    );
                  },
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (error, _) =>
                      Center(child: Text('Error loading notes: $error')),
                ),
              ),
            ],
          ),
        ),

        // Modern Material 3 Floating Action Button
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => _showNewNoteOptions(),
          elevation: 2,
          highlightElevation: 4,
          icon: const Icon(Icons.add_rounded, size: 22),
          label: const Text(
            'New Note',
            style: TextStyle(fontWeight: FontWeight.w600, letterSpacing: 0.2),
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(
    String title,
    bool isDark, {
    int? count,
    IconData? icon,
  }) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 4, top: 2),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(
              icon,
              size: 13,
              color: isDark
                  ? AppColors.darkTextTertiary
                  : AppColors.lightTextTertiary,
            ),
            const SizedBox(width: 5),
          ],
          Text(
            count != null ? '$title ($count)' : title,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.1,
              color: isDark
                  ? AppColors.darkTextTertiary
                  : AppColors.lightTextTertiary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(NoteFilterState filter) {
    if (filter.searchQuery.isNotEmpty) {
      return EmptyStateView(
        icon: Icons.search_off_rounded,
        title: 'No notes found',
        description:
            'No notes matched "${filter.searchQuery}". Try different keywords.',
        actionLabel: 'Clear Search',
        onAction: () {
          _searchController.clear();
          ref.read(noteFilterProvider.notifier).setSearchQuery('');
        },
      );
    }

    if (filter.isFavoritesOnly) {
      return EmptyStateView(
        icon: Icons.star_outline_rounded,
        title: 'No favorite notes yet',
        description: 'Star your most important notes or checklists to view them quickly in favorites.',
        actionLabel: 'View All Notes',
        onAction: () => ref.read(noteFilterProvider.notifier).selectAllNotes(),
      );
    }

    if (filter.isRecentOnly) {
      return EmptyStateView(
        icon: Icons.schedule_rounded,
        title: 'No recent notes',
        description:
            'Notes created or updated in the last 7 days will appear here.',
        actionLabel: 'View All Notes',
        onAction: () => ref.read(noteFilterProvider.notifier).selectAllNotes(),
      );
    }

    if (filter.isPinnedOnly) {
      return EmptyStateView(
        icon: Icons.push_pin_outlined,
        title: 'No pinned notes yet',
        description: 'Pin your most important notes to keep them anchored at the top of your list.',
        actionLabel: 'View All Notes',
        onAction: () => ref.read(noteFilterProvider.notifier).selectAllNotes(),
      );
    }

    if (filter.hasTagFilter) {
      return EmptyStateView(
        icon: Icons.label_off_outlined,
        title: 'No notes with selected tags',
        description: 'No notes matched the active tag filters. Try selecting different tags or create a note with these tags.',
        actionLabel: 'Clear Tag Filters',
        onAction: () => ref.read(noteFilterProvider.notifier).clearTags(),
      );
    }

    if (filter.selectedFolderId != null) {
      return EmptyStateView(
        icon: Icons.folder_open_rounded,
        title: 'Folder is empty',
        description: 'You haven\'t added any notes to this folder yet.',
        actionLabel: 'Create Note Here',
        onAction: () => _navigateToEditor(),
      );
    }

    return EmptyStateView(
      icon: Icons.note_add_outlined,
      title: 'No notes yet',
      description:
          'Capture your thoughts, ideas, and tasks with pure offline privacy.',
      actionLabel: 'Create First Note',
      onAction: () => _navigateToEditor(),
    );
  }

  void _showNewNoteOptions() {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? AppColors.darkSurface : AppColors.lightSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppConstants.radiusLarge),
        ),
      ),
      builder: (bottomContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppConstants.paddingMedium,
            vertical: AppConstants.paddingSmall,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Drag Handle
              Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),

              const SizedBox(height: 8),

              // Title
              Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Create Note',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: isDark
                          ? AppColors.darkTextPrimary
                          : AppColors.lightTextPrimary,
                    ),
                  ),
                ),
              ),

              // Option 1: Text Note
              _buildNoteOptionTile(
                icon: Icons.description_outlined,
                iconColor: AppColors.primary,
                title: 'Text Note',
                subtitle: 'Rich text, formatted ideas, and thoughts',
                onTap: () {
                  Navigator.pop(bottomContext);
                  _navigateToEditor(isChecklist: false);
                },
                isDark: isDark,
              ),

              const SizedBox(height: 6),

              // Option 2: Checklist
              _buildNoteOptionTile(
                icon: Icons.checklist_rounded,
                iconColor: AppColors.accent,
                title: 'Checklist',
                subtitle: 'Interactive task and to-do list',
                onTap: () {
                  Navigator.pop(bottomContext);
                  _navigateToEditor(isChecklist: true);
                },
                isDark: isDark,
              ),

              const SizedBox(height: 6),

              // Option 3: Voice Note
              _buildNoteOptionTile(
                icon: Icons.mic_rounded,
                iconColor: Colors.redAccent,
                title: 'Voice Note',
                subtitle: 'Record voice memo with audio playback',
                onTap: () {
                  Navigator.pop(bottomContext);
                  _navigateToEditor(isVoiceNote: true);
                },
                isDark: isDark,
              ),

              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNoteOptionTile({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    required bool isDark,
  }) {
    return Material(
      color: isDark
          ? AppColors.darkSurfaceVariant.withAlpha(90)
          : AppColors.lightSurfaceVariant,
      borderRadius: BorderRadius.circular(AppConstants.radiusMedium),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppConstants.radiusMedium),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: iconColor.withAlpha(isDark ? 40 : 25),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Center(child: Icon(icon, color: iconColor, size: 22)),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w600,
                        color: isDark
                            ? AppColors.darkTextPrimary
                            : AppColors.lightTextPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark
                            ? AppColors.darkTextSecondary
                            : AppColors.lightTextSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: isDark
                    ? AppColors.darkTextTertiary
                    : AppColors.lightTextTertiary,
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _confirmDelete(NoteEntity note) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppConstants.radiusMedium),
        ),
        title: const Text('Delete Note'),
        content: Text(
          'Are you sure you want to permanently delete "${note.title}"?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () async {
              await ref.read(noteRepositoryProvider).deleteNote(note.id);
              if (dialogContext.mounted) Navigator.pop(dialogContext);
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}
