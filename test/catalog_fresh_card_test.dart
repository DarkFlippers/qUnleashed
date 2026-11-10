import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:qunleashed/pages/apps/data/catalog_api.dart';
import 'package:qunleashed/services/http/app_http.dart';

void main() {
  test('a card read fresh is the card the next read gets', () async {
    final dir = await Directory.systemTemp.createTemp('fresh_card');
    AppHttp.jsonCacheDirectory = dir;
    addTearDown(() async {
      AppHttp.jsonCacheDirectory = null;
      await dir.delete(recursive: true);
    });
    final fixture = jsonDecode(
      File('test/fixtures/catalog/v1.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    var version = '1.0';
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);
    server.listen((request) async {
      final card = jsonDecode(jsonEncode(fixture['detail'])) as Map;
      (card['current_version'] as Map)['version'] = version;
      request.response
        ..headers.contentType = ContentType.json
        ..write(jsonEncode(card));
      await request.response.close();
    });
    final api = AppsCatalogApi(
      server: 'http://127.0.0.1:${server.port}',
      api: '88.16',
      target: 'f7',
    );
    Future<String?> read() async =>
        (await api.fetchApp('pair')).card.currentVersion?.version;

    expect(await read(), '1.0');
    version = '1.1';
    // Replaced on the server, and the copy kept for five minutes says not.
    expect(await read(), '1.0');
    final fresh = await api.fetchReplacement(
      'pair',
      family: CatalogFamily.apps,
    );
    expect(fresh.card.currentVersion?.version, '1.1');
    // What the fresh read answered is what is kept now.
    expect(await read(), '1.1');
  });
}
