import 'package:flutter/material.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../shared/models/tag_entity.dart';

class TagChip extends StatelessWidget {
  final TagEntity tag;
  final bool isSelected;
  final VoidCallback? onTap;
  final VoidCallback? onDeleted;
  final bool compact;

  const TagChip({
    super.key,
    required this.tag,
    this.isSelected = false,
    this.onTap,
    this.onDeleted,
    this.compact = false,
  });

  static Color parseColor(String hex) {
    try {
      final clean = hex.replaceAll('#', '').replaceFirst('0x', '');
      if (clean.length == 6) {
        return Color(int.parse('FF$clean', radix: 16));
      } else if (clean.length == 8) {
        return Color(int.parse(clean, radix: 16));
      }
    } catch (_) {}
    return const Color(0xFF2563EB);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final tagColor = parseColor(tag.colorHex);

    final bgColor = isSelected
        ? tagColor
        : tagColor.withAlpha(isDark ? 35 : 25);
    final textColor = isSelected
        ? Colors.white
        : (isDark ? Colors.white.withAlpha(230) : Colors.black87);
    final borderColor = isSelected
        ? tagColor
        : tagColor.withAlpha(isDark ? 70 : 60);

    return Material(
      color: bgColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(compact ? 6 : AppConstants.radiusSmall),
        side: BorderSide(color: borderColor, width: 1.0),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(compact ? 6 : AppConstants.radiusSmall),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 6 : 8,
            vertical: compact ? 2 : 4,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: compact ? 6 : 8,
                height: compact ? 6 : 8,
                decoration: BoxDecoration(
                  color: isSelected ? Colors.white : tagColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 5),
              Text(
                tag.name,
                style: TextStyle(
                  fontSize: compact ? 11 : 12,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                  color: textColor,
                ),
              ),
              if (onDeleted != null) ...[
                const SizedBox(width: 4),
                GestureDetector(
                  onTap: onDeleted,
                  child: Icon(
                    Icons.close_rounded,
                    size: compact ? 12 : 14,
                    color: textColor.withAlpha(180),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
