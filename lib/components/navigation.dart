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
/// would be 24 strings to keep in step with nothing enforcing it, where this
/// is derived from the enum and cannot drift. (24, not the 25 this said:
/// replacing the Log screen with Diagnostics moved it.)
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

/// Whether [context]'s page is still the top of the navigator.
///
/// The guard for a handler whose whole effect is a synchronous push. A second
/// tap on the card that pushed a page stacks an identical copy of it, and both
/// have to be dismissed separately; where the pushed page fetches in
/// `initState`, it also fetches twice. `Route.isCurrent` goes false for the
/// pusher as soon as the pushed entry is present, which happens synchronously
/// with the push, so the second tap answers no.
///
/// A flag set in the handler cannot do this job here, because there is no await
/// to hold it across: it would have to be cleared when the pushed route
/// returns, which means keeping state for a question the navigator already
/// answers.
///
/// How reachable the second tap is depends on the platform and on where the
/// control sits. This app overrides no `pageTransitionsTheme`, so the
/// transition is the framework default per platform, and what decides whether
/// the click lands on the control or on the page arriving over it is coverage
/// under hit-testing. The guard does not depend on any of that, which is why
/// it is applied everywhere rather than behind a platform check. #244.
///
/// It costs no legitimate tap after a pop, which a draft of this comment
/// claimed it did: `pop()` flushes the history synchronously and leaves the
/// popped entry past `remove`, so the page below is current again the instant
/// the pop is requested rather than when the exit animation finalizes -
/// measured against the pinned SDK, not reasoned. That also settles the
/// comparison with a flag cleared on the pushed route's future, which would
/// clear at the same instant and needs a field, a `setState` and
/// dispose-safety.
///
/// What it does refuse is a push from a page with *anything* above it, a
/// dialog or a bottom sheet included. For a handler whose whole body is a
/// push, that is right. It is why this is not folded into [openRoute], whose
/// callers include two that push from a page while a sheet or dialog of their
/// own is still being dismissed.
///
/// [ModalRoute.isCurrentOf] rather than `ModalRoute.of(context)?.isCurrent`:
/// the aspect-scoped accessor depends on that one field, where the plain `of`
/// registers a dependency on the whole route scope and rebuilds the caller
/// when any of five unrelated properties changes.
///
/// True when there is no [ModalRoute] - a widget pumped outside one, which is
/// most widget tests. Refusing to push when the question cannot be answered
/// would break navigation to stop a duplicate of it.
bool isTopRoute(BuildContext context) =>
    ModalRoute.isCurrentOf(context) ?? true;

/// Pushes a page built by [builder], unless something is already above
/// [context]'s page.
///
/// The guarded form of `Navigator.of(context).push(MaterialPageRoute(...))`,
/// and what a tap handler whose whole effect is a push should call. The check
/// and the push are worth nothing apart, and nine sites held them adjacent by
/// hand before this existed - three others in the same files did not, which is
/// how #244 stayed open at them.
///
/// Unnamed, like the two dozen `MaterialPageRoute`s inside features: ADR 0013
/// puts route names on the ones [openRoute] owns, derived from the enum, and
/// naming these would be strings to keep in step with nothing enforcing it.
///
/// Answers null without pushing when it refuses, which a caller reading the
/// pop's result cannot tell from a page dismissed with nothing - correctly, as
/// in both cases nothing came back.
Future<T?> pushPage<T>(BuildContext context, WidgetBuilder builder) {
  if (!isTopRoute(context)) return Future<T?>.value();
  return Navigator.of(context).push<T>(MaterialPageRoute<T>(builder: builder));
}
