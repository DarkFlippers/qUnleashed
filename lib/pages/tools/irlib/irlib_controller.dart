import 'dart:async';
import 'dart:io' as io;

import 'package:flipperlib/flipperlib.dart';
import 'package:flutter/foundation.dart';

import '../../archive/archive_storage.dart';
import '../../archive/models/archive_category.dart';
import 'irlib_api.dart';
import 'irlib_models.dart';

class IrLibController extends ChangeNotifier {
  IrLibController({
    IrLibApi? api,
    FlipperClient? client,
    ArchiveStorage? storage,
  })  : _api = api ?? IrLibApi(),
        _client = client ?? FlipperOneClient().get(),
        _storage = storage ?? ArchiveStorage();

  final IrLibApi _api;
  final FlipperClient _client;
  final ArchiveStorage _storage;

  String _path = '';
  bool _loading = false;
  String? _error;
  List<IrEntry> _entries = const [];

  bool _searching = false;
  String _searchQuery = '';
  List<IrEntry> _searchResults = const [];
  String _searchProgressPath = '';

  String _deviceName = '';

  IrLibApi get api => _api;
  FlipperClient get client => _client;
  String get path => _path;
  bool get loading => _loading;
  String? get error => _error;
  List<IrEntry> get entries => _entries;
  bool get searching => _searching;
  String get searchQuery => _searchQuery;
  List<IrEntry> get searchResults => _searchResults;
  String get searchProgressPath => _searchProgressPath;
  bool get isConnected => _client.isConnected;
  String get deviceName => _deviceName;

  bool get canGoUp => _path.isNotEmpty;

  String get title {
    if (_path.isEmpty) return 'Flipper-IRDB';
    final segs = _path.split('/');
    return segs.last;
  }

  Future<void> initialize() async {
    final live = ArchiveStorage.normalizeDeviceName(_client.connectedDevice?.name);
    _deviceName = live ?? (await _storage.readLastDeviceName()) ?? 'Library';
    await openPath('');
  }

  Future<void> refresh() => openPath(_path, force: true);

  Future<void> openPath(String newPath, {bool force = false}) async {
    _path = _normalize(newPath);
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      if (force) _api.invalidateList(_path);
      final list = await _api.listDir(_path);
      _entries = list;
    } catch (e) {
      _error = '$e';
      _entries = const [];
      LogService.log('[IRLib] list "$_path" failed: $e');
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> goUp() async {
    if (!canGoUp) return;
    final idx = _path.lastIndexOf('/');
    final parent = idx <= 0 ? '' : _path.substring(0, idx);
    await openPath(parent);
  }

  Future<void> startSearch(String query) async {
    final q = query.trim();
    _searchQuery = q;
    if (q.isEmpty) {
      _searching = false;
      _searchResults = const [];
      notifyListeners();
      return;
    }
    if (_searching) return;
    _searching = true;
    _searchResults = const [];
    _searchProgressPath = '';
    notifyListeners();
    try {
      final results = await _api.searchAllIrFiles(
        query: q,
        onProgress: (found, current) {
          _searchProgressPath = current;
          notifyListeners();
        },
      );
      _searchResults = results;
    } catch (e) {
      _error = '$e';
      LogService.log('[IRLib] search "$q" failed: $e');
    } finally {
      _searching = false;
      notifyListeners();
    }
  }

  void clearSearch() {
    _searchQuery = '';
    _searchResults = const [];
    _searching = false;
    notifyListeners();
  }

  Future<List<int>?> readFileBytes(IrEntry entry) async {
    try {
      return await _api.fetchFile(entry);
    } catch (e) {
      _error = '$e';
      LogService.log('[IRLib] fetch ${entry.path} failed: $e');
      notifyListeners();
      return null;
    }
  }

  Future<io.File?> saveToArchive(IrEntry entry, List<int> bytes) async {
    try {
      final fileName = _archiveFileName(entry.name);
      return await _storage.saveBytes(
        _deviceName,
        ArchiveCategory.infrared,
        fileName,
        bytes,
      );
    } catch (e) {
      _error = '$e';
      LogService.log('[IRLib] save ${entry.path} failed: $e');
      notifyListeners();
      return null;
    }
  }

  Future<bool> sendToFlipper(
    IrEntry entry,
    List<int> bytes, {
    void Function(double progress)? onProgress,
  }) async {
    if (!_client.isConnected) return false;
    try {
      final fileName = _archiveFileName(entry.name);
      final remotePath = '/ext/infrared/$fileName';
      await _client.storageWriteChunked(
        remotePath,
        bytes,
        onProgress: onProgress,
      );
      return true;
    } catch (e) {
      _error = '$e';
      LogService.log('[IRLib] send ${entry.path} failed: $e');
      notifyListeners();
      return false;
    }
  }

  String _archiveFileName(String original) {
    final name = original.toLowerCase().endsWith('.ir')
        ? original
        : '$original.ir';
    return name.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');
  }

  String _normalize(String p) {
    var s = p.trim();
    while (s.startsWith('/')) {
      s = s.substring(1);
    }
    while (s.endsWith('/')) {
      s = s.substring(0, s.length - 1);
    }
    return s;
  }

  @override
  void dispose() {
    _api.close();
    super.dispose();
  }
}
