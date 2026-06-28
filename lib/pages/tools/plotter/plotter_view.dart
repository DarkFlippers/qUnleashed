import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../../theme/theme.dart';
import 'analysis/slicer.dart';
import 'engine.dart';
import 'models.dart';
import 'plotter_painter.dart';

const List<({String text, String value})> _slicerOptions = [
  (text: 'PCM', value: 'PCM'),
  (text: 'PWM', value: 'PWM'),
  (text: 'PPM', value: 'PPM'),
  (text: 'MC', value: 'MC'),
  (text: 'DM', value: 'DM'),
  (text: 'NRZI', value: 'NRZI'),
  (text: 'CMI', value: 'CMI'),
  (text: 'PIWM', value: 'PIWM'),
];

class PlotterView extends StatefulWidget {
  const PlotterView({super.key, required this.data});

  final PlotData data;

  @override
  State<PlotterView> createState() => _PlotterViewState();
}

class _PlotterViewState extends State<PlotterView> {
  late PlotterEngine _engine;

  final _shortCtrl = TextEditingController();
  final _longCtrl = TextEditingController();
  final _syncCtrl = TextEditingController();
  final _gapCtrl = TextEditingController();
  String _modulation = '';

  double _width = 0;
  double _k = 1;
  double _tx = 0;
  double _lastScale = 1;

  double get _maxZoom {
    if (_width <= 0) return 1;
    final z = _engine.width / _width;
    return z < 1 ? 1 : z;
  }

  @override
  void initState() {
    super.initState();
    _engine = PlotterEngine(widget.data);
    _syncControlsFromEngine();
  }

