import 'package:flutter/material.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/utils/date_formatter.dart';
import '../../../../core/utils/note_helper.dart';
import '../../../../shared/models/note_entity.dart';
import '../../../../shared/models/folder_entity.dart';
import 'rich_note_preview.dart';

class NoteCard extends StatelessWidget {
  final NoteEntity note;
  final FolderEntity? folder;
  final VoidCallback onTap;
  final VoidCallback onTogglePin;
  final VoidCallback onToggleArchive;
  final VoidCallback onDelete;

  const NoteCard({
    super.key,
    required this.note,
    this.folder,
    required this.onTap,
    required this.onTogglePin,
    required this.onToggleArchive,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Pick card tint
    final colorList = isDark ? AppColors.darkNoteColors : AppColors.lightNoteColors;
    final cardColor = note.colorIndex < colorList.length
        ? colorList[note.colorIndex]
        : (isDark ? AppColors.darkSurface : AppColors.lightSurface);

    final borderColor = isDark ? AppColors.darkBorder : AppColors.lightBorder;
    final primaryTextColor = isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary;
    final secondaryTextColor = isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary;
    final subtleTextColor = isDark ? AppColors.darkTextTertiary : AppColors.lightTextTertiary;

    final isChecklist = note.isChecklist || NoteHelper.isChecklistContent(note.content);

    return Material(
      color: cardColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppConstants.radiusMedium),
        side: BorderSide(color: borderColor, width: 1.0),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppConstants.radiusMedium),
        child: Padding(
          padding: const EdgeInsets.all(AppConstants.paddingMedium),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header Row: Title & Pin/Menu
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      note.title.isNotEmpty ? note.title : 'Untitled Note',
                      style: AppTypography.titleMedium(primaryTextColor),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (note.isPinned)
                    const Padding(
                      padding: EdgeInsets.only(left: 6),
                      child: Icon(
                        Icons.push_pin,
                        size: 16,
                        color: AppColors.pinColor,
                      ),
                    ),
                  if (note.isArchived)
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                      icon: Icon(Icons.unarchive_outlined, size: 18, color: secondaryTextColor),
                      tooltip: 'Restore to Home',
                      onPressed: onToggleArchive,
                    ),
                  const SizedBox(width: 4),
                  _buildOptionsMenu(context, secondaryTextColor),
                ],
              ),

              if (isChecklist) ...[
                const SizedBox(height: 8),
                _buildChecklistPreview(
                  NoteHelper.formatForEditor(note.content),
                  isDark,
                  primaryTextColor,
                  secondaryTextColor,
                  subtleTextColor,
                ),
              ] else if (note.content.trim().isNotEmpty) ...[
                const SizedBox(height: 8),
                RichNotePreview(
                  content: note.content,
                  maxLines: 4,
                  primaryColor: primaryTextColor,
                  secondaryColor: secondaryTextColor,
                  subtleColor: subtleTextColor,
                ),
              ],

              const SizedBox(height: 12),

              // Footer: Folder badge & Date
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  if (folder != null)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: (isDark ? Colors.white : Colors.black).withAlpha(15),
                        borderRadius: BorderRadius.circular(AppConstants.radiusSmall),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.folder_outlined,
                            size: 12,
                            color: subtleTextColor,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            folder!.name,
                            style: AppTypography.labelSmall(subtleTextColor),
                          ),
                        ],
                      ),
                    )
                  else if (isChecklist)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppColors.accent.withAlpha(25),
                        borderRadius: BorderRadius.circular(AppConstants.radiusSmall),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.check_box_outlined,
                            size: 12,
                            color: AppColors.accent,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'Checklist',
                            style: AppTypography.labelSmall(AppColors.accent),
                          ),
                        ],
                      ),
                    )
                  else
                    const SizedBox.shrink(),

                  Text(
                    DateFormatter.formatSmart(note.updatedAt),
                    style: AppTypography.labelSmall(subtleTextColor),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildChecklistPreview(
    String content,
    bool isDark,
    Color primaryTextColor,
    Color secondaryTextColor,
    Color subtleTextColor,
  ) {
    final lines = content.split('\n').where((l) => l.trim().isNotEmpty).toList();
    if (lines.isEmpty) return const SizedBox.shrink();

    final previewLines = lines.take(3).toList();
    final remainingCount = lines.length - previewLines.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ...previewLines.map((line) {
          final trimmed = line.trim();
          final isDone = trimmed == '[x]' ||
              trimmed == '- [x]' ||
              trimmed.startsWith('[x] ') ||
              trimmed.startsWith('- [x] ');
          final isPending = trimmed == '[ ]' ||
              trimmed == '- [ ]' ||
              trimmed.startsWith('[ ] ') ||
              trimmed.startsWith('- [ ] ');
          final rawText = isDone
              ? (trimmed == '[x]' || trimmed == '- [x]'
                  ? ''
                  : (trimmed.startsWith('- [x] ') ? trimmed.substring(6) : trimmed.substring(4)))
              : (isPending
                  ? (trimmed == '[ ]' || trimmed == '- [ ]'
                      ? ''
                      : (trimmed.startsWith('- [ ] ') ? trimmed.substring(6) : trimmed.substring(4)))
                  : trimmed);

          final inlineSpans = NoteHelper.parseInlineMarkdown(rawText);

          return Padding(
            padding: const EdgeInsets.only(bottom: 3),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Icon(
                  isDone
                      ? Icons.check_circle_rounded
                      : (isPending ? Icons.radio_button_unchecked_rounded : Icons.circle),
                  size: isPending || isDone ? 14 : 6,
                  color: isDone ? AppColors.accent : subtleTextColor,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text.rich(
                    TextSpan(
                      children: inlineSpans.map((span) {
                        return TextSpan(
                          text: span.text,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: span.isBold ? FontWeight.bold : FontWeight.normal,
                            fontStyle: span.isItalic ? FontStyle.italic : FontStyle.normal,
                            fontFamily: span.isCode ? 'monospace' : null,
                            decoration: isDone
                                ? TextDecoration.lineThrough
                                : (span.isStrike
                                    ? TextDecoration.lineThrough
                                    : (span.isUnderline ? TextDecoration.underline : null)),
                            color: isDone
                                ? subtleTextColor
                                : (span.isBold ? primaryTextColor : secondaryTextColor),
                            backgroundColor: span.isCode
                                ? (isDark ? const Color(0x33FFFFFF) : const Color(0x1F000000))
                                : null,
                          ),
                        );
                      }).toList(),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          );
        }),
        if (remainingCount > 0)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              '+$remainingCount more items',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: subtleTextColor,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildOptionsMenu(BuildContext context, Color secondaryTextColor) {
    return SizedBox(
      width: 24,
      height: 24,
      child: PopupMenuButton<String>(
        padding: EdgeInsets.zero,
        icon: Icon(Icons.more_vert, size: 18, color: secondaryTextColor),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppConstants.radiusMedium),
        ),
        onSelected: (value) {
          switch (value) {
            case 'pin':
              onTogglePin();
              break;
            case 'archive':
              onToggleArchive();
              break;
            case 'delete':
              onDelete();
              break;
          }
        },
        itemBuilder: (context) => [
          PopupMenuItem(
            value: 'pin',
            child: Row(
              children: [
                Icon(
                  note.isPinned ? Icons.push_pin_outlined : Icons.push_pin,
                  size: 18,
                  color: note.isPinned ? null : AppColors.pinColor,
                ),
                const SizedBox(width: 10),
                Text(note.isPinned ? 'Unpin' : 'Pin note'),
              ],
            ),
          ),
          PopupMenuItem(
            value: 'archive',
            child: Row(
              children: [
                Icon(
                  note.isArchived ? Icons.unarchive_outlined : Icons.archive_outlined,
                  size: 18,
                ),
                const SizedBox(width: 10),
                Text(note.isArchived ? 'Unarchive' : 'Archive'),
              ],
            ),
          ),
          const PopupMenuDivider(),
          const PopupMenuItem(
            value: 'delete',
            child: Row(
              children: [
                Icon(Icons.delete_outline, size: 18, color: AppColors.danger),
                SizedBox(width: 10),
                Text('Delete', style: TextStyle(color: AppColors.danger)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
