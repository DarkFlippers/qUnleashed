import '../../../services/localization/l10n.dart';

import 'dart:convert';

import '../../../services/assembler/app_build_router.dart';
import '../../../services/http/app_http.dart';
import 'catalog_api.dart';
import 'catalog_context.dart';
import 'models/card.dart';

enum BinaryStage { queued, download, build }

typedef BinaryProgress = void Function(BinaryStage stage, double progress);

/// A file to install and the API it was built for, major and minor: what the
/// `.fim` records as Version Build API.
class FetchedBinary {
  const FetchedBinary(this.bytes, {required this.buildApi});

  final List<int> bytes;
  final String? buildApi;
}

abstract class AppBinarySource {
  Future<FetchedBinary> fetch(
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
  Future<FetchedBinary> fetch(
    AppCard card, {
    required AppCurrentVersion version,
    required BinaryProgress onProgress,
    required bool Function() isCancelled,
  }) async {
    // A CLI app is built and written like any other, from its own family's
    // routes: the application ones do not know its versions.
    final family =
        CatalogFamily.byServerName(card.family) ?? CatalogFamily.apps;
    String? built;
    void heard(String buildApi) => built = buildApi;
    if (catalog.sourceBuildEnabled) {
      final bytes = await AppBuildRouter.build(
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
        onBuildApi: heard,
      );
      // Built here: the device's own API is what it was built against.
      return FetchedBinary(bytes, buildApi: built ?? catalog.deviceApi);
    }

    void report(int received, int? total) {
      if (total == null || total <= 0) return;
      onProgress(BinaryStage.download, received / total);
    }

    try {
      final bytes = await api.fetchFapBuild(
        version.id,
        onProgress: report,
        family: family,
        onBuildApi: heard,
      );
      return FetchedBinary(
        bytes,
        buildApi: built ?? version.currentBuild?.sdk?.api ?? api.api,
      );
    } on AppHttpException catch (e) {
      if (e.statusCode != 404) rethrow;
      final appApi = await _appApi(card, version);
      final canFallback = appApi.isNotEmpty && appApi != api.api;
      if (canFallback && catalog.apiFallbackEnabled) {
        final bytes = await api.fetchFapBuild(
          version.id,
          onProgress: report,
          apiOverride: appApi,
          family: family,
          onBuildApi: heard,
        );
        return FetchedBinary(bytes, buildApi: built ?? appApi);
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
