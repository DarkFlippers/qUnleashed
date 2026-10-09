// What `AppHttp` reports about each request — ADR 0013 §2's hand-made spans.
//
// Nothing instruments `dart:io`'s `HttpClient`, so these are the app's own.
// The two things worth holding are the ones that are easy to get wrong: each
// exchange is reported **once**, and a cache hit that never touches the
// network reports nothing at all.
import 'dart:convert';
import 'dart:io' as io;

import 'package:flutter_test/flutter_test.dart';
import 'package:qunleashed/services/http/app_http.dart';
import 'package:qunleashed/services/logging.dart';

/// A server that answers whatever the test tells it to.
class _Server {
  _Server(this._handle);

  final Future<void> Function(io.HttpRequest req) _handle;
  late io.HttpServer _server;

  Future<Uri> start() async {
    _server = await io.HttpServer.bind(io.InternetAddress.loopbackIPv4, 0);
    _server.listen((req) async {
      await _handle(req);
      await req.response.close();
    });
    return Uri.parse('http://127.0.0.1:${_server.port}/thing');
  }

  Future<void> stop() => _server.close(force: true);
}

Future<Uri> serving(Future<void> Function(io.HttpRequest req) handle) async {
  final server = _Server(handle);
  addTearDown(server.stop);
  return server.start();
}

void main() {
  late List<HttpExchange> seen;

  setUp(() {
    seen = [];
    AppHttp.exchangeSink = seen.add;
    LogService.clearHistory();
  });

  tearDown(() {
    AppHttp.exchangeSink = null;
    LogService.clearHistory();
  });

  test('a successful getJson is reported once, with its status', () async {
    final uri = await serving((req) async {
      req.response.headers.contentType = io.ContentType.json;
      req.response.write('{"ok":true}');
    });

    await AppHttp.getJson(uri);

    expect(seen, hasLength(1));
    expect(seen.single.method, 'GET');
    expect(seen.single.status, 200);
    expect(seen.single.ok, isTrue);
    expect(seen.single.error, isNull);
  });

  test('exactly once, though getJson goes through get', () async {
    // `get` is deliberately not observed: it hands the response back with the
    // body unread, so the only duration it could report is time-to-headers -
    // a 40 ms firmware download. Observing both would double-count instead.
    final uri = await serving((req) async => req.response.write('{}'));

    await AppHttp.getJson(uri);
    await AppHttp.getJson(uri);

    expect(seen, hasLength(2), reason: 'one per call, not two');
  });

  test('a raw get reports nothing', () async {
    final uri = await serving((req) async => req.response.write('{}'));
    final res = await AppHttp.get(uri);
    await res.drain<void>();
    expect(seen, isEmpty);
  });

  test('an error status is reported as a failure, with the code', () async {
    final uri = await serving((req) async {
      req.response.statusCode = 503;
      req.response.write('busy');
    });

    await expectLater(AppHttp.getJson(uri), throwsA(isA<AppHttpException>()));

    expect(seen, hasLength(1));
    expect(seen.single.status, 503);
    expect(seen.single.ok, isFalse);
    expect(seen.single.error, isA<AppHttpException>());
  });

  test('a request that never got a response has no status at all', () async {
    // Absence is null, not 0 - ADR 0009. A span claiming status 0 would sort
    // and filter as a real code.
    final uri = Uri.parse('http://127.0.0.1:1/nothing-is-listening');

    await expectLater(AppHttp.getJson(uri), throwsA(anything));

    expect(seen, hasLength(1));
    expect(seen.single.status, isNull);
    expect(seen.single.ok, isFalse);
  });

  test('the elapsed time is the whole exchange, body included', () async {
    final uri = await serving((req) async {
      await Future<void>.delayed(const Duration(milliseconds: 60));
      req.response.write('{}');
    });

    await AppHttp.getJson(uri);

    expect(
      seen.single.elapsed,
      greaterThanOrEqualTo(const Duration(milliseconds: 50)),
      reason: 'the server slept before answering, so the span must show it',
    );
    expect(seen.single.endedAt.isBefore(seen.single.startedAt), isFalse);
  });

  test('downloadToFile reports the transfer, not just the headers', () async {
    final body = 'x' * 200000;
    final uri = await serving((req) async {
      // Written in chunks with a pause, so time-to-headers and time-to-done
      // are measurably different.
      req.response.add(utf8.encode(body.substring(0, 1000)));
      await req.response.flush();
      await Future<void>.delayed(const Duration(milliseconds: 60));
      req.response.add(utf8.encode(body.substring(1000)));
    });
    final target = '${io.Directory.systemTemp.createTempSync().path}/out.bin';

    await AppHttp.downloadToFile(uri, target);

    expect(seen, hasLength(1));
    expect(
      seen.single.elapsed,
      greaterThanOrEqualTo(const Duration(milliseconds: 50)),
    );
  });

  test('a cache hit that never revalidates reports nothing', () async {
    // The reason the wrap is around the request and not around the method: a
    // span for a request that did not happen shows the app talking to a server
    // it never touched.
    var requests = 0;
    final uri = await serving((req) async {
      requests += 1;
      req.response.headers.set(io.HttpHeaders.etagHeader, '"v1"');
      req.response.write('{"n":1}');
    });
    AppHttp.jsonCacheDirectory = io.Directory.systemTemp.createTempSync();
    addTearDown(() => AppHttp.jsonCacheDirectory = null);

    await AppHttp.getJsonCached(uri, ttl: const Duration(hours: 1));
    expect(seen, hasLength(1), reason: 'the first call fetches');

    seen.clear();
    await AppHttp.getJsonCached(uri, ttl: const Duration(hours: 1));

    expect(requests, 1, reason: 'the second call was served from disk');
    expect(seen, isEmpty, reason: 'and so reported no exchange');
  });

  test('a sink that throws costs neither the answer nor the process', () async {
    // The request has already succeeded by the time the sink runs, and a
    // recorder must not turn a good answer into an exception the caller never
    // expected.
    AppHttp.exchangeSink = (_) => throw StateError('recorder is broken');
    final uri = await serving((req) async => req.response.write('{"ok":1}'));

    final value = await AppHttp.getJson(uri);

    expect(value, {'ok': 1});
    expect(
      LogService.history.where((l) => l.contains('exchange sink threw')),
      hasLength(1),
      reason: 'swallowed silently, this would be a dead reporting feature',
    );
  });

  test('no sink installed changes nothing', () async {
    AppHttp.exchangeSink = null;
    final uri = await serving((req) async => req.response.write('{"ok":1}'));
    expect(await AppHttp.getJson(uri), {'ok': 1});
  });
}
