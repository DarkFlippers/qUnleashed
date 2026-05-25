import 'dart:io' as io;

import '../models/category.dart';

class ArchiveKeyMeta {
  const ArchiveKeyMeta({this.protocol, this.extra});
  final String? protocol;
  final String? extra;
}

Future<ArchiveKeyMeta?> parseArchiveKeyMeta(
  ArchiveCategory cat,
  String? localPath,
) async {
  if (localPath == null || localPath.isEmpty) return null;
  try {
    final file = io.File(localPath);
    if (!await file.exists()) return null;
    final content = await file.readAsString();
    return _parse(cat, content);
  } catch (_) {
    return null;
  }
}

ArchiveKeyMeta _parse(ArchiveCategory cat, String content) {
  final lines = content.split('\n').map((l) => l.trim()).toList();
  switch (cat) {
    case ArchiveCategory.nfc:
      return _parseNfc(lines);
    case ArchiveCategory.rfid:
      return _parseRfid(lines);
    case ArchiveCategory.infrared:
      return _parseInfrared(lines);
    case ArchiveCategory.subghz:
    case ArchiveCategory.wardriving:
      return _parseSubGhz(lines);
    case ArchiveCategory.badusb:
      return _parseBadUsb(lines);
    case ArchiveCategory.ibutton:
      return _parseIButton(lines);
  }
}

String? _field(List<String> lines, String key) {
  final prefix = '$key:';
  for (final line in lines) {
    if (line.startsWith(prefix)) {
      final v = line.substring(prefix.length).trim();
      if (v.isNotEmpty) return v;
    }
  }
  return null;
}

ArchiveKeyMeta _parseNfc(List<String> lines) {
  return ArchiveKeyMeta(
    protocol: _field(lines, 'Device type'),
    extra: _field(lines, 'UID'),
  );
}

ArchiveKeyMeta _parseRfid(List<String> lines) {
  return ArchiveKeyMeta(
    protocol: _field(lines, 'Key type'),
    extra: _field(lines, 'Data'),
  );
}

ArchiveKeyMeta _parseInfrared(List<String> lines) {
  String? protocol;
  int signalCount = 0;
  for (final line in lines) {
    if (line.startsWith('name:')) signalCount++;
    if (protocol == null && line.startsWith('protocol:')) {
      final v = line.substring('protocol:'.length).trim();
      if (v.isNotEmpty && v.toLowerCase() != 'raw') protocol = v;
    }
  }
  return ArchiveKeyMeta(
    protocol: protocol,
    extra: signalCount > 1 ? '$signalCount signals' : null,
  );
}

ArchiveKeyMeta _parseSubGhz(List<String> lines) {
  final freqStr = _field(lines, 'Frequency');
  String? freqLabel;
  if (freqStr != null) {
    final hz = int.tryParse(freqStr);
    if (hz != null) {
      final mhz = hz / 1000000.0;
      final formatted = mhz == mhz.truncateToDouble()
          ? mhz.toInt().toString()
          : mhz.toStringAsFixed(1);
      freqLabel = '$formatted MHz';
    }
  }
  return ArchiveKeyMeta(
    protocol: _field(lines, 'Protocol'),
    extra: freqLabel,
  );
}

ArchiveKeyMeta _parseBadUsb(List<String> lines) {
  for (final line in lines) {
    if (line.startsWith('REM ') || line.startsWith('REM\t')) {
      final comment = line.substring(4).trim();
      if (comment.isNotEmpty && comment.length <= 60) {
        return ArchiveKeyMeta(protocol: null, extra: comment);
      }
    }
  }
  return const ArchiveKeyMeta();
}

ArchiveKeyMeta _parseIButton(List<String> lines) {
  return ArchiveKeyMeta(
    protocol: _field(lines, 'Key type'),
    extra: null,
  );
}
