import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../http/app_http.dart';
import '../localization/l10n.dart';

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

/// The caller stopped waiting for the build. A job that was still queued is
/// dropped on the server as well; one that already started keeps building
/// there and holds this client's slot until it finishes.
class RemoteBuildCancelledException implements Exception {
  const RemoteBuildCancelledException();

  @override
  String toString() => l10n.remoteBuildCancelled;
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
      throw RemoteBuildException(l10n.remoteNotConfigured);
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
    bool Function()? isCancelled,
  }) async {
    if (!canBuild) {
      throw RemoteBuildException(l10n.remoteNoSigningKey);
    }
    final active = _activeAlias;
    if (active != null) {
      throw RemoteBuildException(l10n.remoteBusyWithApp(active));
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
        throw RemoteBuildException(l10n.remoteNoJobId);
      }
      final deadline = DateTime.now().add(timeout);
      while (true) {
        if (isCancelled?.call() ?? false) {
          await _cancelJob(id, clientId);
          throw const RemoteBuildCancelledException();
        }
        switch (status['status'] as String? ?? '') {
          case 'ready':
            return await _downloadArtifact(id, clientId, onPhase);
          case 'failed':
            throw RemoteBuildException(
              (status['error'] as String?)?.trim().isNotEmpty == true
                  ? l10n.remoteBuildFailedWith('${status['error']}')
                  : l10n.remoteBuildFailed,
            );
          case 'queued':
            onPhase?.call(RemoteBuildPhase.queued, 0);
          case 'building':
            onPhase?.call(RemoteBuildPhase.building, 0);
          default:
            throw RemoteBuildException(
              l10n.remoteUnknownStatus('${status['status']}'),
            );
        }
        if (DateTime.now().isAfter(deadline)) {
          throw RemoteBuildException(l10n.remoteTimedOut);
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
      throw RemoteBuildException(l10n.remoteEmptyArtifact);
    }
    return bytes;
  }

  /// Best effort: the server drops the job only while it is still queued, a
  /// 409 means the build had already started and nothing can stop it there.
  Future<void> _cancelJob(String id, String clientId) async {
    final path = '/api/v1/builds/$id';
    try {
      final request = await AppHttp.client.deleteUrl(_endpoint(path));
      _signedHeaders(
        'DELETE',
        path,
        const [],
        clientId,
      ).forEach(request.headers.set);
      final response = await request.close();
      await response.drain<void>();
    } catch (_) {}
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
    throw RemoteBuildException(l10n.remoteUnexpectedResponse);
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
            ? l10n.remoteRejectedWith(detail)
            : l10n.remoteRejected,
      401 || 403 => l10n.remoteBadSignature,
      404 when call == _RemoteCall.submit => l10n.remoteBundleNotFound,
      404 => l10n.remoteJobNotFound,
      409 when call == _RemoteCall.artifact => l10n.remoteArtifactNotReady,
      409 => l10n.remoteBusyOther,
      410 => l10n.remoteArtifactExpired,
      429 => l10n.remoteQueueFull,
      502 => l10n.remoteBundleHostUnavailable,
      504 => l10n.remoteBundleHostTimeout,
      _ =>
        detail.isNotEmpty
            ? l10n.remoteServerErrorWith(detail)
            : l10n.remoteServerErrorCode(statusCode),
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
