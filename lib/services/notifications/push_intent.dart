import 'dart:convert';

class PushIntent {
  const PushIntent({
    required this.type,
    this.entry,
    this.channel,
    this.version,
    this.url,
  });

  static const String typeFirmware = 'firmware';
  static const String typeApp = 'app';

  final String type;
  final String? entry;
  final String? channel;
  final String? version;
  final String? url;

  static PushIntent? fromData(Map<String, dynamic> data) {
    final type = data['type'];
    if (type is! String || type.isEmpty) return null;

    String? field(String key) {
      final value = data[key];
      return value is String && value.isNotEmpty ? value : null;
    }

    return PushIntent(
      type: type,
      entry: field('entry'),
      channel: field('channel'),
      version: field('version'),
      url: field('url'),
    );
  }

  static PushIntent? decode(String? payload) {
    if (payload == null || payload.isEmpty) return null;
    try {
      final decoded = jsonDecode(payload);
      if (decoded is! Map) return null;
      return fromData(decoded.cast<String, dynamic>());
    } catch (_) {
      return null;
    }
  }

  String encode() => jsonEncode({
    'type': type,
    if (entry != null) 'entry': entry,
    if (channel != null) 'channel': channel,
    if (version != null) 'version': version,
    if (url != null) 'url': url,
  });
}
