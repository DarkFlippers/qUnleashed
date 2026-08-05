import 'dart:io';

import 'package:flutter/services.dart' show AssetManifest, rootBundle;
import 'package:path_provider/path_provider.dart';

/// Asset path prefix (see pubspec `assets:`) holding the bundled hardnested
/// bitflip tables, shipped LZ4-compressed (~9.2 MB; ~700 MB raw).
const String _assetPrefix = 'assets/hardnested_tables/';

/// Sub-directory the native solver expects under the tables root.
const String _tablesSubdir = 'hardnested_tables';

/// Extracts the bundled hardnested bitflip tables to a writable directory (once)
/// and returns the directory that *contains* `hardnested_tables/` - i.e. the
/// value to hand to `qunleashed_hardnested_set_tables_path`.
///
/// Must run on the main isolate: it uses `rootBundle` and `path_provider`, which
/// need the platform channels unavailable inside `Isolate.run`. The returned
/// path is then passed into the recovery isolate as a plain string.
Future<String> ensureHardnestedTables() async {
  final support = await getApplicationSupportDirectory();
  final tablesDir = Directory('${support.path}/$_tablesSubdir');
  await tablesDir.create(recursive: true);

  final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
  final assets = manifest.listAssets().where(
    (asset) => asset.startsWith(_assetPrefix),
  );

  for (final asset in assets) {
    final name = asset.substring(_assetPrefix.length);
    if (name.isEmpty) continue;
    final target = File('${tablesDir.path}/$name');
    // Tables are immutable, so an existing file of the right size is reused;
    // this makes extraction idempotent and cheap after the first run.
    final data = await rootBundle.load(asset);
    final bytes = data.buffer.asUint8List(
      data.offsetInBytes,
      data.lengthInBytes,
    );
    if (await target.exists() && await target.length() == bytes.length) {
      continue;
    }
    await target.writeAsBytes(bytes, flush: true);
  }

  return support.path;
}
