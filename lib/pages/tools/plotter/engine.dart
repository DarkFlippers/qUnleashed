import 'analysis/histogram.dart';
import 'analysis/slicer.dart';
import 'models.dart';

class PlotterReport {
  PlotterReport({
    required this.timings,
    required this.guess,
    required this.bits,
  });

  final List<String> timings;
  final String guess;
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

    final guessText = StringBuffer()
      ..writeln(
        'DC bias (Pulse/Gap skew): '
        '${(analyzer.pulseGapSkew * 100).toStringAsFixed(1)}%',
      )
      ..writeln('Guessing modulation: ${g.name}')
      ..writeln(
        'modulation: ${g.modulation ?? 'unknown'}   '
        'short: ${fmt(g.short)}   long: ${fmt(g.long)}   '
        'sync: ${fmt(g.sync)}   gap: ${fmt(g.gap)}   '
        'reset: ${fmt(g.reset)}',
      )
      ..writeln('RfRaw (rx): ${analyzer.rfrawB1 ?? '-'}')
      ..write('RfRaw (tx): ${analyzer.rfrawB0 ?? '-'}');

    return PlotterReport(
      timings: [
        'Pulses: ${analyzer.histPulses.stringPrint()}',
        'Gaps: ${analyzer.histGaps.stringPrint()}',
        'Periods: ${analyzer.histPeriods.stringPrint()}',
        'Timings: ${analyzer.histTimings.stringPrint()}',
      ],
      guess: guessText.toString(),
      bits: bitsHex,
    );
  }
}
