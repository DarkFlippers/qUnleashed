import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qunleashed/pages/apps/catalog/widgets/install_failure.dart';
import 'package:qunleashed/pages/apps/data/artifact_signature.dart';
import 'package:qunleashed/pages/apps/data/catalog_api.dart';
import 'package:qunleashed/services/assembler/remote_build_service.dart';
import 'package:qunleashed/services/http/app_http.dart';
import 'package:qunleashed/services/localization/gen/l10n_generated.dart';

void main() {
  final s = lookupL10n(const Locale('en'));
  final notFound = AppHttpException(404, 'https://catalog.test/x', '{}');

  test('every install failure says something of its own', () {
    final said = {
      'signature': installFailureText(
        s,
        ArtifactSignatureException('u', 'not signed'),
      ),
      'unknown key': installFailureText(
        s,
        ArtifactSignatureException('u', 'unknown key "k"'),
      ),
      'engine': installFailureText(s, StateError(s.appsErrorNoVersion)),
      'remote build': installFailureText(
        s,
        RemoteBuildException(s.remoteNoBuildApi),
      ),
      'gone': installFailureText(s, CatalogVersionGoneException('v', notFound)),
      'http': installFailureText(s, notFound),
      'catalog': installFailureText(s, AppsCatalogException(0, 'u', 'x')),
      'other': installFailureText(s, const FormatException('odd')),
    };
    expect(said, {
      'signature': s.appsSignatureRejected,
      'unknown key': s.appsSignatureUnknownKey,
      'engine': s.appsErrorNoVersion,
      'remote build': s.remoteNoBuildApi,
      'gone': s.appsErrorVersionGone,
      'http': s.appsErrorCatalogHttp(404),
      'catalog': s.appsErrorCatalogResponse,
      'other': s.appsErrorInstallFailed('FormatException: odd'),
    });
    expect(said.values.toSet(), hasLength(said.length));
  });
}
