import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../shared/models/attachment_entity.dart';
import '../../providers/attachment_providers.dart';
import 'attachment_tile.dart';

class AttachmentSection extends ConsumerWidget {
  final String noteId;
  final VoidCallback onAddAttachment;
  final void Function(AttachmentEntity attachment)? onAttachmentTap;
  final void Function(AttachmentEntity attachment)? onAttachmentDelete;
  final bool isImporting;
  final String? documentsBasePath;

  const AttachmentSection({
    super.key,
    required this.noteId,
    required this.onAddAttachment,
    this.onAttachmentTap,
    this.onAttachmentDelete,
    this.isImporting = false,
    this.documentsBasePath,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final attachmentsAsync = ref.watch(noteAttachmentsStreamProvider(noteId));
    final attachments = attachmentsAsync.value ?? [];

    if (attachments.isEmpty && !isImporting) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final effectiveBasePath =
        documentsBasePath ?? ref.watch(documentsBasePathProvider).value;

    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isImporting)
            const Padding(
              padding: EdgeInsets.only(bottom: 6),
              child: ClipRRect(
                borderRadius: BorderRadius.all(Radius.circular(2)),
                child: LinearProgressIndicator(
                  minHeight: 2.5,
                  color: AppColors.primary,
                  backgroundColor: Colors.transparent,
                ),
              ),
            ),
          SizedBox(
            height: 82,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              clipBehavior: Clip.none,
              itemCount: attachments.length + 1,
              separatorBuilder: (context, index) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                if (index < attachments.length) {
                  final attachment = attachments[index];
                  return AttachmentTile(
                    key: ValueKey('attachment_${attachment.id}'),
                    attachment: attachment,
                    documentsBasePath: effectiveBasePath,
                    onTap: () => onAttachmentTap?.call(attachment),
                    onDelete: () => onAttachmentDelete?.call(attachment),
                  );
                }

                // Final item: Quick "Add" card
                return _buildAddButton(context, isDark);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAddButton(BuildContext context, bool isDark) {
    final borderColor =
        isDark ? AppColors.darkBorderSubtle : AppColors.lightBorderSubtle;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onAddAttachment,
        borderRadius: BorderRadius.circular(AppConstants.radiusMedium),
        child: Container(
          width: 60,
          height: 80,
          decoration: BoxDecoration(
            color: isDark
                ? AppColors.darkSurface.withValues(alpha: 0.5)
                : AppColors.lightSurface.withValues(alpha: 0.7),
            borderRadius: BorderRadius.circular(AppConstants.radiusMedium),
            border: Border.all(color: borderColor, width: 1.2),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.add_rounded,
                size: 24,
                color: isDark
                    ? AppColors.darkTextSecondary
                    : AppColors.lightTextSecondary,
              ),
              const SizedBox(height: 2),
              Text(
                'Add',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: isDark
                      ? AppColors.darkTextTertiary
                      : AppColors.lightTextTertiary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
