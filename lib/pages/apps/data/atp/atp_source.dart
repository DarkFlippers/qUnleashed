import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;

import 'package:archive/archive_io.dart';
import 'package:flutter/foundation.dart';

import '../../../../components/archive_unpack.dart';
import '../../../../components/codec/bm.dart';
import '../../../../components/codec/fap/icon.dart';
import '../../../../components/path.dart';
import '../../../../services/http/app_http.dart';
import '../../../../services/logging.dart';
import '../../../../services/storage/paths.dart';
import 'atp_index.dart';

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

  AtpBlock? get block => _block;
  bool get loading => _loading;
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
          _rebind();
          LogService.log('[ATP] index: ${_index!.blocks.length} block(s)');
        }
      } catch (e) {
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
        _rebind();
      }
    } catch (e) {
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
      ..addEntries(
        picked?.entries.map((e) => MapEntry(e.appId, e)) ?? const [],
      );
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
    if (file == null) {
      throw StateError(
        '"${entry.archivePath}" is not a path the pack can hold',
      );
    }
    if (!await file.exists()) {
      final key = '$tag/${entry.pack}';
      await (_unpacking[key] ??= _unpack(entry.pack, url, tag, onProgress)
        ..whenComplete(() => _unpacking.remove(key)));
    }
    if (!await file.exists()) {
      throw StateError(
        '"${entry.archivePath}" is not in the ${entry.pack} pack',
      );
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

  /// Where [_unpack] would have written this entry, resolved the same way, so
  /// the reader never looks somewhere the writer could not put a file.
  /// `null` when the entry names no path the unpacker would accept.
  Future<io.File?> fapFile(AtpEntry entry, String tag) async {
    final dir = await _packDirectory(entry.pack, tag);
    final path = resolveArchivePath(dir.path, entry.archivePath);
    return path == null ? null : io.File(path);
  }

  /// Why [tally] should be reported as a failure, or null if the pack is
  /// usable.
  ///
  /// Deliberately laxer than the IR library's equivalent, which fails once a
  /// small share of entries is lost. A pack holds tens of apps rather than
  /// thousands of remotes, so any share worth setting is either never reached
  /// or reached by two bad names; and unlike a remote, a missing app is caught
  /// precisely where it is used — [fetchFap] finds no file and says which app
  /// is not in which pack. The case that has to fail here is the one that
  /// check cannot improve on: nothing was written at all, so every app in the
  /// pack would report itself missing, one at a time.
  @visibleForTesting
  static String? failureFor(UnpackTally tally) {
    if (tally.extracted > 0) return null;
    if (tally.skipped == 0 && tally.dropped == 0) {
      return 'it contained no .fap entries';
    }
    if (tally.skipped == 0) {
      return 'all ${tally.dropped} entries resolved outside the pack directory';
    }
    return 'all ${tally.skipped + tally.dropped} entries failed '
        '(first: ${tally.firstError})';
  }

  /// Writes every `.fap` entry of [archive] under [rootPath], skipping the ones
  /// that cannot be written or read instead of abandoning the whole pack.
  ///
  /// Only `.fap` entries are considered, so `extracted + skipped + dropped` is
  /// their number and not the archive's — a pack also carries a manifest and
  /// build logs, and those are ignored rather than counted as losses.
  ///
  /// Consumes [archive]: each entry's decompressed bytes are released once
  /// written.
  @visibleForTesting
  static Future<UnpackTally> unpackPackTo(
    Archive archive,
    String rootPath, {
    String? separator,
  }) async {
    // create(recursive: true) is not free when the directory is already there,
    // and a pack puts many apps under the same few folders.
    final created = <String>{};
    Future<void> ensureDir(String path) async {
      if (!created.add(path)) return;
      await io.Directory(path).create(recursive: true);
    }

    var extracted = 0;
    var skipped = 0;
    var dropped = 0;
    String? firstError;

    for (final file in archive.files) {
      if (!file.isFile || !file.name.endsWith('.fap')) continue;

      final parts = file.name.split('/');
      final start = parts.indexWhere((e) => e.startsWith('artifacts-'));
      // The pack is a third-party download, so an entry that points out of
      // the pack directory is dropped rather than written.
      final outPath = resolveArchivePath(
        rootPath,
        parts.sublist(start >= 0 ? start + 1 : 0).join('/'),
        separator: separator,
      );
      if (outPath == null) {
        dropped += 1;
        continue;
      }

      try {
        // A null here means the entry has no readable content. Writing an
        // empty file instead would leave a 0-byte .fap that exists, so
        // fetchFap hands the installer an empty app rather than saying the
        // app is not in the pack.
        final bytes = file.readBytes();
        if (bytes == null) {
          skipped += 1;
          firstError ??= '${file.name}: the archive entry could not be read';
          continue;
        }
        final out = io.File(outPath);
        await ensureDir(out.parent.path);
        // Deliberately unflushed: the zip is re-downloadable and an
        // interrupted unpack already leaves a partial tree, so an fsync per
        // app buys nothing for what it costs.
        await out.writeAsBytes(bytes);
        // readBytes caches the inflated bytes on the entry and nothing frees
        // them, so without this the whole decompressed pack stays live.
        file.clear();
        extracted += 1;
      } on io.FileSystemException catch (e) {
        // Narrow on purpose. Every failure this tolerates is a
        // FileSystemException - a reserved name, a full disk, a collision
        // with something the archive already wrote there. Catching Object
        // would fold a decoder bug into "the filesystem refused it".
        skipped += 1;
        firstError ??= '${file.name}: $e';
      }
    }

    return UnpackTally(
      extracted: extracted,
      skipped: skipped,
      dropped: dropped,
      firstError: firstError,
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
      final tally = await unpackPackTo(archive, dir.path);
      final failure = failureFor(tally);
      if (failure != null) {
        throw StateError('the $pack pack could not be unpacked: $failure');
      }
      LogService.log(
        '[ATP] unpacked ${tally.extracted} apps from the $pack pack'
        '${tally.skipped > 0 ? ', skipped ${tally.skipped} '
                  '(first: ${tally.firstError})' : ''}'
        '${tally.dropped > 0 ? ', dropped ${tally.dropped}' : ''}',
      );
    } finally {
      try {
        if (await zip.exists()) await zip.delete();
      } catch (_) {}
    }
  }
}
