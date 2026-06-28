import 'dart:math' as math;
import 'dart:typed_data';

import 'models.dart';

const String _wrongFileMessage =
    'Wrong file type. Only SubGhz RAW, RFID RAW and Infrared signals files are accepted.';

PlotterParseResult parsePlotterFile(Uint8List buffer) {
  final text = _decode(buffer).split(RegExp(r'\r?\n'));

  if (text.isNotEmpty && text[0].startsWith('RIFL')) {
    return PlotterParseResult(data: _processRfid(buffer));
  }

  final firstLine = text.isEmpty ? '' : text[0].trim();
  if (firstLine.contains('Flipper SubGhz RAW File')) {
    return PlotterParseResult(data: _processSubGhz(text));
  } else if (firstLine.contains('IR signals file')) {
    return PlotterParseResult(signals: _processIr(text));
  }
  throw PlotterParseException(_wrongFileMessage);
}

String _decode(Uint8List buffer) {
  return String.fromCharCodes(buffer);
}

double _toNumber(String token) => double.tryParse(token) ?? 0;

PlotData _processSubGhz(List<String> text) {
  int? frequency;
  var rawData = '';
  for (final line in text) {
    if (line.startsWith('Frequency')) {
      frequency = int.tryParse(line.split(' ')[1]);
    } else if (line.startsWith('RAW_Data')) {
      var raw = line.replaceAll('RAW_Data: ', ' ');
      final deviations =
          RegExp(r'(\s\d+\s\d+)|(\s-\d+\s-\d+)').allMatches(raw);
      for (final match in deviations) {
        final m = match.group(0)!;
        final s = m.trim().split(' ');
        if (s[1].startsWith('-')) {
          s.insert(1, '1');
        } else {
          s.insert(1, '-1');
        }
        raw = raw.replaceFirst(m, ' ${s.join(' ')}');
      }
      rawData += raw;
    }
  }

  rawData = rawData.trim();

  if (rawData.startsWith('-')) {
    rawData = '0 $rawData';
  }
  final pulses = rawData
      .replaceAll('-', '')
      .split(' ')
      .map(_toNumber)
      .toList();

  if (frequency == null || pulses.length < 2) {
    throw PlotterParseException(_wrongFileMessage);
  }

  return PlotData(centerFreqHz: frequency, pulses: pulses);
}

List<IrSignal> _processIr(List<String> text) {
  final signals = <IrSignal>[];
  var i = -1;
  for (final line in text) {
    if (line.startsWith('#')) {
      i++;
      signals.add(IrSignal());
    } else if (i < 0) {
      continue;
    } else if (line.startsWith('name')) {
      signals[i].name = line.split(' ')[1];
    } else if (line.startsWith('type')) {
      signals[i].type = line.split(' ')[1];
    } else if (line.startsWith('frequency')) {
      signals[i].frequency = int.tryParse(line.split(' ')[1]);
    } else if (line.startsWith('data')) {
      final idx = line.indexOf(': ');
      if (idx >= 0) {
        signals[i].data = line
            .substring(idx + 2)
            .trim()
            .split(' ')
            .map(_toNumber)
            .toList();
      }
    }
  }

  final raw = signals.where((e) => e.type == 'raw').toList();
  if (raw.isEmpty) {
    throw PlotterParseException(_wrongFileMessage);
  }
  return raw;
}

class _Header {
  _Header({
    required this.magic,
    required this.version,
    required this.frequency,
    required this.dutyCycle,
    required this.maxBufferSize,
  });

  final int magic;
  final int version;
  final double frequency;
  final double dutyCycle;
  final int maxBufferSize;
}

({int value, int length}) _readVarInt(Uint8List buffer) {
  var value = 0;
  var length = 0;
  while (true) {
    if (length >= buffer.length) {
      return (value: value, length: length);
    }
    final currentByte = buffer[length];
    value |= (currentByte & 0x7f) << (length * 7);
    length += 1;
    if (length > 5) {
      throw PlotterParseException('VarInt exceeds allowed bounds.');
    }
    if ((currentByte & 0x80) != 0x80) break;
  }
  return (value: value, length: length);
}

PlotData _processRfid(Uint8List rawData) {
  final view = ByteData.sublistView(rawData);

  int u32(int offset) =>
      offset + 4 <= rawData.length ? view.getUint32(offset, Endian.little) : 0;
  double f32(int offset) =>
      offset + 4 <= rawData.length ? view.getFloat32(offset, Endian.little) : 0;

  final header = _Header(
    magic: u32(0),
    version: u32(4),
    frequency: f32(8),
    dutyCycle: f32(12),
    maxBufferSize: u32(16),
  );

  var dataOffset = 20;
  var bufferSize = u32(dataOffset);
  final varints = <double>[];
  if (bufferSize > header.maxBufferSize) {
    throw PlotterParseException(
      'Buffer size ($bufferSize) exceeds max_buffer_size '
      '(${header.maxBufferSize})',
    );
  }
  while (rawData.length > dataOffset) {
    final end = math.min(dataOffset + bufferSize, rawData.length);
    final buffer = Uint8List.sublistView(rawData, dataOffset, end);
    var bufferOffset = 4;
    while (bufferOffset < buffer.length) {
      final varint =
          _readVarInt(Uint8List.sublistView(buffer, bufferOffset));
      if (varint.length == 0) break;
      bufferOffset += varint.length;
      varints.add(varint.value.toDouble());
    }
    dataOffset += bufferSize + 4;
    bufferSize = u32(dataOffset);
  }

  if (varints.length < 2) {
    throw PlotterParseException(_wrongFileMessage);
  }

  return PlotData(
    centerFreqHz: header.frequency.round(),
    pulses: varints,
  );
}
