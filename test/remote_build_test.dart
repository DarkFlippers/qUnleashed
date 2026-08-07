import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qunleashed/services/assembler/remote_build_service.dart';

/// The live test runs only against a real deployment:
///   QU_BUILD_SERVER_URL=https://flibler.aperturefox.ru \
///   QU_BUILD_SERVER_KEY=`secret` flutter test test/remote_build_test.dart

const _secret = 'test-secret';
const _clientId = 'client-1';

String _expectedSign(HttpRequest request, List<int> body) {
  final time = request.headers.value('X-QU-Time')!;
  final bodyHash = sha256.convert(body).toString();
  final message =
      '$time\n${request.method}\n${request.uri.path}\n$bodyHash\n$_clientId';
  return Hmac(
    sha256,
    utf8.encode(_secret),
  ).convert(utf8.encode(message)).toString();
}

class _FakeBuildServer {
  _FakeBuildServer(this.server);

  final HttpServer server;
  final List<String> failures = [];
  int statusPolls = 0;
  bool failBuild = false;
  int? submitCode;
  int? artifactCode;
  String? errorDetail;

  String get url => 'http://127.0.0.1:${server.port}';

  static Future<_FakeBuildServer> start() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final fake = _FakeBuildServer(server);
    server.listen(fake._handle);
    return fake;
  }

  Future<void> _handle(HttpRequest request) async {
    final body = await request.fold<List<int>>([], (a, b) => a..addAll(b));
    final userAgent = request.headers.value(HttpHeaders.userAgentHeader) ?? '';
    if (!userAgent.contains('qUnleashed')) {
      failures.add('user-agent: $userAgent');
    }
    if (request.headers.value('X-QU-Sign') != _expectedSign(request, body)) {
      failures.add('signature mismatch on ${request.uri.path}');
      request.response.statusCode = 403;
      await request.response.close();
      return;
    }

    final path = request.uri.path;
    if (request.method == 'POST' && path == '/api/v1/builds') {
      final decoded = jsonDecode(utf8.decode(body)) as Map<String, dynamic>;
      if (decoded['bundle_url'] == null || decoded['target'] == null) {
        failures.add('bad submit body: $decoded');
      }
      if (submitCode != null) {
        request.response.statusCode = submitCode!;
        _json(request.response, {'detail': errorDetail ?? 'error'});
      } else {
        _json(request.response, {'id': 'job-1', 'status': 'queued'});
      }
    } else if (request.method == 'GET' && path == '/api/v1/builds/job-1') {
      statusPolls += 1;
      if (failBuild) {
        _json(request.response, {
          'id': 'job-1',
          'status': 'failed',
          'error': 'ufbt failed with exit code 2',
        });
      } else if (statusPolls == 1) {
        _json(request.response, {
          'id': 'job-1',
          'status': 'building',
          'detail': 'building',
        });
      } else {
        _json(request.response, {
          'id': 'job-1',
          'status': 'ready',
          'fap_name': 'test_app.fap',
        });
      }
    } else if (request.method == 'GET' &&
        path == '/api/v1/builds/job-1/artifact') {
      if (artifactCode != null) {
        request.response.statusCode = artifactCode!;
        _json(request.response, {'detail': errorDetail ?? 'error'});
      } else {
        request.response.headers.contentType = ContentType.binary;
        request.response.add(utf8.encode('FAPDATA'));
      }
    } else {
      failures.add('unexpected request: ${request.method} $path');
      request.response.statusCode = 404;
    }
    await request.response.close();
  }

  void _json(HttpResponse response, Map<String, dynamic> body) {
    response.headers.contentType = ContentType.json;
    response.write(jsonEncode(body));
  }

  Future<void> close() => server.close(force: true);
}

