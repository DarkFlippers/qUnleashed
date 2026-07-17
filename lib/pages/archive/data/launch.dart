enum LaunchMethod { none, app, rpc }

class LaunchRule {
  const LaunchRule({this.whenProtocol, this.whenMeta, required this.method});

  final String? whenProtocol;
  final ({String key, String value})? whenMeta;
  final LaunchMethod method;
}

class LaunchConfig {
  const LaunchConfig({
    this.defaultMethod = LaunchMethod.none,
    this.rules = const [],
    this.holdToSend = false,
  });

  final LaunchMethod defaultMethod;
  final List<LaunchRule> rules;
  final bool holdToSend;

  bool get canLaunch =>
      defaultMethod != LaunchMethod.none ||
      rules.any((r) => r.method != LaunchMethod.none);

  bool get hasProtocolRules => rules.any((r) => r.whenProtocol != null);

  LaunchMethod resolve({String? protocol, Map<String, String>? meta}) {
    for (final r in rules) {
      if (r.whenProtocol != null &&
          protocol != null &&
          protocol.toLowerCase() == r.whenProtocol!.toLowerCase()) {
        return r.method;
      }
      final whenMeta = r.whenMeta;
      if (whenMeta != null && meta != null && meta[whenMeta.key] == whenMeta.value) {
        return r.method;
      }
    }
    return defaultMethod;
  }
}
