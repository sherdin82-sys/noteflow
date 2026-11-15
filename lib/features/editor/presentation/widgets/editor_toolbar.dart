import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/theme/app_colors.dart';

class EditorToolbar extends StatelessWidget {
  final QuillController controller;
  final VoidCallback onChanged;

  const EditorToolbar({
    super.key,
    required this.controller,
    required this.onChanged,
  });

  void _toggleFormat(Attribute attribute, bool isActive) {
    if (isActive) {
      controller.formatSelection(Attribute.clone(attribute, null));
    } else {
      controller.formatSelection(attribute);
    }
    onChanged();
  }

  void _cycleHeading(Style style) {
    if (style.containsKey(Attribute.h1.key)) {
      controller.formatSelection(Attribute.h2);
    } else if (style.containsKey(Attribute.h2.key)) {
      controller.formatSelection(Attribute.h3);
    } else if (style.containsKey(Attribute.h3.key)) {
      controller.formatSelection(Attribute.header);
    } else {
      controller.formatSelection(Attribute.h1);
    }
    onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final iconColor = isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary;

    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final style = controller.getSelectionStyle();
        final isBold = style.containsKey(Attribute.bold.key);
        final isItalic = style.containsKey(Attribute.italic.key);
        final isUnderline = style.containsKey(Attribute.underline.key);
        final isStrike = style.containsKey(Attribute.strikeThrough.key);

        final isH1 = style.containsKey(Attribute.h1.key);
        final isH2 = style.containsKey(Attribute.h2.key);
        final isH3 = style.containsKey(Attribute.h3.key);
        final isHeading = isH1 || isH2 || isH3;

        final isChecklist = style.containsKey(Attribute.unchecked.key) || style.containsKey(Attribute.checked.key);
        final isBullet = style.containsKey(Attribute.ul.key);
        final isOrdered = style.containsKey(Attribute.ol.key);
        final isQuote = style.containsKey(Attribute.blockQuote.key);
        final isCode = style.containsKey(Attribute.codeBlock.key);

        return Container(
          height: 48,
          decoration: BoxDecoration(
            color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
            border: Border(
              top: BorderSide(
                color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
                width: 1.0,
              ),
            ),
          ),
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: AppConstants.paddingSmall),
            children: [
              // Undo & Redo
              _buildToolButton(
                icon: Icons.undo_rounded,
                tooltip: 'Undo',
                isActive: false,
                isEnabled: controller.hasUndo,
                iconColor: iconColor,
                isDark: isDark,
                onPressed: () {
                  if (controller.hasUndo) {
                    controller.undo();
                    onChanged();
                  }
                },
              ),
              _buildToolButton(
                icon: Icons.redo_rounded,
                tooltip: 'Redo',
                isActive: false,
                isEnabled: controller.hasRedo,
                iconColor: iconColor,
                isDark: isDark,
                onPressed: () {
                  if (controller.hasRedo) {
                    controller.redo();
                    onChanged();
                  }
                },
              ),
              const VerticalDivider(width: 12, indent: 12, endIndent: 12),

              // Heading cycle
              _buildToolButton(
                icon: isH3
                    ? Icons.format_size_rounded
                    : (isH2 ? Icons.text_fields_rounded : Icons.title_rounded),
                tooltip: isH1 ? 'Heading 1 (Tap for H2)' : (isH2 ? 'Heading 2 (Tap for H3)' : (isH3 ? 'Heading 3 (Tap for Normal)' : 'Heading 1')),
                isActive: isHeading,
                iconColor: iconColor,
                isDark: isDark,
                onPressed: () => _cycleHeading(style),
              ),

              // Inline formats: Bold, Italic, Underline, Strikethrough
              _buildToolButton(
                icon: Icons.format_bold_rounded,
                tooltip: 'Bold',
                isActive: isBold,
                iconColor: iconColor,
                isDark: isDark,
                onPressed: () => _toggleFormat(Attribute.bold, isBold),
              ),
              _buildToolButton(
                icon: Icons.format_italic_rounded,
                tooltip: 'Italic',
                isActive: isItalic,
                iconColor: iconColor,
                isDark: isDark,
                onPressed: () => _toggleFormat(Attribute.italic, isItalic),
              ),
              _buildToolButton(
                icon: Icons.format_underlined_rounded,
                tooltip: 'Underline',
                isActive: isUnderline,
                iconColor: iconColor,
                isDark: isDark,
                onPressed: () => _toggleFormat(Attribute.underline, isUnderline),
              ),
              _buildToolButton(
                icon: Icons.format_strikethrough_rounded,
                tooltip: 'Strikethrough',
                isActive: isStrike,
                iconColor: iconColor,
                isDark: isDark,
                onPressed: () => _toggleFormat(Attribute.strikeThrough, isStrike),
              ),

              const VerticalDivider(width: 12, indent: 12, endIndent: 12),

              // Lists: Checklist, Bullet List, Numbered List
              _buildToolButton(
                icon: Icons.check_box_outlined,
                tooltip: 'Checklist Item',
                isActive: isChecklist,
                iconColor: iconColor,
                isDark: isDark,
                onPressed: () => _toggleFormat(Attribute.unchecked, isChecklist),
              ),
              _buildToolButton(
                icon: Icons.format_list_bulleted_rounded,
                tooltip: 'Bullet List',
                isActive: isBullet,
                iconColor: iconColor,
                isDark: isDark,
                onPressed: () => _toggleFormat(Attribute.ul, isBullet),
              ),
              _buildToolButton(
                icon: Icons.format_list_numbered_rounded,
                tooltip: 'Numbered List',
                isActive: isOrdered,
                iconColor: iconColor,
                isDark: isDark,
                onPressed: () => _toggleFormat(Attribute.ol, isOrdered),
              ),

              const VerticalDivider(width: 12, indent: 12, endIndent: 12),

              // Blocks: Quote & Code Block
              _buildToolButton(
                icon: Icons.format_quote_rounded,
                tooltip: 'Quote Block',
                isActive: isQuote,
                iconColor: iconColor,
                isDark: isDark,
                onPressed: () => _toggleFormat(Attribute.blockQuote, isQuote),
              ),
              _buildToolButton(
                icon: Icons.code_rounded,
                tooltip: 'Code Block',
                isActive: isCode,
                iconColor: iconColor,
                isDark: isDark,
                onPressed: () => _toggleFormat(Attribute.codeBlock, isCode),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildToolButton({
    required IconData icon,
    required String tooltip,
    required bool isActive,
    required Color iconColor,
    required bool isDark,
    required VoidCallback onPressed,
    bool isEnabled = true,
  }) {
    final effectiveColor = !isEnabled
        ? (isDark ? AppColors.darkTextTertiary.withAlpha(90) : AppColors.lightTextTertiary.withAlpha(90))
        : (isActive ? AppColors.primary : iconColor);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Center(
        child: Container(
          decoration: BoxDecoration(
            color: isActive ? AppColors.primary.withAlpha(isDark ? 45 : 30) : Colors.transparent,
            borderRadius: BorderRadius.circular(AppConstants.radiusSmall),
          ),
          child: IconButton(
            focusNode: FocusNode(canRequestFocus: false),
            icon: Icon(icon, size: 20, color: effectiveColor),
            tooltip: tooltip,
            splashRadius: 20,
            constraints: const BoxConstraints(minWidth: 38, minHeight: 38),
            padding: const EdgeInsets.all(8),
            onPressed: isEnabled ? onPressed : null,
          ),
        ),
      ),
    );
  }
}
