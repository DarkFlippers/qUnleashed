import 'dart:math' as math;

import 'hexbuffer.dart';

class Guess {
  Guess(
    this.name, {
    this.modulation,
    this.short,
    this.long,
    this.sync,
    this.gap,
    this.reset,
    this.tolerance,
  });

  final String name;
  final String? modulation;
  final double? short;
  final double? long;
  final double? sync;
  final double? gap;
  final double? reset;
  final double? tolerance;
}

class Bin {
  Bin([double? num]) {
    if (num != null) {
      count = 1;
      sum = num;
      mean = num;
      devi = 0;
      min = num;
      max = num;
    } else {
      count = 0;
      sum = 0;
      mean = null;
      devi = 0;
      min = null;
      max = null;
    }
  }

  late int count;
  late double sum;
  double? mean;
  late double devi;
  double? min;
  double? max;

  void add(double num) {
    count++;
    sum += num;
    mean = sum / count;
    min = min == null ? num : math.min(num, min!);
    max = max == null ? num : math.max(num, max!);
    devi = (max! - min!) / 2;
  }

  void fuse(Bin bin) {
    count += bin.count;
    sum += bin.sum;
    mean = sum / count;
    min = math.min(min!, bin.min!);
    max = math.max(max!, bin.max!);
    devi = (max! - min!) / 2;
  }

  bool contains(double num) => num >= min! && num <= max!;
}

const int _maxHistBins = 16;

class Histogram {
  Histogram(List<double> data, [double tolerance = 0.2]) {
    histogramSum(data, tolerance);
  }

  final List<Bin> bins = [];

  int get length => bins.length;

  void histogramSum(List<double> data, [double tolerance = 0.2]) {
    final len = data.length;
    for (var n = 0; n < len; ++n) {
      var bin = 0;
      for (; bin < bins.length; ++bin) {
        final bn = data[n];
        final bm = bins[bin].mean!;
        if ((bn - bm).abs() < tolerance * math.max(bn, bm)) {
          bins[bin].add(data[n]);
          break;
        }
      }
      if (bin == bins.length && bin < _maxHistBins) {
        bins.add(Bin(data[n]));
      }
    }
  }

  void deleteBin(int index) {
    bins.removeAt(index);
  }

  void swapBins(int index1, int index2) {
    if (index1 < bins.length && index2 < bins.length) {
      final temp = bins[index1];
      bins[index1] = bins[index2];
      bins[index2] = temp;
    }
  }

  void sortMean() {
    if (bins.length < 2) return;
    for (var n = 0; n < bins.length - 1; ++n) {
      for (var m = n + 1; m < bins.length; ++m) {
        if (bins[m].mean! < bins[n].mean!) {
          swapBins(m, n);
        }
      }
    }
  }

  void sortCount() {
    if (bins.length < 2) return;
    for (var n = 0; n < bins.length - 1; ++n) {
      for (var m = n + 1; m < bins.length; ++m) {
        if (bins[m].count < bins[n].count) {
          swapBins(m, n);
        }
      }
    }
  }

  void fuseBins([double tolerance = 0.2]) {
    if (bins.length < 2) return;
    for (var n = 0; n < bins.length - 1; ++n) {
      for (var m = n + 1; m < bins.length; ++m) {
        final bn = bins[n].mean!;
        final bm = bins[m].mean!;
        if ((bn - bm).abs() < tolerance * math.max(bn, bm)) {
          bins[n].fuse(bins[m]);
          deleteBin(m);
          m--;
        }
      }
    }
  }

  void trimBins([double tolerance = 0]) {
    for (var n = 0; n < bins.length; ++n) {
      if (bins[n].mean! <= tolerance) {
        deleteBin(n);
      }
    }
  }

  int findBinIndex(double width) {
    for (var n = 0; n < bins.length; ++n) {
      if (bins[n].contains(width)) {
        return n;
      }
    }
    return -1;
  }

  String stringPrint([String separator = ', ']) {
    final ret = <String>[];
    for (final b in bins) {
      ret.add('${b.count}× ${b.mean!.toStringAsFixed(1)} '
          '±${b.devi.toStringAsFixed(1)} µs');
    }
    return ret.join(separator);
  }
}

class Analyzer {
  Analyzer(List<double> data, [double tolerance = 0.2]) {
    analysePulses(data, tolerance);
    createRfraw(data);
  }

  late List<double> pulses;
  late List<double> gaps;
  late List<double> periods;
  late double pulseSum;
  late double gapSum;
  late double pulseGapRatio;
  late double pulseGapSkew;

  late Histogram histPulses;
  late Histogram histGaps;
  late Histogram histPeriods;
  late Histogram histTimings;

  String? rfrawB0;
  String? rfrawB1;

  void analysePulses(List<double> data, [double tolerance = 0.2]) {
    pulses = [];
    gaps = [];
    periods = [];
    pulseSum = 0;
    gapSum = 0;
    for (var j = 0; j < data.length - 2; j += 2) {
      final m = data[j];
      final s = data[j + 1];
      pulses.add(m);
      gaps.add(s);
      periods.add(m + s);
      pulseSum += m;
      gapSum += s;
    }
    final m = data[data.length - 2];
    pulses.add(m);
    pulseSum += m;
    pulseGapRatio = pulseSum / gapSum;
    pulseGapSkew = pulseGapRatio - 1;

    histPulses = Histogram(pulses, tolerance);
    histGaps = Histogram(gaps, tolerance);
    histPeriods = Histogram(periods, tolerance);
    histTimings = Histogram(data, tolerance);

    histPulses.trimBins(tolerance);
    histGaps.trimBins(tolerance);
    histPeriods.trimBins(tolerance);
    histTimings.trimBins(tolerance);

    histPulses.fuseBins(tolerance);
    histGaps.fuseBins(tolerance);
    histPeriods.fuseBins(tolerance);
    histTimings.fuseBins(tolerance);
  }

