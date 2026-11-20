import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../shared/models/tag_entity.dart';
import 'tag_chip.dart';

class TagDialog extends StatefulWidget {
  final TagEntity? existingTag;
  final List<TagEntity> allTags;

  const TagDialog({
    super.key,
    this.existingTag,
    required this.allTags,
  });

  static const List<String> tagColorPalette = [
    '0xFFEF4444', // Red
    '0xFFF97316', // Orange
    '0xFFF59E0B', // Amber
    '0xFF10B981', // Emerald
    '0xFF06B6D4', // Cyan
    '0xFF2563EB', // Cobalt Blue
    '0xFF6366F1', // Indigo
    '0xFF8B5CF6', // Purple
    '0xFFEC4899', // Pink
    '0xFF14B8A6', // Teal
    '0xFF84CC16', // Lime
    '0xFF64748B', // Slate
  ];

  static Future<TagEntity?> show({
    required BuildContext context,
    TagEntity? existingTag,
    required List<TagEntity> allTags,
  }) {
    return showDialog<TagEntity>(
      context: context,
      builder: (_) => TagDialog(
        existingTag: existingTag,
        allTags: allTags,
      ),
    );
  }

  @override
  State<TagDialog> createState() => _TagDialogState();
}

class _TagDialogState extends State<TagDialog> {
  late final TextEditingController _nameController;
  late String _selectedColorHex;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.existingTag?.name ?? '');
    _selectedColorHex = widget.existingTag?.colorHex ?? TagDialog.tagColorPalette[5]; // Cobalt default
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _save() {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _errorMessage = 'Tag name cannot be empty');
      return;
    }

    final isDuplicate = widget.allTags.any((t) =>
        (widget.existingTag == null || t.id != widget.existingTag!.id) &&
        TagEntity.namesEqual(t.name, name));

    if (isDuplicate) {
      setState(() => _errorMessage = 'A tag with this name already exists');
      return;
    }

    final now = DateTime.now();
    final tag = widget.existingTag != null
        ? widget.existingTag!.copyWith(
            name: name,
            colorHex: _selectedColorHex,
            updatedAt: now,
          )
        : TagEntity(
            id: const Uuid().v4(),
            name: name,
            colorHex: _selectedColorHex,
            createdAt: now,
            updatedAt: now,
          );

    Navigator.pop(context, tag);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return AlertDialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppConstants.radiusMedium),
      ),
      title: Text(
        widget.existingTag != null ? 'Edit Tag' : 'New Tag',
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _nameController,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(
                hintText: 'Tag name (e.g. Urgent, Work)',
                errorText: _errorMessage,
              ),
              onChanged: (_) {
                if (_errorMessage != null) {
                  setState(() => _errorMessage = null);
                }
              },
              onSubmitted: (_) => _save(),
            ),
            const SizedBox(height: 16),
            Text(
              'TAG COLOR',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2,
                color: isDark ? AppColors.darkTextTertiary : AppColors.lightTextTertiary,
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: TagDialog.tagColorPalette.map((colorHex) {
                final color = TagChip.parseColor(colorHex);
                final isSelected = _selectedColorHex == colorHex;

                return GestureDetector(
                  onTap: () => setState(() => _selectedColorHex = colorHex),
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: isSelected ? Colors.white : Colors.transparent,
                        width: 2.5,
                      ),
                      boxShadow: isSelected
                          ? [
                              BoxShadow(
                                color: color.withAlpha(120),
                                blurRadius: 6,
                                spreadRadius: 1,
                              ),
                            ]
                          : null,
                    ),
                    child: isSelected
                        ? const Icon(Icons.check, size: 16, color: Colors.white)
                        : null,
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _save,
          child: Text(widget.existingTag != null ? 'Save' : 'Create'),
        ),
      ],
    );
  }
}
