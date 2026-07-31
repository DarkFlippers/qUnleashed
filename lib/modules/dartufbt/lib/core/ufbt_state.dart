import 'dart:convert';
import 'dart:io';

class UfbtState {
  const UfbtState(this.values);

  final Map<String, dynamic> values;

  static const List<String> alwaysUpdateVersions = ['unknown', 'local'];

  static UfbtState? read(File file) {
    if (!file.existsSync()) return null;
    final decoded = jsonDecode(file.readAsStringSync());
    if (decoded is! Map) return null;
    return UfbtState(Map<String, dynamic>.from(decoded));
  }

  void write(File file) {
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(
      const JsonEncoder.withIndent('    ').convert(values),
    );
  }

  String? get hwTarget => values['hw_target'] as String?;

  String? get mode => values['mode'] as String?;

  String? get version => values['version'] as String?;

  String? get jsonIndex => values['json_index'] as String?;

  String? get channel => values['channel'] as String?;

  bool get isVersionUnknown =>
      version == null || alwaysUpdateVersions.contains(version);
}
