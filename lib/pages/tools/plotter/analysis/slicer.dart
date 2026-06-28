import 'bitbuffer.dart';
import 'histogram.dart';

class Hint {
  const Hint(this.x0, this.x1);

  final double x0;
  final double x1;
}

class SliceResult {
  SliceResult(this.hints, this.bits);

  final List<Hint> hints;
  final Bitbuffer bits;
}

class SlicerParams {
  SlicerParams({
    this.modulation = '',
    double? short,
    double? long,
    double? sync,
    double? gap,
  })  : short = short ?? double.nan,
        long = long ?? double.nan,
        sync = sync ?? double.nan,
        gap = gap ?? double.nan;

  factory SlicerParams.fromGuess(Guess guess) => SlicerParams(
        modulation: guess.modulation ?? '',
        short: guess.short,
        long: guess.long,
        sync: guess.sync,
        gap: guess.gap,
      );

  String modulation;
  double short;
  double long;
  double sync;
  double gap;
}

bool _truthy(double v) => !v.isNaN && v != 0;

int _trunc(double v) => v.isFinite ? v.truncate() : 0;

double _at(List<double> pulses, int index) =>
    index >= 0 && index < pulses.length ? pulses[index] : double.nan;

SliceResult sliceGuess(List<double> pulses, SlicerParams guess) {
  switch (guess.modulation) {
    case 'PCM':
      return slicePCM(pulses, guess);
    case 'MC':
      return sliceMC(pulses, guess);
    case 'PPM':
      return slicePPM(pulses, guess);
    case 'PWM':
      return slicePWM(pulses, guess);
    case 'DM':
      return sliceDM(pulses, guess);
    case 'NRZI':
      return sliceNRZI(pulses, guess);
    case 'CMI':
      return sliceCMI(pulses, guess);
    case 'PIWM':
      return slicePIWM(pulses, guess);
    default:
      return SliceResult([], Bitbuffer());
  }
}

SliceResult slicePCM(List<double> pulses, SlicerParams guess) {
  if (guess.long.isNaN || guess.long == guess.short) {
    return sliceNRZ(pulses, guess);
  } else {
    return sliceRZ(pulses, guess);
  }
}

SliceResult sliceNRZ(List<double> pulses, SlicerParams guess) {
  final short = guess.short;
  final gap = guess.gap;

  final bits = Bitbuffer();
  final hints = <Hint>[];

  var x = 0.0;
  for (var j = 0; j < pulses.length; j += 1) {
    final symbol = 1 - (j % 2);
    final w = pulses[j];
    if (_truthy(gap) && w > gap) {
      bits.pushBreak();
    } else {
      final cnt = _trunc(w / short + 0.5);
      for (var k = 0; k < cnt; ++k) {
        hints.add(Hint(x + (w / cnt) * k, x + (w / cnt) * (k + 1)));
        bits.push(symbol);
      }
    }
    x += w;
  }

  return SliceResult(hints, bits);
}

SliceResult sliceRZ(List<double> pulses, SlicerParams guess) {
  final short = guess.short;
  final long = guess.long;
  final gap = guess.gap;

  final shortl = short * 0.5;
  final shortu = short * 1.5;

  final bits = Bitbuffer();
  final hints = <Hint>[];

  var x = 0.0;
  for (var j = 0; j < pulses.length; j += 2) {
    final m = pulses[j];
    final s = _at(pulses, j + 1);
    if (m < shortl || m > shortu) {
      bits.pushBreak();
      x += m + s;
      continue;
    }
    var onew = (m * long) / short;
    var zs = s + m - onew;
    if (zs < long / 2) {
      onew = m + s;
      zs = 0;
    }
    hints.add(Hint(x, x + onew));
    bits.pushOne();
    x += onew;
    if (_truthy(gap) && s > gap) {
      bits.pushBreak();
      x += zs;
      continue;
    }
    final cnt = _trunc(zs / long + 0.5);
    for (var k = 0; k < cnt; ++k) {
      hints.add(Hint(x + (zs * k) / cnt, x + (zs * (k + 1)) / cnt));
      bits.pushZero();
    }
    x += zs;
  }

  return SliceResult(hints, bits);
}

