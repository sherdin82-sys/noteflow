import 'package:flutter/material.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/models/folder_entity.dart';

class FolderFilterBar extends StatelessWidget {
  final List<FolderEntity> folders;
  final String? selectedFolderId;
  final ValueChanged<String?> onSelectFolder;
  final VoidCallback onAddFolder;

  const FolderFilterBar({
    super.key,
    required this.folders,
    required this.selectedFolderId,
    required this.onSelectFolder,
    required this.onAddFolder,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isAllSelected = selectedFolderId == null;

    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppConstants.paddingMedium),
        children: [
          // "All Notes" chip
          _buildChip(
            context: context,
            label: 'All Notes',
            isSelected: isAllSelected,
            onTap: () => onSelectFolder(null),
          ),
          const SizedBox(width: 8),

          // Dynamic folder chips
          for (final folder in folders) ...[
            _buildChip(
              context: context,
              label: folder.name,
              isSelected: selectedFolderId == folder.id,
              onTap: () => onSelectFolder(folder.id),
            ),
            const SizedBox(width: 8),
          ],

          // Add Folder button
          Material(
            color: Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppConstants.radiusMedium),
              side: BorderSide(
                color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
                style: BorderStyle.solid,
                width: 1.0,
              ),
            ),
            child: InkWell(
              onTap: onAddFolder,
              borderRadius: BorderRadius.circular(AppConstants.radiusMedium),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Row(
                  children: [
                    Icon(
                      Icons.add,
                      size: 16,
                      color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Folder',
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

  Widget _buildChip({
    required BuildContext context,
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final selectedBg = isDark ? AppColors.primary : AppColors.primary;
    final unselectedBg = isDark ? AppColors.darkSurfaceVariant : AppColors.lightSurfaceVariant;

    const selectedText = Colors.white;
    final unselectedText = isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary;

    return Material(
      color: isSelected ? selectedBg : unselectedBg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppConstants.radiusMedium),
        side: BorderSide(
          color: isSelected
              ? Colors.transparent
              : (isDark ? AppColors.darkBorderSubtle : AppColors.lightBorderSubtle),
          width: 1.0,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppConstants.radiusMedium),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 160),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          alignment: Alignment.center,
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
              color: isSelected ? selectedText : unselectedText,
            ),
          ),
        ),
      ),
    );
  }
}
