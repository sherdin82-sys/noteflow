import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../shared/models/reminder_entity.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/constants/app_constants.dart';
import '../../providers/reminder_providers.dart';
import 'reminder_bottom_sheet.dart';

class ReminderCard extends ConsumerWidget {
  final ReminderEntity reminder;
  final VoidCallback? onOpenNote;

  const ReminderCard({
    super.key,
    required this.reminder,
    this.onOpenNote,
  });

  String _formatTime(DateTime dt) {
    final hour = dt.hour == 0 ? 12 : (dt.hour > 12 ? dt.hour - 12 : dt.hour);
    final minute = dt.minute.toString().padLeft(2, '0');
    final period = dt.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$minute $period';
  }

  String _formatDateTime(DateTime dt) {
    final now = DateTime.now();
    final timeStr = _formatTime(dt);
    if (dt.year == now.year && dt.month == now.month && dt.day == now.day) {
      return 'Today, $timeStr';
    }
    final tomorrow = now.add(const Duration(days: 1));
    if (dt.year == tomorrow.year && dt.month == tomorrow.month && dt.day == tomorrow.day) {
      return 'Tomorrow, $timeStr';
    }
    final yesterday = now.subtract(const Duration(days: 1));
    if (dt.year == yesterday.year && dt.month == yesterday.month && dt.day == yesterday.day) {
      return 'Yesterday, $timeStr';
    }
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${months[dt.month - 1]} ${dt.day}, $timeStr';
  }

  String _repeatModeLabel(ReminderRepeatMode mode) {
    switch (mode) {
      case ReminderRepeatMode.daily:
        return 'Every day';
      case ReminderRepeatMode.weekly:
        return 'Every week';
      case ReminderRepeatMode.monthly:
        return 'Every month';
      case ReminderRepeatMode.custom:
        return 'Custom';
      case ReminderRepeatMode.never:
        return '';
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final surfaceColor = isDark ? AppColors.darkSurface : AppColors.lightSurface;
    final textColor = isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary;
    final secondaryText = isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary;

    final isOverdue = reminder.isOverdue && !reminder.isCompleted;
    final isSnoozed = reminder.snoozedUntil != null && reminder.snoozedUntil!.isAfter(DateTime.now());
    final effectiveTime = reminder.effectiveScheduledAt;

    return Dismissible(
      key: Key('rem_${reminder.id}'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: Colors.redAccent,
          borderRadius: BorderRadius.circular(AppConstants.radiusMedium),
        ),
        child: const Icon(Icons.delete_outline_rounded, color: Colors.white),
      ),
      onDismissed: (_) {
        ref.read(reminderServiceProvider).deleteReminder(reminder.id);
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: surfaceColor,
          borderRadius: BorderRadius.circular(AppConstants.radiusMedium),
          border: Border.all(
            color: isOverdue
                ? (isDark ? Colors.red.withOpacity(0.4) : Colors.red.withOpacity(0.3))
                : (isDark ? AppColors.darkBorder : AppColors.lightBorder),
            width: isOverdue ? 1.5 : 1.0,
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppConstants.radiusMedium),
          onTap: () {
            ReminderBottomSheet.show(
              context: context,
              noteId: reminder.noteId,
              checklistItemId: reminder.checklistItemId,
              voiceRecordingId: reminder.voiceRecordingId,
              defaultTitle: reminder.title,
              defaultPreview: reminder.notesPreview,
              existingReminder: reminder,
            );
          },
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top row: Checkbox, Title, and Action menu
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Completion checkbox
                    Transform.scale(
                      scale: 1.1,
                      child: Checkbox(
                        value: reminder.isCompleted,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                        onChanged: (val) {
                          final service = ref.read(reminderServiceProvider);
                          if (val == true) {
                            service.completeReminder(reminder.id);
                          } else {
                            service.updateReminder(reminder.copyWith(
                              isCompleted: false,
                              clearCompletedAt: true,
                            ));
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Title and preview
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            reminder.title,
                            style: AppTypography.titleMedium(textColor).copyWith(
                              decoration: reminder.isCompleted ? TextDecoration.lineThrough : null,
                              color: reminder.isCompleted ? secondaryText : textColor,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (reminder.notesPreview.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              reminder.notesPreview,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: AppTypography.bodySmall(secondaryText).copyWith(
                                decoration: reminder.isCompleted ? TextDecoration.lineThrough : null,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    // Context badge (Note, Checklist, or Audio)
                    if (reminder.isChecklistItemReminder)
                      Tooltip(
                        message: 'Checklist Item Reminder',
                        child: Icon(Icons.checklist_rounded, size: 18, color: secondaryText),
                      )
                    else if (reminder.isVoiceRecordingReminder)
                      Tooltip(
                        message: 'Voice Note Reminder',
                        child: Icon(Icons.mic_rounded, size: 18, color: secondaryText),
                      )
                    else
                      Tooltip(
                        message: 'Note Reminder',
                        child: Icon(Icons.description_outlined, size: 18, color: secondaryText),
                      ),
                  ],
                ),
                const SizedBox(height: 12),

                // Info pills row: Date/Time, Snoozed, Repeat
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    // Time pill
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: isOverdue
                            ? (isDark ? Colors.red.withOpacity(0.2) : Colors.red.withOpacity(0.12))
                            : (isDark ? Colors.white.withOpacity(0.06) : Colors.black.withOpacity(0.05)),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            isOverdue ? Icons.error_outline_rounded : Icons.alarm_rounded,
                            size: 13,
                            color: isOverdue ? Colors.redAccent : secondaryText,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            _formatDateTime(effectiveTime),
                            style: AppTypography.labelSmall(
                              isOverdue ? Colors.redAccent : secondaryText,
                            ).copyWith(fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),

                    // Snooze indicator
                    if (isSnoozed)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: isDark ? Colors.amber.withOpacity(0.2) : Colors.amber.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.snooze_rounded, size: 13, color: Colors.orangeAccent),
                            const SizedBox(width: 4),
                            Text(
                              'Snoozed ${reminder.snoozeCount}x',
                              style: AppTypography.labelSmall(Colors.orangeAccent).copyWith(fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                      ),

                    // Repeat indicator
                    if (reminder.repeatMode != ReminderRepeatMode.never)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primary.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.repeat_rounded, size: 13, color: theme.colorScheme.primary),
                            const SizedBox(width: 4),
                            Text(
                              _repeatModeLabel(reminder.repeatMode),
                              style: AppTypography.labelSmall(theme.colorScheme.primary).copyWith(fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 12),

                // Quick Action Bar
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (!reminder.isCompleted) ...[
                      TextButton.icon(
                        icon: const Icon(Icons.snooze_rounded, size: 15),
                        label: const Text('+15m'),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          visualDensity: VisualDensity.compact,
                        ),
                        onPressed: () {
                          ref.read(reminderServiceProvider).snoozeReminder(reminder.id);
                        },
                      ),
                      const SizedBox(width: 4),
                      TextButton.icon(
                        icon: const Icon(Icons.check_rounded, size: 15),
                        label: const Text('Done'),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          visualDensity: VisualDensity.compact,
                        ),
                        onPressed: () {
                          ref.read(reminderServiceProvider).completeReminder(reminder.id);
                        },
                      ),
                    ],
                    if (onOpenNote != null) ...[
                      const SizedBox(width: 4),
                      IconButton(
                        icon: const Icon(Icons.arrow_forward_ios_rounded, size: 14),
                        tooltip: 'Open Note',
                        onPressed: onOpenNote,
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