SliceResult slicePPM(List<double> pulses, SlicerParams guess) {
  final short = guess.short;
  final long = guess.long;
  final sync = guess.sync;
  final gap = guess.gap;

  final shortl = short * 0.5;
  final shortu = short * 1.5;
  final longl = long * 0.5;
  final longu = long * 1.5;
  final syncl = sync * 0.5;
  final syncu = sync * 1.5;

  final bits = Bitbuffer();
  final hints = <Hint>[];

  var x = 0.0;
  for (var j = 0; j < pulses.length; j += 2) {
    final m = pulses[j];
    final s = _at(pulses, j + 1);
    final x0 = x;
    x += m + s;
    if (s > shortl && s < shortu) {
      hints.add(Hint(x0, x));
      bits.pushOne();
    } else if (s > longl && s < longu) {
      hints.add(Hint(x0, x));
      bits.pushZero();
    } else if (s > syncl && s < syncu) {
      hints.add(Hint(x0, x));
      bits.pushBreak();
    } else if (_truthy(gap) && s > gap) {
      bits.pushBreak();
    }
  }

  return SliceResult(hints, bits);
}

SliceResult slicePWM(List<double> pulses, SlicerParams guess) {
  final short = guess.short;
  final long = guess.long;
  final sync = guess.sync;
  final gap = guess.gap;

  final shortl = short * 0.5;
  final shortu = short * 1.5;
  final longl = long * 0.5;
  final longu = long * 1.5;
  final syncl = sync * 0.5;
  final syncu = sync * 1.5;

  final bits = Bitbuffer();
  final hints = <Hint>[];

  var x = 0.0;
  for (var j = 0; j < pulses.length; j += 2) {
    final m = pulses[j];
    final s = _at(pulses, j + 1);

    final x0 = x;
    var x1 = x + m + s;
    if (s > gap) {
      x1 = x + m + gap;
    }
    x += m + s;

    if (m > shortl && m < shortu) {
      hints.add(Hint(x0, x1));
      bits.pushOne();
    } else if (m > longl && m < longu) {
      hints.add(Hint(x0, x1));
      bits.pushZero();
    } else if (m > syncl && m < syncu) {
      hints.add(Hint(x0, x1));
      bits.pushBreak();
    }
    if (_truthy(gap) && s > gap) {
      bits.pushBreak();
    }
  }

  return SliceResult(hints, bits);
}

int _manchesterAligned(List<double> pulses, int offset, double short) {
  for (var j = offset; j < pulses.length; j += 2) {
    final mw = pulses[j];
    final cw = _trunc(mw / short + 0.5);
    if (cw > 1) return 0;
    final sw = _at(pulses, j + 1);
    final sc = _trunc(sw / short + 0.5);
    if (sc > 1) return 1;
  }
  return 0;
}

