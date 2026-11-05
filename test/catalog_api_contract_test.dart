import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qunleashed/pages/apps/data/artifact_signature.dart';
import 'package:qunleashed/pages/apps/data/catalog_api.dart';
import 'package:qunleashed/pages/apps/data/catalog_state.dart';
import 'package:qunleashed/pages/apps/data/models/manifest.dart';
import 'package:qunleashed/services/http/app_http.dart';

void main() {
  final fixture = jsonDecode(
    File('test/fixtures/catalog/v1.json').readAsStringSync(),
  ) as Map<String, dynamic>;
  late HttpServer server;
  late Directory cache;
  late AppsCatalogApi api;
  final requests = <Uri>[];
  final bodies = <Map<String, dynamic>>[];

  setUp(() async {
    requests.clear();
    bodies.clear();
    cache = Directory.systemTemp.createTempSync('catalog_contract');
    AppHttp.jsonCacheDirectory = cache;
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    api = AppsCatalogApi(
      server: 'http://127.0.0.1:${server.port}',
      api: '88.16',
      target: 'f7',
    );
    server.listen((request) async {
      requests.add(request.uri);
      final path = Uri.decodeComponent(request.uri.path);
      String key;
      switch (path) {
        case '/api/v1/status':
          key = 'status';
        case '/api/v1/application/category':
          key = 'categories';
        case '/api/v1/application':
          key = 'list';
        case '/api/v1/application/pair':
          key = request.uri.queryParameters['app'] == 'pair_extra'
              ? 'extra'
              : 'detail';
        case '/api/v1/application/lookup':
          bodies.add(
            jsonDecode(await utf8.decoder.bind(request).join())
                as Map<String, dynamic>,
          );
          key = 'lookup';
        case '/api/v1/menustyles/menu_style_wave':
          key = 'style';
        case '/api/v1/animations/dance':
          key = 'animation';
        case '/api/v1/animations/version/anim:dance@1.0/plan':
          key = 'plan';
        case '/api/v1/search':
          key = 'search';
        case '/api/v1/authors':
          key = 'authors';
        // The original v0 paths and bodies are tested through its protocol directly.
        case '/api/v0/sdk':
          key = 'v0_sdk';
        case '/api/v0/category':
          key = 'categories';
        case '/api/v0/0/application':
          key = 'list';
        case '/api/v0/application/pair':
          key = 'detail';
        case '/api/v0/1/application':
          bodies.add(
            jsonDecode(await utf8.decoder.bind(request).join())
                as Map<String, dynamic>,
          );
          key = 'lookup';
        default:
          request.response.statusCode = 404;
          await request.response.close();
          return;
      }
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode(
          key == 'v0_sdk'
              ? [
                  {'id': 'sdk', 'name': 'dev', 'api': '88.16', 'target': 'f7'},
                ]
              : fixture[key],
        ),
      );
      await request.response.close();
    });
  });

  tearDown(() async {
    await server.close(force: true);
    AppHttp.jsonCacheDirectory = null;
    cache.deleteSync(recursive: true);
  });

  test(
    'v1 renders actual server answers, including every app in an item',
    () async {
      expect((await api.fetchSdks()).single.api, '88.16');
      expect(await api.fetchCategories(), isNotEmpty);
      final page = await api.fetchApps(
        sortBy: AppsSort.popularWeek,
        authorId: 'Ann',
      );
      expect(page.items.single.appCount, 2);
      expect(page.items.single.entries, isEmpty);
      expect(
        requests.last.queryParameters,
        containsPair('sort_by', 'downloads_week'),
      );
      expect(requests.last.queryParameters, containsPair('author_id', 'Ann'));

      final detail = await api.fetchApp('pair');
      expect(detail.card.entries.map((app) => app.appid), [
        'pair',
        'pair_extra',
      ]);
      final extra = detail.forApp(detail.card.entries.last);
      expect(extra.card.alias, 'pair_extra');
      expect(extra.card.currentVersion!.id, 'pair_extra@1.0');
      expect(extra.description, detail.description);
      expect(extra.links!.sourceCode!.uri, 'https://git.example.org/pair');
      final selected = await api.fetchApp('pair', app: 'pair_extra');
      expect(selected.card.selectedAppId, 'pair_extra');
      expect(selected.card.currentVersion!.id, extra.card.currentVersion!.id);

      final lookup = await api.fetchAppsByUids(['pair', 'pair_extra']);
      expect(lookup, isNotEmpty);
      expect(bodies.single, {
        'ids': ['pair', 'pair_extra'],
        'api': '88.16',
        'target': 'f7',
      });
      expect((await api.search('pair')).items.single.alias, 'pair');
      expect(
        (await api.fetchAuthors()).map((a) => a.id),
        containsAll(['ann', 'bob']),
      );
    },
  );

  test(
    'animations ignore device filters and retain the server installation plan',
    () async {
      final animation = await api.fetchApp(
        'dance',
        family: CatalogFamily.animations,
      );
      expect(animation.card.family, 'animation');
      expect(requests.last.queryParameters, isEmpty);
      final plan = await api.fetchAnimationPlan('anim:dance@1.0');
      expect(
        plan.files.map((file) => file.devicePath),
        contains('/ext/dolphin/dance/meta.txt'),
      );
      expect(plan.manifestPath, '/ext/dolphin/manifest.txt');
      expect(plan.entry!.name, 'dance');
      final style = await api.fetchApp(
        'menu_style_wave',
        family: CatalogFamily.menuStyles,
      );
      expect(style.card.installPath, '/ext/apps_data/loader/plugins');
    },
  );

  test('updates stay with the installed app of a multi-app item', () async {
    final detail = await api.fetchApp('pair');
    final installed = AppManifest(
      uid: detail.card.id,
      versionUid: 'pair_extra@0.9',
      fullName: 'Pair Extra',
      path: '/ext/apps/GPIO/pair_extra.fap',
      sdkApi: '88.16',
      iconBase64: '',
      devCatalog: false,
    );
    expect(installedApp(detail.card, installed)!.appid, 'pair_extra');
    expect(
      catalogAppState(
        card: (await api.fetchApps()).items.single,
        manifest: installed,
        targetSdk: (88, 16),
      ),
      CatalogAppState.update,
    );
    expect(
      catalogAppState(
        card: detail.card.forApp(detail.card.entries.first),
        manifest: installed,
        targetSdk: (88, 16),
      ),
      CatalogAppState.install,
    );
  });

  test('v0 retains its original endpoints and lookup body', () async {
    final v0 = CatalogV0Api(
      server: api.server,
      userAgent: AppHttp.userAgent,
      api: '88.16',
      target: 'f7',
    );
    await v0.fetchSdks();
    await v0.fetchCategories();
    await v0.fetchApps(isLatestReleaseVersion: true, hasVersion: true);
    expect(
      requests.last.queryParameters,
      containsPair('is_latest_release_version', 'true'),
    );
    await v0.fetchApp('pair');
    await v0.fetchAppsByUids([
      '64971d0f6617ba37a4bc79b3',
      'pair',
      'style:menu_style_wave',
    ]);
    expect(bodies.single['applications'], ['64971d0f6617ba37a4bc79b3']);
    expect(bodies.single.containsKey('ids'), isFalse);
    expect(requests.map((uri) => uri.path), [
      '/api/v0/sdk',
      '/api/v0/category',
      '/api/v0/0/application',
      '/api/v0/application/pair',
      '/api/v0/1/application',
    ]);
    api.server = AppsCatalogApi.officialServer;
    expect(api.hasV1, isFalse);
    await expectLater(
      api.fetchApp('dance', family: CatalogFamily.animations),
      throwsA(isA<CatalogNeedsV1Exception>()),
    );
  });

  test(
    'signed artifacts verify their digest and reject a modified body',
    () async {
      final bytes = Uint8List.fromList([1, 2, 3]);
      final digest = sha256.convert(bytes).bytes;
      final algorithm = Ed25519();
      final pair = await algorithm.newKeyPairFromSeed(List.filled(32, 17));
      final key = await pair.extractPublicKey();
      final signature = await algorithm.sign(digest, keyPair: pair);
      String hex(List<int> data) =>
          data.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
      final headers = {
        'x-qu-kid': 'test',
        'x-qu-sha256': hex(digest),
        'x-qu-sign-ed25519': hex(signature.bytes),
      };
      final uri = Uri.parse('https://catalog.test/file');
      expect(
        await verifySignedArtifact(
          uri,
          (bytes: bytes, headers: headers),
          keys: {'test': hex(key.bytes)},
        ),
        bytes,
      );
      await expectLater(
        verifySignedArtifact(
          uri,
          (bytes: Uint8List.fromList([4]), headers: headers),
          keys: {'test': hex(key.bytes)},
        ),
        throwsA(isA<ArtifactSignatureException>()),
      );
    },
  );
}
