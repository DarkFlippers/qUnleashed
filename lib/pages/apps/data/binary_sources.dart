import '../../../services/localization/l10n.dart';

import 'dart:convert';

import '../../../services/assembler/app_build_router.dart';
import '../../../services/http/app_http.dart';
import 'catalog_api.dart';
import 'catalog_context.dart';
import 'models/card.dart';

enum BinaryStage { queued, download, build }

typedef BinaryProgress = void Function(BinaryStage stage, double progress);

abstract class AppBinarySource {
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

    try {
      return await api.fetchFapBuild(
        version.id,
        onProgress: report,
        family: family,
      );
    } on AppHttpException catch (e) {
      if (e.statusCode != 404) rethrow;
      final appApi = await _appApi(card, version);
      final canFallback = appApi.isNotEmpty && appApi != api.api;
      if (canFallback && catalog.apiFallbackEnabled) {
        return api.fetchFapBuild(
          version.id,
          onProgress: report,
          apiOverride: appApi,
          family: family,
        );
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
