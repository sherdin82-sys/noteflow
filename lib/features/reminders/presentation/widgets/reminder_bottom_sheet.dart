import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../shared/models/reminder_entity.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/constants/app_constants.dart';
import '../../services/reminder_native_bridge.dart';
import '../../providers/reminder_providers.dart';

class ReminderBottomSheet extends StatefulWidget {
  final String noteId;
  final String? checklistItemId;
  final String? voiceRecordingId;
  final String defaultTitle;
  final String defaultPreview;
  final ReminderEntity? existingReminder;

  const ReminderBottomSheet({
    super.key,
    required this.noteId,
    this.checklistItemId,
    this.voiceRecordingId,
    required this.defaultTitle,
    this.defaultPreview = '',
    this.existingReminder,
  });

  static Future<ReminderEntity?> show({
    required BuildContext context,
    required String noteId,
    String? checklistItemId,
    String? voiceRecordingId,
    required String defaultTitle,
    String defaultPreview = '',
    ReminderEntity? existingReminder,
  }) {
    return showModalBottomSheet<ReminderEntity>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => ReminderBottomSheet(
        noteId: noteId,
        checklistItemId: checklistItemId,
        voiceRecordingId: voiceRecordingId,
        defaultTitle: defaultTitle,
        defaultPreview: defaultPreview,
        existingReminder: existingReminder,
      ),
    );
  }

  @override
  State<ReminderBottomSheet> createState() => _ReminderBottomSheetState();
}

class _ReminderBottomSheetState extends State<ReminderBottomSheet> {
  late DateTime _selectedDateTime;
  late ReminderRepeatMode _repeatMode;
  late TextEditingController _titleController;
  late final AppLifecycleListener _lifecycleListener;
  bool _canExactAlarm = true;
  bool _notificationsEnabled = true;

  @override
  void initState() {
    super.initState();
    _lifecycleListener = AppLifecycleListener(
      onResume: () => _checkPermissions(),
    );

    if (widget.existingReminder != null) {
      _selectedDateTime = widget.existingReminder!.effectiveScheduledAt;
      _repeatMode = widget.existingReminder!.repeatMode;
      _titleController = TextEditingController(text: widget.existingReminder!.title);
    } else {
      final now = DateTime.now();
      // Default to 1 hour from now, rounded to the next 15-minute mark
      var initial = now.add(const Duration(hours: 1));
      final minuteRounded = ((initial.minute / 15).ceil() * 15) % 60;
      _selectedDateTime = DateTime(initial.year, initial.month, initial.day, initial.hour, minuteRounded);
      _repeatMode = ReminderRepeatMode.never;
      _titleController = TextEditingController(text: widget.defaultTitle);
    }

    _checkPermissions();
  }

  @override
  void dispose() {
    _lifecycleListener.dispose();
    _titleController.dispose();
    super.dispose();
  }

  Future<void> _checkPermissions() async {
    try {
      final exact = await ReminderNativeBridge.canScheduleExactAlarms();
      final enabled = await ReminderNativeBridge.areNotificationsEnabled();
      if (mounted) {
        setState(() {
          _canExactAlarm = exact;
          _notificationsEnabled = enabled;
        });
      }
    } catch (_) {}
  }

