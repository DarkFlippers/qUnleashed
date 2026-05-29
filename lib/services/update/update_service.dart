import 'dart:async';
import 'dart:convert';

import 'firmware_directory.dart';
import 'ofw_parser.dart';
import 'unleashed_parser.dart';
import '../repository/app.dart';

class FirmwareUpdateCheckResult {
  const FirmwareUpdateCheckResult({
    required this.source,
    required this.sourceName,
    required this.previousVersion,
    required this.newVersion,
  });

  final String source;
  final String sourceName;
  final String previousVersion;
  final String newVersion;
}

class UpdateService {
  static final UpdateService instance = UpdateService._();
  UpdateService._();

  final _updateController = StreamController<void>.broadcast();
  Stream<void> get onUpdated => _updateController.stream;

  bool _sessionChecked = false;
  bool _checking = false;

  FirmwareDirectory? _ofwDirectory;
  FirmwareDirectory? _unleashedDirectory;

  FirmwareDirectory? get ofwDirectory => _ofwDirectory;
  FirmwareDirectory? get unleashedDirectory => _unleashedDirectory;

  FirmwareDirectory? directoryForSource(String key) =>
      key == 'ofw' ? _ofwDirectory : _unleashedDirectory;

  Future<void> initialize() async {
    await _loadFromDisk();
    _updateController.add(null);
  }

  Future<void> checkIfNeeded() async {
    if (_sessionChecked || _checking) return;
    _checking = true;
    try {
      await _fetchAll();
      _sessionChecked = true;
      _updateController.add(null);
    } finally {
      _checking = false;
    }
  }

  Future<void> refresh() async {
    if (_checking) return;
    _sessionChecked = false;
    await checkIfNeeded();
  }

  Future<List<FirmwareUpdateCheckResult>> checkForUpdates() async {
    if (_checking) return const [];

    _checking = true;
    try {
      final updates = await Future.wait([
        _checkSourceForUpdate(
          key: 'ofw',
          sourceName: 'Official Firmware',
          parser: OfwParser.instance,
        ),
        _checkSourceForUpdate(
          key: 'unlshd',
          sourceName: 'Unleashed Firmware',
          parser: UnleashedParser.instance,
        ),
      ]);
      _sessionChecked = true;
      _updateController.add(null);
      return updates.nonNulls.toList();
    } finally {
      _checking = false;
    }
  }

  Future<FirmwareUpdateCheckResult?> _checkSourceForUpdate({
    required String key,
    required String sourceName,
    required FirmwareParser parser,
  }) async {
    await _loadSourceFromDisk(key);
    final before = _releaseVersion(directoryForSource(key));

    await _fetchSource(key, parser);
    final after = _releaseVersion(directoryForSource(key));

    if (!_versionChanged(before, after)) return null;
    return FirmwareUpdateCheckResult(
      source: key,
      sourceName: sourceName,
      previousVersion: before!,
      newVersion: after!,
    );
  }

  Future<void> _fetchAll() async {
    await Future.wait([
      _fetchSource('ofw', OfwParser.instance),
      _fetchSource('unlshd', UnleashedParser.instance),
    ]);
  }

  Future<void> _fetchSource(String key, FirmwareParser parser) async {
    try {
      final dir = await parser.fetch();
      if (key == 'ofw') {
        _ofwDirectory = dir;
      } else {
        _unleashedDirectory = dir;
      }
      await _saveToDisk(key, dir);
    } catch (_) {}
  }

  Future<void> _loadFromDisk() async {
    for (final key in ['ofw', 'unlshd']) {
      await _loadSourceFromDisk(key);
    }
  }

  Future<void> _loadSourceFromDisk(String key) async {
    try {
      final file = await updateCacheFile(key);
      if (!await file.exists()) return;
      final json =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      final dir = FirmwareDirectory.fromJson(json);
      if (key == 'ofw') {
        _ofwDirectory = dir;
        OfwParser.instance.injectCache(dir);
      } else {
        _unleashedDirectory = dir;
        UnleashedParser.instance.injectCache(dir);
      }
    } catch (_) {
      return;
    }
  }

  Future<void> _saveToDisk(String key, FirmwareDirectory dir) async {
    try {
      final file = await updateCacheFile(key);
      await file.writeAsString(jsonEncode(dir.toJson()));
    } catch (_) {}
  }

  String? _releaseVersion(FirmwareDirectory? dir) =>
      dir?.channelById('release')?.latest?.version;

  bool _versionChanged(String? before, String? after) =>
      before != null && after != null && before != after;
}
