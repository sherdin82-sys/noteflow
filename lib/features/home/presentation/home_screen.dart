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
import 'widgets/home_header.dart';
import 'widgets/folder_filter_bar.dart';
import 'widgets/note_card.dart';
import '../../editor/presentation/note_editor_screen.dart';
import '../../voice_notes/presentation/voice_note_editor_screen.dart';
import '../../archive/presentation/archive_screen.dart';
import '../../folders/presentation/folders_screen.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final TextEditingController _searchController = TextEditingController();
  final _uuid = const Uuid();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _navigateToEditor({
    NoteEntity? note,
    String? noteId,
    bool isChecklist = false,
    bool isVoiceNote = false,
  }) {
    final filterState = ref.read(noteFilterProvider);
    final isVoice = isVoiceNote || (note?.isVoiceNote ?? false);

    if (isVoice) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => VoiceNoteEditorScreen(
            noteId: note?.id ?? noteId,
            initialNote: note,
            initialFolderId: note?.folderId ?? filterState.selectedFolderId,
          ),
        ),
      );
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => NoteEditorScreen(
          noteId: note?.id ?? noteId,
          initialNote: note,
          initialFolderId: note?.folderId ?? filterState.selectedFolderId,
          isChecklist: note?.isChecklist ?? isChecklist,
          isVoiceNote: note?.hasAudio ?? false,
        ),
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
    final filterState = ref.watch(noteFilterProvider);
    final filterNotifier = ref.read(noteFilterProvider.notifier);
    final repo = ref.read(noteRepositoryProvider);

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // Top Header: Branding, Search, Folders, Archive, Theme & Sort Actions
            HomeHeader(
              searchController: _searchController,
              isDark: isDark,
              currentSort: filterState.sortOrder,
              onSearchChanged: (query) => filterNotifier.setSearchQuery(query),
              onClearSearch: () {
                _searchController.clear();
                filterNotifier.setSearchQuery('');
              },
              onToggleTheme: () => ref.read(themeModeProvider.notifier).toggleTheme(),
              onOpenFolders: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const FoldersScreen()),
              ),
              onOpenArchive: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ArchiveScreen()),
              ),
              onSortChanged: (sort) => filterNotifier.setSortOrder(sort),
            ),

            // Category & Folder Filter Chips
            foldersAsync.when(
              data: (folders) => FolderFilterBar(
                folders: folders,
                selectedFolderId: filterState.selectedFolderId,
                onSelectFolder: (id) => filterNotifier.setSelectedFolder(id),
                onAddFolder: _showCreateFolderDialog,
              ),
              loading: () => const SizedBox(height: 40),
              error: (_, __) => const SizedBox(height: 40),
            ),

            const SizedBox(height: 12),

            // Main Note List View
            Expanded(
              child: homeNotesAsync.when(
                data: (data) {
                  if (data.isEmpty) {
                    return _buildEmptyState(filterState);
                  }

                  final folders = foldersAsync.value ?? [];
                  final folderMap = {for (var f in folders) f.id: f};

                  return RefreshIndicator(
                    onRefresh: () async {
                      ref.invalidate(activeNotesStreamProvider);
                    },
                    child: ListView(
                      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppConstants.paddingMedium,
                        vertical: AppConstants.paddingSmall,
                      ),
                      children: [
                        // Pinned Section
                        if (data.pinnedNotes.isNotEmpty) ...[
                          _buildSectionHeader('PINNED', isDark),
                          const SizedBox(height: 8),
                          ...data.pinnedNotes.map(
                            (note) => Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: NoteCard(
                                note: note,
                                folder: note.folderId != null ? folderMap[note.folderId] : null,
                                onTap: () => _navigateToEditor(note: note),
                                onTogglePin: () => repo.togglePin(note.id),
                                onToggleArchive: () => repo.toggleArchive(note.id),
                                onDelete: () => _confirmDelete(note),
                              ),
                            ),
                          ),
                          const SizedBox(height: 14),
                        ],

                        // Other Notes Section
                        if (data.otherNotes.isNotEmpty) ...[
                          if (data.pinnedNotes.isNotEmpty)
                            _buildSectionHeader('NOTES', isDark),
                          const SizedBox(height: 8),
                          ...data.otherNotes.map(
                            (note) => Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: NoteCard(
                                note: note,
                                folder: note.folderId != null ? folderMap[note.folderId] : null,
                                onTap: () => _navigateToEditor(note: note),
                                onTogglePin: () => repo.togglePin(note.id),
                                onToggleArchive: () => repo.toggleArchive(note.id),
                                onDelete: () => _confirmDelete(note),
                              ),
                            ),
                          ),
                        ],

                        // Extra bottom padding for FAB clearance
                        const SizedBox(height: 104),
                      ],
                    ),
                  );
                },
                loading: () => const Center(
                  child: CircularProgressIndicator(),
                ),
                error: (error, _) => Center(
                  child: Text('Error loading notes: $error'),
                ),
              ),
            ),
          ],
        ),
      ),

      // Floating Action Button
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showNewNoteOptions(),
        icon: const Icon(Icons.add_rounded),
        label: const Text('New Note'),
      ),
    );
  }

  Widget _buildSectionHeader(String title, bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 4),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.2,
          color: isDark ? AppColors.darkTextTertiary : AppColors.lightTextTertiary,
        ),
      ),
    );
  }

  Widget _buildEmptyState(NoteFilterState filter) {
    if (filter.searchQuery.isNotEmpty) {
      return EmptyStateView(
        icon: Icons.search_off_rounded,
        title: 'No notes found',
        description: 'No notes matched "${filter.searchQuery}". Try different keywords.',
        actionLabel: 'Clear Search',
        onAction: () {
          _searchController.clear();
          ref.read(noteFilterProvider.notifier).setSearchQuery('');
        },
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
      description: 'Capture your thoughts, ideas, and tasks with pure offline privacy.',
      actionLabel: 'Create First Note',
      onAction: () => _navigateToEditor(),
    );
  }

  void _showNewNoteOptions() {
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
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withAlpha(20),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.description_outlined, color: AppColors.primary),
                ),
                title: const Text('Text Note', style: TextStyle(fontWeight: FontWeight.w600)),
                subtitle: const Text('Rich text, thoughts, and formatting'),
                onTap: () {
                  Navigator.pop(bottomContext);
                  _navigateToEditor(isChecklist: false);
                },
              ),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.accent.withAlpha(20),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.checklist_rounded, color: AppColors.accent),
                ),
                title: const Text('Checklist', style: TextStyle(fontWeight: FontWeight.w600)),
                subtitle: const Text('To-do list with interactive checkboxes'),
                onTap: () {
                  Navigator.pop(bottomContext);
                  _navigateToEditor(isChecklist: true);
                },
              ),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.redAccent.withAlpha(20),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.mic_rounded, color: Colors.redAccent),
                ),
                title: const Text('Voice Note', style: TextStyle(fontWeight: FontWeight.w600)),
                subtitle: const Text('Record audio memo with notes and playback'),
                onTap: () {
                  Navigator.pop(bottomContext);
                  _navigateToEditor(isVoiceNote: true);
                },
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
        content: Text('Are you sure you want to permanently delete "${note.title}"?'),
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
