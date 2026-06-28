import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../../theme/theme.dart';
import '../../../widgets/notification.dart';
import 'models.dart';
import 'parsing.dart';
import 'plotter_view.dart';

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

  @override
  void initState() {
    super.initState();
    _fileName = widget.initialName;
    final bytes = widget.initialBytes;
    if (bytes != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _handleBytes(bytes));
    }
  }

  void _handleBytes(Uint8List bytes) {
    try {
      final result = parsePlotterFile(bytes);
      setState(() {
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
    } on PlotterParseException catch (e) {
      if (!mounted) return;
      context.showNotification(e.message, type: QNotificationType.error);
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
    _handleBytes(bytes);
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
    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        backgroundColor: colors.accent,
        foregroundColor: colors.onAccent,
        title: const Text('Pulse Plotter'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _FilePickRow(fileName: _fileName, onPick: _pickFile),
          if (_signals.length > 1) ...[
            const SizedBox(height: 16),
            _SignalSelector(
              signals: _signals,
              current: _current,
              onChanged: _onSelectSignal,
            ),
          ],
          if (_data != null) ...[
            const SizedBox(height: 20),
            PlotterView(key: ValueKey(_data), data: _data!),
          ],
          const SizedBox(height: 28),
          const _AboutSection(),
        ],
      ),
    );
  }
}

class _FilePickRow extends StatelessWidget {
  const _FilePickRow({required this.fileName, required this.onPick});

  final String? fileName;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Row(
      children: [
        ElevatedButton.icon(
          onPressed: onPick,
          icon: const Icon(Icons.file_upload, size: 18),
          label: const Text('Select file'),
          style: ElevatedButton.styleFrom(
            backgroundColor: colors.accent,
            foregroundColor: colors.onAccent,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            fileName ?? 'No file selected',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: colors.textMuted, fontSize: 13),
          ),
        ),
      ],
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
      decoration: const InputDecoration(
        labelText: 'Select signal',
        border: OutlineInputBorder(),
        isDense: true,
      ),
      dropdownColor: colors.card,
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
    final body = TextStyle(color: colors.textSecondary, fontSize: 13, height: 1.5);
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
