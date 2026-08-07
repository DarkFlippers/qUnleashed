import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../http/app_http.dart';

/// The builder address is public; only the signing key is a secret, so the
/// server-build UI is always available and a build without a key fails loudly
/// instead of the whole feature disappearing from the app.
const String kRemoteBuildServerUrl = String.fromEnvironment(
  'QU_BUILD_SERVER_URL',
  defaultValue: 'https://flibler.aperturefox.ru',
);
const String kRemoteBuildServerKey = String.fromEnvironment(
  'QU_BUILD_SERVER_KEY',
);

class RemoteBuildException implements Exception {
  RemoteBuildException(this.message);

  final String message;

  @override
  String toString() => message;
}

enum RemoteBuildPhase { queued, building, download }

enum _RemoteCall { status, submit, poll, artifact }

class RemoteServerStatus {
  const RemoteServerStatus({
    required this.version,
    required this.queueLength,
    required this.sdkVersions,
  });

  final String version;
  final int queueLength;
  final List<String> sdkVersions;
}

class RemoteBuildService {
  RemoteBuildService._()
    : serverUrl = kRemoteBuildServerUrl,
      sharedKey = kRemoteBuildServerKey;

  RemoteBuildService.test({
    required this.serverUrl,
    required this.sharedKey,
    this.pollInterval = Duration.zero,
    String? clientId,
  }) : _clientId = clientId;

  static final RemoteBuildService instance = RemoteBuildService._();

  static const String userAgent = 'qUnleashed';
  static const String _clientIdPrefsKey = 'remote_build_client_id';

  final String serverUrl;
  final String sharedKey;

  Duration pollInterval = const Duration(seconds: 2);
  Duration timeout = const Duration(minutes: 20);

  /// The address is baked in, so the server UI is always reachable; only a
  /// build needs the signing key.
  bool get canBuild => serverUrl.isNotEmpty && sharedKey.isNotEmpty;

  String? _activeAlias;
  String? _clientId;

  bool get busy => _activeAlias != null;
  String? get activeAlias => _activeAlias;

  static String sign({
    required String secret,
    required int timestamp,
    required String method,
    required String path,
    required List<int> body,
    required String clientId,
  }) {
    final bodyHash = sha256.convert(body).toString();
    final message =
        '$timestamp\n${method.toUpperCase()}\n$path\n$bodyHash\n$clientId';
    return Hmac(
      sha256,
      utf8.encode(secret),
    ).convert(utf8.encode(message)).toString();
  }

  /// The server status endpoint needs no signature, so the settings page can
  /// show whether the builder is alive before any app is installed.
  Future<RemoteServerStatus> serverStatus() async {
    if (serverUrl.isEmpty) {
      throw RemoteBuildException('Build server is not configured');
    }
    final response = await AppHttp.get(
      _endpoint('/api/v1/status'),
      headers: {io.HttpHeaders.userAgentHeader: userAgent},
    );
    final text = await response.transform(utf8.decoder).join();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw RemoteBuildException(
        _serverError(response.statusCode, text, _RemoteCall.status),
      );
    }
    final body = _decodeObject(text);
    final sdks = (body['sdk'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .where((entry) => entry['deployed'] == true)
        .map(
          (entry) => '${entry['version'] ?? '—'} · ${entry['target'] ?? '—'}',
        )
        .toList();
    return RemoteServerStatus(
      version: body['version'] as String? ?? '—',
      queueLength: (body['queue_length'] as num?)?.toInt() ?? 0,
      sdkVersions: sdks,
    );
  }

  Future<List<int>> build({
    required String bundleUrl,
    required String alias,
    required String target,
    String? api,
    String? uid,
    String? versionUid,
    String channel = 'release',
    String? indexUrl,
    void Function(RemoteBuildPhase phase, double progress)? onPhase,
  }) async {
    if (!canBuild) {
      throw RemoteBuildException(
        'This build has no server signing key, rebuild it with '
        '--dart-define=QU_BUILD_SERVER_KEY',
      );
    }
    final active = _activeAlias;
    if (active != null) {
      throw RemoteBuildException(
        'Server is building "$active", wait for it to finish',
      );
    }
    _activeAlias = alias;
    try {
      final clientId = await _ensureClientId();
      var status = await _postJson('/api/v1/builds', clientId, {
        'bundle_url': bundleUrl,
        'alias': alias,
        'target': target,
        if (api != null && api.isNotEmpty) 'api': api,
        'channel': channel,
        if (indexUrl != null && indexUrl.isNotEmpty) 'index_url': indexUrl,
        if (uid != null && uid.isNotEmpty) 'uid': uid,
        if (versionUid != null && versionUid.isNotEmpty)
          'version_uid': versionUid,
      });
      final id = status['id'] as String? ?? '';
      if (id.isEmpty) {
        throw RemoteBuildException('Build server returned no job id');
      }
      final deadline = DateTime.now().add(timeout);
      while (true) {
        switch (status['status'] as String? ?? '') {
          case 'ready':
            return await _downloadArtifact(id, clientId, onPhase);
          case 'failed':
            throw RemoteBuildException(
              (status['error'] as String?)?.trim().isNotEmpty == true
                  ? 'Server build failed: ${status['error']}'
                  : 'Server build failed',
            );
          case 'queued':
            onPhase?.call(RemoteBuildPhase.queued, 0);
          case 'building':
            onPhase?.call(RemoteBuildPhase.building, 0);
          default:
            throw RemoteBuildException(
              'Unknown build status: ${status['status']}',
            );
        }
        if (DateTime.now().isAfter(deadline)) {
          throw RemoteBuildException('Server build timed out');
        }
        await Future<void>.delayed(pollInterval);
        status = await _getJson('/api/v1/builds/$id', clientId);
      }
    } finally {
      _activeAlias = null;
    }
  }

  Future<List<int>> _downloadArtifact(
    String id,
    String clientId,
    void Function(RemoteBuildPhase phase, double progress)? onPhase,
  ) async {
    final path = '/api/v1/builds/$id/artifact';
    onPhase?.call(RemoteBuildPhase.download, 0);
    final List<int> bytes;
    try {
      bytes = await AppHttp.getBytes(
        _endpoint(path),
        headers: _signedHeaders('GET', path, const [], clientId),
        onProgress: (received, total) {
          if (total == null || total <= 0) return;
          onPhase?.call(RemoteBuildPhase.download, received / total);
        },
      );
    } on AppHttpException catch (e) {
      throw RemoteBuildException(
        _serverError(e.statusCode, e.body ?? '', _RemoteCall.artifact),
      );
    }
    if (bytes.isEmpty) {
      throw RemoteBuildException('Build server returned an empty artifact');
    }
    return bytes;
  }

  Future<Map<String, dynamic>> _postJson(
    String path,
    String clientId,
    Map<String, dynamic> body,
  ) async {
    final bytes = utf8.encode(jsonEncode(body));
    final request = await AppHttp.client.postUrl(_endpoint(path));
    request.headers.set(io.HttpHeaders.contentTypeHeader, 'application/json');
    _signedHeaders('POST', path, bytes, clientId).forEach(request.headers.set);
    request.add(bytes);
    final response = await request.close();
    final text = await response.transform(utf8.decoder).join();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw RemoteBuildException(
        _serverError(response.statusCode, text, _RemoteCall.submit),
      );
    }
    return _decodeObject(text);
  }

