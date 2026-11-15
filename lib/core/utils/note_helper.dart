import 'dart:convert';

class NoteHelper {
  /// Detects whether [content] is a valid Quill Delta JSON array.
  static bool isDeltaContent(String content) {
    if (content.isEmpty) return false;
    final trimmed = content.trim();
    if (!trimmed.startsWith('[') || !trimmed.endsWith(']')) return false;
    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is List && decoded.isNotEmpty) {
        return decoded.any((e) => e is Map && e.containsKey('insert'));
      }
    } catch (_) {}
    return false;
  }

  /// Detects whether [content] represents checklist items, either encoded as
  /// a Quill Delta (with `list: 'checked'` or `list: 'unchecked'`) or plain markdown text (`[ ] `, `[x] `).
  static bool isChecklistContent(String content) {
    if (content.isEmpty) return false;
    final trimmed = content.trim();

    if (isDeltaContent(trimmed)) {
      try {
        final List<dynamic> ops = jsonDecode(trimmed) as List<dynamic>;
        for (final op in ops) {
          if (op is Map<String, dynamic> && op.containsKey('attributes')) {
            final attrs = op['attributes'];
            if (attrs is Map && (attrs['list'] == 'checked' || attrs['list'] == 'unchecked')) {
              return true;
            }
          }
        }
      } catch (_) {}
      return false;
    }

    final lines = trimmed.split('\n');
    for (final line in lines) {
      final t = line.trim();
      if (t.startsWith('[ ] ') || t.startsWith('[x] ') || t.startsWith('- [ ] ') || t.startsWith('- [x] ')) {
        return true;
      }
    }
    return false;
  }

  /// Converts either a Quill Delta JSON string or formatted text into
  /// clean, human-readable formatted Markdown text for the editor.
  /// If [content] is already plain text or markdown, it is returned untouched.
  static String formatForEditor(String content) {
    if (content.isEmpty) return '';
    final trimmed = content.trim();
    if (!isDeltaContent(trimmed)) {
      return content;
    }

    try {
      final List<dynamic> operations = jsonDecode(trimmed) as List<dynamic>;
      final List<_DeltaLine> lines = [];
      _DeltaLine currentLine = _DeltaLine();

      for (final op in operations) {
        if (op is! Map<String, dynamic>) continue;
        final insert = op['insert'];
        final attributes = op['attributes'] as Map<String, dynamic>? ?? {};

        if (insert is Map<String, dynamic>) {
          if (insert.containsKey('image')) {
            final url = insert['image'];
            currentLine.spans.add(_DeltaSpan('![Image]($url)', {}));
          } else if (insert.containsKey('divider')) {
            lines.add(currentLine);
            currentLine = _DeltaLine();
            currentLine.spans.add(_DeltaSpan('---', {}));
            lines.add(currentLine);
            currentLine = _DeltaLine();
          }
          continue;
        }

        if (insert is! String) continue;

        final text = insert;
        if (!text.contains('\n')) {
          currentLine.spans.add(_DeltaSpan(text, attributes));
        } else {
          final parts = text.split('\n');
          for (int i = 0; i < parts.length; i++) {
            final part = parts[i];
            if (part.isNotEmpty) {
              currentLine.spans.add(_DeltaSpan(part, attributes));
            }

            if (i < parts.length - 1) {
              currentLine.applyBlockAttributes(attributes);
              lines.add(currentLine);
              currentLine = _DeltaLine();
            }
          }
        }
      }

      if (currentLine.spans.isNotEmpty) {
        lines.add(currentLine);
      }

      // If document is completely empty or just had a single blank line
      if (lines.isEmpty) return '';
      if (lines.length == 1 && lines.first.isEmpty) return '';

      return lines.map((l) => l.toFormattedString()).join('\n');
    } catch (_) {
      // In case of any unexpected JSON parsing error, fall back safely
      return extractPlainText(content);
    }
  }

  /// Extracts clean readable plain text from either plain text or a Quill Delta JSON string
  static String extractPlainText(String content) {
    if (content.isEmpty) return '';

    final trimmed = content.trim();
    if (isDeltaContent(trimmed)) {
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

class _DeltaSpan {
  final String text;
  final Map<String, dynamic> attributes;

  _DeltaSpan(this.text, [this.attributes = const {}]);

  String format() {
    if (text.isEmpty) return '';
    if (attributes.isEmpty) return text;

    // Isolate leading and trailing whitespace to preserve valid markdown delimiter syntax
    final leadingMatch = RegExp(r'^\s*').firstMatch(text);
    final leading = leadingMatch?.group(0) ?? '';
    final trailingMatch = RegExp(r'\s*$').firstMatch(text);
    final trailing = trailingMatch?.group(0) ?? '';

    if (leading.length == text.length) {
      return text;
    }

    var core = text.substring(leading.length, text.length - trailing.length);

    if (attributes['code'] == true) {
      core = '`$core`';
    } else {
      final isBold = attributes['bold'] == true;
      final isItalic = attributes['italic'] == true;
      final isStrike = attributes['strike'] == true;

      if (isBold && isItalic) {
        core = '***$core***';
      } else if (isBold) {
        core = '**$core**';
      } else if (isItalic) {
        core = '*$core*';
      }

      if (isStrike) {
        core = '~~$core~~';
      }
    }

    if (attributes['link'] is String) {
      final url = attributes['link'];
      core = '[$core]($url)';
    }

    return '$leading$core$trailing';
  }
}

class _DeltaLine {
  final List<_DeltaSpan> spans = [];
  final Map<String, dynamic> blockAttributes = {};

  bool get isEmpty => spans.isEmpty && blockAttributes.isEmpty;

  void applyBlockAttributes(Map<String, dynamic> attrs) {
    if (attrs.containsKey('header')) blockAttributes['header'] = attrs['header'];
    if (attrs.containsKey('list')) blockAttributes['list'] = attrs['list'];
    if (attrs.containsKey('blockquote')) blockAttributes['blockquote'] = attrs['blockquote'];
    if (attrs.containsKey('code-block')) blockAttributes['code-block'] = attrs['code-block'];
  }

  String toFormattedString() {
    String prefix = '';
    final header = blockAttributes['header'];
    if (header == 1 || header == '1') {
      prefix = '# ';
    } else if (header == 2 || header == '2') {
      prefix = '## ';
    } else if (header == 3 || header == '3') {
      prefix = '### ';
    }

    final list = blockAttributes['list'];
    if (list == 'checked') {
      prefix = '[x] ';
    } else if (list == 'unchecked') {
      prefix = '[ ] ';
    } else if (list == 'bullet') {
      prefix = '• ';
    } else if (list == 'ordered') {
      prefix = '1. ';
    }

    if (blockAttributes['blockquote'] == true) {
      prefix = '> ';
    }

    if (blockAttributes['code-block'] == true) {
      prefix = '    ';
    }

    final body = spans.map((s) => s.format()).join();
    if (body.isEmpty && prefix.isNotEmpty) {
      return prefix.trimRight();
    }
    return '$prefix$body';
  }
}
