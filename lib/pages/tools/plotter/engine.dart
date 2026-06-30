import 'analysis/histogram.dart';
import 'analysis/slicer.dart';
import 'models.dart';

class HistogramCell {
  const HistogramCell({
    required this.count,
    required this.mean,
    required this.devi,
  });

  final int count;
  final double mean;
  final double devi;
}

class HistogramRow {
  const HistogramRow({required this.label, required this.cells});

  final String label;
  final List<HistogramCell> cells;
}

class GuessParam {
  const GuessParam(this.label, this.value);

  final String label;
  final String value;
}

class PlotterReport {
  PlotterReport({
    required this.histograms,
    required this.hasModulation,
    required this.modulationName,
    required this.dcBiasPercent,
    required this.params,
    required this.rfRawRx,
    required this.rfRawTx,
    required this.bits,
  });

  final List<HistogramRow> histograms;
  final bool hasModulation;
  final String modulationName;
  final double dcBiasPercent;
  final List<GuessParam> params;
  final String? rfRawRx;
  final String? rfRawTx;
  final String bits;
}

class PlotterEngine {
  PlotterEngine(this.data) {
    width = data.pulses.fold<double>(0, (a, b) => a + b);
    analyzer = Analyzer(data.pulses);
    guessResult = analyzer.guess();
    slicer = SlicerParams.fromGuess(guessResult);
    _apply();
  }

  final PlotData data;
  late final double width;
  late final Analyzer analyzer;
  late final Guess guessResult;
  late SlicerParams slicer;

  List<Hint> hints = [];
  List<Hint> altHints = [];
  late PlotterReport report;

  void setSlicer(SlicerParams params) {
    if (params.modulation.isNotEmpty) {
      slicer = params;
    } else {
      slicer = SlicerParams.fromGuess(guessResult);
    }
    if (data.pulses.isEmpty) return;
    _apply();
  }

  void _apply() {
    final result = sliceGuess(data.pulses, slicer);
    hints = result.hints;
    altHints = _altHints(hints);
    report = _buildReport(result.bits.toHexString());
  }

  List<Hint> _altHints(List<Hint> hints) {
    final alt = <Hint>[];
    Hint? prev;
    for (var i = 0; i < hints.length; i++) {
      final d = hints[i];
      if (i > 0 && prev!.x1 != d.x0) {
        alt.add(Hint(prev.x1, d.x0));
      }
      prev = d;
    }
    return alt;
  }

  PlotterReport _buildReport(String bitsHex) {
    final g = guessResult;
    String fmt(double? v) => v != null ? v.toStringAsFixed(1) : '-';

    return PlotterReport(
      histograms: [
        HistogramRow(label: 'Pulses', cells: _cells(analyzer.histPulses)),
        HistogramRow(label: 'Gaps', cells: _cells(analyzer.histGaps)),
        HistogramRow(label: 'Periods', cells: _cells(analyzer.histPeriods)),
        HistogramRow(label: 'Timings', cells: _cells(analyzer.histTimings)),
      ],
      hasModulation: g.modulation != null,
      modulationName: g.name,
      dcBiasPercent: analyzer.pulseGapSkew * 100,
      params: [
        GuessParam('Modulation', g.modulation ?? 'unknown'),
        GuessParam('Short', fmt(g.short)),
        GuessParam('Long', fmt(g.long)),
        GuessParam('Sync', fmt(g.sync)),
        GuessParam('Gap', fmt(g.gap)),
        GuessParam('Reset', fmt(g.reset)),
      ],
      rfRawRx: analyzer.rfrawB1,
      rfRawTx: analyzer.rfrawB0,
      bits: bitsHex,
    );
  }

  List<HistogramCell> _cells(Histogram h) => [
        for (final b in h.bins)
          HistogramCell(count: b.count, mean: b.mean ?? 0, devi: b.devi),
      ];
}
