import '../../../services/localization/l10n.dart';
import '../../../components/codec/fap/api_version.dart';
import 'models/card.dart';

/// How the catalog works right now. Resolved automatically from the firmware
/// API, the catalog SDK list and the builder availability; the user only ever
/// overrides it from the apps settings.
enum CatalogMode {
  resolving,
  normal,
  sourceBuild,
  nearestApi,
  managerOnly;

  String get label => switch (this) {
    CatalogMode.resolving => l10n.catalogModeResolving,
    CatalogMode.normal => l10n.catalogModeNormal,
    CatalogMode.sourceBuild => l10n.catalogModeSourceBuild,
    CatalogMode.nearestApi => l10n.catalogModeNearestApi,
    CatalogMode.managerOnly => l10n.catalogModeManagerOnly,
  };
}

/// What the apps settings page allows instead of the automatic decision.
enum CatalogModePreference {
  auto,
  catalog,
  sourceBuild,
  manager;

  static CatalogModePreference parse(String? raw) {
    for (final value in CatalogModePreference.values) {
      if (value.name == raw) return value;
    }
    return CatalogModePreference.auto;
  }
}

enum ApiVerdict { normal, mismatch, tooOld, tooNew }

/// Picks the working mode: the catalog as is when the API matches, source
/// builds when it does not and the builder can run, the nearest catalog API
/// when it cannot, and the apps manager when nothing else is left.
CatalogMode resolveCatalogMode({
  required ApiVerdict verdict,
  required bool hasNearestApi,
  required bool builderAvailable,
  CatalogModePreference preference = CatalogModePreference.auto,
}) {
  if (preference == CatalogModePreference.manager) {
    return CatalogMode.managerOnly;
  }
  if (preference == CatalogModePreference.catalog) {
    if (verdict == ApiVerdict.normal) return CatalogMode.normal;
    return hasNearestApi ? CatalogMode.nearestApi : CatalogMode.managerOnly;
  }
  if (preference == CatalogModePreference.sourceBuild && builderAvailable) {
    return CatalogMode.sourceBuild;
  }
  switch (verdict) {
    case ApiVerdict.normal:
      return CatalogMode.normal;
    case ApiVerdict.mismatch:
      if (builderAvailable) return CatalogMode.sourceBuild;
      return hasNearestApi ? CatalogMode.nearestApi : CatalogMode.managerOnly;
    case ApiVerdict.tooNew:
      return builderAvailable ? CatalogMode.sourceBuild : CatalogMode.managerOnly;
    case ApiVerdict.tooOld:
      return CatalogMode.managerOnly;
  }
}

class ApiResolution {
  const ApiResolution(this.verdict, [this.api]);

  final ApiVerdict verdict;
  final String? api;
}

ApiResolution resolveCatalogApi(List<AppSdk> sdks, String? deviceApi) {
  final device = parseApi(deviceApi);

  ((int, int), String)? sameBelow;
  ((int, int), String)? sameAbove;
  ((int, int), String)? adjacentBelow;
  int? maxMajor;

  for (final s in sdks) {
    final a = parseApi(s.api);
    if (a == null) continue;
    if (maxMajor == null || a.$1 > maxMajor) maxMajor = a.$1;
    if (device == null) continue;
    if (a.$1 == device.$1) {
      if (a.$2 <= device.$2) {
        if (sameBelow == null || a.$2 > sameBelow.$1.$2) sameBelow = (a, s.api);
      } else {
        if (sameAbove == null || a.$2 < sameAbove.$1.$2) sameAbove = (a, s.api);
      }
    } else if (a.$1 == device.$1 - 1) {
      if (adjacentBelow == null || compareApi(a, adjacentBelow.$1) > 0) {
        adjacentBelow = (a, s.api);
      }
    }
  }

  if (maxMajor == null) return ApiResolution(ApiVerdict.normal, deviceApi);
  if (device == null) {
    return ApiResolution(ApiVerdict.mismatch, latestSdk(sdks)?.api);
  }
  if (sameBelow != null) return ApiResolution(ApiVerdict.normal, sameBelow.$2);
  if (sameAbove != null) return ApiResolution(ApiVerdict.mismatch, sameAbove.$2);
  if (adjacentBelow != null) {
    return ApiResolution(ApiVerdict.mismatch, adjacentBelow.$2);
  }
  return maxMajor > device.$1
      ? const ApiResolution(ApiVerdict.tooOld)
      : const ApiResolution(ApiVerdict.tooNew);
}

AppSdk? latestSdk(List<AppSdk> sdks) {
  AppSdk? best;
  (int, int)? bestApi;
  for (final s in sdks) {
    if (s.isLatestRelease) return s;
    final a = parseApi(s.api);
    if (a == null) continue;
    if (bestApi == null || compareApi(a, bestApi) > 0) {
      best = s;
      bestApi = a;
    }
  }
  return best;
}
