import 'package:flutter/material.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/theme/app_colors.dart';

class EditorToolbar extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback onChanged;

  const EditorToolbar({
    super.key,
    required this.controller,
    required this.onChanged,
  });

  void _wrapSelection(String prefix, String suffix) {
    final text = controller.text;
    final selection = controller.selection;

    if (!selection.isValid || selection.isCollapsed) {
      final cursor = selection.isValid ? selection.baseOffset : text.length;
      final newText = text.replaceRange(cursor, cursor, '$prefix$suffix');
      controller.value = TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(offset: cursor + prefix.length),
      );
    } else {
      final selected = text.substring(selection.start, selection.end);
      final newText = text.replaceRange(selection.start, selection.end, '$prefix$selected$suffix');
      controller.value = TextEditingValue(
        text: newText,
        selection: TextSelection(
          baseOffset: selection.start + prefix.length,
          extentOffset: selection.end + prefix.length,
        ),
      );
    }
    onChanged();
  }

  void _insertAtLineStart(String prefix) {
    final text = controller.text;
    final selection = controller.selection;
    final cursor = selection.isValid ? selection.baseOffset : text.length;

    // Find the start of the current line
    final lineStart = text.lastIndexOf('\n', cursor > 0 ? cursor - 1 : 0);
    final insertPos = lineStart == -1 ? 0 : lineStart + 1;

    final newText = text.replaceRange(insertPos, insertPos, prefix);
    controller.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: cursor + prefix.length),
    );
    onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final iconColor = isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary;

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
          _buildToolButton(
            icon: Icons.title,
            tooltip: 'Heading',
            iconColor: iconColor,
            onPressed: () => _insertAtLineStart('# '),
          ),
          _buildToolButton(
            icon: Icons.format_bold,
            tooltip: 'Bold',
            iconColor: iconColor,
            onPressed: () => _wrapSelection('**', '**'),
          ),
          _buildToolButton(
            icon: Icons.format_italic,
            tooltip: 'Italic',
            iconColor: iconColor,
            onPressed: () => _wrapSelection('*', '*'),
          ),
          _buildToolButton(
            icon: Icons.format_strikethrough,
            tooltip: 'Strikethrough',
            iconColor: iconColor,
            onPressed: () => _wrapSelection('~~', '~~'),
          ),
          const VerticalDivider(width: 16, indent: 10, endIndent: 10),
          _buildToolButton(
            icon: Icons.check_box_outlined,
            tooltip: 'Checklist Task',
            iconColor: iconColor,
            onPressed: () => _insertAtLineStart('[ ] '),
          ),
          _buildToolButton(
            icon: Icons.format_list_bulleted,
            tooltip: 'Bullet List',
            iconColor: iconColor,
            onPressed: () => _insertAtLineStart('• '),
          ),
          _buildToolButton(
            icon: Icons.format_list_numbered,
            tooltip: 'Numbered List',
            iconColor: iconColor,
            onPressed: () => _insertAtLineStart('1. '),
          ),
          const VerticalDivider(width: 16, indent: 10, endIndent: 10),
          _buildToolButton(
            icon: Icons.format_quote,
            tooltip: 'Quote',
            iconColor: iconColor,
            onPressed: () => _insertAtLineStart('> '),
          ),
          _buildToolButton(
            icon: Icons.code,
            tooltip: 'Code Block',
            iconColor: iconColor,
            onPressed: () => _wrapSelection('```\n', '\n```'),
          ),
          _buildToolButton(
            icon: Icons.horizontal_rule,
            tooltip: 'Divider',
            iconColor: iconColor,
            onPressed: () {
              final text = controller.text;
              final cursor = controller.selection.isValid ? controller.selection.baseOffset : text.length;
              final newText = text.replaceRange(cursor, cursor, '\n---\n');
              controller.value = TextEditingValue(
                text: newText,
                selection: TextSelection.collapsed(offset: cursor + 5),
              );
              onChanged();
            },
          ),
        ],
      ),
    );
  }

  Widget _buildToolButton({
    required IconData icon,
    required String tooltip,
    required Color iconColor,
    required VoidCallback onPressed,
  }) {
    return IconButton(
      icon: Icon(icon, size: 20, color: iconColor),
      tooltip: tooltip,
      splashRadius: 20,
      onPressed: onPressed,
    );
  }
}
