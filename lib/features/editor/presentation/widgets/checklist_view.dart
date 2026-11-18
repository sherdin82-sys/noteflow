import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/note_helper.dart';

class ChecklistItem {
  final String id;
  bool isCompleted;
  late final TextEditingController controller;
  late final FocusNode focusNode;

  ChecklistItem({
    String? id,
    required this.isCompleted,
    required String text,
  }) : id = id ?? const Uuid().v4() {
    controller = TextEditingController(text: text);
    focusNode = FocusNode();
  }

  String get text => controller.text;

  void dispose() {
    controller.dispose();
    focusNode.dispose();
  }
}

class ChecklistView extends StatefulWidget {
  final String rawContent;
  final ValueChanged<String> onContentChanged;
  final bool autoFocus;

  const ChecklistView({
    super.key,
    required this.rawContent,
    required this.onContentChanged,
    this.autoFocus = false,
  });

  @override
  State<ChecklistView> createState() => _ChecklistViewState();
}

class _ChecklistViewState extends State<ChecklistView> {
  final List<ChecklistItem> _items = [];
  bool _isInternalChange = false;
  String _lastSerialized = '';

  @override
  void initState() {
    super.initState();
    _parseRawContent(widget.rawContent);
    if (widget.autoFocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _items.isNotEmpty) {
          _items.first.focusNode.requestFocus();
          _items.first.controller.selection = const TextSelection.collapsed(offset: 0);
        }
      });
    }
  }

  @override
  void dispose() {
    for (final item in _items) {
      item.dispose();
    }
    _items.clear();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant ChecklistView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.rawContent != widget.rawContent) {
      if (_isInternalChange) {
        _isInternalChange = false;
        return;
      }
      final currentFormatted = _serialize();
      if (currentFormatted != widget.rawContent && _lastSerialized != widget.rawContent) {
        _parseRawContent(widget.rawContent);
      }
    }
  }

  ChecklistItem _createItem({required bool isCompleted, required String text}) {
    final item = ChecklistItem(isCompleted: isCompleted, text: text);
    _setupItemKeyHandler(item);
    return item;
  }

  void _setupItemKeyHandler(ChecklistItem item) {
    item.focusNode.onKeyEvent = (node, event) {
      if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.backspace) {
        final index = _items.indexOf(item);
        if (index < 0) return KeyEventResult.ignored;

        final selection = item.controller.selection;

        // If the item is empty, delete it and move focus to previous item
        if (item.controller.text.isEmpty && _items.length > 1) {
          _removeItem(index);
          return KeyEventResult.handled;
        }

        // If cursor is at the very beginning (offset 0), merge text with previous item
        if (selection.isCollapsed && selection.baseOffset == 0 && index > 0) {
          final prevItem = _items[index - 1];
          final prevLength = prevItem.controller.text.length;
          prevItem.controller.text = prevItem.controller.text + item.controller.text;

          setState(() {
            _items.removeAt(index);
          });
          item.dispose();
          _notifyChange();

          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              prevItem.focusNode.requestFocus();
              prevItem.controller.selection = TextSelection.collapsed(offset: prevLength);
            }
          });
          return KeyEventResult.handled;
        }
      }
      return KeyEventResult.ignored;
    };
  }

  String _sanitizeText(String raw) {
    var t = raw;
    while (t.startsWith('[ ] ') || t.startsWith('[x] ') || t.startsWith('- [ ] ') || t.startsWith('- [x] ')) {
      t = t.startsWith('- [ ] ') || t.startsWith('- [x] ') ? t.substring(6) : t.substring(4);
    }
    if (t == '[ ]' || t == '[x]' || t == '- [ ]' || t == '- [x]') {
      t = '';
    }
    return t;
  }

  void _parseRawContent(String content) {
    for (final item in _items) {
      item.dispose();
    }
    _items.clear();

    final formatted = NoteHelper.formatForEditor(content);
    final lines = formatted.split('\n');

    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;

      if (trimmed == '[x]' || trimmed == '- [x]') {
        _items.add(_createItem(isCompleted: true, text: ''));
      } else if (trimmed == '[ ]' || trimmed == '- [ ]') {
        _items.add(_createItem(isCompleted: false, text: ''));
      } else if (trimmed.startsWith('[x] ') || trimmed.startsWith('- [x] ')) {
        final text = trimmed.startsWith('- [x] ') ? trimmed.substring(6) : trimmed.substring(4);
        _items.add(_createItem(isCompleted: true, text: _sanitizeText(text)));
      } else if (trimmed.startsWith('[ ] ') || trimmed.startsWith('- [ ] ')) {
        final text = trimmed.startsWith('- [ ] ') ? trimmed.substring(6) : trimmed.substring(4);
        _items.add(_createItem(isCompleted: false, text: _sanitizeText(text)));
      } else if (trimmed.startsWith('• ') || trimmed.startsWith('- ') || trimmed.startsWith('* ')) {
        _items.add(_createItem(isCompleted: false, text: _sanitizeText(trimmed.substring(2))));
      } else if (RegExp(r'^\d+\.\s').hasMatch(trimmed)) {
        _items.add(_createItem(isCompleted: false, text: _sanitizeText(trimmed.replaceFirst(RegExp(r'^\d+\.\s'), ''))));
      } else {
        _items.add(_createItem(isCompleted: false, text: _sanitizeText(trimmed)));
      }
    }

    if (_items.isEmpty) {
      _items.add(_createItem(isCompleted: false, text: ''));
    }

    _lastSerialized = _serialize();
  }

  String _serialize() {
    return _items.map((item) {
      final check = item.isCompleted ? '[x]' : '[ ]';
      final text = item.controller.text;
      return text.isEmpty ? check : '$check $text';
    }).join('\n');
  }

  void _notifyChange() {
    _isInternalChange = true;
    final serialized = _serialize();
    _lastSerialized = serialized;
    widget.onContentChanged(serialized);
    setState(() {});
  }

  void _handleSubmitted(int index) {
    if (index < 0 || index >= _items.length) return;
    final currentItem = _items[index];
    final text = currentItem.controller.text;
    final selection = currentItem.controller.selection;

    String leftText = text;
    String rightText = '';

    if (selection.isValid && selection.baseOffset >= 0 && selection.baseOffset <= text.length) {
      final offset = selection.baseOffset;
      leftText = text.substring(0, offset);
      rightText = text.substring(offset);
    }

    currentItem.controller.text = leftText;

    final newItem = _createItem(
      isCompleted: false,
      text: rightText,
    );

    setState(() {
      _items.insert(index + 1, newItem);
    });

    _notifyChange();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        newItem.focusNode.requestFocus();
        newItem.controller.selection = const TextSelection.collapsed(offset: 0);
      }
    });
  }

  void _addItem({int? afterIndex}) {
    final newItem = _createItem(isCompleted: false, text: '');
    setState(() {
      if (afterIndex != null && afterIndex < _items.length) {
        _items.insert(afterIndex + 1, newItem);
      } else {
        _items.add(newItem);
      }
    });
    _notifyChange();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        newItem.focusNode.requestFocus();
      }
    });
  }

  void _removeItem(int index) {
    if (index < 0 || index >= _items.length) return;
    final item = _items[index];

    setState(() {
      if (_items.length > 1) {
        _items.removeAt(index);
        final nextFocusIndex = index > 0 ? index - 1 : 0;
        if (nextFocusIndex < _items.length) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              final target = _items[nextFocusIndex];
              target.focusNode.requestFocus();
              target.controller.selection = TextSelection.collapsed(
                offset: target.controller.text.length,
              );
            }
          });
        }
      } else {
        item.controller.text = '';
        item.isCompleted = false;
      }
    });

    if (_items.length > 1 || item != _items[0]) {
      item.dispose();
    }

    _notifyChange();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryTextColor = isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary;
    final completedTextColor = isDark ? AppColors.darkTextTertiary : AppColors.lightTextTertiary;
    final subtleTextColor = isDark ? AppColors.darkTextTertiary : AppColors.lightTextTertiary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ReorderableListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          buildDefaultDragHandles: false,
          itemCount: _items.length,
          onReorder: (oldIndex, newIndex) {
            setState(() {
              if (newIndex > oldIndex) newIndex -= 1;
              final item = _items.removeAt(oldIndex);
              _items.insert(newIndex, item);
            });
            _notifyChange();
          },
          itemBuilder: (context, index) {
            final item = _items[index];

            return Padding(
              key: ValueKey(item.id),
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Dedicated drag handle
                  ReorderableDragStartListener(
                    index: index,
                    child: Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: Icon(
                        Icons.drag_indicator_rounded,
                        size: 20,
                        color: subtleTextColor.withAlpha(120),
                      ),
                    ),
                  ),

                  // Interactive checkbox
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      item.isCompleted = !item.isCompleted;
                      _notifyChange();
                    },
                    child: Padding(
                      padding: const EdgeInsets.only(right: 10),
                      child: Icon(
                        item.isCompleted
                            ? Icons.check_circle_rounded
                            : Icons.radio_button_unchecked_rounded,
                        size: 22,
                        color: item.isCompleted
                            ? AppColors.accent
                            : (isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary),
                      ),
                    ),
                  ),

                  // Task text field
                  Expanded(
                    child: TextField(
                      key: ValueKey('input-${item.id}'),
                      controller: item.controller,
                      focusNode: item.focusNode,
                      textInputAction: TextInputAction.next,
                      onSubmitted: (_) => _handleSubmitted(index),
                      onChanged: (_) => _notifyChange(),
                      style: TextStyle(
                        fontSize: 16,
                        color: item.isCompleted ? completedTextColor : primaryTextColor,
                        decoration: item.isCompleted ? TextDecoration.lineThrough : null,
                        decorationColor: completedTextColor,
                      ),
                      decoration: InputDecoration(
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(vertical: 8),
                        hintText: 'Task description...',
                        hintStyle: TextStyle(
                          fontSize: 16,
                          color: isDark ? AppColors.darkTextTertiary : AppColors.lightTextTertiary,
                        ),
                      ),
                    ),
                  ),

                  // Quick remove button
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                    icon: Icon(
                      Icons.close_rounded,
                      size: 18,
                      color: isDark ? AppColors.darkTextTertiary : AppColors.lightTextTertiary,
                    ),
                    tooltip: 'Remove task',
                    onPressed: () => _removeItem(index),
                  ),
                ],
              ),
            );
          },
        ),

        const SizedBox(height: 8),

        // Add task button
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppConstants.radiusSmall),
              ),
            ),
            onPressed: () => _addItem(),
            icon: const Icon(Icons.add_rounded, size: 20, color: AppColors.primary),
            label: const Text(
              'Add Item',
              style: TextStyle(
                color: AppColors.primary,
                fontWeight: FontWeight.w600,
                fontSize: 15,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
