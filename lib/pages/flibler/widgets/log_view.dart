import 'package:flutter/material.dart';
import 'package:dartufbt/dartufbt.dart';

import '../../../components/cardlist.dart';
import '../../../theme/theme.dart';
import '../../../services/assembler/controller.dart';

class AssemblerLogView extends StatefulWidget {
  const AssemblerLogView({super.key, required this.controller});

  final AssemblerController controller;

  @override
  State<AssemblerLogView> createState() => _AssemblerLogViewState();
}

class _AssemblerLogViewState extends State<AssemblerLogView> {
  final ScrollController _scroll = ScrollController();
  bool _follow = true;
  int _lastCount = 0;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    final atBottom = _scroll.offset >= _scroll.position.maxScrollExtent - 24;
    if (atBottom != _follow) setState(() => _follow = atBottom);
  }

  void _scheduleFollow(int count) {
    if (!_follow || count == _lastCount) return;
    _lastCount = count;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients || !_follow) return;
      _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  Color _colorFor(AssemblerLine line, QAppColors colors) {
    if (line.kind == AssemblerLineKind.build) return colors.textPrimary;
    return switch (line.level) {
      UfbtLogLevel.debug => colors.textMuted,
      UfbtLogLevel.warning => Colors.amber.shade600,
      UfbtLogLevel.error || UfbtLogLevel.critical => colors.danger,
      _ => colors.textPrimary,
    };
  }

  static final RegExp _buildTag = RegExp(r'^\t([^\t]+)\t([\s\S]*)$');

  Widget _line(AssemblerLine line, QAppColors colors, TextStyle style) {
    if (line.kind == AssemblerLineKind.build) {
      final match = _buildTag.firstMatch(line.text);
      if (match != null) {
        return Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: '\t${match.group(1)}',
                style: style.copyWith(color: colors.accent),
              ),
              TextSpan(text: '\t${match.group(2)}'),
            ],
          ),
          style: style,
        );
      }
    }
    return Text(line.text.isEmpty ? ' ' : line.text, style: style);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final lines = widget.controller.lines;
        _scheduleFollow(lines.length);
        return DecoratedBox(
          decoration: BoxDecoration(
            color: colors.terminalBackground,
            borderRadius: BorderRadius.circular(kGroupedOuterRadius),
          ),
          child: Stack(
            children: [
              Positioned.fill(
                child: lines.isEmpty
                    ? Center(
                        child: Text(
                          'No output yet',
                          style: TextStyle(
                            color: colors.textMuted,
                            fontSize: 12,
                            fontFamily: 'monospace',
                          ),
                        ),
                      )
                    : Scrollbar(
                        controller: _scroll,
                        child: ListView.builder(
                          controller: _scroll,
                          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                          itemCount: lines.length,
                          itemBuilder: (context, index) {
                            final line = lines[index];
                            return _line(
                              line,
                              colors,
                              TextStyle(
                                color: _colorFor(line, colors),
                                fontSize: 11.5,
                                height: 1.45,
                                fontFamily: 'monospace',
                              ),
                            );
                          },
                        ),
                      ),
              ),
              if (!_follow)
                Positioned(
                  right: 12,
                  bottom: 12,
                  child: FloatingActionButton.small(
                    heroTag: 'assembler-log-follow',
                    backgroundColor: colors.accent,
                    foregroundColor: colors.onAccent,
                    onPressed: () {
                      setState(() => _follow = true);
                      if (_scroll.hasClients) {
                        _scroll.jumpTo(_scroll.position.maxScrollExtent);
                      }
                    },
                    child: const Icon(Icons.arrow_downward, size: 18),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
