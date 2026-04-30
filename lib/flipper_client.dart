library flipper_client;

export 'package:flipperzero/flipperzero.dart';

export 'src/flipper_client.dart';

import 'src/flipper_client.dart';

class FlipperOneClient {
  static final FlipperOneClient _singleton = FlipperOneClient._internal();

  FlipperClient? _client;

  FlipperOneClient._internal();

  factory FlipperOneClient() => _singleton;

  FlipperClient get() {
    _client ??= FlipperClient();
    return _client!;
  }

  FlipperClient call() => get();
}
