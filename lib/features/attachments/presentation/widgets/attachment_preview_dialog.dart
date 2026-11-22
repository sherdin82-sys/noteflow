import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../shared/models/attachment_entity.dart';
import '../../providers/attachment_providers.dart';
import '../../services/attachment_native_bridge.dart';

class AttachmentPreviewDialog extends ConsumerWidget {
  final AttachmentEntity attachment;
  final VoidCallback? onDelete;
  final String? documentsBasePath;

  const AttachmentPreviewDialog({
    super.key,
    required this.attachment,
    this.onDelete,
    this.documentsBasePath,
  });

  static Future<void> show({
    required BuildContext context,
    required AttachmentEntity attachment,
    VoidCallback? onDelete,
    String? documentsBasePath,
  }) {
    return showDialog(
      context: context,
      builder: (ctx) => AttachmentPreviewDialog(
        attachment: attachment,
        onDelete: onDelete,
        documentsBasePath: documentsBasePath,
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final baseDir =
        documentsBasePath ?? ref.watch(documentsBasePathProvider).value;
    File? physicalFile;
    bool isMissing = false;
    if (baseDir != null && baseDir.isNotEmpty) {
      physicalFile = File('$baseDir/${attachment.relativePath}');
      isMissing = !physicalFile.existsSync();
    } else {
      isMissing = true;
    }

    final isImage = attachment.category == AttachmentCategory.image &&
        !isMissing &&
        physicalFile != null;

    return Dialog(
      backgroundColor: isDark ? AppColors.darkSurface : AppColors.lightSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppConstants.radiusLarge),
      ),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header with filename and close button
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        attachment.originalName,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: isDark
                              ? AppColors.darkTextPrimary
                              : AppColors.lightTextPrimary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${attachment.formattedSize} • ${attachment.fileExtension.toUpperCase()}',
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark
                              ? AppColors.darkTextTertiary
                              : AppColors.lightTextTertiary,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.of(context).pop(),
                  tooltip: 'Close',
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          // Content body: InteractiveViewer for images, or file card for documents
          Flexible(
            child: Container(
              constraints: const BoxConstraints(maxHeight: 380),
              width: double.infinity,
              color: isDark ? Colors.black26 : Colors.black12,
              child: isImage
                  ? InteractiveViewer(
                      minScale: 0.5,
                      maxScale: 4.0,
                      child: Image.file(
                        physicalFile!,
                        fit: BoxFit.contain,
                        errorBuilder: (ctx, err, stack) =>
                            _buildMissingState(isDark),
                      ),
                    )
                  : _buildDocumentDetails(context, isDark, isMissing),
            ),
          ),
          const Divider(height: 1),

          // Action bar (Open, Share, Delete)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                TextButton.icon(
                  onPressed: () => _confirmDelete(context),
                  icon: const Icon(Icons.delete_outline_rounded,
                      color: AppColors.danger, size: 18),
                  label: const Text(
                    'Remove',
                    style: TextStyle(
                        color: AppColors.danger, fontWeight: FontWeight.w600),
                  ),
                ),
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.share_rounded, size: 20),
                      tooltip: 'Share',
                      onPressed: () async {
                        // Native share handoff
                        final bridge = AttachmentNativeBridge();
                        await bridge.shareAttachment(
                          relativePath: attachment.relativePath,
                          mimeType: attachment.mimeType,
                          originalName: attachment.originalName,
                        );
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.open_in_new_rounded, size: 20),
                      tooltip: 'Open in App',
                      onPressed: () async {
                        // Native open handoff
                        final bridge = AttachmentNativeBridge();
                        await bridge.openAttachment(
                          relativePath: attachment.relativePath,
                          mimeType: attachment.mimeType,
                          originalName: attachment.originalName,
                        );
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMissingState(bool isDark) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.broken_image_rounded, size: 48, color: AppColors.danger),
          SizedBox(height: 8),
          Text(
            'Physical file missing on device storage',
            style: TextStyle(color: AppColors.danger, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _buildDocumentDetails(
      BuildContext context, bool isDark, bool isMissing) {
    if (isMissing) {
      return _buildMissingState(isDark);
    }

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.insert_drive_file_rounded,
            size: 64,
            color: isDark ? AppColors.primaryLight : AppColors.primary,
          ),
          const SizedBox(height: 12),
          Text(
            attachment.originalName,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: isDark
                  ? AppColors.darkTextPrimary
                  : AppColors.lightTextPrimary,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          Text(
            '${attachment.formattedSize} • ${attachment.mimeType}',
            style: TextStyle(
              fontSize: 12,
              color: isDark
                  ? AppColors.darkTextTertiary
                  : AppColors.lightTextTertiary,
            ),
          ),
        ],
      ),
    );
  }

  void _confirmDelete(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove Attachment?'),
        content: Text(
            'Are you sure you want to remove "${attachment.originalName}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop(); // Dismiss confirmation
              Navigator.of(context).pop(); // Dismiss preview dialog
              onDelete?.call();
            },
            child: const Text(
              'Remove',
              style: TextStyle(
                  color: AppColors.danger, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }
}
