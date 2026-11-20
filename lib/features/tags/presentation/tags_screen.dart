import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/database/database_provider.dart';
import '../../../shared/models/tag_entity.dart';
import '../../../shared/widgets/empty_state_view.dart';
import '../../home/providers/home_notes_provider.dart';
import 'widgets/tag_chip.dart';
import 'widgets/tag_dialog.dart';

class TagsScreen extends ConsumerStatefulWidget {
  const TagsScreen({super.key});

  @override
  ConsumerState<TagsScreen> createState() => _TagsScreenState();
}

class _TagsScreenState extends ConsumerState<TagsScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _showTagDialog({TagEntity? existing, required List<TagEntity> allTags}) async {
    final result = await TagDialog.show(
      context: context,
      existingTag: existing,
      allTags: allTags,
    );

    if (result != null && mounted) {
      await ref.read(noteRepositoryProvider).saveTag(result);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(existing != null ? 'Tag updated' : 'Tag created'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  void _confirmDelete(TagEntity tag, int usageCount) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppConstants.radiusMedium),
        ),
        title: Text('Delete "${tag.name}"?'),
        content: Text(
          usageCount > 0
              ? 'This tag is assigned to $usageCount ${usageCount == 1 ? 'note' : 'notes'}.\n\n'
                  'Deleting this tag will remove it from all notes. Notes will NOT be deleted.'
              : 'Are you sure you want to delete this tag?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () async {
              await ref.read(noteRepositoryProvider).deleteTag(tag.id);
              if (dialogContext.mounted) Navigator.pop(dialogContext);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Deleted "${tag.name}" tag'),
                    duration: const Duration(seconds: 2),
                  ),
                );
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryTextColor = isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary;
    final secondaryTextColor = isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary;

    final tagsAsync = ref.watch(tagsStreamProvider);
    final notesAsync = ref.watch(activeNotesStreamProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text('Tags', style: AppTypography.titleLarge(primaryTextColor)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      floatingActionButton: tagsAsync.when(
        data: (tags) => FloatingActionButton.extended(
          onPressed: () => _showTagDialog(allTags: tags),
          icon: const Icon(Icons.add),
          label: const Text('New Tag'),
        ),
        loading: () => const SizedBox.shrink(),
        error: (_, __) => const SizedBox.shrink(),
      ),
      body: tagsAsync.when(
        data: (tags) {
          if (tags.isEmpty) {
            return EmptyStateView(
              icon: Icons.label_outline_rounded,
              title: 'No Tags Yet',
              description: 'Create custom color-coded tags to organize and quickly filter your notes.',
              actionLabel: 'Create First Tag',
              onAction: () => _showTagDialog(allTags: tags),
            );
          }

          final notes = notesAsync.value ?? [];
          final filtered = _searchQuery.isEmpty
              ? tags
              : tags.where((t) => t.name.toLowerCase().contains(_searchQuery)).toList();

          return Column(
            children: [
              // Search input
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppConstants.paddingMedium,
                  vertical: AppConstants.paddingSmall,
                ),
                child: TextField(
                  controller: _searchController,
                  onChanged: (val) => setState(() => _searchQuery = val.trim().toLowerCase()),
                  decoration: InputDecoration(
                    hintText: 'Search tags...',
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
                child: filtered.isEmpty
                    ? Center(
                        child: Text(
                          'No tags matching "$_searchQuery"',
                          style: TextStyle(color: secondaryTextColor),
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(
                          AppConstants.paddingMedium,
                          AppConstants.paddingSmall,
                          AppConstants.paddingMedium,
                          100,
                        ),
                        itemCount: filtered.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final tag = filtered[index];
                          final count = notes.where((n) => n.tagIds.contains(tag.id)).length;
                          final color = TagChip.parseColor(tag.colorHex);

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
                              onTap: () {
                                // Filter Home notes by this tag and pop back
                                final notifier = ref.read(noteFilterProvider.notifier);
                                notifier.clearTags();
                                notifier.toggleTag(tag.id);
                                Navigator.pop(context);
                              },
                              leading: Container(
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(
                                  color: color.withAlpha(isDark ? 45 : 30),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: color.withAlpha(isDark ? 80 : 60)),
                                ),
                                child: Center(
                                  child: Icon(Icons.label_rounded, color: color, size: 20),
                                ),
                              ),
                              title: Text(
                                tag.name,
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
                                    tooltip: 'Edit Tag',
                                    onPressed: () => _showTagDialog(
                                      existing: tag,
                                      allTags: tags,
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline, size: 18),
                                    color: AppColors.danger,
                                    tooltip: 'Delete Tag',
                                    onPressed: () => _confirmDelete(tag, count),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(child: Text('Error: $err')),
      ),
    );
  }
}
