import 'dart:async';
import 'dart:convert';

import 'package:flipperlib/flipperlib.dart';
import 'package:flutter/foundation.dart';

import '../../../components/codec/dolphin/manifest.dart';
import '../../../services/dolphin/library.dart';
import '../../../services/guarded.dart';
import '../../../services/logging.dart';

class DolphinRegistry extends ChangeNotifier {
  DolphinRegistry({required this.client});

  final FlipperClient client;

  final Set<String> _names = {};
  bool _loaded = false;
  bool _loading = false;
  bool _wanted = false;

  bool contains(String name) => name.isNotEmpty && _names.contains(name);

  Future<void> ensureFresh() async {
    _wanted = true;
    if (_loaded || _loading) return;
    await refresh();
  }

  Future<void> refresh() {
    if (_loading || !client.isRpcReady) return Future.value();
    return client.runTask(FlipperRequestPriority.background, _refresh);
  }

  Future<void> _refresh() async {
    final token = client.deviceToken;
    _loading = true;
    try {
      final text = await readManifest(kDolphinManifestPath);
      if (token.isStale) return;
      _names
        ..clear()
        ..addAll(DolphinManifest.parse(text).entries.keys);
      _loaded = true;
    } catch (e) {
      LogService.warn('[Dolphin] reading the animation manifest failed: $e');
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<String> readManifest(String path) async {
    try {
      final bytes = await client.storageReadChunked(
        path,
        timeout: const Duration(seconds: 20),
      );
      return utf8.decode(bytes, allowMalformed: true);
    } on FlipperRpcStorageNotExistException {
      return '';
    }
  }

  void put(String name) {
    if (name.isEmpty || !_names.add(name)) return;
    notifyListeners();
  }

  void handleConnect() {
    if (!_wanted || _loaded) return;
    unawaited(guarded('[Dolphin] read animation manifest', refresh));
  }

  void handleDisconnect() {
    _loaded = false;
    notifyListeners();
  }

  void handleDeviceChange() {
    _names.clear();
    _loaded = false;
    notifyListeners();
  }
}
