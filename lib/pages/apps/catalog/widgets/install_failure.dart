import '../../../../services/assembler/remote_build_service.dart'
    show RemoteBuildException;
import '../../../../services/http/app_http.dart' show AppHttpException;
import '../../../../services/localization/l10n.dart';
import '../../data/artifact_signature.dart';
import '../../data/catalog_api.dart'
    show AppsCatalogException, CatalogVersionGoneException;

/// What a failed install tells the user. Every failure says something: the
/// engine records each one (InstallEngine.takeFailure), and one that ends
/// with the button back where it was and nothing said leaves the user to
/// guess.
String installFailureText(L10n s, Object failure) => switch (failure) {
  ArtifactSignatureException(:final unknownKey) =>
    unknownKey ? s.appsSignatureUnknownKey : s.appsSignatureRejected,
  // The engine's own errors are StateErrors with a localized message.
  StateError(:final message) => message,
  RemoteBuildException(:final message) => message,
  CatalogVersionGoneException() => s.appsErrorVersionGone,
  AppHttpException(:final statusCode) => s.appsErrorCatalogHttp(statusCode),
  AppsCatalogException() => s.appsErrorCatalogResponse,
  _ => s.appsErrorInstallFailed('$failure'),
};