  void _applyPreset(DateTime target) {
    setState(() {
      _selectedDateTime = target;
    });
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDateTime.isBefore(now) ? now : _selectedDateTime,
      firstDate: now.subtract(const Duration(days: 1)),
      lastDate: DateTime(now.year + 5),
    );
    if (picked != null) {
      setState(() {
        _selectedDateTime = DateTime(
          picked.year,
          picked.month,
          picked.day,
          _selectedDateTime.hour,
          _selectedDateTime.minute,
        );
      });
    }
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_selectedDateTime),
    );
    if (picked != null) {
      setState(() {
        _selectedDateTime = DateTime(
          _selectedDateTime.year,
          _selectedDateTime.month,
          _selectedDateTime.day,
          picked.hour,
          picked.minute,
        );
      });
    }
  }

  String _formatTime(DateTime dt) {
    final hour = dt.hour == 0 ? 12 : (dt.hour > 12 ? dt.hour - 12 : dt.hour);
    final minute = dt.minute.toString().padLeft(2, '0');
    final period = dt.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$minute $period';
  }

  String _formatDate(DateTime dt) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${months[dt.month - 1]} ${dt.day}, ${dt.year}';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surfaceColor = isDark ? AppColors.darkSurface : AppColors.lightSurface;
    final textColor = isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary;
    final secondaryText = isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary;
    final primaryColor = Theme.of(context).colorScheme.primary;

    final now = DateTime.now();

    // Preset options
    final today6pm = DateTime(now.year, now.month, now.day, 18, 0);
    final tomorrow9am = DateTime(now.year, now.month, now.day + 1, 9, 0);
    final tomorrow6pm = DateTime(now.year, now.month, now.day + 1, 18, 0);
    final daysToNextMon = (8 - now.weekday) % 7 == 0 ? 7 : (8 - now.weekday) % 7;
    final nextWeekMon9am = DateTime(now.year, now.month, now.day + daysToNextMon, 9, 0);

    return Consumer(
      builder: (context, ref, child) {
        return Container(
          padding: EdgeInsets.only(
            left: AppConstants.paddingLarge,
            right: AppConstants.paddingLarge,
            top: AppConstants.paddingMedium,
            bottom: MediaQuery.of(context).viewInsets.bottom +
                MediaQuery.of(context).padding.bottom +
                AppConstants.paddingLarge,
          ),
          decoration: BoxDecoration(
            color: surfaceColor,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(AppConstants.radiusLarge),
            ),
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Drag handle
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: isDark ? Colors.white24 : Colors.black12,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Title row
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      widget.existingReminder != null ? 'Edit Reminder' : 'Set Reminder',
                      style: AppTypography.titleLarge(textColor),
                    ),
                    if (widget.existingReminder != null)
                      IconButton(
                        tooltip: 'Delete Reminder',
                        icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent),
                        onPressed: () async {
                          final service = ref.read(reminderServiceProvider);
                          await service.deleteReminder(widget.existingReminder!.id);
                          if (context.mounted) Navigator.pop(context);
                        },
                      ),
                  ],
                ),
                const SizedBox(height: 16),

                // Permission warning if applicable
                if (!_notificationsEnabled) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.amber.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(AppConstants.radiusMedium),
                      border: Border.all(color: Colors.amber.withOpacity(0.3)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.warning_amber_rounded, color: Colors.amber, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Notifications are disabled in system settings.',
                            style: AppTypography.bodySmall(textColor),
                          ),
                        ),
                        TextButton(
                          onPressed: () => ReminderNativeBridge.openNotificationSettings(),
                          child: const Text('Enable'),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                ] else if (!_canExactAlarm) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.blue.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(AppConstants.radiusMedium),
                      border: Border.all(color: Colors.blue.withOpacity(0.3)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.info_outline_rounded, color: Colors.blueAccent, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Exact alarms restricted. Reminders will trigger with approximate timing.',
                            style: AppTypography.bodySmall(textColor),
                          ),
                        ),
                        TextButton(
                          onPressed: () => ReminderNativeBridge.requestExactAlarmPermission(),
                          child: const Text('Allow'),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                ],

                // Quick Presets
                Text(
                  'QUICK PRESETS',
                  style: AppTypography.labelSmall(secondaryText).copyWith(letterSpacing: 1.1),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (now.hour < 17)
                      _buildPresetChip(
                        label: 'Later Today (6 PM)',
                        target: today6pm,
                        isDark: isDark,
                      ),
                    _buildPresetChip(
                      label: 'Tomorrow (9 AM)',
                      target: tomorrow9am,
                      isDark: isDark,
                    ),
                    _buildPresetChip(
                      label: 'Tomorrow (6 PM)',
                      target: tomorrow6pm,
                      isDark: isDark,
                    ),
                    _buildPresetChip(
                      label: 'Next Week (Mon 9 AM)',
                      target: nextWeekMon9am,
                      isDark: isDark,
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // Custom Date & Time
                Text(
                  'SCHEDULE DATE & TIME',
                  style: AppTypography.labelSmall(secondaryText).copyWith(letterSpacing: 1.1),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: InkWell(
                        onTap: _pickDate,
                        borderRadius: BorderRadius.circular(AppConstants.radiusMedium),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                          decoration: BoxDecoration(
                            color: isDark ? AppColors.darkSurfaceVariant : AppColors.lightSurfaceVariant,
                            borderRadius: BorderRadius.circular(AppConstants.radiusMedium),
                            border: Border.all(
                              color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.calendar_month_rounded, size: 18, color: primaryColor),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _formatDate(_selectedDateTime),
                                  style: AppTypography.bodyMedium(textColor).copyWith(fontWeight: FontWeight.w500),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 2,
                      child: InkWell(
                        onTap: _pickTime,
                        borderRadius: BorderRadius.circular(AppConstants.radiusMedium),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                          decoration: BoxDecoration(
                            color: isDark ? AppColors.darkSurfaceVariant : AppColors.lightSurfaceVariant,
                            borderRadius: BorderRadius.circular(AppConstants.radiusMedium),
                            border: Border.all(
                              color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.access_time_rounded, size: 18, color: primaryColor),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _formatTime(_selectedDateTime),
                                  style: AppTypography.bodyMedium(textColor).copyWith(fontWeight: FontWeight.w500),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // Recurrence
                Text(
                  'REPEAT',
                  style: AppTypography.labelSmall(secondaryText).copyWith(letterSpacing: 1.1),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: isDark ? AppColors.darkSurfaceVariant : AppColors.lightSurfaceVariant,
                    borderRadius: BorderRadius.circular(AppConstants.radiusMedium),
                    border: Border.all(
                      color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
                    ),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<ReminderRepeatMode>(
                      value: _repeatMode,
                      isExpanded: true,
                      dropdownColor: surfaceColor,
                      icon: Icon(Icons.arrow_drop_down_rounded, color: primaryColor),
                      items: const [
                        DropdownMenuItem(
                          value: ReminderRepeatMode.never,
                          child: Text('Does not repeat'),
                        ),
                        DropdownMenuItem(
                          value: ReminderRepeatMode.daily,
                          child: Text('Every day'),
                        ),
                        DropdownMenuItem(
                          value: ReminderRepeatMode.weekly,
                          child: Text('Every week'),
                        ),
                        DropdownMenuItem(
                          value: ReminderRepeatMode.monthly,
                          child: Text('Every month'),
                        ),
                      ],
                      onChanged: (val) {
                        if (val != null) {
                          setState(() {
                            _repeatMode = val;
                          });
                        }
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 28),

                // Action Buttons
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(AppConstants.radiusMedium),
                          ),
                        ),
                        child: Text('Cancel', style: AppTypography.titleMedium(secondaryText)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: FilledButton(
                        onPressed: () async {
                          final service = ref.read(reminderServiceProvider);

                          // Request notifications permission if Android 13+
                          await ReminderNativeBridge.requestNotificationPermission();

                          if (widget.existingReminder != null) {
                            final updated = widget.existingReminder!.copyWith(
                              title: _titleController.text.trim().isNotEmpty
                                  ? _titleController.text.trim()
                                  : widget.defaultTitle,
                              scheduledAt: _selectedDateTime,
                              repeatMode: _repeatMode,
                              isCompleted: false,
                              clearCompletedAt: true,
                              clearSnoozedUntil: true,
                            );
                            await service.updateReminder(updated);
                            if (context.mounted) Navigator.pop(context, updated);
                          } else {
                            final created = await service.createReminder(
                              noteId: widget.noteId,
                              checklistItemId: widget.checklistItemId,
                              voiceRecordingId: widget.voiceRecordingId,
                              title: _titleController.text.trim().isNotEmpty
                                  ? _titleController.text.trim()
                                  : widget.defaultTitle,
                              notesPreview: widget.defaultPreview,
                              scheduledAt: _selectedDateTime,
                              repeatMode: _repeatMode,
                            );
                            if (context.mounted) Navigator.pop(context, created);
                          }
                        },
                        style: FilledButton.styleFrom(
                          backgroundColor: primaryColor,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(AppConstants.radiusMedium),
                          ),
                        ),
                        child: Text(
                          widget.existingReminder != null ? 'Update Reminder' : 'Set Reminder',
                          style: AppTypography.titleMedium(Colors.white).copyWith(fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildPresetChip({
    required String label,
    required DateTime target,
    required bool isDark,
  }) {
    final isSelected = _selectedDateTime.year == target.year &&
        _selectedDateTime.month == target.month &&
        _selectedDateTime.day == target.day &&
        _selectedDateTime.hour == target.hour &&
        _selectedDateTime.minute == target.minute;

    return ActionChip(
      label: Text(label),
      backgroundColor: isSelected
          ? Theme.of(context).colorScheme.primary.withOpacity(0.18)
          : (isDark ? AppColors.darkSurfaceVariant : AppColors.lightSurfaceVariant),
      side: BorderSide(
        color: isSelected
            ? Theme.of(context).colorScheme.primary
            : (isDark ? AppColors.darkBorder : AppColors.lightBorder),
      ),
      labelStyle: AppTypography.labelSmall(
        isSelected
            ? Theme.of(context).colorScheme.primary
            : (isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary),
      ).copyWith(fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal),
      onPressed: () => _applyPreset(target),
    );
  }
}
