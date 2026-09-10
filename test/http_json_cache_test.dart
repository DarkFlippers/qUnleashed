import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qunleashed/services/http/app_http.dart';

/// A payload big enough that the split matters, small enough to stay quick.
final Map<String, Object?> payload = {
  'data': [
    for (var i = 0; i < 40; i++) {'id': 'app_$i', 'name': 'Application $i'},
  ],
  'total': 40,
};

/// A server that answers one JSON document, counts requests, and honours
/// If-None-Match so revalidation can be observed rather than assumed.
class FakeCatalog {
  FakeCatalog(this._server)
    : uri = Uri.parse('http://127.0.0.1:${_server.port}/catalog.json') {
    _server.listen((req) async {
      requests += 1;
      ifNoneMatch.add(req.headers.value(HttpHeaders.ifNoneMatchHeader));
      userAgents.add(req.headers.value(HttpHeaders.userAgentHeader));
      if (status != 200) {
        req.response.statusCode = status;
        req.response.write('upstream said no');
        await req.response.close();
        return;
      }
      if (req.headers.value(HttpHeaders.ifNoneMatchHeader) == etag) {
        req.response.statusCode = HttpStatus.notModified;
        final rotated = etagOn304;
        if (rotated != null) {
          req.response.headers.set(HttpHeaders.etagHeader, rotated);
        }
        await req.response.close();
        return;
      }
      if (sendEtag) req.response.headers.set(HttpHeaders.etagHeader, etag);
      req.response.write(rawBody ?? jsonEncode(body));
      await req.response.close();
    });
  }

  static Future<FakeCatalog> start() async =>
      FakeCatalog(await HttpServer.bind(InternetAddress.loopbackIPv4, 0));

  final HttpServer _server;

  /// Captured up front: reading `port` off a closed server throws, and the
  /// offline tests need the address after shutting it down.
  final Uri uri;
  bool _stopped = false;
  int requests = 0;
  int status = 200;
  String etag = 'W/"v1"';
  bool sendEtag = true;
  Object? body = payload;

  /// Sent verbatim instead of [body] - a captive portal's HTML, say.
  String? rawBody;

  /// A validator handed back on a 304, as servers do when they rotate a weak
  /// one without the body changing.
  String? etagOn304;
  final List<String?> ifNoneMatch = [];
  final List<String?> userAgents = [];

  Future<void> stop() async {
    if (_stopped) return;
    _stopped = true;
    await _server.close(force: true);
  }
}

