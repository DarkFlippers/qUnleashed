import 'package:flutter/widgets.dart';

import 'controller.dart';
import 'gen/l10n_generated.dart';

export 'gen/l10n_generated.dart' show L10n;

/// Strings for the locale the app currently runs in, for code that has a
/// [BuildContext]. Widgets read strings through this.
///
/// Falls back to [l10n] where no [Localizations] scope carries [L10n] — a
/// widget test that builds a bare `MaterialApp`, or a widget shown outside the
/// app's own tree — instead of throwing.
extension L10nContext on BuildContext {
  L10n get l10n => Localizations.of<L10n>(this, L10n) ?? l10nGlobal;
}

/// Strings for code that has no [BuildContext] — services, controllers and
/// enum labels. Resolves against the same locale the widget tree uses.
L10n get l10n => l10nGlobal;

L10n get l10nGlobal => lookupL10n(QLocaleController.instance.resolved);
