import 'package:flutter_test/flutter_test.dart';
import 'package:qunleashed/pages/apps/data/catalog_state.dart';
import 'package:qunleashed/pages/apps/data/models/card.dart';
import 'package:qunleashed/pages/apps/data/models/manifest.dart';

void main() {
  AppManifest installed(String sdkApi) => AppManifest(
    uid: 'demo',
    versionUid: '',
    fullName: 'Demo',
    path: '/ext/apps/Tools/demo.fap',
    sdkApi: sdkApi,
    iconBase64: '',
    devCatalog: false,
  );

  final card = AppCard.fromJson(const {
    'id': 'demo',
    'alias': 'demo',
    'current_version': {'id': 'demo@1', 'name': 'Demo', 'version': '1'},
  });

  test('a build of a newer minor of the same major needs no update', () {
    // Installed from a catalog on dev 88.23, running on release 88.19.
    expect(
      catalogAppState(
        card: card,
        manifest: installed('88.23'),
        targetSdk: (88, 19),
      ),
      CatalogAppState.open,
    );
  });

  test('a build of another major does', () {
    expect(
      catalogAppState(
        card: card,
        manifest: installed('87.1'),
        targetSdk: (88, 19),
      ),
      CatalogAppState.update,
    );
  });
}