SliceResult sliceMC(List<double> pulses, SlicerParams guess) {
  final short = guess.short;
  final bits = Bitbuffer();
  final hints = <Hint>[];

  var aligned = _manchesterAligned(pulses, 0, short) != 0;

  var x = 0.0;
  var x1 = 0.0;
  for (var j = 0; j < pulses.length; j += 2) {
    final mark = pulses[j];
    final mcnt = _trunc(mark / short + 0.5);
    final space = _at(pulses, j + 1);
    final scnt = _trunc(space / short + 0.5);

    if (mcnt == 1) {
      if (!aligned) {
        hints.add(Hint(x1, x + mark));
        bits.pushZero();
        x1 = x + mark;
      } else {
        x1 = x;
      }
      aligned = !aligned;
    } else if (mcnt == 2) {
      if (!aligned) {
        hints.add(Hint(x1, x + mark / 2));
        bits.pushZero();
        x1 = x + mark / 2;
      } else {
        bits.pushBreak();
        x1 = x + mark / 2;
      }
      aligned = false;
    } else if (mcnt > 2) {
      if (!aligned) {
        hints.add(Hint(x1, x + mark / mcnt));
        bits.pushZero();
        x1 = x + mark - mark / mcnt;
      } else {
        x1 = x + mark - mark / mcnt;
      }
      bits.pushBreak();
      aligned = _manchesterAligned(pulses, j + 1, short) != 0;
    }

    if (scnt == 1) {
      if (!aligned) {
        hints.add(Hint(x1, x + mark + space));
        bits.pushOne();
        x1 = x + mark + space;
      } else {
        x1 = x + mark;
      }
      aligned = !aligned;
    } else if (scnt == 2) {
      if (!aligned) {
        hints.add(Hint(x1, x + mark + space / 2));
        bits.pushOne();
        x1 = x + mark + space / 2;
      } else {
        bits.pushBreak();
        x1 = x + mark + space / 2;
      }
      aligned = false;
    } else if (scnt > 2) {
      if (!aligned) {
        hints.add(Hint(x1, x + mark + space / scnt));
        bits.pushOne();
        x1 = x + mark + space - space / scnt;
      } else {
        x1 = x + mark + space - space / scnt;
      }
      bits.pushBreak();
      aligned = _manchesterAligned(pulses, j + 1, short) != 0;
    }

    x += mark + space;
  }

  return SliceResult(hints, bits);
}

SliceResult sliceDM(List<double> pulses, SlicerParams guess) {
  final short = guess.short;
  final bits = Bitbuffer();
  final hints = <Hint>[];

  var x = 0.0;
  var x1 = double.nan;
  for (var j = 0; j < pulses.length; j += 2) {
    final mark = pulses[j];
    final mcnt = _trunc(mark / short + 0.5);
    final space = _at(pulses, j + 1);
    final scnt = _trunc(space / short + 0.5);

    final x1Falsy = x1.isNaN || x1 == 0;

    if (x1Falsy && mcnt == 1 && scnt == 1) {
      hints.add(Hint(x, x + mark + space));
      bits.pushZero();
    } else if (mcnt == 1 && scnt == 1) {
      hints.add(Hint(x1, x + mark));
      bits.pushZero();
      x1 = x + mark;
    } else if (!x1Falsy && mcnt == 1 && scnt == 2) {
      hints.add(Hint(x1, x + mark));
      bits.pushZero();
      hints.add(Hint(x + mark, x + mark + space));
      bits.pushOne();
      x1 = double.nan;
    } else if (mcnt == 2 && scnt == 1) {
      hints.add(Hint(x, x + mark));
      bits.pushOne();
      x1 = x + mark;
    } else if (mcnt == 2 && scnt == 2) {
      hints.add(Hint(x, x + mark));
      bits.pushOne();
      hints.add(Hint(x + mark, x + mark + space));
      bits.pushOne();
    } else if (x1Falsy && mcnt == 1) {
      hints.add(Hint(x, x + mark + short));
      bits.pushZero();
      bits.pushBreak();
    } else if (x1Falsy && mcnt == 2) {
      hints.add(Hint(x, x + mark));
      bits.pushOne();
      bits.pushBreak();
    } else {
      if (!x1Falsy) {
        hints.add(Hint(x1, x1 + short * 2));
        bits.pushZero();
      }
      x1 = double.nan;
      bits.pushBreak();
    }
    x += mark + space;
  }

  return SliceResult(hints, bits);
}

SliceResult sliceNRZI(List<double> pulses, SlicerParams guess) {
  final short = guess.short;
  final bits = Bitbuffer();
  final hints = <Hint>[];

  var x = 0.0;
  var x1 = 0.0;
  for (var j = 0; j < pulses.length; j += 1) {
    final w = pulses[j];
    final cnt = _trunc(w / short + 0.5);
    if (x1 != 0) {
      hints.add(Hint(x1, x + short / 2));
      bits.pushOne();
    }
    x1 = x + short / 2;
    for (var k = 1; k < cnt; ++k) {
      hints.add(Hint(x1, x1 + w / cnt));
      bits.pushZero();
      x1 += w / cnt;
    }
    x += w;
  }

  return SliceResult(hints, bits);
}

