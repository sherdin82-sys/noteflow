import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/database/database_provider.dart';
import '../../../shared/models/note_entity.dart';
import '../../../shared/widgets/empty_state_view.dart';
import '../../home/presentation/widgets/note_card.dart';
import '../../editor/presentation/note_editor_screen.dart';

class ArchiveScreen extends ConsumerStatefulWidget {
  const ArchiveScreen({super.key});

  @override
  ConsumerState<ArchiveScreen> createState() => _ArchiveScreenState();
}

class _ArchiveScreenState extends ConsumerState<ArchiveScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _navigateToEditor(NoteEntity note) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => NoteEditorScreen(
          noteId: note.id,
          initialNote: note,
          initialFolderId: note.folderId,
          isChecklist: note.isChecklist,
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
        title: const Text('Delete Permanently'),
        content: Text('Are you sure you want to permanently delete "${note.title}"? This cannot be undone.'),
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

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryTextColor = isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary;
    final secondaryTextColor = isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary;

    final archivedNotesAsync = ref.watch(archivedNotesStreamProvider);
    final foldersAsync = ref.watch(foldersStreamProvider);
    final repo = ref.read(noteRepositoryProvider);

    final folders = foldersAsync.value ?? [];
    final folderMap = {for (var f in folders) f.id: f};

    return Scaffold(
      appBar: AppBar(
        title: Text('Archive', style: AppTypography.titleLarge(primaryTextColor)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Column(
        children: [
          // Search within archive
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppConstants.paddingMedium,
              vertical: AppConstants.paddingSmall,
            ),
            child: TextField(
              controller: _searchController,
              onChanged: (val) => setState(() => _searchQuery = val.trim().toLowerCase()),
              decoration: InputDecoration(
                hintText: 'Search archived notes...',
                prefixIcon: Icon(Icons.search, size: 20, color: secondaryTextColor),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _searchQuery = '');
                        },
                      )
                    : null,
              ),
            ),
          ),

          Expanded(
            child: archivedNotesAsync.when(
              data: (notes) {
                var filtered = notes;
                if (_searchQuery.isNotEmpty) {
                  filtered = notes.where((n) {
                    return n.title.toLowerCase().contains(_searchQuery) ||
                        n.content.toLowerCase().contains(_searchQuery);
                  }).toList();
                }

                if (filtered.isEmpty) {
                  return EmptyStateView(
                    icon: Icons.archive_outlined,
                    title: _searchQuery.isNotEmpty ? 'No matches found' : 'Archive is empty',
                    description: _searchQuery.isNotEmpty
                        ? 'No archived notes match your search.'
                        : 'Notes you archive will appear here instead of your main screen.',
                  );
                }

                return ListView.builder(
                  keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: const EdgeInsets.fromLTRB(
                    AppConstants.paddingMedium,
                    AppConstants.paddingMedium,
                    AppConstants.paddingMedium,
                    100,
                  ),
                  itemCount: filtered.length,
                  itemBuilder: (context, index) {
                    final note = filtered[index];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: NoteCard(
                        note: note,
                        folder: note.folderId != null ? folderMap[note.folderId] : null,
                        onTap: () => _navigateToEditor(note),
                        onTogglePin: () {},
                        onToggleArchive: () async {
                          await repo.toggleArchive(note.id);
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Note unarchived and restored to Home')),
                            );
                          }
                        },
                        onDelete: () => _confirmDelete(note),
                      ),
                    );
                  },
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, _) => Center(child: Text('Error: $err')),
            ),
          ),
        ],
      ),
    );
  }
}
