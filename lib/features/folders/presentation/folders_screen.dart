import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/database/database_provider.dart';
import '../../../shared/models/folder_entity.dart';
import '../../../shared/widgets/empty_state_view.dart';

class FoldersScreen extends ConsumerStatefulWidget {
  const FoldersScreen({super.key});

  @override
  ConsumerState<FoldersScreen> createState() => _FoldersScreenState();
}

class _FoldersScreenState extends ConsumerState<FoldersScreen> {
  final _uuid = const Uuid();

  void _showFolderDialog({FolderEntity? existing}) {
    final nameController = TextEditingController(text: existing?.name ?? '');

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppConstants.radiusMedium),
        ),
        title: Text(existing != null ? 'Edit Folder' : 'New Folder'),
        content: TextField(
          controller: nameController,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Folder name (e.g. Finance, Projects)',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              final name = nameController.text.trim();
              if (name.isNotEmpty) {
                final folder = existing != null
                    ? existing.copyWith(name: name)
                    : FolderEntity(
                        id: _uuid.v4(),
                        name: name,
                        colorHex: '0xFF2563EB',
                        iconName: 'folder',
                        createdAt: DateTime.now(),
                      );
                await ref.read(noteRepositoryProvider).saveFolder(folder);
              }
              if (mounted) Navigator.pop(dialogContext);
            },
            child: Text(existing != null ? 'Save' : 'Create'),
          ),
        ],
      ),
    );
  }

  void _confirmDelete(FolderEntity folder) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppConstants.radiusMedium),
        ),
        title: const Text('Delete Folder'),
        content: Text('Are you sure you want to delete "${folder.name}"? Notes inside will not be deleted, but unassigned.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () async {
              await ref.read(noteRepositoryProvider).deleteFolder(folder.id);
              if (mounted) Navigator.pop(dialogContext);
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

    final foldersAsync = ref.watch(foldersStreamProvider);
    final notesAsync = ref.watch(activeNotesStreamProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text('Folders', style: AppTypography.titleLarge(primaryTextColor)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: foldersAsync.when(
        data: (folders) {
          if (folders.isEmpty) {
            return EmptyStateView(
              icon: Icons.folder_open_rounded,
              title: 'No Folders Yet',
              description: 'Create folders to organize your projects, ideas, and work notes.',
              actionLabel: 'Create Folder',
              onAction: () => _showFolderDialog(),
            );
          }

          final notes = notesAsync.value ?? [];

          return ListView.separated(
            padding: const EdgeInsets.all(AppConstants.paddingMedium),
            itemCount: folders.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final folder = folders[index];
              final count = notes.where((n) => n.folderId == folder.id).length;

              return Material(
                color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppConstants.radiusMedium),
                  side: BorderSide(
                    color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
                    width: 1.0,
                  ),
                ),
                child: ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withAlpha(20),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.folder_rounded, color: AppColors.primary, size: 22),
                  ),
                  title: Text(
                    folder.name,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: primaryTextColor,
                    ),
                  ),
                  subtitle: Text(
                    '$count ${count == 1 ? 'note' : 'notes'}',
                    style: TextStyle(color: secondaryTextColor),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.edit_outlined, size: 18),
                        onPressed: () => _showFolderDialog(existing: folder),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline, size: 18, color: AppColors.danger),
                        onPressed: () => _confirmDelete(folder),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(child: Text('Error: $err')),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showFolderDialog(),
        icon: const Icon(Icons.create_new_folder_outlined),
        label: const Text('New Folder'),
      ),
    );
  }
}
