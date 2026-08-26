import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../../../services/assembler/app_build_router.dart';
import '../../../services/http/app_http.dart';
import 'atp/atp_index.dart';
import 'atp/atp_source.dart';
import 'catalog_api.dart';
import 'catalog_context.dart';
import 'models/card.dart';

enum BinaryStage { queued, download, build }

typedef BinaryProgress = void Function(BinaryStage stage, double progress);

abstract class AppBinarySource {
  String get id;

  String get label;

  Future<List<int>> fetch(
    AppCard card, {
    required AppCurrentVersion version,
    required BinaryProgress onProgress,
    required bool Function() isCancelled,
  });

  String buildApi(AppCard card, AppCurrentVersion version);

  Future<String> iconBase64(AppCard card, AppCurrentVersion version);
}

class CatalogBinarySource implements AppBinarySource {
  CatalogBinarySource({required this.api, required this.catalog});

  final AppsCatalogApi api;
  final CatalogContext catalog;

  @override
  String get id => 'catalog';

  @override
  String get label => 'Apps catalog';

  @override
  String buildApi(AppCard card, AppCurrentVersion version) =>
      version.currentBuild?.sdk?.api ?? api.api ?? '';

  @override
  Future<String> iconBase64(AppCard card, AppCurrentVersion version) async {
    if (version.iconUri.isEmpty) return '';
    try {
      return base64Encode(await AppHttp.getBytes(Uri.parse(version.iconUri)));
    } catch (_) {
      return '';
    }
  }

  @override
  Future<List<int>> fetch(
    AppCard card, {
    required AppCurrentVersion version,
    required BinaryProgress onProgress,
    required bool Function() isCancelled,
  }) async {
    if (catalog.sourceBuildEnabled) {
      return AppBuildRouter.build(
        alias: card.alias,
        bundleUrl: api.sourceBundleUri(version.id).toString(),
        target: catalog.deviceTarget ?? 'f7',
        api: catalog.deviceApi,
        uid: card.id,
        versionUid: version.id,
        fetchBundle: (progress) =>
            api.fetchSourceBundle(version.id, onProgress: progress),
        isCancelled: isCancelled,
        onStage: (stage, progress) => onProgress(switch (stage) {
          AppBuildStage.queued => BinaryStage.queued,
          AppBuildStage.download => BinaryStage.download,
          AppBuildStage.build => BinaryStage.build,
        }, progress),
      );
    }

    void report(int received, int? total) {
      if (total == null || total <= 0) return;
      onProgress(BinaryStage.download, received / total);
    }

    try {
      return await api.fetchFapBuild(version.id, onProgress: report);
    } on AppHttpException catch (e) {
      if (e.statusCode != 404) rethrow;
      final appApi = await _appApi(card, version);
      final canFallback = appApi.isNotEmpty && appApi != api.api;
      if (canFallback && catalog.apiFallbackEnabled) {
        return api.fetchFapBuild(
          version.id,
          onProgress: report,
          apiOverride: appApi,
        );
      }
      throw StateError(
        canFallback
            ? 'App is built for API $appApi, firmware has ${api.api ?? '?'}; '
                  'switch the catalog mode in the apps settings to install it'
            : 'No compatible build for this firmware (API ${api.api ?? '?'})',
      );
    }
  }

  Future<String> _appApi(AppCard card, AppCurrentVersion version) async {
    final known = version.currentBuild?.sdk?.api ?? '';
    if (known.isNotEmpty) return known;
    try {
      final detail = await api.fetchApp(card.alias);
      return detail.card.currentVersion?.currentBuild?.sdk?.api ?? '';
    } catch (_) {
      return '';
    }
  }
}

class AtpBinarySource implements AppBinarySource {
  AtpBinarySource(this.source);

  final AtpSource source;

  @override
  String get id => 'atp';

  @override
  String get label => 'All-the-plugins';

  @override
  String buildApi(AppCard card, AppCurrentVersion version) =>
      source.block?.api ?? '';

  @override
  Future<String> iconBase64(AppCard card, AppCurrentVersion version) async =>
      source.entryFor(card.alias)?.iconBase64 ?? '';

  @override
  Future<List<int>> fetch(
    AppCard card, {
    required AppCurrentVersion version,
    required BinaryProgress onProgress,
    required bool Function() isCancelled,
  }) async {
    final entry = source.entryFor(card.alias);
    if (entry == null) {
      throw StateError(
        'The all-the-plugins release has no build of "${card.alias}" for this '
        'firmware',
      );
    }
    final url = source.block?.urlFor(entry);
    if (url == null || url.isEmpty) {
      throw StateError('No release archive for pack "${entry.pack}"');
    }
    final bytes = await AtpArchive.instance.fetchFap(
      entry,
      url,
      tag: source.tag,
      onProgress: (received, total) {
        if (total == null || total <= 0) return;
        onProgress(BinaryStage.download, received / total);
      },
    );
    _verify(entry, bytes);
    return bytes;
  }

  void _verify(AtpEntry entry, List<int> bytes) {
    if (entry.size > 0 && bytes.length != entry.size) {
      throw StateError(
        '${entry.appId}.fap is ${bytes.length} bytes, index says ${entry.size}',
      );
    }
    if (entry.md5.isEmpty) return;
    final actual = md5.convert(bytes).toString().toLowerCase();
    if (actual != entry.md5) {
      throw StateError(
        '${entry.appId}.fap md5 $actual, index says ${entry.md5}',
      );
    }
  }
}

class AppSourceRegistry {
  AppSourceRegistry({required this.catalog, required this.atp});

  final CatalogBinarySource catalog;
  final AtpBinarySource atp;

  AppBinarySource forCard(AppCard card) => card.isAtp ? atp : catalog;

  String? installDir(String alias) => atp.source.entryFor(alias)?.installDir;
}
