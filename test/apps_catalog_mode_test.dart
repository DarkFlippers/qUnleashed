import 'package:flutter_test/flutter_test.dart';
import 'package:qunleashed/pages/apps/data/catalog_mode.dart';
import 'package:qunleashed/pages/apps/data/models/card.dart';

AppSdk _sdk(String api, {String target = 'f7', bool latest = false}) => AppSdk(
  id: api,
  name: 'unlshd-$api',
  target: target,
  api: api,
  isLatestRelease: latest,
);

CatalogMode _modeFor(
  List<AppSdk> sdks,
  String deviceApi, {
  bool builderAvailable = false,
  CatalogModePreference preference = CatalogModePreference.auto,
}) {
  final res = resolveCatalogApi(sdks, deviceApi);
  return resolveCatalogMode(
    verdict: res.verdict,
    hasNearestApi: res.api != null,
    builderAvailable: builderAvailable,
    preference: preference,
  );
}

void main() {
  final catalog = [_sdk('86.0'), _sdk('87.0'), _sdk('87.1', latest: true)];

  test('api served by the catalog runs it as is', () {
    expect(_modeFor(catalog, '87.1'), CatalogMode.normal);
    expect(_modeFor(catalog, '87.6'), CatalogMode.normal);
  });

  test('a newer minor of the same major is still the catalog', () {
    // Release firmware 88.19 against a catalog that only has dev 88.23: the
    // loader checks the major only, so this is not compatibility mode.
    final dev = [_sdk('88.23')];
    expect(_modeFor(dev, '88.19'), CatalogMode.normal);
    expect(_modeFor(dev, '88.19', builderAvailable: true), CatalogMode.normal);
    expect(resolveCatalogApi(dev, '88.19').api, '88.23');
    // The closest at or below the device still wins when there is one.
    expect(
      resolveCatalogApi([_sdk('88.10'), _sdk('88.23')], '88.19').api,
      '88.10',
    );
    // A major apart is compatibility, two are out of reach.
    expect(_modeFor(dev, '89.0'), CatalogMode.nearestApi);
    expect(_modeFor(dev, '90.0'), CatalogMode.managerOnly);
    expect(_modeFor([_sdk('87.5')], '88.0'), CatalogMode.nearestApi);
  });

  test('catalog behind the firmware builds from source when it can', () {
    expect(
      _modeFor(catalog, '88.0', builderAvailable: true),
      CatalogMode.sourceBuild,
    );
  });

  test('without a builder the nearest catalog api is used', () {
    expect(_modeFor(catalog, '88.0'), CatalogMode.nearestApi);
    expect(_modeFor(catalog, '87.0'), CatalogMode.normal);
  });

  test('firmware the catalog cannot serve leaves the manager', () {
    expect(_modeFor(catalog, '85.0'), CatalogMode.managerOnly);
    expect(_modeFor(catalog, '90.0'), CatalogMode.managerOnly);
    expect(
      _modeFor(catalog, '90.0', builderAvailable: true),
      CatalogMode.sourceBuild,
    );
  });

  test('a stored preference wins over the automatic decision', () {
    expect(
      _modeFor(catalog, '87.1', preference: CatalogModePreference.manager),
      CatalogMode.managerOnly,
    );
    expect(
      _modeFor(
        catalog,
        '88.0',
        builderAvailable: true,
        preference: CatalogModePreference.catalog,
      ),
      CatalogMode.nearestApi,
    );
    expect(
      _modeFor(
        catalog,
        '87.1',
        builderAvailable: true,
        preference: CatalogModePreference.sourceBuild,
      ),
      CatalogMode.sourceBuild,
    );
  });

  test('build-from-source preference falls back when nothing can build', () {
    expect(
      _modeFor(catalog, '87.1', preference: CatalogModePreference.sourceBuild),
      CatalogMode.normal,
    );
    expect(
      _modeFor(catalog, '88.0', preference: CatalogModePreference.sourceBuild),
      CatalogMode.nearestApi,
    );
  });

  test('stored preference names survive a reload', () {
    for (final value in CatalogModePreference.values) {
      expect(CatalogModePreference.parse(value.name), value);
    }
    expect(CatalogModePreference.parse(null), CatalogModePreference.auto);
    expect(CatalogModePreference.parse('gone'), CatalogModePreference.auto);
  });
}
