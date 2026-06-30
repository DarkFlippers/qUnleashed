import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../theme/theme.dart';
import '../../../widgets/notification.dart';
import 'analysis/slicer.dart';
import 'engine.dart';
import 'models.dart';
import 'plot_controller.dart';
import 'plotter_painter.dart';
import 'ui.dart';

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

const double _slicerInlineBreakpoint = 480;
const double _twoColumnBreakpoint = 820;

class PlotterView extends StatefulWidget {
  const PlotterView({super.key, required this.data});

  final PlotData data;

  @override
  State<PlotterView> createState() => _PlotterViewState();
}

class _PlotterViewState extends State<PlotterView> {
  late PlotterEngine _engine;
  late PlotController _controller;

  final _shortCtrl = TextEditingController();
  final _longCtrl = TextEditingController();
  final _syncCtrl = TextEditingController();
  final _gapCtrl = TextEditingController();
  String _modulation = '';

  @override
  void initState() {
    super.initState();
    _engine = PlotterEngine(widget.data);
    _controller = PlotController(dataWidth: _engine.width);
    _syncControlsFromEngine();
  }

  @override
  void didUpdateWidget(PlotterView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.data, widget.data)) {
      _engine = PlotterEngine(widget.data);
      _controller.dispose();
      _controller = PlotController(dataWidth: _engine.width);
      _syncControlsFromEngine();
      setState(() {});
    }
  }

  @override
  void dispose() {
    _controller.dispose();
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
    FocusScope.of(context).unfocus();
    _engine.setSlicer(SlicerParams(
      modulation: _modulation,
      short: _parseField(_shortCtrl),
      long: _parseField(_longCtrl),
      sync: _parseField(_syncCtrl),
      gap: _parseField(_gapCtrl),
    ));
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final report = _engine.report;
        final twoColumn = constraints.maxWidth >= _twoColumnBreakpoint;

        final header = _PlotHeader(
          frequencyHz: widget.data.centerFreqHz,
          controller: _controller,
        );
        final plot = _InteractivePlot(controller: _controller, engine: _engine);
        final viewControls = _ViewControls(controller: _controller);
        final slicer = _SlicerControls(
          modulation: _modulation,
          shortCtrl: _shortCtrl,
          longCtrl: _longCtrl,
          syncCtrl: _syncCtrl,
          gapCtrl: _gapCtrl,
          onModulationChanged: (v) => setState(() => _modulation = v ?? ''),
          onSlice: _onSlice,
        );
        final modulation =
            report.hasModulation ? _ModulationCard(report: report) : null;
        final histogram = _HistogramTable(rows: report.histograms);
        final bits = _BitsCard(
          bits: report.bits,
          rfRawRx: report.rfRawRx,
          rfRawTx: report.rfRawTx,
        );

        if (twoColumn) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    header,
                    const SizedBox(height: 10),
                    plot,
                    const SizedBox(height: 12),
                    viewControls,
                    const SizedBox(height: 16),
                    bits,
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    slicer,
                    if (modulation != null) ...[
                      const SizedBox(height: 16),
                      modulation,
                    ],
                    const SizedBox(height: 16),
                    histogram,
                  ],
                ),
              ),
            ],
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            header,
            const SizedBox(height: 10),
            plot,
            const SizedBox(height: 12),
            viewControls,
            const SizedBox(height: 16),
            slicer,
            const SizedBox(height: 16),
            if (modulation != null) ...[
              modulation,
              const SizedBox(height: 16),
            ],
            histogram,
            const SizedBox(height: 16),
            bits,
          ],
        );
      },
    );
  }
}

class _InteractivePlot extends StatefulWidget {
  const _InteractivePlot({required this.controller, required this.engine});

  final PlotController controller;
  final PlotterEngine engine;

  @override
  State<_InteractivePlot> createState() => _InteractivePlotState();
}

class _InteractivePlotState extends State<_InteractivePlot> {
  double _lastScale = 1;

  PlotController get _c => widget.controller;

