import 'dart:io';
import 'package:flutter/material.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../shared/models/attachment_entity.dart';

class AttachmentTile extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final baseDir = documentsBasePath;
    File? physicalFile;
    bool isMissing = false;
    if (baseDir != null) {
      physicalFile = File('$baseDir/${attachment.relativePath}');
      isMissing = !physicalFile.existsSync();
    }

    final isImage = attachment.category == AttachmentCategory.image && !isMissing;

    final backgroundColor = isDark
        ? (isMissing ? AppColors.danger.withValues(alpha: 0.1) : AppColors.darkSurfaceVariant)
        : (isMissing ? AppColors.danger.withValues(alpha: 0.08) : AppColors.lightSurfaceVariant);

    final borderColor = isDark
        ? (isMissing ? AppColors.danger.withValues(alpha: 0.4) : AppColors.darkBorder)
        : (isMissing ? AppColors.danger.withValues(alpha: 0.3) : AppColors.lightBorder);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        onLongPress: onDelete,
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
              if (isImage && physicalFile != null)
                Positioned.fill(
                  child: Image.file(
                    physicalFile,
                    fit: BoxFit.cover,
                    cacheWidth: 200,
                    errorBuilder: (context, error, stackTrace) {
                      return _buildFallbackIcon(isDark, isMissing: true);
                    },
                  ),
                )
              else
                _buildDocumentContent(context, isDark, isMissing),

              // Gradient and size overlay for images
              if (isImage)
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
                          Colors.black.withValues(alpha: 0.7),
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
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDocumentContent(BuildContext context, bool isDark, bool isMissing) {
    if (isMissing) {
      return Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Icon(
              Icons.broken_image_rounded,
              color: AppColors.danger,
              size: 20,
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  attachment.originalName,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
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

    final iconData = _getCategoryIcon(attachment.category, attachment.fileExtension);
    final iconColor = _getCategoryColor(attachment.category, attachment.fileExtension);

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
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
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
                  color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                attachment.formattedSize,
                style: TextStyle(
                  fontSize: 9,
                  color: isDark ? AppColors.darkTextTertiary : AppColors.lightTextTertiary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFallbackIcon(bool isDark, {bool isMissing = false}) {
    return Center(
      child: Icon(
        isMissing ? Icons.broken_image_rounded : Icons.image_rounded,
        color: isMissing ? AppColors.danger : (isDark ? AppColors.darkTextTertiary : AppColors.lightTextTertiary),
        size: 28,
      ),
    );
  }

  static IconData _getCategoryIcon(AttachmentCategory category, String ext) {
    final lowerExt = ext.toLowerCase();
    if (lowerExt == 'pdf') return Icons.picture_as_pdf_rounded;
    if (lowerExt == 'doc' || lowerExt == 'docx') return Icons.description_rounded;
    if (lowerExt == 'xls' || lowerExt == 'xlsx' || lowerExt == 'csv') return Icons.table_chart_rounded;
    if (lowerExt == 'txt') return Icons.text_snippet_rounded;

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
    if (lowerExt == 'pdf') return const Color(0xFFEF4444);
    if (lowerExt == 'doc' || lowerExt == 'docx') return const Color(0xFF2563EB);
    if (lowerExt == 'xls' || lowerExt == 'xlsx' || lowerExt == 'csv') return const Color(0xFF10B981);
    if (lowerExt == 'txt') return const Color(0xFF64748B);

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