void main() {
  test('signature matches the server reference vector', () {
    final sign = RemoteBuildService.sign(
      secret: 'test-secret',
      timestamp: 1700000000,
      method: 'POST',
      path: '/api/v1/builds',
      body: utf8.encode('{"a":1}'),
      clientId: 'client-1',
    );
    expect(
      sign,
      'cac731ef11893f020bfbc4d65b81ad9cfb822ae6219398cf1e09972d371ac8a1',
    );
  });

  test('server status is read without a signature', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    var signed = true;
    server.listen((request) async {
      signed = request.headers.value('X-QU-Sign') != null;
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode({
          'version': '0.1.0',
          'queue_length': 2,
          'sdk': [
            {'deployed': true, 'version': 'unlshd-090', 'target': 'f7'},
            {'deployed': false, 'version': null, 'target': 'f18'},
          ],
        }),
      );
      await request.response.close();
    });

    final status = await RemoteBuildService.test(
      serverUrl: 'http://127.0.0.1:${server.port}',
      sharedKey: _secret,
    ).serverStatus();

    expect(signed, isFalse);
    expect(status.version, '0.1.0');
    expect(status.queueLength, 2);
    expect(status.sdkVersions, ['unlshd-090 · f7']);
  });

  test('a build without a signing key refuses to start', () {
    final service = RemoteBuildService.test(
      serverUrl: 'https://build.test',
      sharedKey: '',
    );
    expect(service.canBuild, isFalse);
    expect(
      () => service.build(
        bundleUrl: 'https://catalog.flipperzero.one/x/bundle',
        alias: 'x',
        target: 'f7',
      ),
      throwsA(
        isA<RemoteBuildException>().having(
          (e) => e.message,
          'message',
          contains('QU_BUILD_SERVER_KEY'),
        ),
      ),
    );
  });

  test('full build flow: submit, poll, download', () async {
    final fake = await _FakeBuildServer.start();
    addTearDown(fake.close);

    final service = RemoteBuildService.test(
      serverUrl: fake.url,
      sharedKey: _secret,
      clientId: _clientId,
    );

    final phases = <RemoteBuildPhase>[];
    final bytes = await service.build(
      bundleUrl:
          'https://catalog.flipperzero.one/api/v0/application/version/v1/bundle',
      alias: 'test_app',
      target: 'f7',
      api: '86.0',
      uid: 'uid-1',
      versionUid: 'v1',
      onPhase: (phase, progress) {
        if (phases.isEmpty || phases.last != phase) phases.add(phase);
      },
    );

    expect(fake.failures, isEmpty);
    expect(utf8.decode(bytes), 'FAPDATA');
    expect(phases, [
      RemoteBuildPhase.queued,
      RemoteBuildPhase.building,
      RemoteBuildPhase.download,
    ]);
    expect(service.busy, isFalse);
  });

  test('failed build surfaces the server error', () async {
    final fake = await _FakeBuildServer.start();
    addTearDown(fake.close);
    fake.failBuild = true;

    final service = RemoteBuildService.test(
      serverUrl: fake.url,
      sharedKey: _secret,
      clientId: _clientId,
    );

    await expectLater(
      service.build(
        bundleUrl:
            'https://catalog.flipperzero.one/api/v0/application/version/v1/bundle',
        alias: 'test_app',
        target: 'f7',
      ),
      throwsA(
        isA<RemoteBuildException>().having(
          (e) => e.message,
          'message',
          contains('ufbt failed'),
        ),
      ),
    );
    expect(service.busy, isFalse);
  });

  test('second build while busy is rejected', () async {
    final fake = await _FakeBuildServer.start();
    addTearDown(fake.close);

    final service = RemoteBuildService.test(
      serverUrl: fake.url,
      sharedKey: _secret,
      clientId: _clientId,
    )..pollInterval = const Duration(milliseconds: 50);

    final first = service.build(
      bundleUrl:
          'https://catalog.flipperzero.one/api/v0/application/version/v1/bundle',
      alias: 'first_app',
      target: 'f7',
    );

    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(service.busy, isTrue);
    expect(service.activeAlias, 'first_app');
    await expectLater(
      service.build(
        bundleUrl:
            'https://catalog.flipperzero.one/api/v0/application/version/v2/bundle',
        alias: 'second_app',
        target: 'f7',
      ),
      throwsA(
        isA<RemoteBuildException>().having(
          (e) => e.message,
          'message',
          contains('first_app'),
        ),
      ),
    );

    await first;
    expect(service.busy, isFalse);
  });

  Future<void> expectSubmitError(
    int code,
    String detail,
    Matcher message,
  ) async {
    final fake = await _FakeBuildServer.start();
    addTearDown(fake.close);
    fake
      ..submitCode = code
      ..errorDetail = detail;

    final service = RemoteBuildService.test(
      serverUrl: fake.url,
      sharedKey: _secret,
      clientId: _clientId,
    );

    await expectLater(
      service.build(
        bundleUrl:
            'https://catalog.flipperzero.one/api/v0/application/version/v1/bundle',
        alias: 'test_app',
        target: 'f7',
      ),
      throwsA(
        isA<RemoteBuildException>().having(
          (e) => e.message,
          'message',
          message,
        ),
      ),
    );
    expect(service.busy, isFalse);
  }

  test('submit conflict means this client already has a build', () async {
    await expectSubmitError(
      409,
      'Another build is in progress: job-0',
      contains('already building another app'),
    );
  });

  test('submit rejects surface the new status codes', () async {
    await expectSubmitError(400, 'Invalid target', contains('Invalid target'));
    await expectSubmitError(404, 'Bundle not found', contains('App bundle'));
    await expectSubmitError(
      429,
      'Build queue is full',
      contains('queue is full'),
    );
    await expectSubmitError(
      502,
      'Bad gateway',
      contains('bundle host is unavailable'),
    );
    await expectSubmitError(504, 'Timeout', contains('bundle host timed out'));
  });

  Future<void> expectArtifactError(
    int code,
    String detail,
    Matcher message,
  ) async {
    final fake = await _FakeBuildServer.start();
    addTearDown(fake.close);
    fake
      ..artifactCode = code
      ..errorDetail = detail;

    final service = RemoteBuildService.test(
      serverUrl: fake.url,
      sharedKey: _secret,
      clientId: _clientId,
    );

    await expectLater(
      service.build(
        bundleUrl:
            'https://catalog.flipperzero.one/api/v0/application/version/v1/bundle',
        alias: 'test_app',
        target: 'f7',
      ),
      throwsA(
        isA<RemoteBuildException>().having(
          (e) => e.message,
          'message',
          message,
        ),
      ),
    );
    expect(service.busy, isFalse);
  }

  test('artifact conflict and expiry are mapped to readable errors', () async {
    await expectArtifactError(
      409,
      'Build is not ready',
      contains('not ready on the server'),
    );
    await expectArtifactError(
      410,
      'Artifact expired',
      contains('expired on the server'),
    );
  });

  test('a rejected signature is reported as an authorization error', () async {
    final fake = await _FakeBuildServer.start();
    addTearDown(fake.close);

    final service = RemoteBuildService.test(
      serverUrl: fake.url,
      sharedKey: 'wrong-secret',
      clientId: _clientId,
    );

    await expectLater(
      service.build(
        bundleUrl:
            'https://catalog.flipperzero.one/api/v0/application/version/v1/bundle',
        alias: 'test_app',
        target: 'f7',
      ),
      throwsA(
        isA<RemoteBuildException>().having(
          (e) => e.message,
          'message',
          contains('signing key'),
        ),
      ),
    );
  });

  final liveUrl = Platform.environment['QU_BUILD_SERVER_URL'];
  final liveKey = Platform.environment['QU_BUILD_SERVER_KEY'];
  final liveReady = (liveUrl ?? '').isNotEmpty && (liveKey ?? '').isNotEmpty;

  test(
    'live server builds a catalog app end to end',
    () async {
      final http = HttpClient();
      final req = await http.getUrl(
        Uri.parse(
          'https://catalog.flipperzero.one/api/v0/application/flappy_bird',
        ),
      );
      req.headers.set(HttpHeaders.userAgentHeader, 'qunleashed-app');
      final res = await req.close();
      final detail =
          jsonDecode(await res.transform(utf8.decoder).join())
              as Map<String, dynamic>;
      http.close();
      final uid = (detail['_id'] ?? detail['id']) as String;
      final cv = detail['current_version'] as Map<String, dynamic>;
      final versionId = (cv['_id'] ?? cv['id']) as String;
      final api =
          ((cv['current_build'] as Map<String, dynamic>?)?['sdk']
                  as Map<String, dynamic>?)?['api']
              as String? ??
          '';

      final service = RemoteBuildService.test(
        serverUrl: liveUrl!,
        sharedKey: liveKey!,
        clientId: 'live-test',
        pollInterval: const Duration(seconds: 3),
      );

      final phases = <RemoteBuildPhase>[];
      final bytes = await service.build(
        bundleUrl:
            'https://catalog.flipperzero.one/api/v0/application/version/$versionId/bundle',
        alias: 'flappy_bird',
        target: 'f7',
        api: api,
        uid: uid,
        versionUid: versionId,
        onPhase: (phase, _) {
          if (phases.isEmpty || phases.last != phase) phases.add(phase);
        },
      );

      expect(bytes.length, greaterThan(1024));
      expect(bytes.sublist(0, 4), [0x7F, 0x45, 0x4C, 0x46]);
      expect(phases.last, RemoteBuildPhase.download);
      expect(service.busy, isFalse);
    },
    timeout: const Timeout(Duration(minutes: 15)),
    skip: liveReady
        ? false
        : 'QU_BUILD_SERVER_URL / QU_BUILD_SERVER_KEY are not set',
  );
}
