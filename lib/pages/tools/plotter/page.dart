import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:qunleashed/components/appbar.dart';
import '../../../theme/theme.dart';
import '../../../widgets/notification.dart';
import 'models.dart';
import 'parsing.dart';
import 'plotter_view.dart';
import 'ui.dart';

const double _maxContentWidth = 720;
const double _wideContentThreshold = 1000;

class PulsePlotterPage extends StatefulWidget {
  const PulsePlotterPage({
    super.key,
    this.initialBytes,
    this.initialName,
  });

  final Uint8List? initialBytes;
  final String? initialName;

  @override
  State<PulsePlotterPage> createState() => _PulsePlotterPageState();
}

class _PulsePlotterPageState extends State<PulsePlotterPage> {
  PlotData? _data;
  List<IrSignal> _signals = const [];
  IrSignal? _current;
  String? _fileName;
  bool _loading = false;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _fileName = widget.initialName;
    final bytes = widget.initialBytes;
    if (bytes != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _handleBytes(bytes));
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _handleBytes(Uint8List bytes) async {
    setState(() => _loading = true);
    try {
      final result = await compute(parsePlotterFile, bytes);
      if (!mounted) return;
      setState(() {
        _loading = false;
        if (result.signals.isNotEmpty) {
          _signals = result.signals;
          _current = result.signals.first;
          _data = _fromSignal(_current!);
        } else {
          _signals = const [];
          _current = null;
          _data = result.data;
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      final message =
          e is PlotterParseException ? e.message : 'Could not parse this file';
      context.showNotification(message, type: QNotificationType.error);
    }
  }

  PlotData? _fromSignal(IrSignal signal) {
    final pulses = signal.data;
    final frequency = signal.frequency;
    if (pulses == null || pulses.length < 2 || frequency == null) return null;
    return PlotData(centerFreqHz: frequency, pulses: pulses);
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(withData: true);
    if (result == null) return;
    final file = result.files.single;
    final bytes = file.bytes;
    if (bytes == null) {
      if (mounted) {
        context.showNotification(
          'Could not read the selected file',
          type: QNotificationType.error,
        );
      }
      return;
    }
    setState(() {
      _fileName = file.name;
      _data = null;
      _signals = const [];
      _current = null;
    });
    await _handleBytes(bytes);
  }

  void _onSelectSignal(IrSignal? signal) {
    if (signal == null) return;
    setState(() {
      _current = signal;
      _data = _fromSignal(signal);
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final hasContent = _data != null || _signals.isNotEmpty;
    return Scaffold(
      backgroundColor: colors.background,
      appBar: QPageAppBar(
        title: 'Pulse Plotter',
        subtitle: _fileName,
        showDeviceStatus: false,
        actions: [
          QPageAppBarAction(
            tooltip: 'Open signal file',
            icon: const Icon(Icons.folder_open_outlined),
            onPressed: _loading ? null : _pickFile,
          ),
        ],
      ),
      body: hasContent ? _buildContent(context) : _buildEmptyState(context),
    );
  }

  Widget _buildContent(BuildContext context) {
    return Scrollbar(
      controller: _scrollController,
      child: SingleChildScrollView(
        controller: _scrollController,
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 28),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final maxWidth = constraints.maxWidth >= _wideContentThreshold
                ? double.infinity
                : _maxContentWidth;
            return Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxWidth),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_signals.length > 1) ...[
                      _SignalSelector(
                        signals: _signals,
                        current: _current,
                        onChanged: _onSelectSignal,
                      ),
                      const SizedBox(height: 16),
                    ],
                    if (_data != null)
                      PlotterView(key: ValueKey(_data), data: _data!)
                    else
                      const _NoPlotNotice(),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final colors = context.appColors;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 32, 20, 28),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: _maxContentWidth),
            child: Column(
              children: [
                Container(
                  width: 76,
                  height: 76,
                  decoration: BoxDecoration(
                    color: colors.accent.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: _loading
                      ? Padding(
                          padding: const EdgeInsets.all(26),
                          child: CircularProgressIndicator(
                            strokeWidth: 3,
                            color: colors.accent,
                          ),
                        )
                      : Icon(Icons.show_chart, size: 38, color: colors.accent),
                ),
                const SizedBox(height: 18),
                Text(
                  _loading ? 'Parsing signal…' : 'No signal loaded',
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Pick a Sub-GHz, RFID or Infrared capture to\nvisualize and analyze its pulses.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: colors.textSecondary,
                    fontSize: 13,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 22),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _loading ? null : _pickFile,
                    icon: const Icon(Icons.file_upload_outlined, size: 20),
                    label: const Text('Select file'),
                    style: FilledButton.styleFrom(
                      backgroundColor: colors.accent,
                      foregroundColor: colors.onAccent,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 32),
                const _AboutSection(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NoPlotNotice extends StatelessWidget {
  const _NoPlotNotice();

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return PlotterCard(
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
      child: Text(
        'This signal has no plottable raw data.',
        textAlign: TextAlign.center,
        style: TextStyle(color: colors.textSecondary, fontSize: 13),
      ),
    );
  }
}

class _SignalSelector extends StatelessWidget {
  const _SignalSelector({
    required this.signals,
    required this.current,
    required this.onChanged,
  });

  final List<IrSignal> signals;
  final IrSignal? current;
  final ValueChanged<IrSignal?> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return DropdownButtonFormField<IrSignal>(
      initialValue: current,
      isExpanded: true,
      decoration: plotterFieldDecoration(context, label: 'Signal'),
      dropdownColor: colors.card,
      borderRadius: BorderRadius.circular(12),
      style: TextStyle(color: colors.textPrimary, fontSize: 14),
      items: [
        for (final (i, s) in signals.indexed)
          DropdownMenuItem(value: s, child: Text(s.name ?? 'Signal ${i + 1}')),
      ],
      onChanged: onChanged,
    );
  }
}

class _AboutSection extends StatelessWidget {
  const _AboutSection();

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final body =
        TextStyle(color: colors.textSecondary, fontSize: 13, height: 1.5);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'About Pulse plotter',
          style: TextStyle(
            color: colors.textPrimary,
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Sub-GHz/RFID/Infrared signal plotter is a tool to visualize raw '
          'signals (aka pulses) from various sources. Aside from visualizing '
          'saved signals, it can also help analyze raw captures.',
          style: body,
        ),
        const SizedBox(height: 10),
        Text('Accepted file formats:', style: body),
        Text('  • Sub-GHz RAW captures (.sub)', style: body),
        Text('  • RFID RAW captures (.raw)', style: body),
        Text('  • Infrared signal/remote files (.ir)', style: body),
        Text('  • other Flipper File Format RAW-compatible files', style: body),
        const SizedBox(height: 10),
        Text(
          'After parsing the file, the plotter will try to guess the signal '
          'modulation. You can also use the slicer to figure it out manually.',
          style: body,
        ),
      ],
    );
  }
}
