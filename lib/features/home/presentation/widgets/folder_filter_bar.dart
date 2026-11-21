import 'package:flutter/material.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/models/folder_entity.dart';

class FolderFilterBar extends StatelessWidget {
  final List<FolderEntity> folders;
  final String? selectedFolderId;
  final bool isFavoritesSelected;
  final bool isRecentSelected;
  final ValueChanged<String?> onSelectFolder;
  final VoidCallback onSelectFavorites;
  final VoidCallback onSelectRecent;
  final VoidCallback onAddFolder;

  const FolderFilterBar({
    super.key,
    required this.folders,
    required this.selectedFolderId,
    this.isFavoritesSelected = false,
    this.isRecentSelected = false,
    required this.onSelectFolder,
    required this.onSelectFavorites,
    required this.onSelectRecent,
    required this.onAddFolder,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isAllSelected =
        selectedFolderId == null && !isFavoritesSelected && !isRecentSelected;

    return SizedBox(
      height: 34,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(
          horizontal: AppConstants.paddingMedium,
        ),
        children: [
          // "All Notes" chip
          _buildFilterChip(
            context: context,
            label: 'All Notes',
            icon: Icons.notes_rounded,
            isSelected: isAllSelected,
            onTap: () => onSelectFolder(null),
          ),
          const SizedBox(width: 8),

          // "Favorites" chip
          _buildFilterChip(
            context: context,
            label: 'Favorites',
            icon: Icons.star_rounded,
            isSelected: isFavoritesSelected,
            selectedColor: AppColors.pinColor,
            onTap: onSelectFavorites,
          ),
          const SizedBox(width: 8),

          // "Recent" chip
          _buildFilterChip(
            context: context,
            label: 'Recent',
            icon: Icons.schedule_rounded,
            isSelected: isRecentSelected,
            onTap: onSelectRecent,
          ),
          const SizedBox(width: 8),

          // Dynamic folder chips
          for (final folder in folders) ...[
            _buildFolderChip(
              context: context,
              folder: folder,
              isSelected:
                  selectedFolderId == folder.id &&
                  !isFavoritesSelected &&
                  !isRecentSelected,
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
                      Icons.add_rounded,
                      size: 15,
                      color: isDark
                          ? AppColors.darkTextSecondary
                          : AppColors.lightTextSecondary,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Folder',
                      style: AppTypography.labelSmall(
                        isDark
                            ? AppColors.darkTextSecondary
                            : AppColors.lightTextSecondary,
                      ).copyWith(fontWeight: FontWeight.w600),
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

  Widget _buildFilterChip({
    required BuildContext context,
    required String label,
    required IconData icon,
    required bool isSelected,
    Color? selectedColor,
    required VoidCallback onTap,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final selectedBg = selectedColor ?? AppColors.primary;
    final unselectedBg = isDark
        ? AppColors.darkSurfaceVariant
        : AppColors.lightSurfaceVariant;

    const selectedText = Colors.white;
    final unselectedText = isDark
        ? AppColors.darkTextSecondary
        : AppColors.lightTextSecondary;

    return Material(
      color: isSelected ? selectedBg : unselectedBg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppConstants.radiusMedium),
        side: BorderSide(
          color: isSelected
              ? Colors.transparent
              : (isDark
                    ? AppColors.darkBorderSubtle
                    : AppColors.lightBorderSubtle),
          width: 1.0,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppConstants.radiusMedium),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 160),
          padding: const EdgeInsets.symmetric(horizontal: 11),
          alignment: Alignment.center,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 14,
                color: isSelected ? selectedText : unselectedText,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  color: isSelected ? selectedText : unselectedText,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFolderChip({
    required BuildContext context,
    required FolderEntity folder,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    Color folderColor = AppColors.primary;
    try {
      final hex = folder.colorHex.replaceAll('#', '').replaceAll('0x', '');
      folderColor = Color(int.parse('FF$hex', radix: 16));
    } catch (_) {}

    final selectedBg = folderColor;
    final unselectedBg = isDark
        ? AppColors.darkSurfaceVariant
        : AppColors.lightSurfaceVariant;
    const selectedText = Colors.white;
    final unselectedText = isDark
        ? AppColors.darkTextPrimary
        : AppColors.lightTextPrimary;

    return Material(
      color: isSelected ? selectedBg : unselectedBg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppConstants.radiusMedium),
        side: BorderSide(
          color: isSelected
              ? Colors.transparent
              : (isDark
                    ? AppColors.darkBorderSubtle
                    : AppColors.lightBorderSubtle),
          width: 1.0,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppConstants.radiusMedium),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 160),
          padding: const EdgeInsets.symmetric(horizontal: 11),
          alignment: Alignment.center,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  color: isSelected ? Colors.white : folderColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                folder.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  color: isSelected ? selectedText : unselectedText,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
