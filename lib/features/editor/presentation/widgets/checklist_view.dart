import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/note_helper.dart';

class ChecklistItem {
  final String id;
  bool isCompleted;
  String text;

  ChecklistItem({
    String? id,
    required this.isCompleted,
    required this.text,
  }) : id = id ?? const Uuid().v4();
}

class ChecklistView extends StatefulWidget {
  final String rawContent;
  final ValueChanged<String> onContentChanged;

  const ChecklistView({
    super.key,
    required this.rawContent,
    required this.onContentChanged,
  });

  @override
  State<ChecklistView> createState() => _ChecklistViewState();
}

class _ChecklistViewState extends State<ChecklistView> {
  final List<ChecklistItem> _items = [];
  final Map<String, FocusNode> _focusNodes = {};

  @override
  void initState() {
    super.initState();
    _parseRawContent(widget.rawContent);
  }

  FocusNode _getFocusNode(String id) {
    return _focusNodes.putIfAbsent(id, () => FocusNode());
  }

  @override
  void dispose() {
    for (final node in _focusNodes.values) {
      node.dispose();
    }
    _focusNodes.clear();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant ChecklistView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.rawContent != widget.rawContent) {
      final currentFormatted = _serialize();
      if (currentFormatted != widget.rawContent) {
        _parseRawContent(widget.rawContent);
      }
    }
  }

  void _parseRawContent(String content) {
    _items.clear();
    final formatted = NoteHelper.formatForEditor(content);
    final lines = formatted.split('\n');
    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;

      if (trimmed.startsWith('[x] ') || trimmed.startsWith('- [x] ')) {
        final text = trimmed.startsWith('- [x] ') ? trimmed.substring(6) : trimmed.substring(4);
        _items.add(ChecklistItem(isCompleted: true, text: text));
      } else if (trimmed.startsWith('[ ] ') || trimmed.startsWith('- [ ] ')) {
        final text = trimmed.startsWith('- [ ] ') ? trimmed.substring(6) : trimmed.substring(4);
        _items.add(ChecklistItem(isCompleted: false, text: text));
      } else {
        _items.add(ChecklistItem(isCompleted: false, text: trimmed));
      }
    }

    if (_items.isEmpty) {
      _items.add(ChecklistItem(isCompleted: false, text: ''));
    }
  }

  String _serialize() {
    return _items.map((item) {
      final check = item.isCompleted ? '[x]' : '[ ]';
      return '$check ${item.text}';
    }).join('\n');
  }

  void _notifyChange() {
    widget.onContentChanged(_serialize());
    setState(() {});
  }

  void _addItem({int? afterIndex}) {
    final newItem = ChecklistItem(isCompleted: false, text: '');
    setState(() {
      if (afterIndex != null && afterIndex < _items.length) {
        _items.insert(afterIndex + 1, newItem);
      } else {
        _items.add(newItem);
      }
    });
    widget.onContentChanged(_serialize());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _getFocusNode(newItem.id).requestFocus();
      }
    });
  }

  void _removeItem(int index) {
    final removedId = _items[index].id;
    setState(() {
      if (_items.length > 1) {
        _items.removeAt(index);
        final nextFocusIndex = index > 0 ? index - 1 : 0;
        if (nextFocusIndex < _items.length) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              _getFocusNode(_items[nextFocusIndex].id).requestFocus();
            }
          });
        }
      } else {
        _items[0].text = '';
        _items[0].isCompleted = false;
      }
    });
    _focusNodes.remove(removedId)?.dispose();
    widget.onContentChanged(_serialize());
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryTextColor = isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary;
    final completedTextColor = isDark ? AppColors.darkTextTertiary : AppColors.lightTextTertiary;

    return Column(
      children: [
        ReorderableListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
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
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  // Checkbox toggle
                  GestureDetector(
                    onTap: () {
                      item.isCompleted = !item.isCompleted;
                      _notifyChange();
                    },
                    child: Padding(
                      padding: const EdgeInsets.only(right: 10),
                      child: Icon(
                        item.isCompleted ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                        size: 22,
                        color: item.isCompleted ? AppColors.accent : (isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary),
                      ),
                    ),
                  ),

                  // Inline text field
                  Expanded(
                    child: TextFormField(
                      key: ValueKey('input-${item.id}'),
                      focusNode: _getFocusNode(item.id),
                      initialValue: item.text,
                      style: TextStyle(
                        fontSize: 16,
                        color: item.isCompleted ? completedTextColor : primaryTextColor,
                        decoration: item.isCompleted ? TextDecoration.lineThrough : null,
                      ),
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        contentPadding: EdgeInsets.zero,
                        hintText: 'Task description...',
                      ),
                      onChanged: (val) {
                        item.text = val;
                        widget.onContentChanged(_serialize());
                      },
                      onFieldSubmitted: (_) => _addItem(afterIndex: index),
                    ),
                  ),

                  // Delete button
                  IconButton(
                    icon: Icon(
                      Icons.close,
                      size: 18,
                      color: isDark ? AppColors.darkTextTertiary : AppColors.lightTextTertiary,
                    ),
                    onPressed: () => _removeItem(index),
                  ),
                ],
              ),
            );
          },
        ),

        const SizedBox(height: 12),

        // Add task button
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: _addItem,
            icon: const Icon(Icons.add, size: 18, color: AppColors.primary),
            label: const Text('Add Item', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w600)),
          ),
        ),
      ],
    );
  }
}
