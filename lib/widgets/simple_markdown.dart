import 'package:flutter/material.dart';

class SimpleMarkdown extends StatelessWidget {
  const SimpleMarkdown({
    super.key,
    required this.data,
    this.textColor,
    this.mutedColor,
  });

  final String data;
  final Color? textColor;
  final Color? mutedColor;

  @override
  Widget build(BuildContext context) {
    final blocks = _MarkdownParser.parse(data);
    final baseTextColor = textColor ?? Theme.of(context).colorScheme.onSurface;
    final secondaryColor = mutedColor ?? baseTextColor.withValues(alpha: 0.72);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final block in blocks)
          Padding(
            padding: EdgeInsets.only(bottom: block.tight ? 8 : 14),
            child: switch (block) {
              _HeadingBlock(:final text, :final level) => Text(
                  text,
                  style: TextStyle(
                    fontSize: switch (level) {
                      1 => 24,
                      2 => 20,
                      _ => 16,
                    },
                    height: 1.2,
                    fontWeight: FontWeight.w700,
                    color: baseTextColor,
                  ),
                ),
              _BulletBlock(:final text) => Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 2, right: 8),
                      child: Text(
                        '•',
                        style: TextStyle(
                          fontSize: 16,
                          height: 1.35,
                          color: baseTextColor,
                        ),
                      ),
                    ),
                    Expanded(
                      child: _MarkdownTextSpan(
                        text,
                        textColor: baseTextColor,
                        secondaryColor: secondaryColor,
                      ),
                    ),
                  ],
                ),
              _CodeBlock(:final text) => Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
                  ),
                  child: SelectableText(
                    text,
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.45,
                      fontFamily: 'monospace',
                      color: baseTextColor,
                    ),
                  ),
                ),
              _ParagraphBlock(:final text, :final quote) => Container(
                  padding: quote ? const EdgeInsets.only(left: 12) : EdgeInsets.zero,
                  decoration: quote
                      ? BoxDecoration(
                          border: Border(
                            left: BorderSide(
                              color: secondaryColor.withValues(alpha: 0.5),
                              width: 3,
                            ),
                          ),
                        )
                      : null,
                  child: _MarkdownTextSpan(
                    text,
                    textColor: quote ? secondaryColor : baseTextColor,
                    secondaryColor: secondaryColor,
                  ),
                ),
            },
          ),
      ],
    );
  }
}

class _MarkdownTextSpan extends StatelessWidget {
  const _MarkdownTextSpan(
    this.text, {
    required this.textColor,
    required this.secondaryColor,
  });

  final String text;
  final Color textColor;
  final Color secondaryColor;

  @override
  Widget build(BuildContext context) {
    final spans = _MarkdownParser.parseInline(
      text,
      textColor: textColor,
      secondaryColor: secondaryColor,
    );
    return SelectableText.rich(
      TextSpan(
        style: TextStyle(
          fontSize: 14,
          height: 1.45,
          color: textColor,
        ),
        children: spans,
      ),
    );
  }
}

sealed class _MarkdownBlock {
  const _MarkdownBlock({this.tight = false});

  final bool tight;
}

class _HeadingBlock extends _MarkdownBlock {
  const _HeadingBlock(this.text, this.level) : super();

  final String text;
  final int level;
}

class _ParagraphBlock extends _MarkdownBlock {
  const _ParagraphBlock(this.text, {this.quote = false, super.tight});

  final String text;
  final bool quote;
}

class _BulletBlock extends _MarkdownBlock {
  const _BulletBlock(this.text) : super(tight: true);

  final String text;
}

class _CodeBlock extends _MarkdownBlock {
  const _CodeBlock(this.text) : super();

  final String text;
}

final class _MarkdownParser {
  static List<_MarkdownBlock> parse(String input) {
    final normalized = input.replaceAll('\r\n', '\n').trim();
    if (normalized.isEmpty) {
      return const [_ParagraphBlock('Empty changelog')];
    }

    final lines = normalized.split('\n');
    final blocks = <_MarkdownBlock>[];
    final paragraph = StringBuffer();
    final code = StringBuffer();
    var inCode = false;

    void flushParagraph() {
      final text = paragraph.toString().trim();
      paragraph.clear();
      if (text.isNotEmpty) {
        blocks.add(_ParagraphBlock(text));
      }
    }

    void flushCode() {
      final text = code.toString().trimRight();
      code.clear();
      if (text.isNotEmpty) {
        blocks.add(_CodeBlock(text));
      }
    }

    for (final rawLine in lines) {
      final line = rawLine.trimRight();
      final trimmed = line.trimLeft();

      if (trimmed.startsWith('```')) {
        flushParagraph();
        if (inCode) {
          flushCode();
        }
        inCode = !inCode;
        continue;
      }

      if (inCode) {
        code.writeln(line);
        continue;
      }

      if (trimmed.isEmpty) {
        flushParagraph();
        continue;
      }

      final heading = RegExp(r'^(#{1,3})\s+(.+)$').firstMatch(trimmed);
      if (heading != null) {
        flushParagraph();
        blocks.add(_HeadingBlock(heading.group(2)!.trim(), heading.group(1)!.length));
        continue;
      }

      final bullet = RegExp(r'^[-*]\s+(.+)$').firstMatch(trimmed);
      if (bullet != null) {
        flushParagraph();
        blocks.add(_BulletBlock(bullet.group(1)!.trim()));
        continue;
      }

      final ordered = RegExp(r'^\d+\.\s+(.+)$').firstMatch(trimmed);
      if (ordered != null) {
        flushParagraph();
        blocks.add(_BulletBlock(ordered.group(1)!.trim()));
        continue;
      }

      final quote = RegExp(r'^>\s?(.+)$').firstMatch(trimmed);
      if (quote != null) {
        flushParagraph();
        blocks.add(_ParagraphBlock(quote.group(1)!.trim(), quote: true));
        continue;
      }

      if (paragraph.isNotEmpty) {
        paragraph.write(' ');
      }
      paragraph.write(trimmed);
    }

    flushParagraph();
    if (inCode) {
      flushCode();
    }
    return blocks;
  }

  static List<InlineSpan> parseInline(
    String text, {
    required Color textColor,
    required Color secondaryColor,
  }) {
    final spans = <InlineSpan>[];
    final pattern = RegExp(
      r'(\[([^\]]+)\]\(([^)]+)\))|(\*\*([^*]+)\*\*)|(`([^`]+)`)',
    );
    var currentIndex = 0;

    for (final match in pattern.allMatches(text)) {
      if (match.start > currentIndex) {
        spans.add(TextSpan(text: text.substring(currentIndex, match.start)));
      }

      if (match.group(2) != null && match.group(3) != null) {
        spans.add(
          TextSpan(
            text: match.group(2),
            style: TextStyle(
              color: textColor,
              fontWeight: FontWeight.w600,
              decoration: TextDecoration.underline,
              decorationColor: secondaryColor,
            ),
          ),
        );
      } else if (match.group(5) != null) {
        spans.add(
          TextSpan(
            text: match.group(5),
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        );
      } else if (match.group(7) != null) {
        spans.add(
          TextSpan(
            text: match.group(7),
            style: TextStyle(
              fontFamily: 'monospace',
              backgroundColor: Colors.black.withValues(alpha: 0.06),
            ),
          ),
        );
      }

      currentIndex = match.end;
    }

    if (currentIndex < text.length) {
      spans.add(TextSpan(text: text.substring(currentIndex)));
    }

    return spans;
  }
}
