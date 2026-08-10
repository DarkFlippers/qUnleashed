import 'device_info_fields.dart';

abstract final class DeviceInfoReader {
  static String firmwareVersion(Map<String, String> info) =>
      _first(info, const [
        'firmware_version',
        'firmware.version',
        'software_revision',
        'protobuf_version',
      ]) ??
      '-';

  static String buildDate(Map<String, String> info) =>
      _first(info, const ['firmware_build_date', 'build_date', 'datetime']) ??
      '-';

  static String sdCard(Map<String, String> info) =>
      _formatUsedTotal(info, 'storage.sdcard');

  static String deviceName(Map<String, String> info) {
    final v = info['hardware_name'];
    if (v != null && v.trim().isNotEmpty) return v;
    return 'No device';
  }

  static List<MapEntry<String, String>> infoEntries(Map<String, String> info) =>
      [
        MapEntry('Firmware Version', firmwareVersion(info)),
        MapEntry('Build Date', buildDate(info)),
        MapEntry('SD Card (Used/Total)', sdCard(info)),
      ];

  static String? _first(Map<String, String> info, List<String> keys) {
    for (final k in keys) {
      final v = info[k];
      if (v != null && v.trim().isNotEmpty) return v;
    }
    return null;
  }

  static String? str(Map<String, String> info, List<String> keys) {
    for (final k in keys) {
      final v = info[k];
      if (v != null && v.trim().isNotEmpty && v != '-') return v;
    }
    return null;
  }

  static double? number(Map<String, String> info, List<String> keys) {
    final raw = str(info, keys);
    if (raw == null) return null;
    final n = double.tryParse(
      raw.replaceAll('%', '').replaceAll(',', '.').trim(),
    );
    if (n == null || !n.isFinite) return null;
    return n;
  }

  static String _formatUsedTotal(Map<String, String> info, String prefix) {
    final used = info['$prefix.used'];
    final total = info['$prefix.total'];
    if (used == null && total == null) return '-';
    return '${used ?? '?'} / ${total ?? '?'}';
  }

  static String buildExportDump(Map<String, String> info) {
    final buf = StringBuffer();
    for (final f in kDeviceInfoExportFields) {
      buf
        ..write(f.$1)
        ..write(': ')
        ..writeln(_first(info, f.$2) ?? '-');
    }

    // Protobuf parts can fall back to splitting the combined key.
    final combined = info['protobuf_version'];
    if (combined != null) {
      final parts = combined.split('.');
      final raw = buf.toString();
      if (raw.contains('devinfo_protobuf.version.major: -') &&
          parts.isNotEmpty) {
        return raw
            .replaceFirst(
              'devinfo_protobuf.version.major: -',
              'devinfo_protobuf.version.major: ${parts[0]}',
            )
            .replaceFirst(
              'devinfo_protobuf.version.minor: -',
              'devinfo_protobuf.version.minor: ${parts.length > 1 ? parts[1] : '-'}',
            )
            .trimRight();
      }
    }
    return buf.toString().trimRight();
  }
}
