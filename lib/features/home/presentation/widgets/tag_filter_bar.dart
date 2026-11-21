import 'package:flutter/material.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/theme/app_colors.dart';
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
  final VoidCallback? onManageTags;

  const TagFilterBar({
    super.key,
    required this.tags,
    required this.selectedTagIds,
    required this.matchMode,
    required this.onToggleTag,
    required this.onClearTags,
    required this.onToggleMatchMode,
    required this.onAddTag,
    this.onManageTags,
  });

  @override
  Widget build(BuildContext context) {
    if (tags.isEmpty) return const SizedBox.shrink();

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final secondaryTextColor = isDark
        ? AppColors.darkTextSecondary
        : AppColors.lightTextSecondary;

    return Container(
      height: 30,
      margin: const EdgeInsets.only(top: 6),
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(
          horizontal: AppConstants.paddingMedium,
        ),
        children: [
          // Subtle Tags Label with optional Manage trigger
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: InkWell(
              onTap: onManageTags,
              borderRadius: BorderRadius.circular(6),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.local_offer_outlined,
                      size: 13,
                      color: secondaryTextColor,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Tags',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5,
                        color: secondaryTextColor,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Clear tags chip if tags are selected
          if (selectedTagIds.isNotEmpty) ...[
            Material(
              color: isDark
                  ? AppColors.darkSurfaceVariant
                  : AppColors.lightSurfaceVariant,
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
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 2,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.close_rounded,
                        size: 12,
                        color: secondaryTextColor,
                      ),
                      const SizedBox(width: 3),
                      Text(
                        'Clear',
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w600,
                          color: secondaryTextColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 6),

            // Match Mode Toggle if multiple tags selected
            if (selectedTagIds.length > 1) ...[
              Material(
                color: AppColors.primary.withAlpha(isDark ? 35 : 20),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppConstants.radiusSmall),
                  side: BorderSide(
                    color: AppColors.primary.withAlpha(isDark ? 70 : 50),
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
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 2,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          matchMode == TagFilterMatchMode.any
                              ? Icons.all_inclusive_rounded
                              : Icons.filter_alt_rounded,
                          size: 12,
                          color: AppColors.primary,
                        ),
                        const SizedBox(width: 3),
                        Text(
                          matchMode == TagFilterMatchMode.any ? 'Any' : 'All',
                          style: const TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                            color: AppColors.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
            ],
          ],

          // Tag chips
          for (final tag in tags) ...[
            _buildCompactTagChip(
              context: context,
              tag: tag,
              isSelected: selectedTagIds.contains(tag.id),
              onTap: () => onToggleTag(tag.id),
              isDark: isDark,
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
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                child: Row(
                  children: [
                    Icon(
                      Icons.add_rounded,
                      size: 13,
                      color: secondaryTextColor,
                    ),
                    const SizedBox(width: 2),
                    Text(
                      'Tag',
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                        color: secondaryTextColor,
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

  Widget _buildCompactTagChip({
    required BuildContext context,
    required TagEntity tag,
    required bool isSelected,
    required VoidCallback onTap,
    required bool isDark,
  }) {
    final tagColor = TagChip.parseColor(tag.colorHex);
    final primaryTextColor = isDark
        ? AppColors.darkTextPrimary
        : AppColors.lightTextPrimary;

    final bgColor = isSelected
        ? tagColor.withAlpha(isDark ? 50 : 35)
        : (isDark
              ? AppColors.darkSurfaceVariant
              : AppColors.lightSurfaceVariant);

    final borderColor = isSelected
        ? tagColor.withAlpha(isDark ? 140 : 100)
        : (isDark ? AppColors.darkBorderSubtle : AppColors.lightBorderSubtle);

    final textColor = isSelected
        ? (isDark ? Colors.white : tagColor)
        : primaryTextColor;

    return Material(
      color: bgColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppConstants.radiusSmall),
        side: BorderSide(color: borderColor, width: 1.0),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppConstants.radiusSmall),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: tagColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 5),
              Text(
                tag.name,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  color: textColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
