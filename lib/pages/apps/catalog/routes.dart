import 'package:flutter/material.dart';

import '../data/catalog_api.dart' show CatalogFamily;

const String _authorsRoot = 'authors';

String _familyRoot(CatalogFamily family) => switch (family) {
  CatalogFamily.apps => 'apps',
  CatalogFamily.animations => 'animations',
  CatalogFamily.menuStyles => 'menustyles',
  CatalogFamily.cli => 'cli',
};

String catalogAppPath(CatalogFamily family, String id) =>
    '/${_familyRoot(family)}/$id';

String catalogAuthorPath(String id) => '/$_authorsRoot/$id';

class CatalogLink {
  const CatalogLink.app(CatalogFamily this.family, this.id);
  const CatalogLink.author(this.id) : family = null;

  final CatalogFamily? family;
  final String id;

  static final RegExp _id = RegExp(r'^[A-Za-z0-9_.-]+$');
  static final RegExp _alias = RegExp(r'^[A-Za-z0-9_-]+$');

  static CatalogLink? parse(Uri uri) {
    final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    if (segments.length == 1 && _alias.hasMatch(segments.single)) {
      return CatalogLink.app(CatalogFamily.apps, segments.single);
    }
    if (segments.length != 2 || !_id.hasMatch(segments.last)) return null;
    if (segments.first == _authorsRoot) {
      return CatalogLink.author(segments.last);
    }
    for (final family in CatalogFamily.values) {
      if (_familyRoot(family) == segments.first) {
        return CatalogLink.app(family, segments.last);
      }
    }
    return null;
  }
}

final List<Route<void>> _openRoutes = [];

void openCatalogRoute(
  BuildContext context,
  String path,
  WidgetBuilder builder,
) {
  final navigator = Navigator.of(context);
  _openRoutes.removeWhere((route) => !route.isActive);
  for (final route in _openRoutes) {
    if (route.navigator == navigator && route.settings.name == path) {
      navigator.popUntil((r) => r == route);
      return;
    }
  }
  final route = MaterialPageRoute<void>(
    settings: RouteSettings(name: path),
    builder: builder,
  );
  _openRoutes.add(route);
  navigator.push(route);
}
