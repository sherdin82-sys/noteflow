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
      if (t == '[ ]' ||
          t == '[x]' ||
          t == '- [ ]' ||
          t == '- [x]' ||
          t.startsWith('[ ] ') ||
          t.startsWith('[x] ') ||
          t.startsWith('- [ ] ') ||
          t.startsWith('- [x] ')) {
        return true;
      }
    }
    return false;
  }

  /// Explicitly converts legacy Markdown or plain text into a valid native Quill Delta JSON string.
  /// If [markdown] is already a valid Delta JSON string, it is returned as-is.
  static String markdownToDeltaJson(String markdown) {
    if (markdown.isEmpty) {
      return jsonEncode([
        {'insert': '\n'}
      ]);
    }

    final trimmed = markdown.trim();
    if (isDeltaContent(trimmed)) {
      return trimmed;
    }

    final lines = markdown.split('\n');
    final List<Map<String, dynamic>> ops = [];

    for (int i = 0; i < lines.length; i++) {
      var line = lines[i];
      final Map<String, dynamic> blockAttrs = {};

      // Detect block prefixes
      if (line.startsWith('### ')) {
        blockAttrs['header'] = 3;
        line = line.substring(4);
      } else if (line.startsWith('## ')) {
        blockAttrs['header'] = 2;
        line = line.substring(3);
      } else if (line.startsWith('# ')) {
        blockAttrs['header'] = 1;
        line = line.substring(2);
      } else if (line == '[ ]' || line == '- [ ]') {
        blockAttrs['list'] = 'unchecked';
        line = '';
      } else if (line == '[x]' || line == '- [x]') {
        blockAttrs['list'] = 'checked';
        line = '';
      } else if (line.startsWith('[ ] ') || line.startsWith('- [ ] ')) {
        blockAttrs['list'] = 'unchecked';
        line = line.startsWith('- [ ] ') ? line.substring(6) : line.substring(4);
      } else if (line.startsWith('[x] ') || line.startsWith('- [x] ')) {
        blockAttrs['list'] = 'checked';
        line = line.startsWith('- [x] ') ? line.substring(6) : line.substring(4);
      } else if (line.startsWith('- ') || line.startsWith('* ') || line.startsWith('• ')) {
        blockAttrs['list'] = 'bullet';
        line = line.substring(2);
      } else if (RegExp(r'^\d+\.\s').hasMatch(line)) {
        blockAttrs['list'] = 'ordered';
        line = line.replaceFirst(RegExp(r'^\d+\.\s'), '');
      } else if (line.startsWith('> ')) {
        blockAttrs['blockquote'] = true;
        line = line.substring(2);
      } else if (line.startsWith('```')) {
        blockAttrs['code-block'] = true;
        line = line.substring(3);
      }

      // Parse inline styles in line: **bold**, *italic*, ~~strike~~, `code`, <u>underline</u>, [text](url)
      if (line.isNotEmpty) {
        _parseInlineMarkdownToOps(line, ops);
      }

      // Append newline with block attributes
      if (blockAttrs.isNotEmpty) {
        ops.add({'insert': '\n', 'attributes': blockAttrs});
      } else {
        ops.add({'insert': '\n'});
      }
    }

    return jsonEncode(_simplifyOps(ops));
  }

  /// Parses a single line of markdown text into a list of [NoteSpan]s preserving inline styles.
  static List<NoteSpan> parseInlineMarkdown(String line) {
    if (line.isEmpty) return const [];

    final List<NoteSpan> spans = [];
    final inlineRegex = RegExp(
      r'(\*\*\*(.+?)\*\*\*)|(___(.+?)___)|(\*\*(.+?)\*\*)|(__([^_]+)__)|(\*([^*]+)\*)|(_([^_]+)_)|(~~(.+?)~~)|(`(.+?)`)|(<u>(.+?)</u>)|\[([^\]]+)\]\(([^)]+)\)',
    );

    int lastEnd = 0;
    for (final match in inlineRegex.allMatches(line)) {
      if (match.start > lastEnd) {
        spans.add(NoteSpan(text: line.substring(lastEnd, match.start)));
      }

      String text = '';
      bool isBold = false;
      bool isItalic = false;
      bool isStrike = false;
      bool isCode = false;
      bool isUnderline = false;
      String? link;

      if (match.group(1) != null) {
        text = match.group(2)!;
        isBold = true;
        isItalic = true;
      } else if (match.group(3) != null) {
        text = match.group(4)!;
        isBold = true;
        isItalic = true;
      } else if (match.group(5) != null) {
        text = match.group(6)!;
        isBold = true;
      } else if (match.group(7) != null) {
        text = match.group(8)!;
        isBold = true;
      } else if (match.group(9) != null) {
        text = match.group(10)!;
        isItalic = true;
      } else if (match.group(11) != null) {
        text = match.group(12)!;
        isItalic = true;
      } else if (match.group(13) != null) {
        text = match.group(14)!;
        isStrike = true;
      } else if (match.group(15) != null) {
        text = match.group(16)!;
        isCode = true;
      } else if (match.group(17) != null) {
        text = match.group(18)!;
        isUnderline = true;
      } else if (match.group(19) != null) {
        text = match.group(19)!;
        link = match.group(20);
      }

      spans.add(NoteSpan(
        text: text,
        isBold: isBold,
        isItalic: isItalic,
        isStrike: isStrike,
        isCode: isCode,
        isUnderline: isUnderline,
        link: link,
      ));

      lastEnd = match.end;
    }

    if (lastEnd < line.length) {
      spans.add(NoteSpan(text: line.substring(lastEnd)));
    }

    return spans;
  }

  static void _parseInlineMarkdownToOps(String line, List<Map<String, dynamic>> ops) {
    final spans = parseInlineMarkdown(line);
    for (final span in spans) {
      final Map<String, dynamic> attrs = {};
      if (span.isBold) attrs['bold'] = true;
      if (span.isItalic) attrs['italic'] = true;
      if (span.isStrike) attrs['strike'] = true;
      if (span.isCode) attrs['code'] = true;
      if (span.isUnderline) attrs['underline'] = true;
      if (span.link != null) attrs['link'] = span.link;

      if (attrs.isNotEmpty) {
        ops.add({'insert': span.text, 'attributes': attrs});
      } else {
        ops.add({'insert': span.text});
      }
    }
  }

  /// Parses note content (either Quill Delta JSON or Markdown/plain text) into
  /// a list of [NoteSpanLine]s with block formatting and inline spans.
  static List<NoteSpanLine> parseToRichLines(String content) {
    if (content.isEmpty) return const [];

    final deltaJson = isDeltaContent(content) ? content : markdownToDeltaJson(content);

    try {
      final List<dynamic> ops = jsonDecode(deltaJson) as List<dynamic>;
      final List<NoteSpanLine> lines = [];
      List<NoteSpan> currentSpans = [];
      int currentOrderedIndex = 0;

      for (final op in ops) {
        if (op is! Map<String, dynamic>) continue;
        final insert = op['insert'];
        final attributes = op['attributes'] as Map<String, dynamic>? ?? {};

        if (insert is Map<String, dynamic>) {
          if (insert.containsKey('image')) {
            currentSpans.add(const NoteSpan(text: '[Image]', isImage: true));
          } else if (insert.containsKey('divider')) {
            if (currentSpans.isNotEmpty) {
              lines.add(NoteSpanLine(spans: List.of(currentSpans)));
              currentSpans.clear();
            }
            lines.add(const NoteSpanLine(spans: [NoteSpan(text: '———')]));
          }
          continue;
        }

        if (insert is! String) continue;

        final bool isBold = attributes['bold'] == true;
        final bool isItalic = attributes['italic'] == true;
        final bool isUnderline = attributes['underline'] == true;
        final bool isStrike = attributes['strike'] == true;
        final bool isCode = attributes['code'] == true;
        final String? link = attributes['link'] is String ? attributes['link'] as String : null;

        if (!insert.contains('\n')) {
          currentSpans.add(NoteSpan(
            text: insert,
            isBold: isBold,
            isItalic: isItalic,
            isUnderline: isUnderline,
            isStrike: isStrike,
            isCode: isCode,
            link: link,
          ));
        } else {
          final parts = insert.split('\n');
          for (int i = 0; i < parts.length; i++) {
            final part = parts[i];
            if (part.isNotEmpty) {
              currentSpans.add(NoteSpan(
                text: part,
                isBold: isBold,
                isItalic: isItalic,
                isUnderline: isUnderline,
                isStrike: isStrike,
                isCode: isCode,
                link: link,
              ));
            }

            if (i < parts.length - 1) {
              final int? header = attributes['header'] is int
                  ? attributes['header'] as int
                  : (attributes['header'] is String ? int.tryParse(attributes['header'] as String) : null);
              final String? listType = attributes['list'] is String ? attributes['list'] as String : null;
              final bool isBlockquote = attributes['blockquote'] == true;
              final bool isCodeBlock = attributes['code-block'] == true;

              int? listIdx;
              if (listType == 'ordered') {
                currentOrderedIndex++;
                listIdx = currentOrderedIndex;
              } else {
                currentOrderedIndex = 0;
              }

              lines.add(NoteSpanLine(
                spans: List.of(currentSpans),
                header: header,
                listType: listType,
                listIndex: listIdx,
                isBlockquote: isBlockquote,
                isCodeBlock: isCodeBlock,
              ));
              currentSpans.clear();
            }
          }
        }
      }

      if (currentSpans.isNotEmpty) {
        lines.add(NoteSpanLine(spans: List.of(currentSpans)));
      }

      return lines;
    } catch (_) {
      return content.split('\n').map((line) => NoteSpanLine(spans: [NoteSpan(text: line)])).toList();
    }
  }

  static List<Map<String, dynamic>> _simplifyOps(List<Map<String, dynamic>> ops) {
    if (ops.isEmpty) {
      return [
        {'insert': '\n'}
      ];
    }

    final List<Map<String, dynamic>> merged = [];
    for (final op in ops) {
      if (merged.isEmpty) {
        merged.add(Map<String, dynamic>.from(op));
        continue;
      }

      final prev = merged.last;
      final prevInsert = prev['insert'];
      final currInsert = op['insert'];

      final prevAttrs = prev['attributes'] as Map<String, dynamic>?;
      final currAttrs = op['attributes'] as Map<String, dynamic>?;

      final sameAttrs = _mapsEqual(prevAttrs, currAttrs);

      if (prevInsert is String && currInsert is String && sameAttrs && !prevInsert.endsWith('\n')) {
        prev['insert'] = prevInsert + currInsert;
      } else {
        merged.add(Map<String, dynamic>.from(op));
      }
    }

    return merged;
  }

  static bool _mapsEqual(Map<String, dynamic>? a, Map<String, dynamic>? b) {
    if (a == null && b == null) return true;
    if (a == null || b == null) return false;
    if (a.length != b.length) return false;
    for (final key in a.keys) {
      if (!b.containsKey(key) || a[key] != b[key]) return false;
    }
    return true;
  }

  /// Converts a Quill Delta JSON string into clean formatted Markdown/plain text.
  /// Used for previews or exporting.
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

      if (lines.isEmpty) return '';
      if (lines.length == 1 && lines.first.isEmpty) return '';

      return lines.map((l) => l.toFormattedString()).join('\n');
    } catch (_) {
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

    final lines = content.split('\n');
    final buffer = StringBuffer();
    for (final line in lines) {
      var t = line.trim();
      if (t == '[ ]' || t == '[x]' || t == '- [ ]' || t == '- [x]') {
        continue;
      }
      if (t.startsWith('[ ] ') || t.startsWith('[x] ')) {
        t = t.substring(4);
      } else if (t.startsWith('- [ ] ') || t.startsWith('- [x] ')) {
        t = t.substring(6);
      }
      t = t.replaceAll(RegExp(r'\s*<!--id:.*?-->'), '');
      if (t.isNotEmpty) {
        buffer.writeln(t);
      }
    }
    return buffer.toString().trim();
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
      final isUnderline = attributes['underline'] == true;

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
      if (isUnderline) {
        core = '<u>$core</u>';
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

/// Represents a styled text span extracted from rich note content.
class NoteSpan {
  final String text;
  final bool isBold;
  final bool isItalic;
  final bool isUnderline;
  final bool isStrike;
  final bool isCode;
  final String? link;
  final bool isImage;

  const NoteSpan({
    required this.text,
    this.isBold = false,
    this.isItalic = false,
    this.isUnderline = false,
    this.isStrike = false,
    this.isCode = false,
    this.link,
    this.isImage = false,
  });

  @override
  String toString() => 'NoteSpan("$text", bold: $isBold, italic: $isItalic, code: $isCode)';
}

/// Represents a single line of rich spans along with block formatting attributes.
class NoteSpanLine {
  final List<NoteSpan> spans;
  final int? header;
  final String? listType;
  final int? listIndex;
  final bool isBlockquote;
  final bool isCodeBlock;

  const NoteSpanLine({
    required this.spans,
    this.header,
    this.listType,
    this.listIndex,
    this.isBlockquote = false,
    this.isCodeBlock = false,
  });

  bool get isEmpty => spans.isEmpty || spans.every((s) => s.text.trim().isEmpty);

  String get plainText => spans.map((s) => s.text).join();

  @override
  String toString() => 'NoteSpanLine(header: $header, list: $listType, spans: $spans)';
}

