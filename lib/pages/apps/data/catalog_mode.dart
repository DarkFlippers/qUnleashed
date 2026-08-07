import '../../../components/codec/api_version.dart';
import 'models/card.dart';

enum CatalogMode { resolving, normal, mismatch, incompatible, compatibility }

enum ApiVerdict { normal, mismatch, tooOld, tooNew }

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
