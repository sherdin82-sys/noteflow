import 'package:flutter/material.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/models/note_filter.dart';

class HomeHeader extends StatelessWidget {
  final TextEditingController searchController;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onClearSearch;
  final bool isSearching;
  final VoidCallback onStartSearch;
  final VoidCallback onCloseSearch;
  final VoidCallback onToggleTheme;
  final VoidCallback onOpenTags;
  final VoidCallback onOpenFolders;
  final VoidCallback onOpenArchive;
  final VoidCallback onOpenBackup;
  final VoidCallback? onOpenReminders;
  final ValueChanged<NoteSortOrder> onSortChanged;
  final NoteSortOrder currentSort;
  final bool isDark;
  final String? activeFilterTitle;
  final IconData? activeFilterIcon;

  const HomeHeader({
    super.key,
    required this.searchController,
    required this.onSearchChanged,
    required this.onClearSearch,
    required this.isSearching,
    required this.onStartSearch,
    required this.onCloseSearch,
    required this.onToggleTheme,
    required this.onOpenTags,
    required this.onOpenFolders,
    required this.onOpenArchive,
    required this.onOpenBackup,
    this.onOpenReminders,
    required this.onSortChanged,
    required this.currentSort,
    required this.isDark,
    this.activeFilterTitle,
    this.activeFilterIcon,
  });

