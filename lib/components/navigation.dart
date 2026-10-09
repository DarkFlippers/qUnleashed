import 'dart:typed_data';

import 'package:flipperlib/flipperlib.dart';
import 'package:flutter/material.dart';

/// Screens one feature opens in another. The pages themselves are registered by
/// `app/routes.dart`, so a feature never has to import a sibling feature.
enum AppRoute {
  remoteControl,
  pixelEditor,
  plotter,
  archiveMap,
  fliblerProject,
  appSettings,
  mapSettings,
  about,
  assemblerConsole,
  assemblerSettings,
}

/// Arguments for [AppRoute.pixelEditor]: one image file on the Flipper.
class PixelEditorArgs {
  const PixelEditorArgs({required this.remotePath, required this.client});

  final String remotePath;

  /// The Flipper the drawing is read from and written back to. Required
  /// rather than defaulted, so an editor opened from one device cannot save
  /// to another. ADR 0002.
  final FlipperClient client;
}

/// Arguments for [AppRoute.plotter]: a captured signal to plot right away.
class PlotterArgs {
  const PlotterArgs({required this.bytes, required this.name});

  final Uint8List bytes;
  final String name;
}

typedef AppRouteBuilder = Widget Function(BuildContext context, Object? args);

final Map<AppRoute, AppRouteBuilder> _builders = {};

void registerRoute(AppRoute route, AppRouteBuilder builder) {
  _builders[route] = builder;
}

/// Pushes [route] onto the navigator, replacing the current screen when
/// [replace] is set. Throws when nobody registered it, which can only happen if
/// `app/routes.dart` was not run at startup.
///
/// The route is **named**, after the enum. That is the one thing a navigator
/// observer needs in order to say which screen a transaction belongs to, and
/// ADR 0013 puts the names here rather than at the push sites: the 25
/// `MaterialPageRoute`s inside features stay unnamed, because naming them
/// would be 25 strings to keep in step with nothing enforcing it, where this
/// is derived from the enum and cannot drift.
Future<T?> openRoute<T>(
  BuildContext context,
  AppRoute route, {
  Object? args,
  bool replace = false,
}) {
  final builder = _builders[route];
  if (builder == null) {
    throw StateError('Route $route is not registered');
  }
  final page = MaterialPageRoute<T>(
    builder: (ctx) => builder(ctx, args),
    settings: RouteSettings(name: route.name),
  );
  final navigator = Navigator.of(context);
  return replace ? navigator.pushReplacement(page) : navigator.push(page);
}
