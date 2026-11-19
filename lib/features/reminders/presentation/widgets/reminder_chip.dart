import 'package:flutter/material.dart';
import '../../../../shared/models/reminder_entity.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/constants/app_constants.dart';

class ReminderChip extends StatelessWidget {
  final ReminderEntity reminder;
  final VoidCallback? onTap;
  final VoidCallback? onDelete;
  final bool compact;

  const ReminderChip({
    super.key,
    required this.reminder,
    this.onTap,
    this.onDelete,
    this.compact = false,
  });

  String _formatReminderTime(DateTime dt) {
    final hour = dt.hour == 0 ? 12 : (dt.hour > 12 ? dt.hour - 12 : dt.hour);
    final minute = dt.minute.toString().padLeft(2, '0');
    final period = dt.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$minute $period';
  }

  String _formatDisplayText() {
    final now = DateTime.now();
    final effective = reminder.effectiveScheduledAt;
    final isSnoozed = reminder.snoozedUntil != null && reminder.snoozedUntil!.isAfter(now);

    final timeStr = _formatReminderTime(effective);

    if (reminder.isCompleted) {
      return 'Done • $timeStr';
    }

    if (isSnoozed) {
      return 'Snoozed • $timeStr';
    }

    final isToday = effective.year == now.year && effective.month == now.month && effective.day == now.day;
    final tomorrow = now.add(const Duration(days: 1));
    final isTomorrow = effective.year == tomorrow.year && effective.month == tomorrow.month && effective.day == tomorrow.day;

    if (reminder.isOverdue) {
      if (isToday) {
        return 'Overdue • $timeStr';
      } else {
        const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
        return 'Overdue • ${months[effective.month - 1]} ${effective.day}';
      }
    }

    if (isToday) {
      return 'Today, $timeStr';
    } else if (isTomorrow) {
      return 'Tomorrow, $timeStr';
    } else {
      const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
      return '${months[effective.month - 1]} ${effective.day}, $timeStr';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final isOverdue = reminder.isOverdue && !reminder.isCompleted;
    final isCompleted = reminder.isCompleted;
    final isSnoozed = reminder.snoozedUntil != null && reminder.snoozedUntil!.isAfter(DateTime.now());

    Color bg;
    Color border;
    Color fg;

    if (isCompleted) {
      bg = isDark ? Colors.white.withOpacity(0.06) : Colors.black.withOpacity(0.04);
      border = isDark ? Colors.white.withOpacity(0.12) : Colors.black.withOpacity(0.08);
      fg = isDark ? Colors.white54 : Colors.black45;
    } else if (isOverdue) {
      bg = isDark ? Colors.red.withOpacity(0.18) : Colors.red.withOpacity(0.12);
      border = isDark ? Colors.red.withOpacity(0.35) : Colors.red.withOpacity(0.28);
      fg = isDark ? const Color(0xFFFF6B6B) : const Color(0xFFD32F2F);
    } else if (isSnoozed) {
      bg = isDark ? Colors.amber.withOpacity(0.18) : Colors.amber.withOpacity(0.12);
      border = isDark ? Colors.amber.withOpacity(0.35) : Colors.amber.withOpacity(0.28);
      fg = isDark ? const Color(0xFFFFB74D) : const Color(0xFFF57C00);
    } else {
      bg = theme.colorScheme.primary.withOpacity(isDark ? 0.15 : 0.1);
      border = theme.colorScheme.primary.withOpacity(isDark ? 0.3 : 0.2);
      fg = theme.colorScheme.primary;
    }

    final displayText = _formatDisplayText();

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppConstants.radiusMedium),
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 8 : 10,
            vertical: compact ? 3 : 5,
          ),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(AppConstants.radiusMedium),
            border: Border.all(color: border, width: 1.0),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isCompleted
                    ? Icons.check_circle_outline_rounded
                    : (isOverdue
                        ? Icons.notification_important_rounded
                        : (isSnoozed ? Icons.snooze_rounded : Icons.alarm_rounded)),
                size: compact ? 13 : 15,
                color: fg,
              ),
              const SizedBox(width: 5),
              Text(
                displayText,
                style: AppTypography.labelSmall(fg).copyWith(
                  fontWeight: FontWeight.w600,
                  fontSize: compact ? 11 : 12,
                  decoration: isCompleted ? TextDecoration.lineThrough : null,
                ),
              ),
              if (reminder.repeatMode != ReminderRepeatMode.never && !isCompleted) ...[
                const SizedBox(width: 4),
                Icon(
                  Icons.repeat_rounded,
                  size: compact ? 12 : 13,
                  color: fg.withOpacity(0.8),
                ),
              ],
              if (onDelete != null) ...[
                const SizedBox(width: 4),
                GestureDetector(
                  onTap: onDelete,
                  child: Padding(
                    padding: const EdgeInsets.all(2),
                    child: Icon(
                      Icons.close_rounded,
                      size: compact ? 12 : 14,
                      color: fg.withOpacity(0.7),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
