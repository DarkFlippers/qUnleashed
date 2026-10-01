import 'package:flipperlib/flipperlib.dart';
import 'package:flutter/material.dart';

import '../../../../components/dialogs/connection_error.dart';
import '../../../../services/connection/link_service.dart';
import '../../../../services/localization/l10n.dart';
import '../../../../theme/theme.dart';
import '../page_card.dart';

/// What an auto-connect that did not work leaves on the device page.
///
/// Auto-connect runs off a debounced timer, so there is no gesture to hang a
/// dialog on, and a modal popping on a cable event would be wrong even if
/// there were. It is also not a passing failure: the Flipper stays in
/// `_autoTriedUsb` while it is plugged in, so nothing dials it again until
/// something changes. A toast would fade while the condition did not.
///
/// So this stays until the situation does, and it says the same sentence the
/// picker's dialog would have said - [describeConnectError] is shared with it,
/// which is how the `maxSessions` case gets "disconnect one first" here too.
/// #120.
class AutoConnectHintCard extends StatelessWidget {
  const AutoConnectHintCard({super.key, required this.links});

  /// Passed in rather than read here, so this card can be built against a
  /// service with a known failure on it. ADR 0002 - the singleton stays, and
  /// the page is where it is reached for.
  final LinkService links;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: links,
      builder: (context, _) {
        final failure = links.autoConnectFailure;
        if (failure == null) return const SizedBox.shrink();

        final colors = context.appColors;
        final (_, body) = describeConnectError(
          classifyConnectError(failure.error),
          isBle: failure.isBle,
        );

        return Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: FlipperPageCard(
            title: context.l10n.fmAutoConnectFailedTitle(failure.name),
            trailing: IconButton(
              icon: const Icon(Icons.close, size: 20),
              color: colors.textSecondary,
              tooltip: context.l10n.commonClose,
              onPressed: links.dismissAutoConnectFailure,
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  body,
                  style: TextStyle(fontSize: 14, color: colors.textSecondary),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
