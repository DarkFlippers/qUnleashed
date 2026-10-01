import 'package:flipperlib/flipperlib.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qunleashed/services/localization/l10n.dart';
import 'package:qunleashed/components/dialogs/connection_error.dart';

/// Which sentence a failed connect turns into.
///
/// `classifyConnectError` is covered in flipperlib; what is covered here is
/// the half that lives in this app - that every kind has a pair of strings,
/// and that the two "no room for another one" kinds do not share them.
///
/// The case that prompted this: `_connectLocked` throws once the app already
/// holds `maxSessions` links, and nothing matched it, so the user got the
/// generic "Connection failed" with no mention of the link they would have to
/// let go of. #120.
void main() {
  (String, String) describe(Object error, {bool isBle = true}) =>
      describeConnectError(classifyConnectError(error), isBle: isBle);

  group('the app running out of links', () {
    // End to end over the message the client actually throws, which is the
    // regression: classify it, then look up its strings.
    test('is not the generic failure', () {
      final (title, _) = describe(
        StateError(FlipperClient.sessionLimitMessage),
      );

      expect(title, isNot(l10n.connectFailedTitle));
    });

    test('says how many links there are', () {
      final (_, body) = describe(StateError(FlipperClient.sessionLimitMessage));

      expect(body, contains('${FlipperClient.maxSessions}'));
    });

    // The distinction the separate kind exists for: one is fixed in system
    // settings, the other in the picker. Folding them would make one sentence
    // cover both, which is how the generic title got used for this.
    test('is not the system pairing limit', () {
      final session = describeConnectError(
        FlipperConnectErrorKind.sessionLimit,
        isBle: true,
      );
      final paired = describeConnectError(
        FlipperConnectErrorKind.tooManyDevices,
        isBle: true,
      );

      expect(session.$1, isNot(paired.$1));
      expect(session.$2, isNot(paired.$2));
    });

    // The body is the same whichever way the third one was being added - the
    // cap is on links, not on transports.
    test('reads the same over USB', () {
      expect(
        describe(StateError(FlipperClient.sessionLimitMessage), isBle: false),
        describe(StateError(FlipperClient.sessionLimitMessage)),
      );
    });
  });

  group('every kind', () {
    for (final kind in FlipperConnectErrorKind.values) {
      test('has something to say: $kind', () {
        final (title, body) = describeConnectError(kind, isBle: true);

        expect(title, isNotEmpty);
        expect(body, isNotEmpty);
      });
    }
  });

  // The one kind whose body depends on the transport, kept so that adding a
  // kind above does not quietly flatten this one.
  group('a device that did not answer', () {
    test('is told to move closer over BLE', () {
      final (_, body) = describeConnectError(
        FlipperConnectErrorKind.deviceUnreachable,
        isBle: true,
      );

      expect(body, l10n.connectUnreachableBleBody);
    });

    test('is told to replug over USB', () {
      final (_, body) = describeConnectError(
        FlipperConnectErrorKind.deviceUnreachable,
        isBle: false,
      );

      expect(body, l10n.connectUnreachableUsbBody);
    });
  });
}
