import '../../../services/localization/l10n.dart';

import 'dart:convert';

import '../../../services/assembler/app_build_router.dart';
import '../../../services/assembler/built_file.dart';
import '../../../services/http/app_http.dart';
import 'catalog_api.dart';
import 'catalog_context.dart';
import 'models/card.dart';

enum BinaryStage { queued, download, build }

typedef BinaryProgress = void Function(BinaryStage stage, double progress);

abstract class AppBinarySource {
  Future<BuiltFile> fetch(
    AppCard card, {
    required AppCurrentVersion version,
    required BinaryProgress onProgress,
    required bool Function() isCancelled,
  });

  /// The catalog icon as base64, or null when there is none to be had.
  Future<String?> iconBase64(AppCard card, AppCurrentVersion version);
}

class CatalogBinarySource implements AppBinarySource {
  CatalogBinarySource({required this.api, required this.catalog});

  final AppsCatalogApi api;
  final CatalogContext catalog;

  @override
  Future<String?> iconBase64(AppCard card, AppCurrentVersion version) async {
    if (version.iconUri.isEmpty) return null;
    try {
      return base64Encode(await AppHttp.getBytes(Uri.parse(version.iconUri)));
    } catch (_) {
      // Best effort: the app installs without one, as the official app's
      // does, and the manager draws the icon from the .fap instead.
      return null;
    }
  }

  @override
  Future<BuiltFile> fetch(
    AppCard card, {
    required AppCurrentVersion version,
    required BinaryProgress onProgress,
    required bool Function() isCancelled,
  }) async {
    // A CLI app is built and written like any other, from its own family's
    // routes: the application ones do not know its versions.
    final family =
        CatalogFamily.byServerName(card.family) ?? CatalogFamily.apps;
    if (catalog.sourceBuildEnabled) {
      return AppBuildRouter.build(
        alias: card.alias,
        bundleUrl: api.sourceBundleUri(version.id, family: family).toString(),
        target: catalog.deviceTarget ?? 'f7',
        api: catalog.deviceApi,
        uid: card.id,
        versionUid: version.id,
        fetchBundle: (progress) => api.fetchSourceBundle(
          version.id,
          onProgress: progress,
          family: family,
        ),
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

    // Only Archivarius does not say what a file was built for. Then the API
    // is what the official app writes (its getSdkApi): the version's, else
    // the one asked for.
    try {
      final file = await api.fetchFapBuild(
        version.id,
        onProgress: report,
        family: family,
      );
      return BuiltFile(
        file.bytes,
        buildApi: file.buildApi ?? version.currentBuild?.sdk?.api ?? api.api,
      );
    } on AppHttpException catch (e) {
      if (e.statusCode != 404) rethrow;
      final appApi = await _appApi(card, version);
      final canFallback = appApi.isNotEmpty && appApi != api.api;
      if (canFallback && catalog.apiFallbackEnabled) {
        final file = await api.fetchFapBuild(
          version.id,
          onProgress: report,
          apiOverride: appApi,
          family: family,
        );
        return BuiltFile(file.bytes, buildApi: file.buildApi ?? appApi);
      }
      throw StateError(
        canFallback
            ? l10n.appsErrorApiMismatch(appApi, api.api ?? '?')
            : l10n.appsErrorNoBuild(api.api ?? '?'),
      );
    }
  }

  Future<String> _appApi(AppCard card, AppCurrentVersion version) async {
    final known = version.currentBuild?.sdk?.api ?? '';
    if (known.isNotEmpty) return known;
    try {
      final detail = await api.fetchApp(
        card.alias,
        family: CatalogFamily.byServerName(card.family) ?? CatalogFamily.apps,
      );
      return detail.card.currentVersion?.currentBuild?.sdk?.api ?? '';
    } catch (_) {
      return '';
    }
  }
}
