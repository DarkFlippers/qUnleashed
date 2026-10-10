import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qunleashed/services/assembler/remote_build_service.dart';

import 'kept_lines.dart';

/// What the remote build service writes down when the server answers with
/// something it cannot use.
///
/// `remote_build_test.dart` covers what the user is told. This is the other
/// half: three failures that used to leave no trace at all, and each of them
/// is the first question a bug report about a failed build asks.
const _secret = 'test-secret';
const _clientId = 'client-1';

String _sign(HttpRequest request, List<int> body) {
  final time = request.headers.value('X-QU-Time')!;
  final bodyHash = sha256.convert(body).toString();
  final message =
      '$time\n${request.method}\n${request.uri.path}\n$bodyHash\n$_clientId';
  return Hmac(
    sha256,
    utf8.encode(_secret),
  ).convert(utf8.encode(message)).toString();
}

/// Answers whatever it is told to, signature checking included so the service
/// takes the reply seriously.
class _RudeServer {
  _RudeServer(this.server) {
    server.listen(_handle);
  }

  final HttpServer server;

  /// The body every request is answered with.
  String body = '{}';

  /// The status every request is answered with.
  int status = 200;

  /// Paths that have been asked for, in order.
  final seen = <String>[];

  /// Fails the connection outright rather than answering.
  bool refuse = false;

  String get url => 'http://127.0.0.1:${server.port}';

  static Future<_RudeServer> start() async =>
      _RudeServer(await HttpServer.bind(InternetAddress.loopbackIPv4, 0));

  Future<void> _handle(HttpRequest request) async {
    final raw = await request.fold<List<int>>([], (a, b) => a..addAll(b));
    seen.add('${request.method} ${request.uri.path}');
    if (refuse) {
      await request.response.close();
      await server.close(force: true);
      return;
    }
    if (request.headers.value('X-QU-Sign') != _sign(request, raw)) {
      request.response.statusCode = 403;
      await request.response.close();
      return;
    }
    request.response.statusCode = status;
    request.response.write(body);
    await request.response.close();
  }

  Future<void> stop() async {
    try {
      await server.close(force: true);
    } catch (_) {}
  }
}

void main() {
  setUp(recordKeptLines);

  late _RudeServer server;
  late RemoteBuildService service;

  setUp(() async {
    server = await _RudeServer.start();
    service = RemoteBuildService.test(
      serverUrl: server.url,
      sharedKey: _secret,
      clientId: _clientId,
    );
    clearKeptLines();
  });

  tearDown(() => server.stop());

  bool said(String fragment) => keptLines.any((l) => l.contains(fragment));

  Future<Object?> submit() async {
    try {
      return await service.build(
        bundleUrl: 'https://example.invalid/b.zip',
        alias: 'x',
        target: 'f7',
      );
    } catch (e) {
      return e;
    }
  }

  group('a reply that is not an object', () {
    // A proxy's HTML error page and a server that changed its shape read
    // identically from the user's message alone.
    test('is still an error the user is shown', () async {
      server.body = '<html>gateway timeout</html>';

      expect(await submit(), isA<RemoteBuildException>());
    });

    test('says what could not be read', () async {
      server.body = '<html>gateway timeout</html>';

      await submit();

      expect(said('unreadable response'), isTrue);
    });

    test('says so for valid JSON of the wrong shape too', () async {
      server.body = '[1, 2, 3]';

      await submit();

      expect(said('unreadable response'), isTrue);
    });

    // A reply the service understands, even though the build in it failed.
    // `queued` would be understood too and then polled until the deadline,
    // which is a slow way to assert nothing.
    test('says nothing when the reply reads', () async {
      server.body = jsonEncode({
        'id': 'job-1',
        'status': 'failed',
        'error': 'ufbt failed with exit code 2',
      });

      await submit();

      expect(said('unreadable response'), isFalse);
    });
  });

  group('a refusal the server will not explain', () {
    // The status code answers the user. This is the server's own account of
    // why, and losing it turns "why did the build fail" into a guess.
    test('is reported, once', () async {
      server.status = 503;
      server.body = '<html>upstream down</html>';

      await submit();

      expect(said('error body unreadable'), isTrue);
      expect(
        keptLines.where((l) => l.contains('error body unreadable')),
        hasLength(1),
      );
    });

    test('says nothing when the refusal came with a reason', () async {
      server.status = 503;
      server.body = jsonEncode({'detail': 'the queue is full'});

      await submit();

      expect(said('error body unreadable'), isFalse);
    });
  });
}
