import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;

import 'irlib_models.dart';

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
    Duration timeout = const Duration(seconds: 25),
  }) : _http = io.HttpClient()..connectionTimeout = timeout;

  final String owner;
  final String repo;
  final String branch;
  final String userAgent;

  final io.HttpClient _http;
  bool _closed = false;

  final Map<String, List<IrEntry>> _listCache = {};
  final Map<String, List<int>> _fileCache = {};

  void close() {
    if (_closed) return;
    _closed = true;
    _http.close(force: true);
  }

  void invalidateList(String path) {
    _listCache.remove(_normalizePath(path));
  }

  String rawUrl(String path) =>
      'https://raw.githubusercontent.com/$owner/$repo/$branch/${Uri.encodeFull(path)}';

  Future<List<IrEntry>> listDir(String path) async {
    final normalized = _normalizePath(path);
    final cached = _listCache[normalized];
    if (cached != null) return cached;
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
    out.sort((a, b) {
      if (a.isDir != b.isDir) return a.isDir ? -1 : 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    _listCache[normalized] = out;
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
    return jsonDecode(text);
  }

  Future<io.HttpClientResponse> _send(Uri uri) async {
    if (_closed) throw StateError('IrLibApi has been closed');
    final req = await _http.getUrl(uri);
    req.headers
      ..set(io.HttpHeaders.userAgentHeader, userAgent)
      ..set(io.HttpHeaders.acceptHeader, 'application/vnd.github+json');
    return req.close();
  }
}
