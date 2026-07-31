import 'dart:io';

class SdkApiSymbols {
  const SdkApiSymbols({
    required this.version,
    required this.valid,
    required this.disabled,
  });

  final String version;
  final Set<String> valid;
  final Set<String> disabled;

  static const String versionRow = 'Version';
  static const Set<String> symbolRows = {'Function', 'Variable'};
  static const String disabledStatus = '-';

  int get versionAsInt {
    final parts = version.split('.');
    final major = int.tryParse(parts.first) ?? 0;
    final minor = parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;
    return ((major & 0xFFFF) << 16) | (minor & 0xFFFF);
  }

  static SdkApiSymbols load(File file) {
    final valid = <String>{};
    final disabled = <String>{};
    var version = '0.0';

    final lines = file.readAsLinesSync();
    for (var i = 1; i < lines.length; i++) {
      final line = lines[i];
      if (line.isEmpty) continue;
      final cells = line.split(',');
      if (cells.length < 3) continue;
      final entry = cells[0];
      final status = cells[1];
      final name = cells[2];

      if (entry == versionRow) {
        version = name;
        continue;
      }
      if (!symbolRows.contains(entry)) continue;
      if (status == disabledStatus) {
        disabled.add(name);
      } else {
        valid.add(name);
      }
    }

    return SdkApiSymbols(version: version, valid: valid, disabled: disabled);
  }
}
