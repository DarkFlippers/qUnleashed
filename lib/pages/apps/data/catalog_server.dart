/// A catalog origin. API paths belong to the clients, not to the setting.
class CatalogServer {
  static const official = 'https://catalog.flipperzero.one';
  static const community = <String>['https://qunleashed.aperturefox.ru'];
  static const defaultServer = 'https://qunleashed.aperturefox.ru';
  static const preferenceKey = 'apps_catalog_server';

  /// What an installed app's `.fim` names [origin] by (Catalog): its host,
  /// with the port when it has one. Short, because every manifest is read
  /// over BLE, and the same for one server however its origin is spelled.
  static String manifestName(String origin) =>
      Uri.parse(normalize(origin)).authority;

  static String normalize(String input) {
    final text = input.trim();
    if (text.isEmpty) throw const FormatException('Empty catalog domain');
    final uri = Uri.tryParse(text.contains('://') ? text : 'https://$text');
    if (uri == null ||
        (uri.scheme != 'https' && uri.scheme != 'http') ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        (uri.path.isNotEmpty && uri.path != '/') ||
        uri.hasQuery ||
        uri.hasFragment ||
        RegExp(r'\s').hasMatch(text)) {
      throw const FormatException('Expected an HTTP(S) catalog domain');
    }
    return uri.replace(path: '').toString();
  }
}
