import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:qunleashed/services/http/app_http.dart';

/// What happens when a server takes the connection and then says nothing.
///
/// `connectionTimeout` covers the TCP handshake and nothing after it, and
/// `idleTimeout` only reaps idle pooled connections - so a half-open proxy, a
/// captive portal that stalls past the handshake, or a blackholing mobile
/// link left every request pending for the life of the process. Twenty-one
/// call sites, two of which had grown their own caller-side deadline. #130.
class _StallingServer {
  _StallingServer(this._server)
    : uri = Uri.parse('http://127.0.0.1:${_server.port}/thing') {
    _server.listen((req) async {
      requests += 1;
      if (headers == _Headers.never) return;
      req.response.headers.contentType = ContentType.text;
      if (body == _Body.partial) {
        // The shape that matters: headers arrive, some bytes arrive, and then
        // the socket goes quiet without closing.
        req.response.write('half a ');
        await req.response.flush();
        return;
      }
      req.response.write('all of it');
      await req.response.close();
    });
  }

  static Future<_StallingServer> start() async =>
      _StallingServer(await HttpServer.bind(InternetAddress.loopbackIPv4, 0));

  final HttpServer _server;
  final Uri uri;

  int requests = 0;
  _Headers headers = _Headers.sent;
  _Body body = _Body.whole;

  Future<void> stop() async {
    try {
      await _server.close(force: true);
    } catch (_) {
      return;
    }
  }
}

enum _Headers { sent, never }

enum _Body { whole, partial }

void main() {
  late _StallingServer server;

  setUp(() async {
    server = await _StallingServer.start();
    // Short enough that a stall is a test rather than a wait, long enough
    // that a loopback answer always beats it.
    AppHttp.headersDeadline = const Duration(milliseconds: 400);
    AppHttp.idleDeadline = const Duration(milliseconds: 400);
    addTearDown(() async {
      AppHttp.debugResetDeadlines();
      await server.stop();
    });
  });

  group('a server that never answers', () {
    test('does not leave a read pending forever', () async {
      server.headers = _Headers.never;

      await expectLater(
        AppHttp.getJson(server.uri),
        throwsA(isA<TimeoutException>()),
      );
    });

    test('does not leave a download pending forever', () async {
      server.headers = _Headers.never;

      await expectLater(
        AppHttp.getBytes(server.uri),
        throwsA(isA<TimeoutException>()),
      );
    });

    // It did answer the handshake - that is the whole point. A connection
    // timeout would never have fired here.
    test('was reached, and stalled after that', () async {
      server.headers = _Headers.never;

      await AppHttp.getJson(server.uri).then((_) => null, onError: (_) => null);

      expect(server.requests, 1);
    });
  });

  group('a body that stops arriving', () {
    test('is abandoned rather than awaited', () async {
      server.body = _Body.partial;

      await expectLater(
        AppHttp.getBytes(server.uri),
        throwsA(isA<TimeoutException>()),
      );
    });

    // The JSON read has its own path to the body, and a half-arrived
    // document hangs its decode just as surely as a half-arrived download.
    test('is abandoned by a json read as well', () async {
      server.body = _Body.partial;

      await expectLater(
        AppHttp.getJson(server.uri),
        throwsA(isA<TimeoutException>()),
      );
    });

    test('is abandoned by a download to disk too', () async {
      server.body = _Body.partial;
      final dir = Directory.systemTemp.createTempSync('http_deadline');
      addTearDown(() {
        if (dir.existsSync()) dir.deleteSync(recursive: true);
      });

      await expectLater(
        AppHttp.downloadToFile(
          server.uri,
          '${dir.path}${Platform.pathSeparator}thing.bin',
        ),
        throwsA(isA<TimeoutException>()),
      );
    });
  });

  group('a server that answers', () {
    // The deadline is between bytes, not in total, so nothing here can make a
    // slow but live download fail.
    test('is not cut off by either deadline', () async {
      final bytes = await AppHttp.getBytes(server.uri);

      expect(String.fromCharCodes(bytes), 'all of it');
    });
  });
}
