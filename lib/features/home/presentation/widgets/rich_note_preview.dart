import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/note_helper.dart';

/// A lightweight, read-only rich-text preview widget for note cards.
///
/// Efficiently renders bold, italic, underline, strikethrough, headings,
/// lists (bullet, ordered, checklist), blockquotes, code highlights, and images
/// without allocating expensive QuillController or QuillEditor instances.
class RichNotePreview extends StatelessWidget {
  final String content;
  final int maxLines;
  final TextStyle? baseStyle;
  final Color? primaryColor;
  final Color? secondaryColor;
  final Color? subtleColor;

  const RichNotePreview({
    super.key,
    required this.content,
    this.maxLines = 4,
    this.baseStyle,
    this.primaryColor,
    this.secondaryColor,
    this.subtleColor,
  });

  @override
  Widget build(BuildContext context) {
    if (content.trim().isEmpty) return const SizedBox.shrink();

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryTextColor = primaryColor ?? (isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary);
    final secondaryTextColor = secondaryColor ?? (isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary);
    final subtleTextColor = subtleColor ?? (isDark ? AppColors.darkTextTertiary : AppColors.lightTextTertiary);

    final lines = NoteHelper.parseToRichLines(content);
    final displayLines = lines.where((l) => !l.isEmpty).take(maxLines).toList();
    if (displayLines.isEmpty) return const SizedBox.shrink();

    final List<InlineSpan> spanChildren = [];

    for (int lineIdx = 0; lineIdx < displayLines.length; lineIdx++) {
      if (lineIdx > 0) {
        spanChildren.add(const TextSpan(text: '\n'));
      }

      final line = displayLines[lineIdx];

      // Add prefix for bullet, ordered list, checklist, or blockquote
      if (line.listType == 'bullet') {
        spanChildren.add(const TextSpan(
          text: '• ',
          style: TextStyle(
            color: AppColors.accent,
            fontWeight: FontWeight.bold,
            fontSize: 13,
          ),
        ));
      } else if (line.listType == 'ordered') {
        spanChildren.add(TextSpan(
          text: '${line.listIndex ?? (lineIdx + 1)}. ',
          style: const TextStyle(
            color: AppColors.accent,
            fontWeight: FontWeight.w600,
            fontSize: 13,
          ),
        ));
      } else if (line.listType == 'checked') {
        spanChildren.add(const TextSpan(
          text: '☑ ',
          style: TextStyle(
            color: AppColors.accent,
            fontSize: 13,
          ),
        ));
      } else if (line.listType == 'unchecked') {
        spanChildren.add(TextSpan(
          text: '☐ ',
          style: TextStyle(
            color: subtleTextColor,
            fontSize: 13,
          ),
        ));
      } else if (line.isBlockquote) {
        spanChildren.add(const TextSpan(
          text: '▎ ',
          style: TextStyle(
            color: AppColors.accent,
            fontWeight: FontWeight.bold,
            fontSize: 13,
          ),
        ));
      }

      final isHeader = line.header != null;
      final double fontSize = line.header == 1
          ? 15.0
          : (line.header == 2 ? 14.0 : (line.header == 3 ? 13.5 : 13.0));
      final isLineChecked = line.listType == 'checked';

      for (final span in line.spans) {
        if (span.isImage) {
          spanChildren.add(TextSpan(
            text: '📷 [Image] ',
            style: TextStyle(
              fontSize: 12,
              fontStyle: FontStyle.italic,
              color: subtleTextColor,
            ),
          ));
          continue;
        }

        final bool isBold = span.isBold || isHeader;
        final bool isItalic = span.isItalic || line.isBlockquote;
        final Color textColor = isLineChecked
            ? subtleTextColor
            : (isBold ? primaryTextColor : secondaryTextColor);

        TextDecoration? decoration;
        if (isLineChecked || span.isStrike) {
          decoration = TextDecoration.lineThrough;
        } else if (span.isUnderline) {
          decoration = TextDecoration.underline;
        }

        spanChildren.add(TextSpan(
          text: span.text,
          style: TextStyle(
            fontSize: fontSize,
            fontWeight: isBold ? FontWeight.w700 : FontWeight.w400,
            fontStyle: isItalic ? FontStyle.italic : FontStyle.normal,
            decoration: decoration,
            color: textColor,
            fontFamily: (span.isCode || line.isCodeBlock) ? 'monospace' : null,
            backgroundColor: span.isCode
                ? (isDark ? const Color(0x33FFFFFF) : const Color(0x1F000000))
                : null,
          ),
        ));
      }
    }

    return Text.rich(
      TextSpan(children: spanChildren),
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
      style: baseStyle ?? const TextStyle(height: 1.35),
    );
  }
}
