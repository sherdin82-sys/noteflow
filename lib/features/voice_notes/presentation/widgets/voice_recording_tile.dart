import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/audio_helper.dart';
import '../../../../core/utils/date_formatter.dart';
import '../../../../shared/models/voice_recording_entity.dart';
import '../controllers/voice_player_controller.dart';

class VoiceRecordingTile extends ConsumerWidget {
  final VoiceRecordingEntity recording;
  final bool isChecklistMode;
  final VoidCallback onToggleComplete;
  final ValueChanged<String> onRename;
  final VoidCallback onDelete;
  final Widget? dragHandle;

  const VoiceRecordingTile({
    super.key,
    required this.recording,
    required this.isChecklistMode,
    required this.onToggleComplete,
    required this.onRename,
    required this.onDelete,
    this.dragHandle,
  });

  void _showRenameDialog(BuildContext context) {
    final controller = TextEditingController(text: recording.title);
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppConstants.radiusMedium),
        ),
        title: const Text('Rename Recording'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Enter title...',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final newTitle = controller.text.trim();
              if (newTitle.isNotEmpty) {
                onRename(newTitle);
              }
              Navigator.pop(dialogCtx);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _confirmDelete(BuildContext context) {
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppConstants.radiusMedium),
        ),
        title: const Text('Delete Recording'),
        content: Text('Are you sure you want to delete "${recording.title}"? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () {
              Navigator.pop(dialogCtx);
              onDelete();
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryTextColor = isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary;
    final secondaryTextColor = isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary;

    final playbackState = ref.watch(voicePlayerProvider);
    final isCurrent = playbackState.activeRecordingId == recording.id;
    final isPlaying = isCurrent && playbackState.isPlaying;
    final isLoading = isCurrent && playbackState.isLoading;
    final isError = isCurrent && playbackState.isError;

    // Durations: Use actual playback duration if available from native player
    final effectiveDurationMs = (isCurrent && playbackState.duration.inMilliseconds > 0)
        ? playbackState.duration.inMilliseconds
        : recording.durationMs;
    final totalDuration = Duration(milliseconds: effectiveDurationMs);
    final currentPos = isCurrent ? playbackState.position : Duration.zero;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
        borderRadius: BorderRadius.circular(AppConstants.radiusMedium),
        border: Border.all(
          color: isCurrent
              ? AppColors.primary.withAlpha(isDark ? 160 : 120)
              : (isDark ? Colors.white10 : Colors.black12),
          width: isCurrent ? 1.5 : 1,
        ),
        boxShadow: isCurrent
            ? [
                BoxShadow(
                  color: AppColors.primary.withAlpha(isDark ? 30 : 15),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                )
              ]
            : null,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          children: [
            // Top Row: (Checkbox if checklist mode) + Title + Date/Duration + Options Menu + Drag Handle
            Row(
              children: [
                if (isChecklistMode) ...[
                  IconButton(
                    iconSize: 22,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    icon: Icon(
                      recording.isCompleted
                          ? Icons.check_circle_rounded
                          : Icons.radio_button_unchecked_rounded,
                      color: recording.isCompleted ? AppColors.primary : secondaryTextColor,
                    ),
                    onPressed: onToggleComplete,
                  ),
                  const SizedBox(width: 8),
                ],

                // Play / Pause Icon Button
                IconButton.filledTonal(
                  style: IconButton.styleFrom(
                    backgroundColor: isPlaying
                        ? AppColors.primary
                        : AppColors.primary.withAlpha(isDark ? 35 : 20),
                    foregroundColor: isPlaying ? Colors.white : AppColors.primary,
                    padding: const EdgeInsets.all(8),
                    minimumSize: const Size(36, 36),
                  ),
                  icon: isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.primary,
                          ),
                        )
                      : Icon(
                          isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                          size: 20,
                        ),
                  onPressed: () {
                    ref.read(voicePlayerProvider.notifier).playRecording(
                          recording.id,
                          recording.audioPath,
                        );
                  },
                ),
                const SizedBox(width: 10),

                // Title and Metadata
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        recording.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: recording.isCompleted && isChecklistMode
                              ? secondaryTextColor
                              : primaryTextColor,
                          decoration: recording.isCompleted && isChecklistMode
                              ? TextDecoration.lineThrough
                              : null,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Text(
                            AudioHelper.formatDurationMs(recording.durationMs),
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: isCurrent ? AppColors.primary : secondaryTextColor,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text('•', style: TextStyle(color: secondaryTextColor, fontSize: 10)),
                          const SizedBox(width: 6),
                          Text(
                            DateFormatter.formatSmart(recording.createdAt),
                            style: TextStyle(
                              fontSize: 11,
                              color: secondaryTextColor,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                // More Options Menu (Rename / Delete)
                PopupMenuButton<String>(
                  icon: Icon(Icons.more_vert_rounded, size: 20, color: secondaryTextColor),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onSelected: (val) {
                    if (val == 'rename') {
                      _showRenameDialog(context);
                    } else if (val == 'delete') {
                      _confirmDelete(context);
                    }
                  },
                  itemBuilder: (ctx) => [
                    const PopupMenuItem(
                      value: 'rename',
                      child: Row(
                        children: [
                          Icon(Icons.edit_outlined, size: 18),
                          SizedBox(width: 8),
                          Text('Rename'),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'delete',
                      child: Row(
                        children: [
                          Icon(Icons.delete_outline_rounded, size: 18, color: AppColors.danger),
                          SizedBox(width: 8),
                          Text('Delete', style: TextStyle(color: AppColors.danger)),
                        ],
                      ),
                    ),
                  ],
                ),

                // Reorder Drag Handle
                if (dragHandle != null) ...[
                  const SizedBox(width: 4),
                  dragHandle!,
                ],
              ],
            ),

            // Playback Seek Slider & Timestamps (shown when active/playing or selected)
            if (isCurrent) ...[
              if (isError) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline_rounded, size: 14, color: AppColors.danger),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          playbackState.errorMessage ?? 'Audio playback error occurred',
                          style: const TextStyle(fontSize: 11, color: AppColors.danger),
                        ),
                      ),
                    ],
                  ),
                ),
              ] else ...[
                const SizedBox(height: 4),
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
                    overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
                    trackHeight: 3,
                    activeTrackColor: AppColors.primary,
                    inactiveTrackColor: isDark ? Colors.white12 : Colors.black12,
                    thumbColor: AppColors.primary,
                  ),
                  child: Slider(
                    value: currentPos.inMilliseconds
                        .clamp(0, totalDuration.inMilliseconds)
                        .toDouble(),
                    max: totalDuration.inMilliseconds > 0
                        ? totalDuration.inMilliseconds.toDouble()
                        : 1.0,
                    onChanged: (val) {
                      ref
                          .read(voicePlayerProvider.notifier)
                          .seek(Duration(milliseconds: val.toInt()));
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        AudioHelper.formatDuration(currentPos),
                        style: TextStyle(
                          fontSize: 10,
                          fontFamily: 'monospace',
                          color: secondaryTextColor,
                        ),
                      ),
                      Text(
                        AudioHelper.formatDuration(totalDuration),
                        style: TextStyle(
                          fontSize: 10,
                          fontFamily: 'monospace',
                          color: secondaryTextColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}
