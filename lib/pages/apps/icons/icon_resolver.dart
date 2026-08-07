import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import '../../../services/http/app_http.dart';
import '../../../services/storage/fap_icons.dart';
import '../../../components/codec/fap_icon.dart';
import '../data/models/card.dart';
import '../data/models/manifest.dart';
import 'icon_codec.dart';

class IconResolver {
  IconResolver._();
  static final IconResolver instance = IconResolver._();

  final Map<String, String> _catalogQueue = {};
  bool _catalogWorking = false;

  void warmFromCatalog(Iterable<AppCard> apps) {
    for (final app in apps) {
      final alias = app.alias;
      final url = app.iconUri;
      if (alias.isEmpty || url.isEmpty) continue;
      if (url.toLowerCase().endsWith('.svg')) continue;
      _catalogQueue.putIfAbsent(alias, () => url);
    }
    unawaited(_drainCatalogQueue());
  }

  Future<void> _drainCatalogQueue() async {
    if (_catalogWorking) return;
    _catalogWorking = true;
    try {
      while (_catalogQueue.isNotEmpty) {
        final alias = _catalogQueue.keys.first;
        final url = _catalogQueue.remove(alias)!;
        try {
          if (await hasFapIcon(alias)) continue;
          final bytes = await AppHttp.getBytes(Uri.parse(url));
          final bits = decodeCatalogIconToFapBits(bytes);
          if (bits != null) await writeFapIcon(alias, bits);
        } catch (_) {}
      }
    } finally {
      _catalogWorking = false;
    }
  }

  Future<bool> ensureFromManifest(String alias, AppManifest manifest) async {
    if (alias.isEmpty || manifest.iconBase64.isEmpty) return false;
    try {
      if (await hasFapIcon(alias)) return true;
      final png = base64Decode(manifest.iconBase64);
      final bits = decodeCatalogIconToFapBits(Uint8List.fromList(png));
      if (bits == null) return false;
      await writeFapIcon(alias, bits);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> ensureFromFap(String alias, List<int> fapBytes) async {
    if (alias.isEmpty) return false;
    try {
      if (await hasFapIcon(alias)) return true;
      final icon = extractFapIcon(Uint8List.fromList(fapBytes))?.icon;
      if (icon == null) return false;
      await writeFapIcon(alias, icon);
      return true;
    } catch (_) {
      return false;
    }
  }
}
