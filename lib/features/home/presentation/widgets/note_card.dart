import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/date_formatter.dart';
import '../../../../core/utils/note_helper.dart';
import '../../../../core/utils/audio_helper.dart';
import '../../../../core/database/database_provider.dart';
import '../../../../shared/models/note_entity.dart';
import '../../../../shared/models/folder_entity.dart';
import '../../../../shared/models/voice_recording_entity.dart';
import 'rich_note_preview.dart';
import '../../../reminders/providers/reminder_providers.dart';
import '../../../reminders/presentation/widgets/reminder_chip.dart';
import '../../../tags/presentation/widgets/tag_chip.dart';

class NoteCard extends ConsumerWidget {
  final NoteEntity note;
  final FolderEntity? folder;
  final VoidCallback onTap;
  final VoidCallback onTogglePin;
  final VoidCallback onToggleArchive;
  final VoidCallback? onToggleFavorite;
  final VoidCallback onDelete;

  const NoteCard({
    super.key,
    required this.note,
    this.folder,
    required this.onTap,
    required this.onTogglePin,
    required this.onToggleArchive,
    this.onToggleFavorite,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Pick card tint
    final colorList = isDark
        ? AppColors.darkNoteColors
        : AppColors.lightNoteColors;
    final cardColor = note.colorIndex < colorList.length
        ? colorList[note.colorIndex]
        : (isDark ? AppColors.darkSurface : AppColors.lightSurface);

    final borderColor = isDark ? AppColors.darkBorder : AppColors.lightBorder;
    final primaryTextColor = isDark
        ? AppColors.darkTextPrimary
        : AppColors.lightTextPrimary;
    final secondaryTextColor = isDark
        ? AppColors.darkTextSecondary
        : AppColors.lightTextSecondary;
    final subtleTextColor = isDark
        ? AppColors.darkTextTertiary
        : AppColors.lightTextTertiary;

    final isChecklist =
        note.isChecklist || NoteHelper.isChecklistContent(note.content);
    final voiceRecordingsAsync = note.isVoiceNote
        ? ref.watch(voiceRecordingsStreamProvider(note.id))
        : null;

    final border = note.isPinned
        ? Border.all(
            color: AppColors.primary.withAlpha(isDark ? 120 : 90),
            width: 1.5,
          )
        : Border.all(color: borderColor, width: 1.0);

    return Container(
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(AppConstants.radiusMedium),
        border: border,
        boxShadow: note.isPinned
            ? [
                BoxShadow(
                  color: AppColors.primary.withAlpha(isDark ? 25 : 15),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ]
            : null,
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppConstants.radiusMedium),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header: Title & Pin/Favorite/Options
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        note.title.isEmpty ? 'Untitled Note' : note.title,
                        style: TextStyle(
                          fontSize: 15.5,
                          fontWeight: FontWeight.w600,
                          letterSpacing: -0.2,
                          fontStyle: note.title.isEmpty
                              ? FontStyle.italic
                              : FontStyle.normal,
                          color: note.title.isEmpty
                              ? secondaryTextColor
                              : primaryTextColor,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (note.isFavorite) ...[
                      const SizedBox(width: 6),
                      const Icon(
                        Icons.star_rounded,
                        size: 18,
                        color: AppColors.pinColor,
                      ),
                    ],
                    if (note.isPinned) ...[
                      const SizedBox(width: 6),
                      const Icon(
                        Icons.push_pin_rounded,
                        size: 16,
                        color: AppColors.primary,
                      ),
                    ],
                    if (note.isArchived) ...[
                      const SizedBox(width: 4),
                      IconButton(
                        icon: const Icon(Icons.unarchive_outlined, size: 17),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: 24,
                          minHeight: 24,
                        ),
                        visualDensity: VisualDensity.compact,
                        tooltip: 'Restore to Home',
                        onPressed: onToggleArchive,
                      ),
                    ],
                    const SizedBox(width: 2),
                    _buildOptionsMenu(context, secondaryTextColor),
                  ],
                ),

                // Voice Note Preview
                if (note.isVoiceNote && voiceRecordingsAsync != null) ...[
                  const SizedBox(height: 8),
                  voiceRecordingsAsync.when(
                    data: (recordings) {
                      final totalMs = recordings.fold<int>(
                        0,
                        (sum, r) => sum + r.durationMs,
                      );
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withAlpha(
                                isDark ? 30 : 18,
                              ),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: AppColors.primary.withAlpha(
                                  isDark ? 45 : 30,
                                ),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.mic_rounded,
                                  size: 13,
                                  color: AppColors.primary,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  '${recordings.length} ${recordings.length == 1 ? 'recording' : 'recordings'}',
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w600,
                                    color: isDark
                                        ? AppColors.darkTextPrimary
                                        : AppColors.lightTextPrimary,
                                  ),
                                ),
                                if (totalMs > 0) ...[
                                  const SizedBox(width: 5),
                                  Text(
                                    '• ${AudioHelper.formatDurationMs(totalMs)}',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w500,
                                      color: secondaryTextColor,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          _buildVoiceRecordingsPreview(
                            recordings,
                            note.voiceMode == 'checklist',
                            primaryTextColor,
                            secondaryTextColor,
                          ),
                        ],
                      );
                    },
                    loading: () => const SizedBox.shrink(),
                    error: (_, __) => const SizedBox.shrink(),
                  ),
                ] else if (note.hasAudio) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withAlpha(isDark ? 30 : 18),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: AppColors.primary.withAlpha(isDark ? 45 : 30),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.mic_rounded,
                          size: 13,
                          color: AppColors.primary,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Voice Note',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: isDark
                                ? AppColors.darkTextPrimary
                                : AppColors.lightTextPrimary,
                          ),
                        ),
                        if (note.audioDurationMs != null &&
                            note.audioDurationMs! > 0) ...[
                          const SizedBox(width: 5),
                          Text(
                            '• ${AudioHelper.formatDurationMs(note.audioDurationMs!)}',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              color: secondaryTextColor,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],

                // Checklist or Rich Text Preview
                if (!note.isVoiceNote) ...[
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
                      maxLines: 3,
                      primaryColor: primaryTextColor,
                      secondaryColor: secondaryTextColor,
                      subtleColor: subtleTextColor,
                    ),
                  ],
                ],

                // Active Reminder Chip
                Consumer(
                  builder: (context, ref, _) {
                    final rem = ref.watch(noteReminderProvider(note.id));
                    if (rem == null) return const SizedBox.shrink();
                    return Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: ReminderChip(reminder: rem, compact: true),
                      ),
                    );
                  },
                ),

                // Assigned Tags
                if (note.tagIds.isNotEmpty) ...[
                  Consumer(
                    builder: (context, ref, _) {
                      final tagsAsync = ref.watch(tagsStreamProvider);
                      final allTags = tagsAsync.value ?? [];
                      final noteTags = allTags
                          .where((t) => note.tagIds.contains(t.id))
                          .toList();
                      if (noteTags.isEmpty) return const SizedBox.shrink();

                      return Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Wrap(
                          spacing: 5,
                          runSpacing: 4,
                          children: noteTags
                              .map((t) => _buildCardTagChip(t, isDark))
                              .toList(),
                        ),
                      );
                    },
                  ),
                ],

                const SizedBox(height: 10),

                // Footer: Folder badge & Date
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    if (folder != null)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 2.5,
                        ),
                        decoration: BoxDecoration(
                          color: (isDark ? Colors.white : Colors.black)
                              .withAlpha(12),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.folder_outlined,
                              size: 11,
                              color: subtleTextColor,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              folder!.name,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                                color: subtleTextColor,
                              ),
                            ),
                          ],
                        ),
                      )
                    else if (note.isVoiceNote)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 2.5,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.redAccent.withAlpha(20),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.mic_rounded,
                              size: 11,
                              color: Colors.redAccent,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              note.voiceMode == 'checklist'
                                  ? 'Voice Checklist'
                                  : 'Voice Memo',
                              style: const TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w600,
                                color: Colors.redAccent,
                              ),
                            ),
                          ],
                        ),
                      )
                    else if (isChecklist)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 2.5,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.accent.withAlpha(20),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.checklist_rounded,
                              size: 11,
                              color: AppColors.accent,
                            ),
                            SizedBox(width: 4),
                            Text(
                              'Checklist',
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w600,
                                color: AppColors.accent,
                              ),
                            ),
                          ],
                        ),
                      )
                    else
                      const SizedBox.shrink(),

                    Text(
                      DateFormatter.formatSmart(note.updatedAt),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: subtleTextColor,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCardTagChip(dynamic tag, bool isDark) {
    final tagColor = TagChip.parseColor(tag.colorHex);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: tagColor.withAlpha(isDark ? 30 : 20),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: tagColor.withAlpha(isDark ? 60 : 40),
          width: 0.8,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 5,
            height: 5,
            decoration: BoxDecoration(color: tagColor, shape: BoxShape.circle),
          ),
          const SizedBox(width: 4),
          Text(
            tag.name,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
              color: isDark ? AppColors.darkTextPrimary : tagColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVoiceRecordingsPreview(
    List<VoiceRecordingEntity> recordings,
    bool isChecklistMode,
    Color primaryTextColor,
    Color secondaryTextColor,
  ) {
    if (recordings.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Text(
          'No recordings added yet',
          style: TextStyle(
            fontSize: 11.5,
            fontStyle: FontStyle.italic,
            color: secondaryTextColor.withAlpha(160),
          ),
        ),
      );
    }

    final displayRecordings = recordings.take(3).toList();
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (int i = 0; i < displayRecordings.length; i++) ...[
            Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Row(
                children: [
                  if (isChecklistMode)
                    Icon(
                      displayRecordings[i].isCompleted
                          ? Icons.check_circle_rounded
                          : Icons.radio_button_unchecked_rounded,
                      size: 13,
                      color: displayRecordings[i].isCompleted
                          ? AppColors.primary
                          : secondaryTextColor,
                    )
                  else
                    Icon(
                      Icons.audiotrack_rounded,
                      size: 12,
                      color: AppColors.primary.withAlpha(180),
                    ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      displayRecordings[i].title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color:
                            displayRecordings[i].isCompleted && isChecklistMode
                            ? secondaryTextColor
                            : primaryTextColor,
                        decoration:
                            displayRecordings[i].isCompleted && isChecklistMode
                            ? TextDecoration.lineThrough
                            : null,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    AudioHelper.formatDurationMs(
                      displayRecordings[i].durationMs,
                    ),
                    style: TextStyle(
                      fontSize: 10.5,
                      fontFamily: 'monospace',
                      color: secondaryTextColor,
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (recordings.length > 3)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                '+${recordings.length - 3} more recording${recordings.length - 3 == 1 ? '' : 's'}',
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w500,
                  color: secondaryTextColor,
                ),
              ),
            ),
        ],
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
    final lines = content.split('\n');
    final items = <Map<String, dynamic>>[];
    int completedCount = 0;
    int totalChecklistItems = 0;

    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      if (trimmed.startsWith('[x] ') || trimmed.startsWith('[X] ')) {
        totalChecklistItems++;
        completedCount++;
        if (items.length < 3) {
          items.add({'checked': true, 'text': trimmed.substring(4)});
        }
      } else if (trimmed.startsWith('[ ] ')) {
        totalChecklistItems++;
        if (items.length < 3) {
          items.add({'checked': false, 'text': trimmed.substring(4)});
        }
      } else {
        totalChecklistItems++;
        if (items.length < 3) {
          items.add({'checked': false, 'text': trimmed});
        }
      }
    }

    if (items.isEmpty) {
      return Text(
        'Empty checklist',
        style: TextStyle(
          fontSize: 12,
          fontStyle: FontStyle.italic,
          color: subtleTextColor,
        ),
      );
    }

    final remaining = totalChecklistItems - items.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final item in items)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Icon(
                  item['checked'] as bool
                      ? Icons.check_circle_rounded
                      : Icons.radio_button_unchecked_rounded,
                  size: 14,
                  color: item['checked'] as bool
                      ? AppColors.accent
                      : subtleTextColor,
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    item['text'] as String,
                    style: TextStyle(
                      fontSize: 12.5,
                      color: item['checked'] as bool
                          ? subtleTextColor
                          : primaryTextColor,
                      decoration: item['checked'] as bool
                          ? TextDecoration.lineThrough
                          : null,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        if (remaining > 0)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
              decoration: BoxDecoration(
                color: (isDark ? Colors.white : Colors.black).withAlpha(10),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                '+$remaining more item${remaining == 1 ? '' : 's'} ($completedCount/$totalChecklistItems done)',
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w500,
                  color: subtleTextColor,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildOptionsMenu(BuildContext context, Color color) {
    return PopupMenuButton<String>(
      icon: Icon(Icons.more_vert_rounded, size: 18, color: color),
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppConstants.radiusMedium),
      ),
      onSelected: (value) {
        switch (value) {
          case 'pin':
            onTogglePin();
            break;
          case 'favorite':
            onToggleFavorite?.call();
            break;
          case 'archive':
            onToggleArchive();
            break;
          case 'delete':
            onDelete();
            break;
        }
      },
      itemBuilder: (ctx) => [
        PopupMenuItem(
          value: 'pin',
          child: Row(
            children: [
              Icon(
                note.isPinned
                    ? Icons.push_pin_outlined
                    : Icons.push_pin_rounded,
                size: 18,
                color: AppColors.primary,
              ),
              const SizedBox(width: 10),
              Text(note.isPinned ? 'Unpin' : 'Pin to Top'),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'favorite',
          child: Row(
            children: [
              Icon(
                note.isFavorite
                    ? Icons.star_rounded
                    : Icons.star_outline_rounded,
                size: 18,
                color: AppColors.pinColor,
              ),
              const SizedBox(width: 10),
              Text(
                note.isFavorite ? 'Remove from Favorites' : 'Add to Favorites',
              ),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'archive',
          child: Row(
            children: [
              Icon(
                note.isArchived
                    ? Icons.unarchive_outlined
                    : Icons.archive_outlined,
                size: 18,
              ),
              const SizedBox(width: 10),
              Text(note.isArchived ? 'Restore to Home' : 'Archive Note'),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'delete',
          child: Row(
            children: [
              Icon(
                Icons.delete_outline_rounded,
                size: 18,
                color: AppColors.danger,
              ),
              SizedBox(width: 10),
              Text('Delete Note', style: TextStyle(color: AppColors.danger)),
            ],
          ),
        ),
      ],
    );
  }
}
