import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import '../../../services/guarded.dart';
import '../../../services/http/app_http.dart';
import '../../../services/logging.dart';
import '../../../services/storage/fap_icons.dart';
import '../../../components/codec/bm.dart';
import '../../../components/codec/fap/icon.dart';
import '../data/models/card.dart';
import '../data/models/manifest.dart';
import 'icon_codec.dart';

Uint8List? _fapMetaIcon(Uint8List raw) {
  try {
    final bits = BmCodec.decodeBmFile(raw);
    if (bits == null) return null;
    final rowBytes = (fapIconWidth + 7) >> 3;
    if (bits.length < rowBytes * fapIconHeight) return null;
    return bits.any((byte) => byte != 0) ? bits : null;
  } catch (_) {
    return null;
  }
}

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
    unawaited(guarded('[Icons] drain catalog queue', _drainCatalogQueue));
  }

  Future<void> _drainCatalogQueue() async {
    if (_catalogWorking) return;
    _catalogWorking = true;
    var failed = 0;
    var attempted = 0;
    try {
      while (_catalogQueue.isNotEmpty) {
        final alias = _catalogQueue.keys.first;
        final url = _catalogQueue.remove(alias)!;
        try {
          if (await hasFapIcon(alias)) continue;
          attempted++;
          final bytes = await AppHttp.getBytes(Uri.parse(url));
          final bits = decodeCatalogIconToFapBits(bytes);
          if (bits != null) await writeFapIcon(alias, bits);
        } catch (_) {
          failed++;
        }
      }
    } finally {
      if (failed > 0) {
        // Once for the drain, not once per icon. A catalogue that moved its
        // images, or a link that is down, fails every one of them - and a
        // line each would be a hundred of them for one cause.
        LogService.warn(
          '[Icons] could not fetch $failed of $attempted catalogue icon(s)',
        );
      }
      _catalogWorking = false;
    }
  }

  Future<bool> ensureFromManifest(String alias, AppManifest manifest) async {
    if (alias.isEmpty || manifest.iconBase64.isEmpty) return false;
    try {
      if (await hasFapIcon(alias)) return true;
      final raw = Uint8List.fromList(base64Decode(manifest.iconBase64));
      final bits = decodeCatalogIconToFapBits(raw) ?? _fapMetaIcon(raw);
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
