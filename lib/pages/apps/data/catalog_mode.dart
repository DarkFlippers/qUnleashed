import 'models/card.dart';

enum CatalogMode { resolving, normal, mismatch, compatibility, disabled }

(int, int)? parseApi(String? raw) {
  if (raw == null || raw.isEmpty) return null;
  final parts = raw.split('.');
  final major = int.tryParse(parts[0]);
  if (major == null) return null;
  final minor = parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;
  return (major, minor);
}

int compareApi((int, int) a, (int, int) b) {
  if (a.$1 != b.$1) return a.$1.compareTo(b.$1);
  return a.$2.compareTo(b.$2);
}

bool serverHasApi(List<AppSdk> sdks, String? deviceApi) {
  final target = parseApi(deviceApi);
  if (target == null) return false;
  for (final s in sdks) {
    final a = parseApi(s.api);
    if (a != null && compareApi(a, target) == 0) return true;
  }
  return false;
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

String? pickCompatApi(List<AppSdk> sdks, String? deviceApi) {
  final device = parseApi(deviceApi);
  if (sdks.isEmpty) return null;

  AppSdk? bestLeq;
  (int, int)? bestLeqApi;
  AppSdk? lowest;
  (int, int)? lowestApi;

  for (final s in sdks) {
    final a = parseApi(s.api);
    if (a == null) continue;
    if (lowestApi == null || compareApi(a, lowestApi) < 0) {
      lowest = s;
      lowestApi = a;
    }
    if (device != null && compareApi(a, device) <= 0) {
      if (bestLeqApi == null || compareApi(a, bestLeqApi) > 0) {
        bestLeq = s;
        bestLeqApi = a;
      }
    }
  }

  return (bestLeq ?? lowest)?.api;
}
