import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:qunleashed/pages/devices/firmware/directory.dart';
import 'package:qunleashed/services/http/app_http.dart';

/// What the firmware directory has to show after a cold start with no network.
///
/// The parser kept a ten-minute stamp in memory and fetched past the app's
/// own disk cache, so every launch re-fetched and an offline one had nothing
/// at all - which is most of what made #118's "can't check" state and its
/// retry cooldown as load-bearing as they are. #131.
final _directory = {
  'channels': [
    {
      'id': 'release',
      'title': 'Release',
      'versions': [
        {
          'version': '1.0.0',
          'changelog': 'first',
          'files': [
            {
              'url': 'https://example.invalid/f7.tgz',
              'target': 'f7',
              'type': 'update_tgz',
              'sha256': 'a' * 64,
            },
          ],
        },
      ],
    },
  ],
};

/// Serves the directory once, then refuses - which is a device that fetched
/// on one launch and has no network on the next.
class _OnceThenOffline {
  _OnceThenOffline(this._server)
    : uri = Uri.parse('http://127.0.0.1:${_server.port}/directory.json') {
    _server.listen((req) async {
      served += 1;
      if (offline) {
        await req.response.close();
        await _server.close(force: true);
        return;
      }
      req.response.headers.contentType = ContentType.json;
      req.response.write(jsonEncode(_directory));
      await req.response.close();
    });
  }

  static Future<_OnceThenOffline> start() async =>
      _OnceThenOffline(await HttpServer.bind(InternetAddress.loopbackIPv4, 0));

  final HttpServer _server;
  final Uri uri;

  int served = 0;
  bool offline = false;

  Future<void> stop() async {
    try {
      await _server.close(force: true);
    } catch (_) {
      return;
    }
  }
}

/// No `TestWidgetsFlutterBinding.ensureInitialized()`, deliberately, and the
/// same as the three other files covering AppHttp. The binding installs
/// HttpOverrides, which answers every request 400 without reaching anything -
/// so a case that stands up a real server and expects it to be read has to
/// stay out of it. Writing this file with the binding in place is what
/// surfaced #208.
void main() {
  late Directory cacheDir;
  late _OnceThenOffline feed;

  setUp(() async {
    cacheDir = Directory.systemTemp.createTempSync('fw_directory_cache');
    AppHttp.jsonCacheDirectory = cacheDir;
    feed = await _OnceThenOffline.start();
    addTearDown(() async {
      AppHttp.jsonCacheDirectory = null;
      await feed.stop();
      if (cacheDir.existsSync()) cacheDir.deleteSync(recursive: true);
    });
  });

  /// Reads the feed the way the parser's own default does - through the disk
  /// cache, with the parser's TTL.
  Future<FirmwareDirectory> readThroughCache({
    Duration ttl = const Duration(minutes: 10),
  }) async => FirmwareDirectoryReader().read(
    await AppHttp.getJsonCached(feed.uri, ttl: ttl),
  );

  group('a launch with no network', () {
    // The point of the change: the screen shows the last directory rather
    // than nothing. Before this the parser's only memory was in-process, so
    // a cold start offline had no directory at all.
    test('still has the directory the last one fetched', () async {
      await readThroughCache();
      await feed.stop();

      final directory = await readThroughCache(ttl: Duration.zero);

      expect(directory.channelById('release')?.latest?.version, '1.0.0');
    });

    // Without a cached copy there is nothing to serve, and the caller's
    // "can't check" remains the right answer.
    test('has nothing when no launch ever fetched', () async {
      await feed.stop();

      await expectLater(
        readThroughCache(ttl: Duration.zero),
        throwsA(anything),
      );
    });
  });

  // Everything above drives AppHttp directly, which shows the cache behaves
  // and not that the parser reaches for it. This is the seam itself: its
  // default is read rather than replaced, and a plain fetch leaves the cache
  // directory empty.
  group('what the parser fetches through', () {
    test('writes the document to the cache directory', () async {
      await OfwParser.instance.fetchJson(feed.uri);

      expect(cacheDir.listSync(), isNotEmpty);
    });

    // Not covered: that the window it passes is the parser's ten minutes
    // rather than the cache's own five. Both are longer than a test, and
    // nothing here can move a clock - the TTL being shared with `isFresh` is
    // what the comment on the seam records instead.
    test('serves the second read without asking the feed', () async {
      await OfwParser.instance.fetchJson(feed.uri);
      expect(feed.served, 1);

      await OfwParser.instance.fetchJson(feed.uri);

      expect(feed.served, 1);
    });
  });

  group('a launch with a warm cache', () {
    test('does not ask the feed again inside the window', () async {
      await readThroughCache();
      expect(feed.served, 1);

      await readThroughCache();

      expect(feed.served, 1, reason: 'served from disk');
    });

    test('does ask once the window has passed', () async {
      await readThroughCache();

      await readThroughCache(ttl: Duration.zero);

      expect(feed.served, 2);
    });
  });
}