SliceResult sliceCMI(List<double> pulses, SlicerParams guess) {
  final short = guess.short;
  final bits = Bitbuffer();
  final hints = <Hint>[];

  var x = 0.0;
  var x1 = double.nan;
  for (var j = 0; j < pulses.length; j += 2) {
    final mark = pulses[j];
    final mcnt = _trunc(mark / short + 0.5);
    final space = _at(pulses, j + 1);
    final scnt = _trunc(space / short + 0.5);

    final x1Falsy = x1.isNaN || x1 == 0;

    if (mcnt == 1 && scnt == 1) {
      if (x1Falsy) x1 = x - mark;
      hints.add(Hint(x1, x + mark));
      bits.pushZero();
      x1 = x + mark;
    } else if (mcnt == 1 && scnt == 2) {
      if (x1Falsy) x1 = x - mark;
      hints.add(Hint(x1, x + mark));
      bits.pushZero();
      x1 = x + mark + space;
      hints.add(Hint(x + mark, x1));
      bits.pushOne();
    } else if (mcnt == 1 && scnt == 3) {
      if (x1Falsy) x1 = x - mark;
      hints.add(Hint(x1, x + mark));
      bits.pushZero();
      x1 = x + mark + (space * 2) / 3;
      hints.add(Hint(x + mark, x1));
      bits.pushOne();
    } else if (mcnt == 2 && scnt == 1) {
      hints.add(Hint(x1, x + mark));
      bits.pushOne();
      x1 = x + mark;
    } else if (mcnt == 2 && scnt == 2) {
      hints.add(Hint(x1, x + mark));
      bits.pushOne();
      x1 = x + mark + space;
      hints.add(Hint(x + mark, x1));
      bits.pushOne();
    } else if (mcnt == 2 && scnt == 3) {
      hints.add(Hint(x1, x + mark));
      bits.pushOne();
      x1 = x + mark + (space * 2) / 3;
      hints.add(Hint(x + mark, x1));
      bits.pushOne();
    } else if (mcnt == 3 && scnt == 1) {
      hints.add(Hint(x1, x + mark / 3));
      bits.pushZero();
      hints.add(Hint(x + mark / 3, x + mark));
      bits.pushOne();
      x1 = x + mark;
    } else if (mcnt == 3 && scnt == 2) {
      hints.add(Hint(x1, x + mark / 3));
      bits.pushZero();
      hints.add(Hint(x + mark / 3, x + mark));
      bits.pushOne();
      x1 = x + mark + space;
      hints.add(Hint(x + mark, x1));
      bits.pushOne();
    } else if (mcnt == 3 && scnt == 3) {
      hints.add(Hint(x1, x + mark / 3));
      bits.pushZero();
      hints.add(Hint(x, x + mark / 3));
      bits.pushOne();
      hints.add(Hint(x + mark / 3, x + mark));
      bits.pushOne();
      hints.add(Hint(x + mark, x + mark + (space * 3) / 2));
      bits.pushOne();
      x1 = x + mark + (space * 3) / 2;
    } else if (mcnt == 1) {
      hints.add(Hint(x1, x + mark));
      bits.pushZero();
      bits.pushBreak();
      x1 = x + mark;
    } else if (mcnt == 2) {
      hints.add(Hint(x1, x + mark));
      bits.pushOne();
      bits.pushBreak();
      x1 = x + mark;
    } else {
      bits.pushBreak();
    }
    x += mark + space;
  }

  return SliceResult(hints, bits);
}

SliceResult slicePIWM(List<double> pulses, SlicerParams guess) {
  final short = guess.short;
  final bits = Bitbuffer();
  final hints = <Hint>[];

  var x = 0.0;
  for (var j = 0; j < pulses.length; j += 1) {
    final w = pulses[j];
    final cnt = _trunc(w / short + 0.5);

    if (cnt == 1) {
      hints.add(Hint(x, x + w));
      bits.pushOne();
    } else if (cnt == 2) {
      hints.add(Hint(x, x + w));
      bits.pushZero();
    } else {
      bits.pushBreak();
    }
    x += w;
  }

  return SliceResult(hints, bits);
}
