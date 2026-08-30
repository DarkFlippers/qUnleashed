import '../../../services/localization/l10n.dart';
import 'api_version.dart';
import 'info.dart';

/// Why a `.fap` would be refused by the firmware loader, mirroring
/// `flipper_application_validate_manifest()` in
/// `lib/flipper_application/flipper_application.c`.
enum FapVerdict {
  ok,
  unreadable,
  invalidManifest,
  targetMismatch,
  apiTooOld,
  apiTooNew,
  unknown,
}

class FapCompat {
  const FapCompat(this.verdict, {this.appApi, this.deviceApi});

  final FapVerdict verdict;
  final String? appApi;
  final String? deviceApi;

  bool get isBlocking =>
      verdict != FapVerdict.ok && verdict != FapVerdict.unknown;

  String get badge => switch (verdict) {
    FapVerdict.ok => '',
    FapVerdict.unknown => '',
    FapVerdict.unreadable => l10n.fapBadgeBroken,
    FapVerdict.invalidManifest => l10n.fapBadgeBroken,
    FapVerdict.targetMismatch => l10n.fapBadgeHardware,
    FapVerdict.apiTooOld => l10n.fapBadgeOldApi,
    FapVerdict.apiTooNew => l10n.fapBadgeNewApi,
  };

  String get message => switch (verdict) {
    FapVerdict.ok => l10n.fapCompatOk,
    FapVerdict.unknown => l10n.fapCompatUnknown,
    FapVerdict.unreadable => l10n.fapCompatUnreadable,
    FapVerdict.invalidManifest => l10n.fapCompatInvalidManifest,
    FapVerdict.targetMismatch => l10n.fapCompatTargetMismatch,
    FapVerdict.apiTooOld => l10n.fapCompatApiTooOld('$appApi', '$deviceApi'),
    FapVerdict.apiTooNew => l10n.fapCompatApiTooNew('$appApi', '$deviceApi'),
  };
}

FapCompat evaluateFap(
  FapInfo? info, {
  String? deviceApi,
  String? deviceTarget,
}) {
  if (info == null) return const FapCompat(FapVerdict.unreadable);

  final manifest = info.manifest;
  if (manifest == null || !manifest.isValid) {
    return const FapCompat(FapVerdict.invalidManifest);
  }

  if (deviceTarget != null &&
      deviceTarget.isNotEmpty &&
      deviceTarget != manifest.target) {
    return FapCompat(FapVerdict.targetMismatch, appApi: manifest.api);
  }

  final device = parseApi(deviceApi);
  if (device == null) {
    return FapCompat(FapVerdict.unknown, appApi: manifest.api);
  }

  if (manifest.apiMajor < device.$1) {
    return FapCompat(
      FapVerdict.apiTooOld,
      appApi: manifest.api,
      deviceApi: deviceApi,
    );
  }
  if (manifest.apiMajor > device.$1) {
    return FapCompat(
      FapVerdict.apiTooNew,
      appApi: manifest.api,
      deviceApi: deviceApi,
    );
  }

  return FapCompat(FapVerdict.ok, appApi: manifest.api, deviceApi: deviceApi);
}
