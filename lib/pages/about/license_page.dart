import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../../theme.dart';
import 'package:qunleashed/components/appbar.dart';

class AppLicensePage extends StatefulWidget {
  const AppLicensePage({super.key});

  @override
  State<AppLicensePage> createState() => _AppLicensePageState();
}

class _AppLicensePageState extends State<AppLicensePage> {
  final ScrollController _controller = ScrollController();
  String? _text;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final value = await rootBundle.loadString('LICENSE');
      if (!mounted) return;
      setState(() => _text = value);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Scaffold(
      backgroundColor: colors.background,
      appBar: QPageAppBar(
        title: 'GPL v3 License',
        backgroundColor: colors.accent,
        foregroundColor: colors.onAccent,
      ),
      body: _buildBody(colors),
    );
  }

  Widget _buildBody(QAppColors colors) {
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            _error!,
            textAlign: TextAlign.center,
            style: TextStyle(color: colors.danger),
          ),
        ),
      );
    }
    final text = _text;
    if (text == null) {
      return Center(child: CircularProgressIndicator(color: colors.accent));
    }
    return SafeArea(
      top: false,
      child: Scrollbar(
        controller: _controller,
        child: SingleChildScrollView(
          controller: _controller,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          child: SelectableText(
            _normalize(text),
            style: TextStyle(
              color: colors.textPrimary,
              fontSize: 13,
              height: 1.45,
            ),
          ),
        ),
      ),
    );
  }

  static String _normalize(String raw) {
    final lines = raw.split('\n');
    final out = StringBuffer();
    final buffer = StringBuffer();

    void flush() {
      if (buffer.isNotEmpty) {
        out.writeln(buffer.toString().trim());
        buffer.clear();
      }
    }

    for (final line in lines) {
      final trimmed = line.trimRight();
      if (trimmed.isEmpty) {
        flush();
        out.writeln();
        continue;
      }
      final indented =
          line.startsWith(' ') && line.trimLeft().length < line.length - 2;
      if (indented) {
        flush();
        out.writeln(trimmed);
        continue;
      }
      if (buffer.isNotEmpty) buffer.write(' ');
      buffer.write(trimmed.trimLeft());
    }
    flush();
    return out.toString();
  }
}
