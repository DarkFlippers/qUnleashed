import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;

import 'package:flutter/foundation.dart';

import '../../../services/http/app_http.dart';
import 'models.dart';

class IrLibException implements Exception {
  IrLibException(this.statusCode, this.url, [this.body]);
  final int statusCode;
  final String url;
  final String? body;

  @override
  String toString() =>
      'IrLibException($statusCode, $url${body == null ? '' : ', $body'})';
}

class IrLibApi {
  IrLibApi({
    this.owner = 'Lucaslhm',
    this.repo = 'Flipper-IRDB',
    this.branch = 'main',
    this.userAgent = 'qunleashed-irlib',
    this.token = '',
    this.localRoot = '',
  });

  final String owner;
  final String repo;
  final String branch;
  final String userAgent;
  final String token;
  final String localRoot;

  bool _closed = false;

  final Map<String, List<IrEntry>> _listCache = {};
  final Map<String, List<int>> _fileCache = {};

  bool get useLocal => localRoot.trim().isNotEmpty;

  void close() {
    _closed = true;
  }

  void invalidateList(String path) {
    _listCache.remove(_normalizePath(path));
  }

  void invalidateAll() {
    _listCache.clear();
    _fileCache.clear();
  }

  String rawUrl(String path) =>
      'https://raw.githubusercontent.com/$owner/$repo/$branch/${Uri.encodeFull(path)}';

  Future<List<IrEntry>> listDir(String path) async {
    final normalized = _normalizePath(path);
    final cached = _listCache[normalized];
    if (cached != null) return cached;
    final out =
        useLocal ? await _listLocal(normalized) : await _listRemote(normalized);
    out.sort((a, b) {
      if (a.isDir != b.isDir) return a.isDir ? -1 : 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    _listCache[normalized] = out;
    return out;
  }

  Future<List<IrEntry>> _listLocal(String normalized) async {
    final dir = _localDir(normalized);
    if (!await dir.exists()) {
      throw IrLibException(0, dir.path, 'directory not found');
    }
    final out = <IrEntry>[];
    await for (final entity in dir.list(followLinks: false)) {
      final name =
          entity.uri.pathSegments.where((s) => s.isNotEmpty).last;
      if (name.startsWith('.')) continue;
      final relPath = normalized.isEmpty ? name : '$normalized/$name';
      if (entity is io.Directory) {
        out.add(IrEntry(name: name, path: relPath, type: IrEntryType.dir));
      } else if (entity is io.File) {
        final stat = await entity.stat();
        out.add(IrEntry(
          name: name,
          path: relPath,
          type: IrEntryType.file,
          size: stat.size,
        ));
      }
    }
    return out;
  }

  Future<List<IrEntry>> _listRemote(String normalized) async {
    final segs = normalized.isEmpty
        ? ''
        : normalized.split('/').map(Uri.encodeComponent).join('/');
    final uri = Uri.parse(
      'https://api.github.com/repos/$owner/$repo/contents/$segs?ref=$branch',
    );
    final body = await _getJson(uri);
    if (body is! List) {
      throw IrLibException(0, uri.toString(), 'expected list');
    }
    final out = <IrEntry>[];
    for (final raw in body) {
      if (raw is! Map<String, dynamic>) continue;
      final name = '${raw['name']}';
      final p = '${raw['path']}';
      final type = '${raw['type']}';
      final size = (raw['size'] is num) ? (raw['size'] as num).toInt() : 0;
      final dl = raw['download_url'];
      if (type == 'dir') {
        out.add(IrEntry(name: name, path: p, type: IrEntryType.dir));
      } else if (type == 'file') {
        out.add(IrEntry(
          name: name,
          path: p,
          type: IrEntryType.file,
          size: size,
          downloadUrl: dl is String ? dl : null,
        ));
      }
    }
    return out;
  }

  Future<List<IrEntry>> searchAllIrFiles({
    required String query,
    required void Function(int found, String currentPath) onProgress,
    int maxResults = 200,
  }) async {
    final results = <IrEntry>[];
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return results;
    final stack = <String>[''];
    while (stack.isNotEmpty && results.length < maxResults) {
      final p = stack.removeLast();
      onProgress(results.length, p.isEmpty ? '/' : p);
      List<IrEntry> entries;
      try {
        entries = await listDir(p);
      } catch (_) {
        continue;
      }
      for (final e in entries) {
        if (e.isDir) {
          stack.add(e.path);
        } else if (e.isIrFile && e.name.toLowerCase().contains(q)) {
          results.add(e);
          if (results.length >= maxResults) break;
        }
      }
    }
    return results;
  }

  Future<List<int>> fetchFile(IrEntry entry) async {
    if (!entry.isIrFile && entry.type != IrEntryType.file) {
      throw StateError('Not a file: ${entry.path}');
    }
    final cached = _fileCache[entry.path];
    if (cached != null) return cached;
    if (useLocal) {
      final file = io.File(_localDir(entry.path).path);
      if (!await file.exists()) {
        throw IrLibException(0, file.path, 'file not found');
      }
      final bytes = await file.readAsBytes();
      _fileCache[entry.path] = bytes;
      return bytes;
    }
    final url = entry.downloadUrl ?? rawUrl(entry.path);
    final res = await _send(Uri.parse(url));
    if (res.statusCode < 200 || res.statusCode >= 300) {
      final text = await res.transform(utf8.decoder).join();
      throw IrLibException(res.statusCode, url, text);
    }
    final out = <int>[];
    await for (final chunk in res) {
      out.addAll(chunk);
    }
    _fileCache[entry.path] = out;
    return out;
  }

  io.Directory _localDir(String relPath) {
    final sep = io.Platform.pathSeparator;
    final root = localRoot.replaceAll('/', sep).replaceAll('\\', sep);
    if (relPath.isEmpty) return io.Directory(root);
    final rel = relPath.replaceAll('/', sep);
    return io.Directory('$root$sep$rel');
  }

  String _normalizePath(String path) {
    var p = path.trim();
    while (p.startsWith('/')) {
      p = p.substring(1);
    }
    while (p.endsWith('/')) {
      p = p.substring(0, p.length - 1);
    }
    return p;
  }

  Future<dynamic> _getJson(Uri uri) async {
    final res = await _send(uri);
    final text = await res.transform(utf8.decoder).join();
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw IrLibException(res.statusCode, uri.toString(), text);
    }
    if (text.isEmpty) return null;
    return compute(jsonDecode, text);
  }

  Future<io.HttpClientResponse> _send(Uri uri) async {
    if (_closed) throw StateError('IrLibApi has been closed');
    return AppHttp.get(uri, headers: {
      io.HttpHeaders.userAgentHeader: userAgent,
      io.HttpHeaders.acceptHeader: 'application/vnd.github+json',
      if (token.trim().isNotEmpty)
        io.HttpHeaders.authorizationHeader: 'Bearer ${token.trim()}',
    });
  }
}
