import 'package:flutter/foundation.dart';

import '../../../config.dart';
import 'firmware_directory.dart';

class FirmwareRepository extends ChangeNotifier {
  FirmwareRepository._();
  static final FirmwareRepository instance = FirmwareRepository._();

  final Set<String> _loading = {};

  FirmwareDirectory? directoryFor(FirmwareEntry entry) =>
      parserForEntry(entry).cached;

  bool isLoading(FirmwareEntry entry) => _loading.contains(entry.shortName);

  Future<void> ensure(FirmwareEntry entry) async {
    if (parserForEntry(entry).hasCached) return;
    await _fetch(entry);
  }

  Future<void> prefetchAll() =>
      Future.wait(QAppConfig.firmware.firmwares.map(ensure));

  Future<void> refresh() =>
      Future.wait(QAppConfig.firmware.firmwares.map(_fetch));

  Future<void> _fetch(FirmwareEntry entry) async {
    final key = entry.shortName;
    if (_loading.contains(key)) return;
    _loading.add(key);
    notifyListeners();
    try {
      await parserForEntry(entry).fetch();
    } catch (_) {
    } finally {
      _loading.remove(key);
      notifyListeners();
    }
  }
}
