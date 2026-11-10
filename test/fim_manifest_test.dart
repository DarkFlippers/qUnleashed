import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:qunleashed/pages/apps/data/catalog_api.dart';
import 'package:qunleashed/pages/apps/data/catalog_server.dart';
import 'package:qunleashed/pages/apps/data/catalog_state.dart';
import 'package:qunleashed/pages/apps/data/models/card.dart';
import 'package:qunleashed/pages/apps/data/models/manifest.dart';
import 'package:qunleashed/services/http/app_http.dart';

/// The `.fim` is read by the official apps as well as by this one. What
/// flipper-android's FapManifestParser does with one: every `Key: value` line
/// into a map, UID, Version UID and Path required, every other key optional,
/// unknown keys ignored, DevCatalog compared with its own dev-catalog setting.
Map<String, String>? officialRead(String text) {
  final map = <String, String>{};
  for (final line in const LineSplitter().convert(text)) {
    final idx = line.indexOf(':');
    if (idx <= 0) continue;
    map[line.substring(0, idx).trim()] = line.substring(idx + 1).trim();
  }
  for (final key in ['UID', 'Version UID', 'Path']) {
    if (!map.containsKey(key)) return null;
  }
  return map;
}

void main() {
  const full = AppManifest(
    uid: '66a1f0c2e4b0a1b2c3d4e5f6',
    versionUid: '66a1f0c2e4b0a1b2c3d4e5f7',
    fullName: 'ProtoPirate Extra',
    path: '/ext/apps/Sub-GHz/proto_pirate_extra.fap',
    iconBase64: 'iVBORw0KGgo=',
    sdkApi: '87.1',
    devCatalog: true,
    appId: 'proto_pirate_extra',
    appVersion: '3.0.2',
    family: ManifestFamily.app,
    catalog: 'qunleashed.aperturefox.ru',
  );

  test('writes the official keys first, in their order, and ours after', () {
    expect(full.encode(), '''
Filetype: Flipper Application Installation Manifest
Version: 1
Full Name: ProtoPirate Extra
Icon: iVBORw0KGgo=
Version Build API: 87.1
UID: 66a1f0c2e4b0a1b2c3d4e5f6
Version UID: 66a1f0c2e4b0a1b2c3d4e5f7
Path: /ext/apps/Sub-GHz/proto_pirate_extra.fap
DevCatalog: true
App ID: proto_pirate_extra
App Version: 3.0.2
Family: app
Catalog: qunleashed.aperturefox.ru
''');
  });

  test('leaves out what it does not know, but always says DevCatalog', () {
    const bare = AppManifest(uid: 'u', path: '/ext/apps/Tools/x.fap');
    expect(bare.encode(), '''
Filetype: Flipper Application Installation Manifest
Version: 1
UID: u
Path: /ext/apps/Tools/x.fap
DevCatalog: false
''');
  });

  test('reads back everything it wrote', () {
    final back = AppManifest.tryParse(full.encode())!;
    expect(back.encode(), full.encode());
    expect(back.family, ManifestFamily.app);
    expect(back.devCatalog, isTrue);
  });

  test('the official parser keeps what it needs and ignores the rest', () {
    final seen = officialRead(full.encode())!;
    expect(seen['UID'], full.uid);
    expect(seen['Version UID'], full.versionUid);
    expect(seen['Path'], full.path);
    expect(seen['DevCatalog'], 'true');
  });

  test('reads a manifest the official app wrote', () {
    const official = '''
Filetype: Flipper Application Installation Manifest
Version: 1
Full Name: Nfc Magic
Icon: iVBORw0KGgo=
Version Build API: 86.0
UID: 64d2039e13043e71ea766491
Version UID: 6993832f3a42809bf4c35bab
Path: /ext/apps/NFC/nfc_magic.fap
''';
    final m = AppManifest.tryParse(official)!;
    // Written back as it came but for the one line this app always says and
    // the official app leaves out when false.
    expect(m.encode(), '${official}DevCatalog: false\n');
    expect(m.uid, '64d2039e13043e71ea766491');
    expect(m.versionUid, '6993832f3a42809bf4c35bab');
    expect(m.sdkApi, '86.0');
    expect(m.devCatalog, isFalse);
    expect(m.appId, isNull);
    expect(m.appVersion, isNull);
    expect(m.family, isNull);
    expect(m.catalog, isNull);
  });

  test('an empty value is no value', () {
    final m = AppManifest.tryParse('''
Filetype: Flipper Application Installation Manifest
Version: 1
Full Name: Old
Icon:
Version Build API:
UID: 64d2039e13043e71ea766491
Version UID: 6993832f3a42809bf4c35bab
Path: /ext/apps/Tools/old_app.fap
DevCatalog: false
''')!;
    expect(m.iconBase64, isNull);
    expect(m.sdkApi, isNull);
    expect(m.uid, '64d2039e13043e71ea766491');
    expect(AppManifest.tryParse('UID: x\n'), isNull, reason: 'no Path');
  });

  test('an unknown family code is no family', () {
    expect(ManifestFamily.byCode('stl'), ManifestFamily.style);
    expect(ManifestFamily.byCode('cli'), ManifestFamily.cli);
    expect(ManifestFamily.byCode('anim'), isNull);
  });

  test('a catalog is named by its host, and its port when it has one', () {
    expect(
      CatalogServer.manifestName('https://qunleashed.aperturefox.ru'),
      'qunleashed.aperturefox.ru',
    );
    expect(
      CatalogServer.manifestName('https://catalog.flipperzero.one/'),
      'catalog.flipperzero.one',
    );
    expect(
      CatalogServer.manifestName('http://192.168.1.4:8080'),
      '192.168.1.4:8080',
    );
  });

  group('the family a .fim is looked up in', () {
    AppManifest at(String path, [ManifestFamily? family]) =>
        AppManifest(uid: 'u', path: path, family: family);

    test('is what it says', () {
      expect(
        catalogFamilyOf(at('/ext/apps/Tools/x.fap', ManifestFamily.cli)),
        CatalogFamily.cli,
      );
      expect(
        catalogFamilyOf(at('/ext/apps/Tools/x.fap', ManifestFamily.style)),
        CatalogFamily.menuStyles,
      );
    });

    test("is the official app's, apps only, when it does not say", () {
      expect(catalogFamilyOf(at('/ext/apps/Tools/x.fap')), CatalogFamily.apps);
    });

    test('groups what is installed, apps first', () {
      final grouped = groupByFamily([
        at('/ext/apps_data/cli/plugins/cli_x.fal', ManifestFamily.cli),
        at('/ext/apps/Tools/a.fap'),
        at('/ext/apps/Tools/b.fap', ManifestFamily.app),
      ]);
      expect(grouped.keys, [CatalogFamily.apps, CatalogFamily.cli]);
      expect(grouped[CatalogFamily.apps], hasLength(2));
    });
  });

  test('only what came from the catalog in use is asked about there', () {
    const ours = 'qunleashed.aperturefox.ru';
    final split = splitByCatalog([
      const AppManifest(uid: 'a', path: '/ext/apps/T/a.fap', catalog: ours),
      const AppManifest(uid: 'b', path: '/ext/apps/T/b.fap'),
      const AppManifest(
        uid: 'c',
        path: '/ext/apps/T/c.fap',
        catalog: 'catalog.flipperzero.one',
      ),
      const AppManifest(uid: '', path: '/ext/apps/T/d.fap', catalog: ours),
    ], 'https://$ours');
    expect(split.here.map((m) => m.uid), ['a', 'b']);
    expect(split.elsewhere, {'c': 'catalog.flipperzero.one'});
  });

  group('what an install writes', () {
    AppCard cardOf(String? family, String alias) => AppCard.fromJson({
      'id': '66a1f0c2e4b0a1b2c3d4e5f6',
      'alias': alias,
      'category_id': 'x',
      'author': '@me',
      'family': ?family,
    });
    const version = AppCurrentVersion(
      id: '66a1f0c2e4b0a1b2c3d4e5f7',
      name: 'Wave',
      version: '1.2',
      shortDescription: '',
      iconUri: '',
      screenshots: [],
    );
    AppManifest install(String? family, String alias) => catalogManifest(
      card: cardOf(family, alias),
      version: version,
      path: '/x/$alias',
      server: 'https://qunleashed.aperturefox.ru',
      devCatalog: true,
      buildApi: '88.16',
      icon: 'aWNvbg==',
    );

    test('names the app, its version, its family and its catalog', () {
      final m = install('application', 'wave');
      expect(m.uid, '66a1f0c2e4b0a1b2c3d4e5f6');
      expect(m.versionUid, '66a1f0c2e4b0a1b2c3d4e5f7');
      expect(m.appId, 'wave');
      expect(m.appVersion, '1.2');
      expect(m.family, ManifestFamily.app);
      expect(m.catalog, 'qunleashed.aperturefox.ru');
      expect(m.sdkApi, '88.16');
      expect(m.iconBase64, 'aWNvbg==');
      expect(m.devCatalog, isTrue);
    });

    test('by family', () {
      expect(install('cli', 'cli_x').family, ManifestFamily.cli);
      expect(
        install('menustyle', 'menu_style_wave').family,
        ManifestFamily.style,
      );
      expect(install(null, 'wave').family, ManifestFamily.app);
    });
  });

  group('whether a catalog is a dev one', () {
    late HttpServer server;
    late Directory cache;
    Object? said;

    setUp(() async {
      cache = Directory.systemTemp.createTempSync('fim_dev_catalog');
      AppHttp.jsonCacheDirectory = cache;
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({'sdk': const [], 'dev_catalog': ?said}),
        );
        await request.response.close();
      });
    });

    tearDown(() async {
      await server.close(force: true);
      AppHttp.jsonCacheDirectory = null;
      cache.deleteSync(recursive: true);
    });

    Future<bool> ask() =>
        AppsCatalogApi(server: 'http://127.0.0.1:${server.port}')
            .fetchDevCatalog();

    test('is what our server says', () async {
      said = false;
      expect(await ask(), isFalse);
    });

    test('says so when it builds on a dev tree', () async {
      said = true;
      expect(await ask(), isTrue);
    });

    test('is an error when the server does not say', () async {
      said = null;
      await expectLater(ask(), throwsA(isA<AppsCatalogException>()));
    });

    test('the official catalog never is', () async {
      expect(
        await AppsCatalogApi(server: AppsCatalogApi.officialServer)
            .fetchDevCatalog(),
        isFalse,
      );
    });
  });
}