  @override
  void didUpdateWidget(PlotterView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.data, widget.data)) {
      _engine = PlotterEngine(widget.data);
      _k = 1;
      _tx = 0;
      _syncControlsFromEngine();
      setState(() {});
    }
  }

  @override
  void dispose() {
    _shortCtrl.dispose();
    _longCtrl.dispose();
    _syncCtrl.dispose();
    _gapCtrl.dispose();
    super.dispose();
  }

  void _syncControlsFromEngine() {
    final s = _engine.slicer;
    _modulation = s.modulation;
    _shortCtrl.text = _fieldText(s.short);
    _longCtrl.text = _fieldText(s.long);
    _syncCtrl.text = _fieldText(s.sync);
    _gapCtrl.text = _fieldText(s.gap);
  }

  String _fieldText(double v) =>
      v.isFinite ? (v == v.roundToDouble() ? v.toInt().toString() : '$v') : '';

  double _parseField(TextEditingController ctrl) {
    final t = ctrl.text.trim();
    if (t.isEmpty) return double.nan;
    return double.tryParse(t) ?? double.nan;
  }

  void _onSlice() {
    final params = SlicerParams(
      modulation: _modulation,
      short: _parseField(_shortCtrl),
      long: _parseField(_longCtrl),
      sync: _parseField(_syncCtrl),
      gap: _parseField(_gapCtrl),
    );
    _engine.setSlicer(params);
    setState(() {});
  }

  void _setTransform(double k, double tx) {
    var nk = k.clamp(1.0, _maxZoom);
    var ntx = tx;
    if (ntx > 0) ntx = 0;
    if (ntx + _width * nk < _width) ntx = _width - _width * nk;
    if (nk == _k && ntx == _tx) return;
    setState(() {
      _k = nk;
      _tx = ntx;
    });
  }

  void _zoom(double factor, double focalX) {
    final oldK = _k;
    final newK = (_k * factor).clamp(1.0, _maxZoom);
    if (newK == oldK) return;
    final newTx = focalX - (focalX - _tx) * (newK / oldK);
    _setTransform(newK, newTx);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.data.centerFreqHz > 0)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              'Frequency: ${widget.data.centerFreqHz} Hz',
              style: TextStyle(color: colors.textSecondary, fontSize: 13),
            ),
          ),
        LayoutBuilder(
          builder: (context, constraints) {
            _width = constraints.maxWidth;
            final clampedTx = _clampTx(_tx, _k);
            if (clampedTx != _tx) _tx = clampedTx;
            return Listener(
              onPointerSignal: (event) {
                if (event is PointerScrollEvent) {
                  final factor = event.scrollDelta.dy < 0 ? 1.1 : 1 / 1.1;
                  _zoom(factor, event.localPosition.dx);
                }
              },
              child: GestureDetector(
                onScaleStart: (_) => _lastScale = 1,
                onScaleUpdate: (details) {
                  if (details.pointerCount >= 2) {
                    final factor = details.scale / _lastScale;
                    _lastScale = details.scale;
                    _zoom(factor, details.localFocalPoint.dx);
                  } else {
                    _setTransform(_k, _tx + details.focalPointDelta.dx);
                  }
                },
                child: ClipRect(
                  child: SizedBox(
                    width: _width,
                    height: kPlotHeight,
                    child: CustomPaint(
                      painter: PulsePlotterPainter(
                        pulses: _engine.data.pulses,
                        dataWidth: _engine.width,
                        hints: _engine.hints,
                        altHints: _engine.altHints,
                        transform: PlotTransform(_k, _tx),
                        maxZoom: _maxZoom,
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 16),
        _SlicerControls(
          modulation: _modulation,
          shortCtrl: _shortCtrl,
          longCtrl: _longCtrl,
          syncCtrl: _syncCtrl,
          gapCtrl: _gapCtrl,
          onModulationChanged: (v) => setState(() => _modulation = v ?? ''),
          onSlice: _onSlice,
        ),
        const SizedBox(height: 16),
        _ReportPanel(report: _engine.report),
      ],
    );
  }

  double _clampTx(double tx, double k) {
    var ntx = tx;
    if (ntx > 0) ntx = 0;
    if (ntx + _width * k < _width) ntx = _width - _width * k;
    return ntx;
  }
}

class _SlicerControls extends StatelessWidget {
  const _SlicerControls({
    required this.modulation,
    required this.shortCtrl,
    required this.longCtrl,
    required this.syncCtrl,
    required this.gapCtrl,
    required this.onModulationChanged,
    required this.onSlice,
  });

  final String modulation;
  final TextEditingController shortCtrl;
  final TextEditingController longCtrl;
  final TextEditingController syncCtrl;
  final TextEditingController gapCtrl;
  final ValueChanged<String?> onModulationChanged;
  final VoidCallback onSlice;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final selected =
        _slicerOptions.any((o) => o.value == modulation) ? modulation : null;
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      crossAxisAlignment: WrapCrossAlignment.end,
      children: [
        SizedBox(
          width: 120,
          child: DropdownButtonFormField<String>(
            initialValue: selected,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Slicer',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            dropdownColor: colors.card,
            items: [
              for (final o in _slicerOptions)
                DropdownMenuItem(value: o.value, child: Text(o.text)),
            ],
            onChanged: onModulationChanged,
          ),
        ),
        _NumberField(label: 'Short', controller: shortCtrl),
        _NumberField(label: 'Long', controller: longCtrl),
        _NumberField(label: 'Sync', controller: syncCtrl),
        _NumberField(label: 'Gap', controller: gapCtrl),
        SizedBox(
          height: 48,
          child: ElevatedButton.icon(
            onPressed: onSlice,
            icon: const Icon(Icons.content_cut, size: 18),
            label: const Text('Slice'),
            style: ElevatedButton.styleFrom(
              backgroundColor: colors.accent,
              foregroundColor: colors.onAccent,
            ),
          ),
        ),
      ],
    );
  }
}

class _NumberField extends StatelessWidget {
  const _NumberField({required this.label, required this.controller});

  final String label;
  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 90,
      child: TextField(
        controller: controller,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          isDense: true,
        ),
      ),
    );
  }
}

class _ReportPanel extends StatelessWidget {
  const _ReportPanel({required this.report});

  final PlotterReport report;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final mono = TextStyle(
      color: colors.textSecondary,
      fontSize: 12,
      height: 1.5,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final line in report.timings)
          Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Text(line, style: mono),
          ),
        const SizedBox(height: 10),
        Text(report.guess, style: mono),
        const SizedBox(height: 10),
        SelectableText(
          'Bits: ${report.bits}',
          style: TextStyle(
            color: colors.textPrimary,
            fontSize: 12,
            height: 1.5,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}
