import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qunleashed/pages/apps/data/artifact_signature.dart';
import 'package:qunleashed/pages/apps/data/catalog_api.dart';
import 'package:qunleashed/pages/apps/data/catalog_server.dart';
import 'package:qunleashed/pages/apps/data/catalog_state.dart';
import 'package:qunleashed/pages/apps/data/models/card.dart';
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
  // Public ids, as the server hands them out (Archivarius ObjectIds).
  String versionOf(String key) =>
      ((fixture[key] as Map<String, dynamic>)['current_version']
              as Map<String, dynamic>)['id']
          as String;
  final danceVersion = versionOf('animation');
  final extraVersion = versionOf('extra');

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
        case '/api/v1/menustyles/lookup' || '/api/v1/cli/lookup':
          bodies.add(
            jsonDecode(await utf8.decoder.bind(request).join())
                as Map<String, dynamic>,
          );
          key = path == '/api/v1/cli/lookup' ? 'none' : 'style_lookup';
        case '/api/v1/animations/dance':
          key = 'animation';
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
        case final path
            when path == '/api/v1/animations/version/$danceVersion/plan':
          key = 'plan';
        default:
          request.response.statusCode = 404;
          await request.response.close();
          return;
      }
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode(switch (key) {
          'v0_sdk' => [
            {'id': 'sdk', 'name': 'dev', 'api': '88.16', 'target': 'f7'},
          ],
          'style_lookup' => [fixture['style']],
          'none' => const [],
          _ => fixture[key],
        }),
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
      expect(extra.card.currentVersion!.id, extraVersion);
      expect(extra.card.id, detail.card.id);
      expect(detail.card.id, matches(RegExp(r'^[0-9a-f]{24}$')));
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
      final plan = await api.fetchAnimationPlan(danceVersion);
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
      // An earlier version of pair_extra than the one the catalog has.
      versionUid: '5f0a1b2c3d4e5f6a7b8c9d0e',
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

  test('a .fim names its version by its public id', () async {
    final detail = await api.fetchApp('pair');
    final list = (await api.fetchApps()).items.single;
    AppManifest installed(String uid, String versionUid) => AppManifest(
      uid: uid,
      versionUid: versionUid,
      fullName: 'Pair Extra',
      path: '/ext/apps/GPIO/pair_extra.fap',
      sdkApi: '88.16',
      iconBase64: '',
      devCatalog: false,
    );
    CatalogAppState stateOf(AppCard card, AppManifest manifest) =>
        catalogAppState(card: card, manifest: manifest, targetSdk: (88, 16));

    final extra = detail.card.forApp(detail.card.entries.last);
    final current = installed(detail.card.id, extraVersion);
    expect(installedApp(detail.card, current)!.appid, 'pair_extra');
    expect(stateOf(extra, current), CatalogAppState.open);

    final older = installed(detail.card.id, '0' * 24);
    expect(stateOf(extra, older), CatalogAppState.update);
    expect(stateOf(list, older), CatalogAppState.update);
  });

  test('installed apps find their card by its uid', () async {
    final lookup = await api.fetchAppsByUids(['pair']);
    final cards = InstalledCards()..replace(lookup);
    AppManifest installed(String uid) => AppManifest(
      uid: uid,
      versionUid: extraVersion,
      fullName: 'Pair Extra',
      path: '/ext/apps/GPIO/pair_extra.fap',
      sdkApi: '88.16',
      iconBase64: '',
      devCatalog: false,
    );

    final byPublicId = cards.cardFor(installed(lookup.single.id))!;
    expect(byPublicId.alias, 'pair_extra');
    expect(byPublicId.currentVersion!.id, extraVersion);
    expect(cards.cardFor(installed('pair')), isNull);
    expect(
      cards.cardFor(
        AppManifest(
          uid: 'ffffffffffffffffffffffff',
          versionUid: '',
          fullName: '',
          path: '/ext/apps/GPIO/unknown.fap',
          sdkApi: '',
          iconBase64: '',
          devCatalog: false,
        ),
      ),
      isNull,
    );
  });

  test('installed apps are looked up under their own family', () async {
    final style = (fixture['style'] as Map<String, dynamic>);
    final styles = await api.fetchAppsByUids([
      style['id'] as String,
    ], family: CatalogFamily.menuStyles);
    expect(styles.single.alias, 'menu_style_wave');
    expect(requests.last.path, '/api/v1/menustyles/lookup');
    expect(
      await api.fetchAppsByUids(['cli:x'], family: CatalogFamily.cli),
      isEmpty,
    );
    expect(requests.last.path, '/api/v1/cli/lookup');

    // Archivarius has the apps only: nothing else is asked for there.
    api.server = AppsCatalogApi.officialServer;
    final before = requests.length;
    expect(
      await api.fetchAppsByUids(['0' * 24], family: CatalogFamily.cli),
      isEmpty,
    );
    expect(requests, hasLength(before));
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
    'our server in v0 is asked as Official is, and for nothing of v1',
    () async {
      api.protocol = CatalogProtocol.v0;
      await api.fetchSdks();
      await api.fetchCategories();
      await api.fetchApps();
      await api.fetchApp('pair');
      expect(api.serves(CatalogFamily.menuStyles), isFalse);
      expect(
        await api.fetchAppsByUids([
          '64971d0f6617ba37a4bc79b3',
        ], family: CatalogFamily.cli),
        isEmpty,
      );
      expect(await api.fetchDevCatalog(), isFalse);
      await expectLater(
        api.search('pair'),
        throwsA(isA<CatalogNeedsV1Exception>()),
      );
      expect(requests.map((uri) => uri.path), [
        '/api/v0/sdk',
        '/api/v0/category',
        '/api/v0/0/application',
        '/api/v0/application/pair',
      ]);
    },
  );

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
