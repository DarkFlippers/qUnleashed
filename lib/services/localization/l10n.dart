import 'package:flutter/widgets.dart';

import 'controller.dart';
import 'gen/l10n_generated.dart';

export 'gen/l10n_generated.dart' show L10n;

/// Strings for the locale the app currently runs in, for code that has a
/// [BuildContext]. Widgets read strings through this.
extension L10nContext on BuildContext {
  L10n get l10n => L10n.of(this);
}

/// Strings for code that has no [BuildContext] — services, controllers and
/// enum labels. Resolves against the same locale the widget tree uses.
L10n get l10n => lookupL10n(QLocaleController.instance.resolved);
