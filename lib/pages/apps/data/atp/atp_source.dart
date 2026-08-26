import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;

import 'package:archive/archive_io.dart';
import 'package:flutter/foundation.dart';

import '../../../../components/codec/bm.dart';
import '../../../../components/codec/fap/icon.dart';
import '../../../../components/path.dart';
import '../../../../services/http/app_http.dart';
import '../../../../services/logging.dart';
import '../../../../services/storage/paths.dart';
import 'atp_index.dart';

const String kAtpRepoUrl = 'https://github.com/xMasterX/all-the-plugins';
const String _kLatestReleaseUrl =
    'https://api.github.com/repos/xMasterX/all-the-plugins/releases/latest';
const String _kIndexAssetName = 'apps_index.txt';
const Duration _kIndexTtl = Duration(hours: 12);

class AtpSource extends ChangeNotifier {
  AtpSource._();

  static final AtpSource instance = AtpSource._();

  AtpIndex? _index;
  AtpBlock? _block;
  final Map<String, AtpEntry> _byAppId = {};
  final Map<String, Uint8List?> _icons = {};

  bool _loading = false;
  bool _loaded = false;
  Object? _error;

  AtpBlock? get block => _block;
  bool get loading => _loading;
  bool get loaded => _loaded;
  Object? get error => _error;
  String get tag => _block?.tag ?? '';
  List<AtpEntry> get entries => _block?.entries ?? const [];
  AtpEntry? entryFor(String appId) => appId.isEmpty ? null : _byAppId[appId];

  Uint8List? iconFor(String appId) {
    if (_icons.containsKey(appId)) return _icons[appId];
    final entry = _byAppId[appId];
    Uint8List? bits;
    if (entry != null && entry.iconBase64.isNotEmpty) {
      try {
        final decoded = BmCodec.decodeBmFile(
          Uint8List.fromList(base64Decode(entry.iconBase64)),
        );
        final rowBytes = (fapIconWidth + 7) >> 3;
        if (decoded != null &&
            decoded.length >= rowBytes * fapIconHeight &&
            decoded.any((byte) => byte != 0)) {
          bits = decoded;
        }
      } catch (_) {}
    }
    _icons[appId] = bits;
    return bits;
  }

  Future<void> ensureLoaded() async {
    if (_loading) return;
    if (!_loaded) {
      _loading = true;
      notifyListeners();
      try {
        final cached = await _readCache();
        if (cached != null) {
          _index = AtpIndex.parse(cached);
          _loaded = true;
          _error = null;
          _rebind();
          LogService.log('[ATP] index: ${_index!.blocks.length} block(s)');
        }
      } catch (e) {
        _error = e;
        LogService.log('[ATP] index cache read failed: $e');
      } finally {
        _loading = false;
        notifyListeners();
      }
    }
    if (!_loaded || await _cacheIsStale()) await downloadLatest();
  }

  Future<bool> _cacheIsStale() async {
    try {
      final file = await atpIndexFile();
      if (!await file.exists()) return true;
      final age = DateTime.now().difference(await file.lastModified());
      return age > _kIndexTtl;
    } catch (_) {
      return true;
    }
  }