  @override
  Widget build(BuildContext context) {
    final primaryTextColor = isDark
        ? AppColors.darkTextPrimary
        : AppColors.lightTextPrimary;
    final secondaryTextColor = isDark
        ? AppColors.darkTextSecondary
        : AppColors.lightTextSecondary;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppConstants.paddingSmall,
        vertical: 4,
      ),
      child: AnimatedSwitcher(
        duration: AppConstants.fastAnimationDuration,
        child: isSearching
            ? _buildSearchMode(context, primaryTextColor, secondaryTextColor)
            : _buildStandardMode(context, primaryTextColor, secondaryTextColor),
      ),
    );
  }

  /// Compact integrated search mode
  Widget _buildSearchMode(
    BuildContext context,
    Color primaryColor,
    Color secondaryColor,
  ) {
    return Container(
      key: const ValueKey('search_mode'),
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_rounded),
            color: primaryColor,
            tooltip: 'Back to Home',
            onPressed: onCloseSearch,
          ),
          Expanded(
            child: Container(
              height: 40,
              decoration: BoxDecoration(
                color: isDark
                    ? AppColors.darkSurfaceVariant
                    : AppColors.lightSurfaceVariant,
                borderRadius: BorderRadius.circular(AppConstants.radiusMedium),
                border: Border.all(
                  color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
                  width: 1.0,
                ),
              ),
              child: TextField(
                controller: searchController,
                autofocus: true,
                onChanged: onSearchChanged,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: primaryColor,
                ),
                decoration: InputDecoration(
                  hintText: 'Search notes, tags, checklists...',
                  hintStyle: TextStyle(fontSize: 13.5, color: secondaryColor),
                  prefixIcon: Icon(
                    Icons.search_rounded,
                    size: 18,
                    color: secondaryColor,
                  ),
                  suffixIcon: searchController.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.close_rounded, size: 18),
                          color: secondaryColor,
                          onPressed: onClearSearch,
                        )
                      : null,
                  contentPadding: const EdgeInsets.symmetric(vertical: 8),
                  isDense: true,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  filled: false,
                ),
              ),
            ),
          ),
          const SizedBox(width: 4),
        ],
      ),
    );
  }

  /// Modern, uncluttered top app bar
  Widget _buildStandardMode(
    BuildContext context,
    Color primaryColor,
    Color secondaryColor,
  ) {
    return Row(
      key: const ValueKey('standard_mode'),
      children: [
        // Drawer Toggle Button
        IconButton(
          icon: const Icon(Icons.menu_rounded),
          color: primaryColor,
          tooltip: 'Open Navigation Drawer',
          onPressed: () {
            Scaffold.of(context).openDrawer();
          },
        ),

        const SizedBox(width: 4),

        // Brand Identity & Title
        Expanded(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [AppColors.primary, AppColors.accent],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(9),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primary.withAlpha(isDark ? 60 : 35),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: const Center(
                  child: Icon(
                    Icons.edit_note_rounded,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Flexible(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      AppConstants.appName,
                      style: AppTypography.displayMedium(primaryColor).copyWith(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.3,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (activeFilterTitle != null) ...[
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (activeFilterIcon != null) ...[
                            Icon(
                              activeFilterIcon,
                              size: 11,
                              color: AppColors.primary,
                            ),
                            const SizedBox(width: 3),
                          ],
                          Flexible(
                            child: Text(
                              activeFilterTitle!,
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: AppColors.primary,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),

        // Search Action
        IconButton(
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.search_rounded),
          color: secondaryColor,
          tooltip: 'Search Notes',
          onPressed: onStartSearch,
        ),

        // Sort Order Menu
        PopupMenuButton<NoteSortOrder>(
          icon: Icon(Icons.swap_vert_rounded, size: 22, color: secondaryColor),
          tooltip: 'Sort Notes',
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppConstants.radiusMedium),
          ),
          initialValue: currentSort,
          onSelected: onSortChanged,
          itemBuilder: (context) => [
            const PopupMenuItem(
              value: NoteSortOrder.recentlyModified,
              child: Row(
                children: [
                  Icon(Icons.update_rounded, size: 18),
                  SizedBox(width: 10),
                  Text('Recently Modified'),
                ],
              ),
            ),
            const PopupMenuItem(
              value: NoteSortOrder.recentlyCreated,
              child: Row(
                children: [
                  Icon(Icons.history_rounded, size: 18),
                  SizedBox(width: 10),
                  Text('Recently Created'),
                ],
              ),
            ),
            const PopupMenuItem(
              value: NoteSortOrder.titleAZ,
              child: Row(
                children: [
                  Icon(Icons.sort_by_alpha_rounded, size: 18),
                  SizedBox(width: 10),
                  Text('Title (A to Z)'),
                ],
              ),
            ),
            const PopupMenuItem(
              value: NoteSortOrder.titleZA,
              child: Row(
                children: [
                  Icon(Icons.sort_by_alpha_rounded, size: 18),
                  SizedBox(width: 10),
                  Text('Title (Z to A)'),
                ],
              ),
            ),
          ],
        ),

        // Quick Overflow Menu for secondary options
        PopupMenuButton<String>(
          icon: Icon(Icons.more_vert_rounded, size: 20, color: secondaryColor),
          tooltip: 'More Options',
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppConstants.radiusMedium),
          ),
          onSelected: (value) {
            switch (value) {
              case 'theme':
                onToggleTheme();
                break;
              case 'tags':
                onOpenTags();
                break;
              case 'folders':
                onOpenFolders();
                break;
              case 'archive':
                onOpenArchive();
                break;
              case 'reminders':
                onOpenReminders?.call();
                break;
              case 'backup':
                onOpenBackup();
                break;
            }
          },
          itemBuilder: (context) => [
            PopupMenuItem(
              value: 'theme',
              child: Row(
                children: [
                  Icon(
                    isDark
                        ? Icons.light_mode_outlined
                        : Icons.dark_mode_outlined,
                    size: 18,
                  ),
                  const SizedBox(width: 10),
                  Text(isDark ? 'Switch to Light Mode' : 'Switch to Dark Mode'),
                ],
              ),
            ),
            if (onOpenReminders != null)
              const PopupMenuItem(
                value: 'reminders',
                child: Row(
                  children: [
                    Icon(Icons.alarm_rounded, size: 18),
                    SizedBox(width: 10),
                    Text('Reminders'),
                  ],
                ),
              ),
            const PopupMenuItem(
              value: 'archive',
              child: Row(
                children: [
                  Icon(Icons.archive_outlined, size: 18),
                  SizedBox(width: 10),
                  Text('Archive'),
                ],
              ),
            ),
            const PopupMenuItem(
              value: 'backup',
              child: Row(
                children: [
                  Icon(Icons.settings_backup_restore_rounded, size: 18),
                  SizedBox(width: 10),
                  Text('Backup & Restore'),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}
