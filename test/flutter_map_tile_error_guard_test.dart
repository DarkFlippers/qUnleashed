// A guard on the one thing `lib/pages/archive/map/tile_http_client.dart`
// cannot check about itself: the upstream condition it exists to get past.
//
// flutter_map 8 treats a `ClientException` whose message contains `closed` or
// `cancel` as its own cancelled request and answers with a transparent tile,
// reporting nothing. dart:io words a server hanging up mid-response exactly
// that way, so the app's "source is not answering" notice stopped firing for a
// dropped connection, and `TileHttpClient` renames that exception so the
// substring no longer matches.
//
// That fix depends on a string literal in another package's private file, and
// `pubspec.yaml` takes `flutter_map: ^8.3.2`. If a later 8.x widens the
// condition - `ended`, `early`, `abort` - or restructures the branch, the
// rename stops working and **nothing else in this repository notices**:
// `map_tile_client_test.dart` asserts the wrapper against
// `TileHttpClient.readsAsAborted`, which is our own copy of the heuristic, not
// flutter_map's. So this reads flutter_map's source instead.
//
// A ceiling in `pubspec.yaml` was the alternative and is the weaker trade: it
// would also stop 8.4's fixes until someone re-read this, where the guard lets
// the bump through and speaks up only if the premise is gone.
//
// Deliberately narrow. It does not check that the words still sit inside the
// branch that swallows, or that `transparentImage` is still what comes back -
// the file path and the three substrings are enough to tell a reader where to
// look, and more parsing of someone else's private file would only add ways to
// fail for the wrong reason.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Where the swallow lives, relative to the package root.
const _tileImageProvider =
    'lib/src/layer/tile_layer/tile_provider/network/image_provider/'
    'image_provider.dart';

/// What `TileHttpClient.readsAsAborted` mirrors, and what it renames past.
const _heuristic = ["contains('closed')", "contains('cancel')"];

/// The exception type the branch is written on.
const _caught = 'on ClientException';

File _imageProviderSource() {
  final config = File('.dart_tool/package_config.json');
  expect(
    config.existsSync(),
    isTrue,
    reason:
        'no ${config.path}: run `flutter pub get` before this suite, or this '
        'guard checked nothing',
  );

  final packages =
      ((jsonDecode(config.readAsStringSync()) as Map)['packages'] as List)
          .cast<Map<String, Object?>>();
  final entry = packages.where((p) => p['name'] == 'flutter_map').toList();
  expect(
    entry,
    hasLength(1),
    reason:
        'flutter_map is not in ${config.path}. If the map no longer uses it, '
        'delete this guard and `tile_http_client.dart` with it.',
  );

  final root = (entry.single['rootUri']! as String).replaceFirst(
    RegExp(r'/$'),
    '',
  );
  final uri = Uri.parse('$root/$_tileImageProvider');
  return File.fromUri(uri.isAbsolute ? uri : config.parent.uri.resolveUri(uri));
}

void main() {
  test('flutter_map still swallows a tile error by reading its message', () {
    final source = _imageProviderSource();

    // Not a failure of the app: a failure of this guard's address. Whoever
    // sees it has to re-read the branch before trusting the rename again.
    expect(
      source.existsSync(),
      isTrue,
      reason:
          '''
${source.path} is gone, so this guard no longer checks anything.

flutter_map has moved or restructured the tile image provider. Find the
`on ClientException` branch in the new layout and either re-point this guard
at it or, if the swallow is gone, delete `tile_http_client.dart`, its test and
this file - and check that the map's "source is not answering" notice fires
again for a dropped connection.''',
    );

    final text = source.readAsStringSync();
    for (final needle in [_caught, ..._heuristic]) {
      expect(
        text,
        contains(needle),
        reason:
            '''
`$needle` is no longer in ${source.path}.

`TileHttpClient` renames a `ClientException` precisely because flutter_map
decides a tile error is its own cancellation by looking for `closed` and
`cancel` in the message. If that condition changed, the rename is either
useless or now hiding a real error, and the map's notice needs re-checking by
hand: point a tile layer at a source that hangs up mid-response and confirm
`mapSourceNotAnswering` still appears.''',
      );
    }
  });
}
