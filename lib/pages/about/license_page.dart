import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../../services/localization/l10n.dart';
import '../../theme/theme.dart';
import '../devices/device_scope.dart';

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

  /// Reads the licence and reflows it once, here rather than in `build`.
  ///
  /// [_normalize] splits the whole file into its 674 lines and reassembles
  /// them through two `StringBuffer`s, and it used to run from `build` - for a
  /// string that arrives once and never changes afterwards. #344 cut the rate
  /// of those rebuilds by taking the device-info poll off this page (it was
  /// that issue's sharpest example, and
  /// `test/device_scope_client_of_test.dart` has the case pinning the poll no
  /// longer reaching it); what was left was the work itself, on every other
  /// rebuild - a theme change, a locale change, a `MaterialApp` rebuild from
  /// either. #408.
  ///
  /// Which branch `_buildBody` draws is unchanged: [_text] is still null until
  /// this completes, so the spinner is still what a loading page shows, and the
  /// failure path still sets [_error]. **Not a normalised empty string**, which
  /// is the one substitution moving the reflow invites and would cost the error
  /// view - [_error] is tested first, so a null one with [_text] set draws a
  /// blank page instead. `test/license_page_test.dart` owns that argument and
  /// the mutation that measures it.
  Future<void> _load() async {
    try {
      final value = await rootBundle.loadString('LICENSE');
      final text = _normalize(value);
      if (!mounted) return;
      setState(() => _text = text);
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
        client: DeviceScope.clientOf(context),
        title: context.l10n.licenseTitle,
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
            text,
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
