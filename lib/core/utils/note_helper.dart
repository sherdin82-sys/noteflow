import 'dart:convert';

class NoteHelper {
  /// Extracts clean readable plain text from either plain text or a Quill Delta JSON string
  static String extractPlainText(String content) {
    if (content.isEmpty) return '';

    final trimmed = content.trim();
    if (trimmed.startsWith('[') && trimmed.endsWith(']')) {
      try {
        final List<dynamic> operations = jsonDecode(trimmed) as List<dynamic>;
        final buffer = StringBuffer();
        for (final op in operations) {
          if (op is Map<String, dynamic> && op.containsKey('insert')) {
            final insert = op['insert'];
            if (insert is String) {
              buffer.write(insert);
            }
          }
        }
        return buffer.toString().trim();
      } catch (_) {
        // Fallback to raw string if JSON parsing fails
        return content;
      }
    }

    return content;
  }

  /// Calculates word count
  static int wordCount(String text) {
    final plain = extractPlainText(text).trim();
    if (plain.isEmpty) return 0;
    return plain.split(RegExp(r'\s+')).length;
  }
}