void main() {
  late Directory cacheDir;
  late FakeCatalog server;

  setUp(() async {
    cacheDir = Directory.systemTemp.createTempSync('http_json_cache');
    AppHttp.jsonCacheDirectory = cacheDir;
    server = await FakeCatalog.start();
  });

  tearDown(() async {
    // Reset before stopping: `server` is late, so if setUp failed at start()
    // this would otherwise throw a LateInitializationError that masks the real
    // failure and skips the cleanup below.
    AppHttp.jsonCacheDirectory = null;
    if (cacheDir.existsSync()) cacheDir.deleteSync(recursive: true);
    await server.stop();
  });

  String keyFor(Uri uri) =>
      sha256.convert(utf8.encode(uri.toString())).toString();

  File cacheFile(Uri uri, String ext) =>
      File('${cacheDir.path}${Platform.pathSeparator}${keyFor(uri)}.$ext');

  /// Backdates an entry's timestamp so staleness can be tested without waiting.
  void ageEntry(Uri uri, Duration by) {
    final meta = cacheFile(uri, 'meta');
    final data = jsonDecode(meta.readAsStringSync()) as Map<String, dynamic>;
    data['fetched_at'] = DateTime.fromMillisecondsSinceEpoch(
      data['fetched_at'] as int,
    ).subtract(by).millisecondsSinceEpoch;
    meta.writeAsStringSync(jsonEncode(data));
  }

  group('getJsonCached', () {
    test('fetches and returns the document', () async {
      final got = await AppHttp.getJsonCached(server.uri);

      expect((got as Map)['total'], 40);
      expect(server.requests, 1);
    });

    test('serves a fresh entry without touching the network', () async {
      await AppHttp.getJsonCached(server.uri);
      final again = await AppHttp.getJsonCached(server.uri);

      expect((again as Map)['total'], 40);
      expect(server.requests, 1, reason: 'the second read came from disk');
    });

    // The point of the change: the body is stored raw, so reading an entry
    // never means unescaping the whole payload out of a wrapper object on the
    // calling isolate.
    test('stores the body raw, not embedded in the metadata', () async {
      await AppHttp.getJsonCached(server.uri);

      final body = cacheFile(server.uri, 'body');
      final meta = cacheFile(server.uri, 'meta');

      expect(body.existsSync(), isTrue);
      expect(meta.existsSync(), isTrue);
      expect(jsonDecode(body.readAsStringSync()), payload);
      expect(meta.lengthSync(), lessThan(200), reason: 'metadata only');
      expect(meta.readAsStringSync(), isNot(contains('app_0')));
    });

    test(
      'revalidates a stale entry and serves the cached body on 304',
      () async {
        await AppHttp.getJsonCached(server.uri);
        final again = await AppHttp.getJsonCached(
          server.uri,
          ttl: Duration.zero,
        );

        expect(server.requests, 2);
        expect(server.ifNoneMatch.last, 'W/"v1"');
        expect(
          (again as Map)['total'],
          40,
          reason: 'served from the cached body',
        );
      },
    );

    test('a 304 restarts the freshness window', () async {
      const window = Duration(minutes: 10);
      await AppHttp.getJsonCached(server.uri);
      // Aged past the window rather than slept past it, so the difference
      // between re-stamping and not is deterministic instead of a race.
      ageEntry(server.uri, const Duration(hours: 1));

      await AppHttp.getJsonCached(server.uri, ttl: window);
      expect(server.requests, 2, reason: 'the stale entry was revalidated');

      await AppHttp.getJsonCached(server.uri, ttl: window);
      expect(server.requests, 2, reason: 'the 304 made it fresh again');
    });

    test('picks up a changed document when the etag moves', () async {
      await AppHttp.getJsonCached(server.uri);
      server
        ..etag = 'W/"v2"'
        ..body = {'total': 7};

      final got = await AppHttp.getJsonCached(server.uri, ttl: Duration.zero);

      expect((got as Map)['total'], 7);
    });

    // What makes cached screens work with no network.
    test('falls back to the stale copy when the network fails', () async {
      await AppHttp.getJsonCached(server.uri);
      await server.stop();

      final got = await AppHttp.getJsonCached(server.uri, ttl: Duration.zero);

      expect((got as Map)['total'], 40);
    });

    test('rethrows when the network fails and nothing is cached', () async {
      final uri = server.uri;
      await server.stop();

      // The exact type varies - a dead pooled socket and a refused connect
      // differ - but it must not be a parse error, which is the bug class
      // where the fallback's own failure stands in for the network's.
      await expectLater(
        AppHttp.getJsonCached(uri),
        throwsA(allOf(isA<Exception>(), isNot(isA<FormatException>()))),
      );
    });

    test('throws on a non-2xx response and caches nothing', () async {
      server.status = 500;

      await expectLater(
        AppHttp.getJsonCached(server.uri),
        throwsA(isA<AppHttpException>()),
      );
      expect(cacheFile(server.uri, 'body').existsSync(), isFalse);
    });

    // An upgrade must not throw away a cache an offline user is relying on.
    test('migrates a pre-split entry and still serves it offline', () async {
      final uri = server.uri;
      cacheFile(uri, 'json').writeAsStringSync(
        jsonEncode({
          'etag': 'W/"old"',
          'fetched_at': DateTime.now().millisecondsSinceEpoch,
          'body': jsonEncode({'total': 99}),
        }),
      );
      await server.stop();

      final got = await AppHttp.getJsonCached(uri);

      expect((got as Map)['total'], 99);
      expect(cacheFile(uri, 'json').existsSync(), isFalse, reason: 'consumed');
      expect(cacheFile(uri, 'body').existsSync(), isTrue);
      expect(jsonDecode(cacheFile(uri, 'body').readAsStringSync()), {
        'total': 99,
      });
    });

    // The old format failed closed here: a body it could not parse came back
    // as null from read() and became a miss. Decoding outside that guard must
    // not turn it into an error the caller sees.
    test('treats an unparseable body as a miss and refetches', () async {
      await AppHttp.getJsonCached(server.uri);
      cacheFile(server.uri, 'body').writeAsStringSync('{"data": [trunca');

      final got = await AppHttp.getJsonCached(server.uri);

      expect((got as Map)['total'], 40);
      expect(server.requests, 2);
    });

    // A captive portal answers 200 with an HTML login page. Storing that would
    // overwrite a good entry with something that can never be served.
    test('a 200 that is not JSON leaves the previous entry intact', () async {
      await AppHttp.getJsonCached(server.uri);
      // A new etag too, or the server answers 304 and the portal's page never
      // reaches the client at all.
      server
        ..etag = 'W/"v2"'
        ..rawBody = '<html>captive portal</html>';

      await expectLater(
        AppHttp.getJsonCached(server.uri, ttl: Duration.zero),
        throwsA(isA<FormatException>()),
      );

      await server.stop();
      final offline = await AppHttp.getJsonCached(
        server.uri,
        ttl: Duration.zero,
      );
      expect((offline as Map)['total'], 40, reason: 'the good copy survived');
    });

    test('a corrupt body offline surfaces the network error', () async {
      await AppHttp.getJsonCached(server.uri);
      cacheFile(server.uri, 'body').writeAsStringSync('{"data": [trunca');
      await server.stop();

      await expectLater(
        AppHttp.getJsonCached(server.uri, ttl: Duration.zero),
        throwsA(isNot(isA<FormatException>())),
      );
    });

    // Every entry on disk at upgrade time is older than its TTL, so a fresh
    // fixture would never reach the revalidation this has to get right.
    test('a stale pre-split entry keeps its timestamp and its etag', () async {
      cacheFile(server.uri, 'json').writeAsStringSync(
        jsonEncode({
          'etag': 'W/"v1"',
          'fetched_at': DateTime.now()
              .subtract(const Duration(days: 3))
              .millisecondsSinceEpoch,
          'body': jsonEncode(payload),
        }),
      );

      final got = await AppHttp.getJsonCached(server.uri);

      expect(server.requests, 1, reason: 'the migrated entry was still stale');
      expect(server.ifNoneMatch.last, 'W/"v1"', reason: 'etag carried over');
      expect((got as Map)['total'], 40);
    });

    // _migrate returns an entry built from its own locals, so the call that
    // performs the migration cannot show what was persisted - only the
    // metadata it left behind can. A 30-day window keeps the migrated entry
    // fresh so nothing revalidates and re-stamps it first.
    test(
      'migration carries the timestamp and validator into the new format',
      () async {
        final threeDaysAgo = DateTime.now().subtract(const Duration(days: 3));
        cacheFile(server.uri, 'json').writeAsStringSync(
          jsonEncode({
            'etag': 'W/"v1"',
            'fetched_at': threeDaysAgo.millisecondsSinceEpoch,
            'body': jsonEncode(payload),
          }),
        );

        await AppHttp.getJsonCached(server.uri, ttl: const Duration(days: 30));

        final meta =
            jsonDecode(cacheFile(server.uri, 'meta').readAsStringSync())
                as Map<String, dynamic>;
        expect(meta['etag'], 'W/"v1"');
        expect(meta['fetched_at'], threeDaysAgo.millisecondsSinceEpoch);
        expect(server.requests, 0, reason: 'served from the migrated entry');
      },
    );

    test('adopts a validator the server rotates on a 304', () async {
      await AppHttp.getJsonCached(server.uri);
      server.etagOn304 = 'W/"v2"';

      await AppHttp.getJsonCached(server.uri, ttl: Duration.zero);
      await AppHttp.getJsonCached(server.uri, ttl: Duration.zero);

      expect(server.ifNoneMatch.last, 'W/"v2"', reason: 'the rotated one');
    });

    test('forwards caller headers', () async {
      await AppHttp.getJsonCached(
        server.uri,
        headers: {HttpHeaders.userAgentHeader: 'qunleashed-test/9'},
      );

      expect(server.userAgents.last, 'qunleashed-test/9');
    });

    test('revalidates without If-None-Match when there was no etag', () async {
      server.sendEtag = false;
      await AppHttp.getJsonCached(server.uri);

      await AppHttp.getJsonCached(server.uri, ttl: Duration.zero);

      expect(server.requests, 2);
      expect(server.ifNoneMatch.last, isNull);
    });

    test('does not cache an empty response', () async {
      server.rawBody = '';

      expect(await AppHttp.getJsonCached(server.uri), isNull);
      expect(cacheFile(server.uri, 'body').existsSync(), isFalse);
    });

    test('round-trips non-ASCII through the cache', () async {
      server.body = {'name': 'Устройство 🐬', 'total': 1};
      await AppHttp.getJsonCached(server.uri);

      final again = await AppHttp.getJsonCached(server.uri);

      expect((again as Map)['name'], 'Устройство 🐬');
      expect(server.requests, 1, reason: 'read back from disk');
    });

    test(
      'treats a zero-length body as damage, not an empty document',
      () async {
        await AppHttp.getJsonCached(server.uri);
        cacheFile(server.uri, 'body').writeAsStringSync('');

        final got = await AppHttp.getJsonCached(server.uri);

        expect((got as Map)['total'], 40);
        expect(server.requests, 2, reason: 'an empty cache file is a miss');
      },
    );

    // The migration deletes the only readable copy, so it must not run on a
    // half-completed write - a metadata write that failed silently would take
    // an offline user's cache with it, permanently.
    test(
      'keeps the pre-split entry when the new one cannot be written',
      () async {
        final uri = server.uri;
        cacheFile(uri, 'json').writeAsStringSync(
          jsonEncode({
            'etag': 'W/"old"',
            'fetched_at': DateTime.now().millisecondsSinceEpoch,
            'body': jsonEncode(payload),
          }),
        );
        // A directory exactly where the metadata file has to go.
        Directory(cacheFile(uri, 'meta').path).createSync();

        await AppHttp.getJsonCached(uri);

        expect(cacheFile(uri, 'json').existsSync(), isTrue);
      },
    );

    test('ignores metadata whose body file is gone', () async {
      await AppHttp.getJsonCached(server.uri);
      cacheFile(server.uri, 'body').deleteSync();

      final got = await AppHttp.getJsonCached(server.uri);

      expect((got as Map)['total'], 40);
      expect(server.requests, 2, reason: 'a half-written entry is a miss');
    });
  });
}