  double _focalFraction(double localX) {
    final w = _c.viewWidth;
    return w <= 0 ? 0.5 : (localX / w).clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final palette = PlotterPalette.fromColors(colors);
    return Container(
      foregroundDecoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.divider),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: RepaintBoundary(
          child: LayoutBuilder(
            builder: (context, constraints) {
              _c.setViewWidth(constraints.maxWidth);
              return Listener(
                onPointerSignal: (event) {
                  if (event is PointerScrollEvent) {
                    final dx = event.scrollDelta.dx;
                    final dy = event.scrollDelta.dy;
                    if (dx.abs() > dy.abs()) {
                      _c.panByPixels(-dx);
                    } else if (dy != 0) {
                      final factor = dy < 0 ? 1.1 : 1 / 1.1;
                      _c.zoomAround(_c.zoom * factor,
                          _focalFraction(event.localPosition.dx));
                    }
                  }
                },
                child: GestureDetector(
                  onScaleStart: (_) => _lastScale = 1,
                  onScaleUpdate: (details) {
                    if (details.focalPointDelta.dx != 0) {
                      _c.panByPixels(details.focalPointDelta.dx);
                    }
                    if (details.scale != _lastScale) {
                      final factor = details.scale / _lastScale;
                      _lastScale = details.scale;
                      _c.zoomAround(_c.zoom * factor,
                          _focalFraction(details.localFocalPoint.dx));
                    }
                  },
                  child: AnimatedBuilder(
                    animation: _c,
                    builder: (context, _) => SizedBox(
                      width: double.infinity,
                      height: kPlotHeight,
                      child: CustomPaint(
                        painter: PulsePlotterPainter(
                          pulses: widget.engine.data.pulses,
                          dataWidth: widget.engine.width,
                          hints: widget.engine.hints,
                          altHints: widget.engine.altHints,
                          zoom: _c.zoom,
                          left: _c.left,
                          palette: palette,
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _PlotHeader extends StatelessWidget {
  const _PlotHeader({required this.frequencyHz, required this.controller});

  final int frequencyHz;
  final PlotController controller;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Row(
      children: [
        if (frequencyHz > 0)
          _Pill(icon: Icons.graphic_eq, label: _formatFrequency(frequencyHz)),
        const Spacer(),
        AnimatedBuilder(
          animation: controller,
          builder: (context, _) {
            final z = controller.zoom;
            return Text(
              '×${z.toStringAsFixed(z < 10 ? 1 : 0)}',
              style: TextStyle(
                color: colors.textMuted,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            );
          },
        ),
      ],
    );
  }

  String _formatFrequency(int hz) {
    if (hz >= 1000000) return '${(hz / 1000000).toStringAsFixed(2)} MHz';
    if (hz >= 1000) return '${(hz / 1000).toStringAsFixed(1)} kHz';
    return '$hz Hz';
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: colors.accent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: colors.accent),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: colors.accent,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _ViewControls extends StatelessWidget {
  const _ViewControls({required this.controller});

  final PlotController controller;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return PlotterCard(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
      child: AnimatedBuilder(
        animation: controller,
        builder: (context, _) {
          final canPan = controller.canPan;
          return Column(
            children: [
              Row(
                children: [
                  _RoundIconButton(
                    icon: Icons.zoom_out,
                    tooltip: 'Zoom out',
                    onPressed: () => controller.zoomBy(1 / 1.6),
                  ),
                  Expanded(
                    child: SliderTheme(
                      data: _sliderTheme(colors),
                      child: Slider(
                        value: controller.zoomFraction,
                        onChanged: controller.setZoomFraction,
                      ),
                    ),
                  ),
                  _RoundIconButton(
                    icon: Icons.zoom_in,
                    tooltip: 'Zoom in',
                    onPressed: () => controller.zoomBy(1.6),
                  ),
                  _RoundIconButton(
                    icon: Icons.center_focus_strong_outlined,
                    tooltip: 'Reset view',
                    onPressed: canPan ? controller.reset : null,
                  ),
                ],
              ),
              Row(
                children: [
                  const SizedBox(width: 8),
                  Icon(Icons.swap_horiz,
                      size: 18, color: canPan ? colors.textMuted : colors.divider),
                  Expanded(
                    child: SliderTheme(
                      data: _sliderTheme(colors),
                      child: Slider(
                        value: controller.panFraction,
                        onChanged: canPan ? controller.setPanFraction : null,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  SliderThemeData _sliderTheme(QAppColors colors) => SliderThemeData(
        activeTrackColor: colors.accent,
        inactiveTrackColor: colors.divider,
        thumbColor: colors.accent,
        overlayColor: colors.accent.withValues(alpha: 0.16),
        trackHeight: 3,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
        overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
      );
}

class _RoundIconButton extends StatelessWidget {
  const _RoundIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      icon: Icon(icon, size: 22),
      color: colors.textSecondary,
      disabledColor: colors.textMuted.withValues(alpha: 0.4),
    );
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

    final dropdown = DropdownButtonFormField<String>(
      initialValue: selected,
      isExpanded: true,
      decoration: plotterFieldDecoration(context, label: 'Slicer'),
      dropdownColor: colors.card,
      borderRadius: BorderRadius.circular(12),
      style: TextStyle(color: colors.textPrimary, fontSize: 14),
      items: [
        for (final o in _slicerOptions)
          DropdownMenuItem(value: o.value, child: Text(o.text)),
      ],
      onChanged: onModulationChanged,
    );

    final sliceButton = FilledButton.icon(
      onPressed: onSlice,
      icon: const Icon(Icons.content_cut, size: 18),
      label: const Text('Slice'),
      style: FilledButton.styleFrom(
        backgroundColor: colors.accent,
        foregroundColor: colors.onAccent,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );

    return PlotterCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionTitle('Slicer', icon: Icons.tune),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < _slicerInlineBreakpoint;
              if (compact) {
                return Column(
                  children: [
                    dropdown,
                    const SizedBox(height: 10),
                    Row(children: [
                      Expanded(
                          child: _NumberField(label: 'Short', controller: shortCtrl)),
                      const SizedBox(width: 10),
                      Expanded(
                          child: _NumberField(label: 'Long', controller: longCtrl)),
                    ]),
                    const SizedBox(height: 10),
                    Row(children: [
                      Expanded(
                          child: _NumberField(label: 'Sync', controller: syncCtrl)),
                      const SizedBox(width: 10),
                      Expanded(
                          child: _NumberField(label: 'Gap', controller: gapCtrl)),
                    ]),
                    const SizedBox(height: 12),
                    SizedBox(width: double.infinity, child: sliceButton),
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(width: 140, child: dropdown),
                  const SizedBox(width: 10),
                  Expanded(child: _NumberField(label: 'Short', controller: shortCtrl)),
                  const SizedBox(width: 10),
                  Expanded(child: _NumberField(label: 'Long', controller: longCtrl)),
                  const SizedBox(width: 10),
                  Expanded(child: _NumberField(label: 'Sync', controller: syncCtrl)),
                  const SizedBox(width: 10),
                  Expanded(child: _NumberField(label: 'Gap', controller: gapCtrl)),
                  const SizedBox(width: 10),
                  SizedBox(height: 50, child: sliceButton),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _NumberField extends StatelessWidget {
  const _NumberField({required this.label, required this.controller});

  final String label;
  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return TextField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      style: TextStyle(
        color: colors.textPrimary,
        fontSize: 14,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
      decoration: plotterFieldDecoration(context, label: label),
    );
  }
}

class _ModulationCard extends StatelessWidget {
  const _ModulationCard({required this.report});

  final PlotterReport report;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return PlotterCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionTitle('Detected modulation', icon: Icons.auto_awesome),
          const SizedBox(height: 8),
          Text(
            report.modulationName,
            style: TextStyle(
              color: colors.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w700,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final p in report.params)
                _ParamChip(label: p.label, value: p.value),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'DC bias (pulse/gap skew): ${report.dcBiasPercent.toStringAsFixed(1)}%',
            style: TextStyle(color: colors.textMuted, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _ParamChip extends StatelessWidget {
  const _ParamChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: colors.background,
        borderRadius: BorderRadius.circular(8),
      ),
      child: RichText(
        text: TextSpan(
          children: [
            TextSpan(
              text: '$label  ',
              style: TextStyle(color: colors.textMuted, fontSize: 12),
            ),
            TextSpan(
              text: value,
              style: TextStyle(
                color: colors.textPrimary,
                fontSize: 12,
                fontWeight: FontWeight.w700,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HistogramTable extends StatelessWidget {
  const _HistogramTable({required this.rows});

  final List<HistogramRow> rows;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final columns = rows.fold<int>(0, (m, r) => math.max(m, r.cells.length));

    return PlotterCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionTitle('Timing histogram', icon: Icons.bar_chart),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Table(
              defaultColumnWidth: const IntrinsicColumnWidth(),
              defaultVerticalAlignment: TableCellVerticalAlignment.middle,
              children: [
                for (final row in rows)
                  TableRow(
                    children: [
                      _labelCell(colors, row.label),
                      for (var i = 0; i < columns; i++)
                        i < row.cells.length
                            ? _dataCell(colors, row.cells[i])
                            : const SizedBox.shrink(),
                    ],
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _labelCell(QAppColors colors, String label) => Padding(
        padding: const EdgeInsets.fromLTRB(0, 5, 20, 5),
        child: Text(
          label,
          style: TextStyle(
            color: colors.textSecondary,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      );

  Widget _dataCell(QAppColors colors, HistogramCell cell) => Padding(
        padding: const EdgeInsets.fromLTRB(0, 5, 20, 5),
        child: RichText(
          text: TextSpan(
            style: const TextStyle(
              fontSize: 12,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
            children: [
              TextSpan(
                text: '${cell.count}× ',
                style:
                    TextStyle(color: colors.accent, fontWeight: FontWeight.w700),
              ),
              TextSpan(
                text: cell.mean.toStringAsFixed(1),
                style: TextStyle(
                    color: colors.textPrimary, fontWeight: FontWeight.w600),
              ),
              TextSpan(
                text: ' ±${cell.devi.toStringAsFixed(1)} µs',
                style: TextStyle(color: colors.textMuted),
              ),
            ],
          ),
        ),
      );
}

class _BitsCard extends StatelessWidget {
  const _BitsCard({
    required this.bits,
    required this.rfRawRx,
    required this.rfRawTx,
  });

  final String bits;
  final String? rfRawRx;
  final String? rfRawTx;

  @override
  Widget build(BuildContext context) {
    return PlotterCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                  child: _SectionTitle('Decoded bits', icon: Icons.tag)),
              if (bits.isNotEmpty) _CopyButton(value: bits, label: 'bits'),
            ],
          ),
          const SizedBox(height: 10),
          _MonoBlock(
            text: bits.isEmpty ? 'No bits decoded' : bits,
            muted: bits.isEmpty,
          ),
          if (rfRawRx != null || rfRawTx != null) ...[
            const SizedBox(height: 16),
            const _SectionTitle('RfRaw', icon: Icons.cell_tower),
            const SizedBox(height: 10),
            if (rfRawRx != null) _RfRawRow(label: 'rx', value: rfRawRx!),
            if (rfRawTx != null) ...[
              const SizedBox(height: 8),
              _RfRawRow(label: 'tx', value: rfRawTx!),
            ],
          ],
        ],
      ),
    );
  }
}

class _RfRawRow extends StatelessWidget {
  const _RfRawRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          margin: const EdgeInsets.only(top: 8),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: colors.accent.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: colors.accent,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(child: _MonoBlock(text: value)),
        const SizedBox(width: 4),
        _CopyButton(value: value, label: 'RfRaw ($label)'),
      ],
    );
  }
}

class _MonoBlock extends StatelessWidget {
  const _MonoBlock({required this.text, this.muted = false});

  final String text;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: colors.terminalBackground,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.divider),
      ),
      child: SelectableText(
        text,
        style: TextStyle(
          color: muted ? colors.textMuted : colors.terminalText,
          fontSize: 12,
          height: 1.5,
          fontFamily: 'monospace',
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}

class _CopyButton extends StatelessWidget {
  const _CopyButton({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return IconButton(
      tooltip: 'Copy $label',
      visualDensity: VisualDensity.compact,
      onPressed: () async {
        await Clipboard.setData(ClipboardData(text: value));
        if (context.mounted) {
          context.showNotification('Copied $label to clipboard');
        }
      },
      icon: Icon(Icons.copy_rounded, size: 18, color: colors.textSecondary),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text, {required this.icon});

  final String text;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: colors.accent),
        const SizedBox(width: 8),
        Text(
          text,
          style: TextStyle(
            color: colors.textPrimary,
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}
