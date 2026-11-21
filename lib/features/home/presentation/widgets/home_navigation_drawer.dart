import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/theme/theme_provider.dart';
import '../../../../core/database/database_provider.dart';
import '../../../../shared/models/folder_entity.dart';
import '../../providers/home_notes_provider.dart';
import '../../../archive/presentation/archive_screen.dart';
import '../../../folders/presentation/folders_screen.dart';
import '../../../tags/presentation/tags_screen.dart';
import '../../../backup/presentation/backup_restore_screen.dart';
import '../../../reminders/presentation/reminder_management_screen.dart';

class HomeNavigationDrawer extends ConsumerWidget {
  const HomeNavigationDrawer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final filterState = ref.watch(noteFilterProvider);
    final filterNotifier = ref.read(noteFilterProvider.notifier);
    final notesAsync = ref.watch(activeNotesStreamProvider);
    final foldersAsync = ref.watch(foldersStreamProvider);
    final tagsAsync = ref.watch(tagsStreamProvider);

    final allNotes = notesAsync.value ?? [];
    final allFolders = foldersAsync.value ?? [];
    final allTags = tagsAsync.value ?? [];

    final totalNotesCount = allNotes.length;
    final favoritesCount = allNotes.where((n) => n.isFavorite).length;
    final pinnedCount = allNotes.where((n) => n.isPinned).length;

    final primaryTextColor = isDark
        ? AppColors.darkTextPrimary
        : AppColors.lightTextPrimary;
    final secondaryTextColor = isDark
        ? AppColors.darkTextSecondary
        : AppColors.lightTextSecondary;
    final subtleTextColor = isDark
        ? AppColors.darkTextTertiary
        : AppColors.lightTextTertiary;

