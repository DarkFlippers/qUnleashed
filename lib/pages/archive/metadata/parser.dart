import 'dart:io' as io;

import '../models/category.dart';

class ArchiveKeyMeta {
  const ArchiveKeyMeta({
    this.protocol,
    this.extra,
    this.meta = const {},
  });
  final String? protocol;
  final String? extra;
  final Map<String, String> meta;
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
    case ArchiveCategory.javascript:
      return const ArchiveKeyMeta();
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
  final deviceType = _field(lines, 'Device type');
  final uid = _field(lines, 'UID');
  final mifareType = _field(lines, 'Mifare Classic type') ??
      _field(lines, 'Mifare type') ??
      _field(lines, 'NTAG type');

  final typeLabel = (deviceType != null && mifareType != null)
      ? '$deviceType $mifareType'
      : deviceType ?? mifareType;

  return ArchiveKeyMeta(
    protocol: typeLabel,
    extra: uid,
    meta: {
      'device_type': ?deviceType,
      'uid': ?uid,
      'mifare_type': ?mifareType,
    },
  );
}

ArchiveKeyMeta _parseRfid(List<String> lines) {
  final keyType = _field(lines, 'Key type');
  final data = _field(lines, 'Data');
  return ArchiveKeyMeta(
    protocol: keyType,
    extra: data,
    meta: {
      'key_type': ?keyType,
      'data': ?data,
    },
  );
}

ArchiveKeyMeta _parseInfrared(List<String> lines) {
  final protocols = <String>{};
  int signalCount = 0;
  for (final line in lines) {
    if (line.startsWith('name:')) signalCount++;
    if (line.startsWith('protocol:')) {
      final v = line.substring('protocol:'.length).trim();
      if (v.isNotEmpty && v.toLowerCase() != 'raw') protocols.add(v);
    }
  }
  final protocolsLabel = protocols.isEmpty ? null : protocols.join(', ');
  return ArchiveKeyMeta(
    protocol: protocolsLabel,
    extra: signalCount > 0 ? '$signalCount' : null,
    meta: {
      if (signalCount > 0) 'signals': '$signalCount',
      'protocols': ?protocolsLabel,
    },
  );
}

ArchiveKeyMeta _parseSubGhz(List<String> lines) {
  final freqStr = _field(lines, 'Frequency');
  final protocol = _field(lines, 'Protocol');
  final rawPreset = _field(lines, 'Preset');
  final hasRaw = lines.any((l) => l.startsWith('RAW_Data:'));

  String? freqLabel;
  if (freqStr != null) {
    final hz = int.tryParse(freqStr);
    if (hz != null) {
      final mhz = hz / 1000000.0;
      final formatted = mhz == mhz.truncateToDouble()
          ? mhz.toInt().toString()
          : mhz.toStringAsFixed(3);
      freqLabel = '$formatted MHz';
    }
  }

  final preset = rawPreset?.replaceFirst(
    RegExp(r'^FuriHalSubGhzPreset', caseSensitive: false),
    '',
  );

  String? modulation;
  if (rawPreset != null) {
    final p = rawPreset.toLowerCase();
    if (p.contains('ook')) {
      modulation = 'OOK';
    } else if (p.contains('fm') || p.contains('2fsk') || p.contains('4fsk')) {
      modulation = 'FM';
    } else {
      modulation = null;
    }
  }

  return ArchiveKeyMeta(
    protocol: protocol,
    extra: freqLabel,
    meta: {
      'frequency': ?freqStr,
      'frequency_label': ?freqLabel,
      'protocol': ?protocol,
      'preset': ?preset,
      'modulation': ?modulation,
      if (hasRaw) 'has_raw': '1',
    },
  );
}

ArchiveKeyMeta _parseBadUsb(List<String> lines) {
  String? comment;
  var lineCount = 0;
  for (final line in lines) {
    if (line.isEmpty) continue;
    if (line.startsWith('REM ') || line.startsWith('REM\t')) {
      if (comment == null) {
        final c = line.substring(4).trim();
        if (c.isNotEmpty && c.length <= 80) comment = c;
      }
    } else {
      lineCount++;
    }
  }
  return ArchiveKeyMeta(
    protocol: 'DuckyScript',
    extra: comment,
    meta: {
      'kind': 'DuckyScript',
      'lines': '$lineCount',
      'comment': ?comment,
    },
  );
}

ArchiveKeyMeta _parseIButton(List<String> lines) {
  final keyType = _field(lines, 'Key type');
  return ArchiveKeyMeta(
    protocol: keyType,
    extra: null,
    meta: {
      'key_type': ?keyType,
    },
  );
}
