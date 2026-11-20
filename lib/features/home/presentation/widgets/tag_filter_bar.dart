import 'package:flutter/material.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/models/note_filter.dart';
import '../../../../shared/models/tag_entity.dart';
import '../../../tags/presentation/widgets/tag_chip.dart';

class TagFilterBar extends StatelessWidget {
  final List<TagEntity> tags;
  final Set<String> selectedTagIds;
  final TagFilterMatchMode matchMode;
  final ValueChanged<String> onToggleTag;
  final VoidCallback onClearTags;
  final ValueChanged<TagFilterMatchMode> onToggleMatchMode;
  final VoidCallback onAddTag;

  const TagFilterBar({
    super.key,
    required this.tags,
    required this.selectedTagIds,
    required this.matchMode,
    required this.onToggleTag,
    required this.onClearTags,
    required this.onToggleMatchMode,
    required this.onAddTag,
  });

  @override
  Widget build(BuildContext context) {
    if (tags.isEmpty) return const SizedBox.shrink();

    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      height: 34,
      margin: const EdgeInsets.only(top: 8),
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppConstants.paddingMedium),
        children: [
          // Clear tags chip if tags are selected
          if (selectedTagIds.isNotEmpty) ...[
            Material(
              color: isDark ? AppColors.darkSurfaceVariant : AppColors.lightSurfaceVariant,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppConstants.radiusSmall),
                side: BorderSide(
                  color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
                  width: 1.0,
                ),
              ),
              child: InkWell(
                onTap: onClearTags,
                borderRadius: BorderRadius.circular(AppConstants.radiusSmall),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Row(
                    children: [
                      Icon(
                        Icons.clear_all_rounded,
                        size: 14,
                        color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Reset Tags',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),

            // Match Mode Toggle if multiple tags selected
            if (selectedTagIds.length > 1) ...[
              Material(
                color: AppColors.primary.withAlpha(isDark ? 40 : 25),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppConstants.radiusSmall),
                  side: BorderSide(
                    color: AppColors.primary.withAlpha(isDark ? 80 : 60),
                    width: 1.0,
                  ),
                ),
                child: InkWell(
                  onTap: () {
                    onToggleMatchMode(
                      matchMode == TagFilterMatchMode.any
                          ? TagFilterMatchMode.all
                          : TagFilterMatchMode.any,
                    );
                  },
                  borderRadius: BorderRadius.circular(AppConstants.radiusSmall),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    child: Row(
                      children: [
                        Icon(
                          matchMode == TagFilterMatchMode.any
                              ? Icons.all_inclusive_rounded
                              : Icons.filter_alt_rounded,
                          size: 13,
                          color: AppColors.primary,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          matchMode == TagFilterMatchMode.any ? 'Match Any' : 'Match All',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: AppColors.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
            ],
          ],

          // Tag chips
          for (final tag in tags) ...[
            TagChip(
              tag: tag,
              isSelected: selectedTagIds.contains(tag.id),
              compact: true,
              onTap: () => onToggleTag(tag.id),
            ),
            const SizedBox(width: 6),
          ],

          // Quick + Tag button
          Material(
            color: Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppConstants.radiusSmall),
              side: BorderSide(
                color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
                width: 1.0,
              ),
            ),
            child: InkWell(
              onTap: onAddTag,
              borderRadius: BorderRadius.circular(AppConstants.radiusSmall),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Row(
                  children: [
                    Icon(
                      Icons.add,
                      size: 14,
                      color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                    ),
                    const SizedBox(width: 3),
                    Text(
                      'Tag',
                      style: AppTypography.labelSmall(
                        isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