    return Drawer(
      backgroundColor: isDark ? AppColors.darkSurface : AppColors.lightSurface,
      elevation: 1,
      child: SafeArea(
        top: false,
        child: Column(
          children: [
            // Header
            Container(
              width: double.infinity,
              padding: EdgeInsets.fromLTRB(
                AppConstants.paddingLarge,
                MediaQuery.of(context).padding.top + 20,
                AppConstants.paddingLarge,
                AppConstants.paddingMedium,
              ),
              decoration: BoxDecoration(
                color: isDark
                    ? AppColors.darkSurfaceVariant.withAlpha(120)
                    : AppColors.lightSurfaceVariant,
                border: Border(
                  bottom: BorderSide(
                    color: isDark
                        ? AppColors.darkBorder
                        : AppColors.lightBorder,
                    width: 1.0,
                  ),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [AppColors.primary, AppColors.accent],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.primary.withAlpha(
                                isDark ? 60 : 40,
                              ),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: const Center(
                          child: Icon(
                            Icons.edit_note_rounded,
                            color: Colors.white,
                            size: 26,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              AppConstants.appName,
                              style:
                                  AppTypography.displayMedium(primaryTextColor)
                                      .copyWith(
                                        fontSize: 20,
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: -0.3,
                                      ),
                            ),
                            Text(
                              'Offline • Private • Fast',
                              style: AppTypography.labelSmall(subtleTextColor)
                                  .copyWith(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w500,
                                  ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  // Quick stats badge row
                  Wrap(
                    spacing: 8,
                    children: [
                      _buildHeaderBadge(
                        label: '$totalNotesCount notes',
                        icon: Icons.description_outlined,
                        isDark: isDark,
                      ),
                      _buildHeaderBadge(
                        label: '${allFolders.length} folders',
                        icon: Icons.folder_outlined,
                        isDark: isDark,
                      ),
                      _buildHeaderBadge(
                        label: '${allTags.length} tags',
                        icon: Icons.local_offer_outlined,
                        isDark: isDark,
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Scrollable Destinations
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppConstants.paddingSmall,
                  vertical: AppConstants.paddingSmall,
                ),
                children: [
                  // MAIN SECTION
                  _buildSectionLabel('MAIN', subtleTextColor),
                  _buildDrawerItem(
                    context: context,
                    icon: Icons.notes_rounded,
                    label: 'All Notes',
                    badgeText: totalNotesCount > 0 ? '$totalNotesCount' : null,
                    isSelected:
                        filterState.isAllNotes &&
                        !filterState.isPinnedOnly &&
                        !filterState.isRecentOnly,
                    onTap: () {
                      filterNotifier.selectAllNotes();
                      Navigator.pop(context);
                    },
                    isDark: isDark,
                  ),
                  _buildDrawerItem(
                    context: context,
                    icon: Icons.star_rounded,
                    label: 'Favorites',
                    badgeText: favoritesCount > 0 ? '$favoritesCount' : null,
                    badgeColor: AppColors.pinColor,
                    isSelected: filterState.isFavoritesOnly,
                    selectedColor: AppColors.pinColor,
                    onTap: () {
                      filterNotifier.setFavoritesOnly(true);
                      Navigator.pop(context);
                    },
                    isDark: isDark,
                  ),
                  _buildDrawerItem(
                    context: context,
                    icon: Icons.schedule_rounded,
                    label: 'Recent Notes',
                    isSelected: filterState.isRecentOnly,
                    onTap: () {
                      filterNotifier.setRecentOnly(true);
                      Navigator.pop(context);
                    },
                    isDark: isDark,
                  ),
                  _buildDrawerItem(
                    context: context,
                    icon: Icons.push_pin_rounded,
                    label: 'Pinned',
                    badgeText: pinnedCount > 0 ? '$pinnedCount' : null,
                    isSelected: filterState.isPinnedOnly,
                    onTap: () {
                      filterNotifier.setPinnedOnly(true);
                      Navigator.pop(context);
                    },
                    isDark: isDark,
                  ),

                  const SizedBox(height: 12),
                  const Divider(height: 1),
                  const SizedBox(height: 12),

                  // ORGANIZATION SECTION
                  _buildSectionLabel('ORGANIZATION', subtleTextColor),
                  _buildDrawerItem(
                    context: context,
                    icon: Icons.folder_outlined,
                    label: 'Folders',
                    badgeText: allFolders.isNotEmpty
                        ? '${allFolders.length}'
                        : null,
                    trailingIcon: Icons.chevron_right_rounded,
                    isSelected: false,
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const FoldersScreen(),
                        ),
                      );
                    },
                    isDark: isDark,
                  ),
                  // If folders exist, list them for direct 1-tap switching
                  if (allFolders.isNotEmpty) ...[
                    Padding(
                      padding: const EdgeInsets.only(
                        left: 12,
                        top: 2,
                        bottom: 4,
                      ),
                      child: Column(
                        children: allFolders.map((folder) {
                          final count = allNotes
                              .where((n) => n.folderId == folder.id)
                              .length;
                          final isSelected =
                              filterState.selectedFolderId == folder.id &&
                              !filterState.isFavoritesOnly &&
                              !filterState.isRecentOnly &&
                              !filterState.isPinnedOnly;

                          return _buildFolderSubItem(
                            context: context,
                            folder: folder,
                            count: count,
                            isSelected: isSelected,
                            onTap: () {
                              filterNotifier.setSelectedFolder(folder.id);
                              Navigator.pop(context);
                            },
                            isDark: isDark,
                          );
                        }).toList(),
                      ),
                    ),
                  ],

                  _buildDrawerItem(
                    context: context,
                    icon: Icons.label_outline_rounded,
                    label: 'Manage Tags',
                    badgeText: allTags.isNotEmpty ? '${allTags.length}' : null,
                    trailingIcon: Icons.chevron_right_rounded,
                    isSelected: false,
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const TagsScreen()),
                      );
                    },
                    isDark: isDark,
                  ),

                  const SizedBox(height: 12),
                  const Divider(height: 1),
                  const SizedBox(height: 12),

                  // MANAGEMENT SECTION
                  _buildSectionLabel('MANAGEMENT', subtleTextColor),
                  _buildDrawerItem(
                    context: context,
                    icon: Icons.archive_outlined,
                    label: 'Archive',
                    trailingIcon: Icons.chevron_right_rounded,
                    isSelected: false,
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const ArchiveScreen(),
                        ),
                      );
                    },
                    isDark: isDark,
                  ),
                  _buildDrawerItem(
                    context: context,
                    icon: Icons.alarm_rounded,
                    label: 'Reminders',
                    trailingIcon: Icons.chevron_right_rounded,
                    isSelected: false,
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const ReminderManagementScreen(),
                        ),
                      );
                    },
                    isDark: isDark,
                  ),

                  const SizedBox(height: 12),
                  const Divider(height: 1),
                  const SizedBox(height: 12),

                  // PREFERENCES SECTION
                  _buildSectionLabel('PREFERENCES', subtleTextColor),
                  // Dark Mode Switch Tile
                  Container(
                    margin: const EdgeInsets.symmetric(vertical: 2),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: ListTile(
                      dense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 0,
                      ),
                      visualDensity: VisualDensity.compact,
                      leading: Icon(
                        isDark
                            ? Icons.dark_mode_rounded
                            : Icons.light_mode_rounded,
                        size: 20,
                        color: secondaryTextColor,
                      ),
                      title: Text(
                        'Dark Theme',
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w500,
                          color: primaryTextColor,
                        ),
                      ),
                      trailing: Switch(
                        value: isDark,
                        activeColor: AppColors.primary,
                        onChanged: (_) {
                          ref.read(themeModeProvider.notifier).toggleTheme();
                        },
                      ),
                    ),
                  ),

                  _buildDrawerItem(
                    context: context,
                    icon: Icons.settings_backup_restore_rounded,
                    label: 'Backup & Restore',
                    trailingIcon: Icons.chevron_right_rounded,
                    isSelected: false,
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const BackupRestoreScreen(),
                        ),
                      );
                    },
                    isDark: isDark,
                  ),
                ],
              ),
            ),

            // Footer
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppConstants.paddingMedium,
                vertical: 10,
              ),
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(
                    color: isDark
                        ? AppColors.darkBorder
                        : AppColors.lightBorder,
                    width: 1.0,
                  ),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'NoteFlow v${AppConstants.appVersion}',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: subtleTextColor,
                    ),
                  ),
                  Text(
                    '100% Offline',
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w500,
                      color: subtleTextColor,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionLabel(String title, Color color) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 4),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.2,
          color: color,
        ),
      ),
    );
  }

  Widget _buildHeaderBadge({
    required String label,
    required IconData icon,
    required bool isDark,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: (isDark ? Colors.white : Colors.black).withAlpha(15),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 11,
            color: isDark
                ? AppColors.darkTextSecondary
                : AppColors.lightTextSecondary,
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: isDark
                  ? AppColors.darkTextSecondary
                  : AppColors.lightTextSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDrawerItem({
    required BuildContext context,
    required IconData icon,
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
    required bool isDark,
    Color? selectedColor,
    String? badgeText,
    Color? badgeColor,
    IconData? trailingIcon,
  }) {
    final activeColor = selectedColor ?? AppColors.primary;
    final primaryTextColor = isDark
        ? AppColors.darkTextPrimary
        : AppColors.lightTextPrimary;
    final secondaryTextColor = isDark
        ? AppColors.darkTextSecondary
        : AppColors.lightTextSecondary;

    final bgColor = isSelected
        ? activeColor.withAlpha(isDark ? 45 : 30)
        : Colors.transparent;

    final itemTextColor = isSelected ? activeColor : primaryTextColor;
    final iconColor = isSelected ? activeColor : secondaryTextColor;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 2),
      child: Material(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              children: [
                Icon(icon, size: 20, color: iconColor),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: isSelected
                          ? FontWeight.w700
                          : FontWeight.w500,
                      color: itemTextColor,
                    ),
                  ),
                ),
                if (badgeText != null) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: (badgeColor ?? activeColor).withAlpha(
                        isSelected ? 60 : 30,
                      ),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      badgeText,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color:
                            badgeColor ??
                            (isSelected ? activeColor : secondaryTextColor),
                      ),
                    ),
                  ),
                ],
                if (trailingIcon != null) ...[
                  const SizedBox(width: 4),
                  Icon(trailingIcon, size: 16, color: secondaryTextColor),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFolderSubItem({
    required BuildContext context,
    required FolderEntity folder,
    required int count,
    required bool isSelected,
    required VoidCallback onTap,
    required bool isDark,
  }) {
    final primaryTextColor = isDark
        ? AppColors.darkTextPrimary
        : AppColors.lightTextPrimary;
    final secondaryTextColor = isDark
        ? AppColors.darkTextSecondary
        : AppColors.lightTextSecondary;

    Color folderColor = AppColors.primary;
    try {
      final hex = folder.colorHex.replaceAll('#', '').replaceAll('0x', '');
      folderColor = Color(int.parse('FF$hex', radix: 16));
    } catch (_) {}

    final bgColor = isSelected
        ? folderColor.withAlpha(isDark ? 45 : 30)
        : Colors.transparent;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 1),
      child: Material(
        color: bgColor,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: folderColor,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    folder.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: isSelected
                          ? FontWeight.w700
                          : FontWeight.w500,
                      color: isSelected ? folderColor : primaryTextColor,
                    ),
                  ),
                ),
                if (count > 0)
                  Text(
                    '$count',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: secondaryTextColor,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