  Future<Map<String, dynamic>> _getJson(String path, String clientId) async {
    final response = await AppHttp.get(
      _endpoint(path),
      headers: _signedHeaders('GET', path, const [], clientId),
    );
    final text = await response.transform(utf8.decoder).join();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw RemoteBuildException(
        _serverError(response.statusCode, text, _RemoteCall.poll),
      );
    }
    return _decodeObject(text);
  }

  Map<String, dynamic> _decodeObject(String text) {
    try {
      final decoded = jsonDecode(text);
      if (decoded is Map<String, dynamic>) return decoded;
    } catch (_) {}
    throw RemoteBuildException('Unexpected build server response');
  }

  String _serverError(int statusCode, String body, _RemoteCall call) {
    String detail = '';
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) {
        detail = decoded['detail'] as String? ?? '';
      }
    } catch (_) {}
    return switch (statusCode) {
      400 =>
        detail.isNotEmpty
            ? 'Build server rejected the request: $detail'
            : 'Build server rejected the request',
      401 || 403 =>
        'Build server rejected the request signature, '
            'check the signing key and the device clock',
      404 when call == _RemoteCall.submit =>
        'App bundle was not found at its link, '
            'the catalog entry may be outdated',
      404 => 'Build was not found on the server, start it again',
      409 when call == _RemoteCall.artifact =>
        'Build is not ready on the server or has failed',
      409 =>
        'Server is already building another app for this device, '
            'wait for it to finish',
      410 => 'Build artifact has expired on the server, start the build again',
      429 => 'Build queue is full, try again later',
      502 => 'App bundle host is unavailable, try again later',
      504 => 'App bundle host timed out, try again later',
      _ =>
        detail.isNotEmpty
            ? 'Build server error: $detail'
            : 'Build server error: HTTP $statusCode',
    };
  }

  Uri _endpoint(String path) {
    final base = Uri.parse(serverUrl);
    final basePath = base.path.endsWith('/')
        ? base.path.substring(0, base.path.length - 1)
        : base.path;
    return base.replace(path: '$basePath$path', queryParameters: null);
  }

  Map<String, String> _signedHeaders(
    String method,
    String path,
    List<int> body,
    String clientId,
  ) {
    final now = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
    return {
      io.HttpHeaders.userAgentHeader: userAgent,
      'X-QU-Client': clientId,
      'X-QU-Time': '$now',
      'X-QU-Sign': sign(
        secret: sharedKey,
        timestamp: now,
        method: method,
        path: path,
        body: body,
        clientId: clientId,
      ),
    };
  }

  Future<String> _ensureClientId() async {
    final existing = _clientId;
    if (existing != null && existing.isNotEmpty) return existing;
    final prefs = await SharedPreferences.getInstance();
    var id = prefs.getString(_clientIdPrefsKey);
    if (id == null || id.isEmpty) {
      final random = Random.secure();
      id = List.generate(
        16,
        (_) => random.nextInt(256),
      ).map((b) => b.toRadixString(16).padLeft(2, '0')).join();
      await prefs.setString(_clientIdPrefsKey, id);
    }
    return _clientId = id;
  }
}