  Guess guess() {
    final pulses = histPulses;
    final gaps = histGaps;
    final periods = histPeriods;
    pulses.sortMean();
    gaps.sortMean();
    if (pulses.bins.isNotEmpty && pulses.bins[0].mean == 0) {
      pulses.deleteBin(0);
    }

    if (this.pulses.length == 1) {
      return Guess(
        'Single pulse detected. Probably Frequency Shift Keying or just noise...',
      );
    } else if (pulses.length == 1 && gaps.length == 1) {
      return Guess('Un-modulated signal. Maybe a preamble...');
    } else if (pulses.length == 1 && gaps.length > 1) {
      return Guess(
        'Pulse Position Modulation with fixed pulse width',
        modulation: 'PPM',
        short: gaps.bins[0].mean,
        long: gaps.bins[1].mean,
        gap: gaps.bins[1].max! * 1.2,
        reset: gaps.bins[gaps.length - 1].max! * 1.2,
      );
    } else if (pulses.length == 2 && gaps.length == 1) {
      final short = pulses.bins[0].mean!;
      final long = pulses.bins[1].mean!;
      return Guess(
        'Pulse Width Modulation with fixed gap',
        modulation: 'PWM',
        short: short,
        long: long,
        tolerance: (long - short) * 0.4,
        reset: gaps.bins[gaps.length - 1].max! * 1.2,
      );
    } else if (pulses.length == 2 && gaps.length == 2 && periods.length == 1) {
      final short = pulses.bins[0].mean!;
      final long = pulses.bins[1].mean!;
      return Guess(
        'Pulse Width Modulation with fixed period',
        modulation: 'PWM',
        short: short,
        long: long,
        tolerance: (long - short) * 0.4,
        reset: gaps.bins[gaps.length - 1].max! * 1.2,
      );
    } else if (pulses.length == 2 && gaps.length == 2 && periods.length == 3) {
      final short = pulses.bins[0].mean!;
      return Guess(
        'Manchester coding (PCM)',
        modulation: 'MC',
        short: short,
        long: short,
        reset: gaps.bins[gaps.length - 1].max! * 1.2,
      );
    } else if (pulses.length == 2 && gaps.length >= 3) {
      final short = pulses.bins[0].mean!;
      final long = pulses.bins[1].mean!;
      return Guess(
        'Pulse Width Modulation with multiple packets',
        modulation: 'PWM',
        short: short,
        long: long,
        gap: gaps.bins[1].max! * 1.2,
        tolerance: (long - short) * 0.4,
        reset: gaps.bins[gaps.length - 1].max! * 1.2,
      );
    } else if (pulses.length >= 3 &&
        gaps.length >= 3 &&
        (pulses.bins[1].mean! - 2 * pulses.bins[0].mean!).abs() <=
            pulses.bins[0].mean! / 8 &&
        (pulses.bins[2].mean! - 3 * pulses.bins[0].mean!).abs() <=
            pulses.bins[0].mean! / 8 &&
        (gaps.bins[0].mean! - pulses.bins[0].mean!).abs() <=
            pulses.bins[0].mean! / 8 &&
        (gaps.bins[1].mean! - 2 * pulses.bins[0].mean!).abs() <=
            pulses.bins[0].mean! / 8 &&
        (gaps.bins[2].mean! - 3 * pulses.bins[0].mean!).abs() <=
            pulses.bins[0].mean! / 8) {
      return Guess(
        'Pulse Code Modulation (Not Return to Zero)',
        modulation: 'PCM',
        short: pulses.bins[0].mean,
        long: pulses.bins[0].mean,
        reset: pulses.bins[0].mean! * 1024,
      );
    } else if (pulses.length == 3) {
      pulses.sortCount();
      final p1 = pulses.bins[1].mean!;
      final p2 = pulses.bins[2].mean!;
      final short = p1 < p2 ? p1 : p2;
      final long = p1 < p2 ? p2 : p1;
      return Guess(
        'Pulse Width Modulation with sync/delimiter',
        modulation: 'PWM',
        short: short,
        long: long,
        sync: pulses.bins[0].mean,
        reset: gaps.bins[gaps.length - 1].max! * 1.2,
      );
    } else {
      return Guess('No clue...');
    }
  }

  void createRfraw(List<double> data) {
    final timings = histTimings;

    if (timings.bins.isEmpty) return;
    if (timings.bins.length > 8) return;
    if (data.length > 494) return;

    final raw = Hexbuffer();

    for (final b in timings.bins) {
      raw.pushWord(b.mean!);
    }

    for (var j = 0; j < data.length - 1; j += 2) {
      final m = data[j];
      final s = data[j + 1];
      final mi = timings.findBinIndex(m);
      final si = timings.findBinIndex(s);
      raw.pushNibble(mi | 8);
      raw.pushNibble(si);
    }

    raw.pushByte(0x55);

    final raw0 = Hexbuffer();
    raw0.pushByte(0xaa);
    raw0.pushByte(0xb0);
    raw0.pushByte(2 + raw.line.length / 2 - 1);
    raw0.pushByte(timings.bins.length);
    raw0.pushByte(1);

    final raw1 = Hexbuffer();
    raw1.pushByte(0xaa);
    raw1.pushByte(0xb1);
    raw1.pushByte(timings.bins.length);

    rfrawB0 = raw0.line + raw.line;
    rfrawB1 = raw1.line + raw.line;
  }
}
