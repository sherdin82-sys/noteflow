import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/database/database_provider.dart';
import '../../../../shared/models/tag_entity.dart';
import 'tag_chip.dart';
import 'tag_dialog.dart';

class TagSelectorModal extends ConsumerStatefulWidget {
  final List<String> initialSelectedTagIds;
  final ValueChanged<List<String>> onTagsChanged;

  const TagSelectorModal({
    super.key,
    required this.initialSelectedTagIds,
    required this.onTagsChanged,
  });

  static Future<void> show({
    required BuildContext context,
    required List<String> initialSelectedTagIds,
    required ValueChanged<List<String>> onTagsChanged,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppConstants.radiusLarge)),
      ),
      builder: (_) => TagSelectorModal(
        initialSelectedTagIds: initialSelectedTagIds,
        onTagsChanged: onTagsChanged,
      ),
    );
  }

  @override
  ConsumerState<TagSelectorModal> createState() => _TagSelectorModalState();
}

class _TagSelectorModalState extends ConsumerState<TagSelectorModal> {
  final TextEditingController _searchController = TextEditingController();
  late final Set<String> _selectedIds;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _selectedIds = Set<String>.from(widget.initialSelectedTagIds);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _toggle(String tagId) {
    setState(() {
      if (_selectedIds.contains(tagId)) {
        _selectedIds.remove(tagId);
      } else {
        _selectedIds.add(tagId);
      }
    });
    widget.onTagsChanged(_selectedIds.toList());
  }

  Future<void> _createTag(List<TagEntity> allTags) async {
    final newTag = await TagDialog.show(
      context: context,
      allTags: allTags,
    );
    if (newTag != null && mounted) {
      await ref.read(noteRepositoryProvider).saveTag(newTag);
      _toggle(newTag.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tagsAsync = ref.watch(tagsStreamProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
          top: AppConstants.paddingMedium,
          left: AppConstants.paddingMedium,
          right: AppConstants.paddingMedium,
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.65,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Assign Tags',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                  tagsAsync.when(
                    data: (tags) => TextButton.icon(
                      onPressed: () => _createTag(tags),
                      icon: const Icon(Icons.add, size: 16),
                      label: const Text('New Tag'),
                    ),
                    loading: () => const SizedBox.shrink(),
                    error: (_, __) => const SizedBox.shrink(),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // Search input
              TextField(
                controller: _searchController,
                onChanged: (val) => setState(() => _searchQuery = val.trim().toLowerCase()),
                decoration: InputDecoration(
                  hintText: 'Search or filter tags...',
                  prefixIcon: const Icon(Icons.search, size: 18),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.close, size: 16),
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _searchQuery = '');
                          },
                        )
                      : null,
                ),
              ),
              const SizedBox(height: 12),

              // Tags List
              Flexible(
                child: tagsAsync.when(
                  data: (tags) {
                    final filtered = _searchQuery.isEmpty
                        ? tags
                        : tags.where((t) => t.name.toLowerCase().contains(_searchQuery)).toList();

                    if (filtered.isEmpty) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 24),
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.label_off_outlined,
                                size: 32,
                                color: isDark ? Colors.white38 : Colors.black38,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                _searchQuery.isNotEmpty
                                    ? 'No tags matching "$_searchQuery"'
                                    : 'No tags available yet',
                                style: TextStyle(
                                  color: isDark ? Colors.white54 : Colors.black54,
                                ),
                              ),
                              if (_searchQuery.isNotEmpty) ...[
                                const SizedBox(height: 8),
                                FilledButton.tonal(
                                  onPressed: () async {
                                    final created = TagEntity(
                                      id: DateTime.now().millisecondsSinceEpoch.toString(),
                                      name: _searchController.text.trim(),
                                      colorHex: TagDialog.tagColorPalette[3],
                                      createdAt: DateTime.now(),
                                      updatedAt: DateTime.now(),
                                    );
                                    await ref.read(noteRepositoryProvider).saveTag(created);
                                    _toggle(created.id);
                                    _searchController.clear();
                                    setState(() => _searchQuery = '');
                                  },
                                  child: Text('Create "${_searchController.text.trim()}"'),
                                ),
                              ],
                            ],
                          ),
                        ),
                      );
                    }

                    return ListView.separated(
                      shrinkWrap: true,
                      itemCount: filtered.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final tag = filtered[index];
                        final isChecked = _selectedIds.contains(tag.id);
                        final tagColor = TagChip.parseColor(tag.colorHex);

                        return CheckboxListTile(
                          value: isChecked,
                          onChanged: (_) => _toggle(tag.id),
                          secondary: Container(
                            width: 14,
                            height: 14,
                            decoration: BoxDecoration(
                              color: tagColor,
                              shape: BoxShape.circle,
                            ),
                          ),
                          title: Text(
                            tag.name,
                            style: TextStyle(
                              fontWeight: isChecked ? FontWeight.w600 : FontWeight.w500,
                            ),
                          ),
                          controlAffinity: ListTileControlAffinity.trailing,
                          dense: true,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                        );
                      },
                    );
                  },
                  loading: () => const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: CircularProgressIndicator(),
                    ),
                  ),
                  error: (err, _) => Text('Error loading tags: $err'),
                ),
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }
}
