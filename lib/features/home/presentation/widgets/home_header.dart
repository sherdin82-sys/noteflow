import 'package:flutter/material.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/models/note_filter.dart';

class HomeHeader extends StatelessWidget {
  final TextEditingController searchController;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onClearSearch;
  final VoidCallback onToggleTheme;
  final VoidCallback onOpenFolders;
  final VoidCallback onOpenArchive;
  final ValueChanged<NoteSortOrder> onSortChanged;
  final NoteSortOrder currentSort;
  final bool isDark;

  const HomeHeader({
    super.key,
    required this.searchController,
    required this.onSearchChanged,
    required this.onClearSearch,
    required this.onToggleTheme,
    required this.onOpenFolders,
    required this.onOpenArchive,
    required this.onSortChanged,
    required this.currentSort,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final primaryTextColor = isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary;
    final secondaryTextColor = isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppConstants.paddingMedium,
        AppConstants.paddingMedium,
        AppConstants.paddingMedium,
        AppConstants.paddingSmall,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // App Title & Action Icons
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [AppColors.primary, AppColors.accent],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Center(
                        child: Icon(
                          Icons.edit_note_rounded,
                          color: Colors.white,
                          size: 22,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Flexible(
                      child: Text(
                        AppConstants.appName,
                        style: AppTypography.displayMedium(primaryTextColor),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                    ),
                  ],
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Folders Screen
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.all(6),
                    constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                    icon: Icon(
                      Icons.folder_outlined,
                      size: 20,
                      color: secondaryTextColor,
                    ),
                    tooltip: 'Manage Folders',
                    onPressed: onOpenFolders,
                  ),
                  const SizedBox(width: 2),
                  // Archive Screen
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.all(6),
                    constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                    icon: Icon(
                      Icons.archive_outlined,
                      size: 20,
                      color: secondaryTextColor,
                    ),
                    tooltip: 'Archived Notes',
                    onPressed: onOpenArchive,
                  ),
                  const SizedBox(width: 2),
                  // Theme Mode Switcher
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.all(6),
                    constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                    icon: Icon(
                      isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
                      size: 20,
                      color: secondaryTextColor,
                    ),
                    tooltip: isDark ? 'Switch to Light Mode' : 'Switch to Dark Mode',
                    onPressed: onToggleTheme,
                  ),
                  const SizedBox(width: 2),
                  // Sort Order Menu
                  PopupMenuButton<NoteSortOrder>(
                    padding: const EdgeInsets.all(6),
                    constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                    icon: Icon(
                      Icons.sort_rounded,
                      size: 20,
                      color: secondaryTextColor,
                    ),
                    tooltip: 'Sort Notes',
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppConstants.radiusMedium),
                    ),
                    initialValue: currentSort,
                    onSelected: onSortChanged,
                    itemBuilder: (context) => [
                      const PopupMenuItem(
                        value: NoteSortOrder.recentlyModified,
                        child: Text('Recently Modified'),
                      ),
                      const PopupMenuItem(
                        value: NoteSortOrder.recentlyCreated,
                        child: Text('Recently Created'),
                      ),
                      const PopupMenuItem(
                        value: NoteSortOrder.titleAZ,
                        child: Text('Title (A to Z)'),
                      ),
                      const PopupMenuItem(
                        value: NoteSortOrder.titleZA,
                        child: Text('Title (Z to A)'),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),

          const SizedBox(height: 14),

          // Search Input Bar
          TextField(
            controller: searchController,
            onChanged: onSearchChanged,
            style: TextStyle(
              fontSize: 14,
              color: primaryTextColor,
            ),
            decoration: InputDecoration(
              hintText: 'Search notes and ideas...',
              prefixIcon: Icon(
                Icons.search_rounded,
                size: 20,
                color: secondaryTextColor,
              ),
              suffixIcon: searchController.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.close_rounded, size: 18),
                      color: secondaryTextColor,
                      onPressed: onClearSearch,
                    )
                  : null,
            ),
          ),
        ],
      ),
    );
  }
}
