import 'package:flutter/material.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/utils/date_formatter.dart';
import '../../../../core/utils/note_helper.dart';
import '../../../../shared/models/note_entity.dart';

class NoteStatsModal extends StatelessWidget {
  final NoteEntity note;

  const NoteStatsModal({super.key, required this.note});

  /// Opens the Note Details & Statistics modal bottom sheet with safe-area
  /// handling, accessible header, and scrollable content constraints.
  static Future<void> show({
    required BuildContext context,
    required NoteEntity note,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => NoteStatsModal(note: note),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryTextColor = isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary;
    final secondaryTextColor = isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary;

    final plainText = NoteHelper.extractPlainText(note.content);
    final words = NoteHelper.wordCount(plainText);
    final characters = plainText.length;
    final lines = plainText.isEmpty ? 0 : plainText.split('\n').length;
    final readingTimeMinutes = (words / 200).ceil();

    final screenHeight = MediaQuery.sizeOf(context).height;

    return Container(
      constraints: BoxConstraints(maxHeight: screenHeight * 0.85),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(AppConstants.radiusLarge),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Drag handle
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: 12, bottom: 4),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: isDark ? Colors.white24 : Colors.black12,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            // Pinned accessible header with title and close button
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppConstants.paddingLarge,
                8,
                AppConstants.paddingMedium,
                4,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      'Note Details & Statistics',
                      style: AppTypography.titleLarge(primaryTextColor),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    tooltip: 'Close',
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 8),

            // Scrollable statistics and metadata content
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(
                  AppConstants.paddingLarge,
                  0,
                  AppConstants.paddingLarge,
                  AppConstants.paddingLarge,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        _buildStatCard('Words', '$words', isDark),
                        const SizedBox(width: 12),
                        _buildStatCard('Characters', '$characters', isDark),
                        const SizedBox(width: 12),
                        _buildStatCard('Reading Time', '$readingTimeMinutes min', isDark),
                      ],
                    ),
                    const Divider(height: 32),
                    _buildInfoRow('Created', DateFormatter.formatFull(note.createdAt), primaryTextColor, secondaryTextColor),
                    const SizedBox(height: 12),
                    _buildInfoRow('Last Modified', DateFormatter.formatFull(note.updatedAt), primaryTextColor, secondaryTextColor),
                    const SizedBox(height: 12),
                    _buildInfoRow('Lines of Text', '$lines lines', primaryTextColor, secondaryTextColor),
                    const SizedBox(height: 12),
                    _buildInfoRow('Type', note.isChecklist ? 'Interactive Checklist' : 'Rich Text Document', primaryTextColor, secondaryTextColor),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatCard(String label, String value, bool isDark) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkSurfaceVariant : AppColors.lightSurfaceVariant,
          borderRadius: BorderRadius.circular(AppConstants.radiusMedium),
          border: Border.all(
            color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
            width: 1.0,
          ),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: isDark ? AppColors.darkTextTertiary : AppColors.lightTextTertiary,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value, Color primaryText, Color secondaryText) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(fontSize: 13, color: secondaryText),
        ),
        const SizedBox(width: 16),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: primaryText),
          ),
        ),
      ],
    );
  }
}
