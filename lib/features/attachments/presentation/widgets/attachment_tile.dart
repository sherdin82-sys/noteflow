import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../shared/models/attachment_entity.dart';
import '../../providers/attachment_providers.dart';

class AttachmentTile extends ConsumerWidget {
  final AttachmentEntity attachment;
  final VoidCallback? onTap;
  final VoidCallback? onDelete;
  final String? documentsBasePath;

  const AttachmentTile({
    super.key,
    required this.attachment,
    this.onTap,
    this.onDelete,
    this.documentsBasePath,
  });

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

    final isImage = attachment.category == AttachmentCategory.image;

    final backgroundColor = isDark
        ? (isMissing
            ? AppColors.danger.withValues(alpha: 0.1)
            : AppColors.darkSurfaceVariant)
        : (isMissing
            ? AppColors.danger.withValues(alpha: 0.08)
            : AppColors.lightSurfaceVariant);

    final borderColor = isDark
        ? (isMissing
            ? AppColors.danger.withValues(alpha: 0.4)
            : AppColors.darkBorder)
        : (isMissing
            ? AppColors.danger.withValues(alpha: 0.3)
            : AppColors.lightBorder);

    final contentWidget = Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppConstants.radiusMedium),
        child: Container(
          width: isImage ? 80 : 130,
          height: 80,
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(AppConstants.radiusMedium),
            border: Border.all(color: borderColor, width: 1),
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            children: [
              if (isImage)
                _buildImageContent(context, isDark, isMissing, physicalFile)
              else
                _buildDocumentContent(context, isDark, isMissing),

              // Small remove/delete button badge where supported
              if (onDelete != null && isImage)
                Positioned(
                  top: 3,
                  right: 3,
                  child: Material(
                    color: Colors.black.withValues(alpha: 0.65),
                    shape: const CircleBorder(),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: onDelete,
                      child: const Padding(
                        padding: EdgeInsets.all(3.5),
                        child: Icon(
                          Icons.close_rounded,
                          size: 13,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );

    return Semantics(
      label: isImage
          ? 'Image attachment: ${attachment.originalName}, size ${attachment.formattedSize}'
          : 'Attachment: ${attachment.originalName}, size ${attachment.formattedSize}',
      button: true,
      child: Tooltip(
        message: '${attachment.originalName} (${attachment.formattedSize})',
        waitDuration: const Duration(milliseconds: 500),
        child: contentWidget,
      ),
    );
  }

  Widget _buildImageContent(
    BuildContext context,
    bool isDark,
    bool isMissing,
    File? physicalFile,
  ) {
    if (isMissing || physicalFile == null) {
      return _buildFallbackThumbnail(context, isDark, isMissing: true);
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        Image.file(
          physicalFile,
          fit: BoxFit.cover,
          cacheWidth: 240,
          cacheHeight: 240,
          filterQuality: FilterQuality.medium,
          errorBuilder: (context, error, stackTrace) {
            return _buildFallbackThumbnail(context, isDark, isMissing: true);
          },
        ),
        // Gradient and size overlay at bottom
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [
                  Colors.black.withValues(alpha: 0.75),
                  Colors.transparent,
                ],
              ),
            ),
            child: Text(
              attachment.formattedSize,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 9,
                fontWeight: FontWeight.w600,
                shadows: [
                  Shadow(
                    color: Colors.black54,
                    blurRadius: 2,
                    offset: Offset(0, 1),
                  ),
                ],
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFallbackThumbnail(BuildContext context, bool isDark,
      {required bool isMissing}) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.broken_image_rounded,
              color: AppColors.danger,
              size: 22,
            ),
            const SizedBox(height: 3),
            Text(
              attachment.originalName,
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w500,
                color: isDark
                    ? AppColors.darkTextSecondary
                    : AppColors.lightTextSecondary,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 1),
            const Text(
              'Missing',
              style: TextStyle(
                fontSize: 8,
                color: AppColors.danger,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDocumentContent(
      BuildContext context, bool isDark, bool isMissing) {
    if (isMissing) {
      return Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Icon(
                  Icons.broken_image_rounded,
                  color: AppColors.danger,
                  size: 20,
                ),
                if (onDelete != null)
                  GestureDetector(
                    onTap: onDelete,
                    behavior: HitTestBehavior.opaque,
                    child: Icon(
                      Icons.close_rounded,
                      size: 14,
                      color: isDark
                          ? AppColors.darkTextTertiary
                          : AppColors.lightTextTertiary,
                    ),
                  ),
              ],
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  attachment.originalName,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: isDark
                        ? AppColors.darkTextPrimary
                        : AppColors.lightTextPrimary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                const Text(
                  'Missing File',
                  style: TextStyle(
                    fontSize: 9,
                    color: AppColors.danger,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    }

    final iconData =
        _getCategoryIcon(attachment.category, attachment.fileExtension);
    final iconColor =
        _getCategoryColor(attachment.category, attachment.fileExtension);

    return Padding(
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Icon(iconData, color: iconColor, size: 22),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                    decoration: BoxDecoration(
                      color: iconColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      attachment.fileExtension.toUpperCase(),
                      style: TextStyle(
                        color: iconColor,
                        fontSize: 8,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  if (onDelete != null) ...[
                    const SizedBox(width: 4),
                    GestureDetector(
                      onTap: onDelete,
                      behavior: HitTestBehavior.opaque,
                      child: Icon(
                        Icons.close_rounded,
                        size: 14,
                        color: isDark
                            ? AppColors.darkTextTertiary
                            : AppColors.lightTextTertiary,
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                attachment.originalName,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: isDark
                      ? AppColors.darkTextPrimary
                      : AppColors.lightTextPrimary,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                attachment.formattedSize,
                style: TextStyle(
                  fontSize: 9,
                  color: isDark
                      ? AppColors.darkTextTertiary
                      : AppColors.lightTextTertiary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static IconData _getCategoryIcon(AttachmentCategory category, String ext) {
    final lowerExt = ext.toLowerCase();
    if (lowerExt == 'pdf') {
      return Icons.picture_as_pdf_rounded;
    }
    if (lowerExt == 'doc' || lowerExt == 'docx') {
      return Icons.description_rounded;
    }
    if (lowerExt == 'xls' || lowerExt == 'xlsx' || lowerExt == 'csv') {
      return Icons.table_chart_rounded;
    }
    if (lowerExt == 'txt') {
      return Icons.text_snippet_rounded;
    }

    switch (category) {
      case AttachmentCategory.image:
        return Icons.image_rounded;
      case AttachmentCategory.document:
        return Icons.description_rounded;
      case AttachmentCategory.audio:
        return Icons.audiotrack_rounded;
      case AttachmentCategory.video:
        return Icons.videocam_rounded;
      case AttachmentCategory.other:
        return Icons.insert_drive_file_rounded;
    }
  }

  static Color _getCategoryColor(AttachmentCategory category, String ext) {
    final lowerExt = ext.toLowerCase();
    if (lowerExt == 'pdf') {
      return const Color(0xFFEF4444);
    }
    if (lowerExt == 'doc' || lowerExt == 'docx') {
      return const Color(0xFF2563EB);
    }
    if (lowerExt == 'xls' || lowerExt == 'xlsx' || lowerExt == 'csv') {
      return const Color(0xFF10B981);
    }
    if (lowerExt == 'txt') {
      return const Color(0xFF64748B);
    }

    switch (category) {
      case AttachmentCategory.image:
        return const Color(0xFF3B82F6);
      case AttachmentCategory.document:
        return const Color(0xFFF59E0B);
      case AttachmentCategory.audio:
        return const Color(0xFF8B5CF6);
      case AttachmentCategory.video:
        return const Color(0xFFEC4899);
      case AttachmentCategory.other:
        return const Color(0xFF64748B);
    }
  }
}
