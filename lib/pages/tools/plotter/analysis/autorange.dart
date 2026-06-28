class AutoRange {
  const AutoRange(this.scale, this.prefix);

  final double scale;
  final String prefix;
}

const List<AutoRange> _autoranges = [
  AutoRange(1e24, 'Y'),
  AutoRange(1e21, 'Z'),
  AutoRange(1e18, 'E'),
  AutoRange(1e15, 'P'),
  AutoRange(1e12, 'T'),
  AutoRange(1e9, 'G'),
  AutoRange(1e6, 'M'),
  AutoRange(1e3, 'k'),
  AutoRange(1, ''),
  AutoRange(1e-3, 'm'),
  AutoRange(1e-6, 'µ'),
  AutoRange(1e-9, 'n'),
  AutoRange(1e-12, 'p'),
  AutoRange(1e-15, 'f'),
  AutoRange(1e-18, 'a'),
  AutoRange(1e-21, 'z'),
  AutoRange(1e-24, 'y'),
];

AutoRange autorange(double value, [double minInt = 10.0]) {
  if (value == 0.0) return _autoranges[8];
  final scaled = value / minInt;
  for (final range in _autoranges) {
    if (scaled >= range.scale) return range;
  }
  return _autoranges.last;
}

const List<AutoRange> _autorangesTime = [
  AutoRange(31557513, 'Y'),
  AutoRange(2635200, 'M'),
  AutoRange(86400, 'D'),
  AutoRange(3600, 'h'),
  AutoRange(60, 'm'),
  AutoRange(1, 's'),
  AutoRange(1e-3, 'ms'),
  AutoRange(1e-6, 'µs'),
  AutoRange(1e-9, 'ns'),
  AutoRange(1e-12, 'ps'),
  AutoRange(1e-15, 'fs'),
  AutoRange(1e-18, 'as'),
  AutoRange(1e-21, 'zs'),
  AutoRange(1e-24, 'ys'),
];

AutoRange autorangeTime(double value, [double minInt = 10.0]) {
  if (value == 0.0) return _autorangesTime[8];
  final scaled = value / minInt;
  for (final range in _autorangesTime) {
    if (scaled >= range.scale) return range;
  }
  return _autorangesTime.last;
}