  Future<void> downloadLatest() async {
    if (_loading) return;
    _loading = true;
    notifyListeners();
    try {
      final body = await _fetchReleaseIndex();
      if (body != null) {
        final file = await atpIndexFile();
        await file.writeAsString(body, flush: true);
        _index = AtpIndex.parse(body);
        _icons.clear();
        _loaded = true;
        _error = null;
        _rebind();
      }
    } catch (e) {
      _error = e;
      LogService.log('[ATP] release index download failed: $e');
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  String? _boundTarget;

  void _rebind() => bindTarget(_boundTarget);

  void bindTarget(String? target) {
    _boundTarget = target;
    final picked = _index?.blockFor(target: target);
    if (identical(picked, _block)) return;
    _block = picked;
    _byAppId
      ..clear()
      ..addEntries(picked?.entries.map((e) => MapEntry(e.appId, e)) ?? const []);
    _icons.clear();
    if (picked != null) {
      LogService.log(
        '[ATP] ${picked.api} ${picked.target} ${picked.tag}: '
        '${picked.entries.length} apps',
      );
    }
    notifyListeners();
  }

  Future<String?> _readCache() async {
    final file = await atpIndexFile();
    if (!await file.exists()) return null;
    final body = await file.readAsString();
    return body.trim().isEmpty ? null : body;
  }

  Future<String?> _fetchReleaseIndex() async {
    final release = await AppHttp.getJson(Uri.parse(_kLatestReleaseUrl));
    if (release is! Map<String, dynamic>) return null;
    for (final raw in (release['assets'] as List?) ?? const []) {
      if (raw is! Map<String, dynamic>) continue;
      if (raw['name'] != _kIndexAssetName) continue;
      final url = (raw['browser_download_url'] ?? '') as String;
      if (url.isEmpty) continue;
      final bytes = await AppHttp.getBytes(Uri.parse(url));
      return utf8.decode(bytes, allowMalformed: true);
    }
    LogService.log(
      '[ATP] release ${release['tag_name']} has no $_kIndexAssetName',
    );
    return null;
  }
}

class AtpArchive {
  AtpArchive._();

  static final AtpArchive instance = AtpArchive._();

  final Map<String, Future<void>> _unpacking = {};

  Future<List<int>> fetchFap(
    AtpEntry entry,
    String url, {
    required String tag,
    void Function(int received, int? total)? onProgress,
  }) async {
    final file = await fapFile(entry, tag);
    if (!await file.exists()) {
      final key = '$tag/${entry.pack}';
      await (_unpacking[key] ??= _unpack(entry.pack, url, tag, onProgress)
        ..whenComplete(() => _unpacking.remove(key)));
    }
    if (!await file.exists()) {
      throw StateError('"${entry.archivePath}" is not in the ${entry.pack} pack');
    }
    final bytes = await file.readAsBytes();
    onProgress?.call(bytes.length, bytes.length);
    return bytes;
  }

  Future<io.Directory> _packDirectory(String pack, String tag) async {
    final root = await atpRepositoryDirectory();
    return io.Directory(
      pathJoin([
        root.path,
        sanitizePathSegment(tag.isEmpty ? 'release' : tag),
        sanitizePathSegment(pack),
      ]),
    );
  }

  Future<io.File> fapFile(AtpEntry entry, String tag) async {
    final dir = await _packDirectory(entry.pack, tag);
    return io.File(
      pathJoin([
        dir.path,
        ...entry.folder
            .split('/')
            .where((e) => e.isNotEmpty)
            .map(sanitizePathSegment),
        '${entry.appId}.fap',
      ]),
    );
  }

  Future<void> _unpack(
    String pack,
    String url,
    String tag,
    void Function(int received, int? total)? onProgress,
  ) async {
    final dir = await _packDirectory(pack, tag);
    await dir.create(recursive: true);
    final zip = io.File(pathJoin([dir.path, '$pack.zip']));
    try {
      await AppHttp.downloadToFile(
        Uri.parse(url),
        zip.path,
        onProgress: onProgress,
      );
      final archive = ZipDecoder().decodeStream(InputFileStream(zip.path));
      var written = 0;
      for (final file in archive.files) {
        if (!file.isFile || !file.name.endsWith('.fap')) continue;
        final parts = file.name.split('/').where((e) => e.isNotEmpty).toList();
        final start = parts.indexWhere((e) => e.startsWith('artifacts-'));
        final relative = parts.sublist(start >= 0 ? start + 1 : 0);
        if (relative.isEmpty) continue;
        final out = io.File(
          pathJoin([dir.path, ...relative.map(sanitizePathSegment)]),
        );
        await out.parent.create(recursive: true);
        await out.writeAsBytes(file.readBytes() ?? const [], flush: true);
        written++;
      }
      LogService.log('[ATP] unpacked $written apps from the $pack pack');
    } finally {
      try {
        if (await zip.exists()) await zip.delete();
      } catch (_) {}
    }
  }
}
