import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qunleashed/pages/apps/catalog/widgets/mode_badge.dart';
import 'package:qunleashed/pages/apps/data/catalog_mode.dart';
import 'package:qunleashed/services/localization/gen/l10n_generated.dart';
import 'package:qunleashed/theme/theme.dart';

Widget _host(CatalogModeBadge badge) => MaterialApp(
  theme: buildAppTheme(Brightness.dark, const Color(0xFFFF8200)),
  localizationsDelegates: L10n.localizationsDelegates,
  supportedLocales: L10n.supportedLocales,
  home: Scaffold(body: Center(child: badge)),
);

void main() {
  testWidgets('a catalog running as usual shows no badge', (t) async {
    for (final mode in [CatalogMode.normal, CatalogMode.resolving]) {
      await t.pumpWidget(
        _host(
          CatalogModeBadge(mode: mode, deviceApi: '88.19', catalogApi: '88.23'),
        ),
      );
      expect(find.byType(Icon), findsNothing, reason: mode.name);
    }
  });

  testWidgets('modes worth noticing keep their icon', (t) async {
    for (final (mode, device, icon) in [
      (CatalogMode.sourceBuild, '88.19', Icons.construction_rounded),
      (CatalogMode.nearestApi, '89.0', Icons.warning_amber_rounded),
      (CatalogMode.normal, null, Icons.link_off_rounded),
    ]) {
      await t.pumpWidget(
        _host(
          CatalogModeBadge(mode: mode, deviceApi: device, catalogApi: '88.23'),
        ),
      );
      expect(find.byIcon(icon), findsOneWidget, reason: mode.name);
    }
  });
}
