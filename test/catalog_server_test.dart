import 'package:flipperlib/flipperlib.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:qunleashed/pages/apps/data/catalog_api.dart';
import 'package:qunleashed/pages/apps/data/catalog_context.dart';
import 'package:qunleashed/pages/apps/data/catalog_server.dart';
import 'package:qunleashed/pages/apps/data/models/card.dart';

class _Api extends AppsCatalogApi {
  @override
  Future<List<AppSdk>> fetchSdks() async => const [];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('domains normalize without turning an official origin into v1', () {
    expect(
      CatalogServer.normalize(' catalog.flipperzero.one/ '),
      CatalogServer.official,
    );
    expect(
      CatalogServer.normalize('http://localhost:8080/'),
      'http://localhost:8080',
    );
    for (final input in [
      '',
      'ftp://catalog.test',
      'https://u:p@catalog.test',
      'https://catalog.test/api/v1',
      'https://catalog.test?q=1',
      'https://catalog.test/#x',
    ]) {
      expect(
        () => CatalogServer.normalize(input),
        throwsFormatException,
        reason: input,
      );
    }
  });

  test('server selection persists and a new context loads it', () async {
    SharedPreferences.setMockInitialValues({});
    final api = _Api();
    final context = CatalogContext(client: FlipperOneClient().get(), api: api);
    await context.setServer('http://localhost:8080/');
    expect(api.baseUrl, 'http://localhost:8080/api/v0');
    final reloaded = _Api();
    await CatalogContext(
      client: FlipperOneClient().get(),
      api: reloaded,
    ).loadPreference();
    expect(reloaded.server, api.server);
    await context.setServer(CatalogServer.official);
    expect(api.baseUrl, '${CatalogServer.official}/api/v0');
  });

  test('our server is spoken to as chosen, and the choice persists', () async {
    SharedPreferences.setMockInitialValues({});
    final api = _Api();
    final context = CatalogContext(client: FlipperOneClient().get(), api: api);
    await context.setServer('http://localhost:8080/');
    expect(api.protocol, CatalogProtocol.v1);
    expect(api.endpoint, 'http://localhost:8080/api/v1');

    await context.setProtocol(CatalogProtocol.v0);
    expect(api.hasV1, isFalse);
    expect(api.endpoint, 'http://localhost:8080/api/v0');
    final reloaded = _Api();
    await CatalogContext(
      client: FlipperOneClient().get(),
      api: reloaded,
    ).loadPreference();
    expect(reloaded.protocol, CatalogProtocol.v0);
    expect(reloaded.endpoint, api.endpoint);
  });

  test('Official speaks v0 whatever is chosen', () {
    final api = AppsCatalogApi(server: CatalogServer.official);
    expect(api.protocol, CatalogProtocol.v0);
    api.protocol = CatalogProtocol.v1;
    expect(api.hasV1, isFalse);
    expect(api.endpoint, '${CatalogServer.official}/api/v0');
    // The choice is kept for the next server of ours.
    api.server = 'http://localhost:8080';
    expect(api.protocol, CatalogProtocol.v1);
  });
}
