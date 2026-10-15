// What a message loses on its way off the device — ADR 0013 §6.2.
//
// The two directions both have a cost and the tests say which is which.
// Under-redaction sends a card dump to a third party, which cannot be taken
// back. Over-redaction sends `reading <name>.nfc failed` with the one
// detail the reader needed gone, which is an event
// nobody can act on - and the whole reason errors are reported at all. So
// every rule here has a case for what it takes out *and* a case for what it
// must leave alone.
import 'package:flutter_test/flutter_test.dart';
import 'package:qunleashed/services/telemetry/scrub.dart';

void main() {
  setUp(() => Scrub.debugUseHomes([r'C:\Users\Myte']));
  tearDown(() => Scrub.debugUseHomes(null));

  // A group stood here asserting that the *sink* level left filenames, UIDs
  // and coordinates alone, so the on-screen log stayed readable for the person
  // whose device it was. ADR 0013 §1 removed that log, so there is one level
  // now and everything pays - which is what the rest of this file covers.
  //
  // That group was the only thing the split took with it. Nine other tests
  // went out in the same edit and should not have; see the note above
  // `group('URL query strings')`.

  // These are the shapes a review found going out intact. Every one is a real
  // message from `lib/`, not an invented string.
  group('a filename with no directory in front of it', () {
    test('a bare name goes', () {
      // lib/pages/archive/overview/controller.dart logs `key.fileName`, which
      // is `'$name.$extension'` with no path. The /ext rule needs the
      // directory, so this went out whole.
      expect(
        Scrub.outbound('[Archive] restore badge.nfc failed: timeout'),
        '[Archive] restore <name>.nfc failed: timeout',
      );
    });

    test('a quoted multi-word name goes in full', () {
      // lib/pages/tools/subghz/seed/seed_controller.dart logs a name the user
      // just typed, in quotes - which is what makes the spaces safe to match.
      expect(
        Scrub.outbound('[Seed] refused "Garage gate.sub": tooLong'),
        '[Seed] refused "<name>.sub": tooLong',
      );
    });

    test('an unquoted multi-word name keeps everything but its last word', () {
      // The documented under-reach. Nothing delimits the start of a bare
      // multi-word name, and allowing spaces made the rule swallow whole
      // clauses - so this leaks one word rather than destroying the message.
      expect(
        Scrub.outbound('[Archive] restore Office badge.nfc failed'),
        '[Archive] restore Office <name>.nfc failed',
      );
    });

    test('a source file is not a card', () {
      // Why the extensions are an allow-list: `\.[a-z]+` would rewrite every
      // one of these, and they appear in stack traces constantly.
      for (final line in const [
        'thrown from main.dart',
        'see pubspec.yaml',
        'package:qunleashed/services/logging.dart',
        'CMakeLists.txt',
      ]) {
        expect(Scrub.outbound(line), line, reason: line);
      }
    });

    test('a word that merely ends in an extension is not a file', () {
      // Anchored on both sides, so it cannot take half a token.
      expect(Scrub.outbound('v2.ir-blaster'), 'v2.ir-blaster');
    });
  });

  // Restored. These nine went out with the two-level split, on the mistaken
  // grounds that they belonged to the on-screen level - they do not: every one
  // of them drives `Scrub.outbound`, which the split did not touch. Deleting
  // them left `_query` with no coverage at all, which a mutation run found by
  // replacing its one `replaceAllMapped` and watching the whole suite stay
  // green.
  group('URL query strings', () {
    test('the key in a tile URL goes, the endpoint stays', () {
      expect(
        Scrub.outbound(
          'GET https://tiles.carto.com/light/3/4/5.png?api_key=abcdef12 failed',
        ),
        'GET https://tiles.carto.com/light/3/4/5.png?<query> failed',
      );
    });

    test('a URL with no query is untouched', () {
      expect(
        Scrub.outbound('GET https://update.flipperzero.one/firmware.json'),
        'GET https://update.flipperzero.one/firmware.json',
      );
    });

    test('a question mark in prose is not a query string', () {
      expect(Scrub.outbound('is it connected?'), 'is it connected?');
    });
  });

  group('filenames on the Flipper', () {
    test('the name goes, the directory and the extension stay', () {
      expect(
        Scrub.outbound('/ext/nfc/Office badge.nfc could not be read'),
        '/ext/nfc/<name>.nfc could not be read',
      );
    });

    test('a directory keeps its name, because that is the diagnostic half', () {
      // `/ext/nfc` with `nfc` replaced throws away the one part worth reading.
      expect(
        Scrub.outbound('listing /ext/subghz failed'),
        'listing /ext/subghz failed',
      );
    });

    test('nested directories survive down to the file', () {
      expect(
        Scrub.outbound('/ext/subghz/Gates/front gate.sub'),
        '/ext/subghz/Gates/<name>.sub',
      );
    });

    test('/int is covered as well as /ext', () {
      expect(Scrub.outbound('/int/Secret.nfc'), '/int/<name>.nfc');
    });

    test('a sentence after a directory is not read as a filename', () {
      // The directory rule allows spaces in the stem, so the clause
      // separators are what bound it: without them `nfc failed, see notes`
      // reads as one filename and the whole sentence disappears into
      // `<name>.txt`. `.txt` is also off the bare-name allow-list, so nothing
      // here is touched at all.
      expect(
        Scrub.outbound('listing /ext/nfc failed, see notes.txt'),
        'listing /ext/nfc failed, see notes.txt',
      );
    });

    test('a path somewhere else is left alone', () {
      // The rule is about the Flipper's two filesystems, not about every
      // slash in every message. The home-directory rule handles the host's
      // own.
      expect(Scrub.outbound('/usr/lib/libusb.so'), '/usr/lib/libusb.so');
    });
  });

  // What used to be `group('hex runs')`, inverted. A long hex run became
  // `<hex>`, and the rule is gone: a UID, a key, a MAC and a serial are now
  // sent whole, by decision - `Scrub`'s own doc records who decided and why.
  //
  // Asserted rather than deleted, because a deleted test cannot tell a
  // decision from a rule that quietly came back. These are the strings the
  // old group proved were taken out.
  group('identifiers the scrubber deliberately leaves whole', () {
    test('a card UID survives', () {
      expect(Scrub.outbound('UID 04511E2A'), 'UID 04511E2A');
    });

    test('a recovered key survives', () {
      expect(
        Scrub.outbound('recovered FFFFFFFFFFFA for sector 3'),
        'recovered FFFFFFFFFFFA for sector 3',
      );
    });

    test('a BLE address survives, which is the breadcrumb that wanted it', () {
      // `[FlipperClient] connecting to ... (ble:<uuid>)` used to arrive with
      // both halves of the identifier replaced, so the line said nothing
      // about which unit it had failed to reach.
      const line =
          '[FlipperClient] connecting to '
          '(ble:8C4F2B10-D2A5-790D-D1F6-A1B2C3D4E5F6)';
      expect(Scrub.outbound(line), line);
    });

    test('a full commit SHA survives', () {
      final sha = 'a' * 40;
      expect(Scrub.outbound('built from $sha'), 'built from $sha');
    });

    test('a timestamp was never touched and still is not', () {
      expect(
        Scrub.outbound('gave up after 1760000000 ms'),
        'gave up after 1760000000 ms',
      );
    });
  });

  group('coordinates', () {
    test('a pair goes', () {
      expect(
        Scrub.outbound('captured at 50.4501, 30.5234'),
        'captured at <coord>, <coord>',
      );
    });

    test('a version does not', () {
      expect(
        Scrub.outbound('qunleashed@0.15.0-dev+108080'),
        'qunleashed@0.15.0-dev+108080',
      );
    });

    // Renamed from 'a duration does not'. `took 1.25s` is not a format
    // anything in the app produces - the duration case is the test below, at
    // six places - and a test named for coverage it does not provide is how
    // the gap it was standing in for survived three days in production. What
    // it does pin is real and worth keeping: two places is under the
    // four-place floor.
    test('a two-place decimal does not', () {
      expect(Scrub.outbound('took 1.25s'), 'took 1.25s');
    });

    // The format the app actually produces. `Duration.toString()` writes six
    // decimal places, so this is the case the two-place test above was
    // standing in for and did not cover - it reached Sentry as
    // `TimeoutException after 0:00:<coord>` on the one failure whose whole
    // content is the number.
    test('a Duration.toString does not, at six places', () {
      expect(
        Scrub.outbound('TimeoutException after 0:00:30.000000: no data'),
        'TimeoutException after 0:00:30.000000: no data',
      );
      expect(
        Scrub.outbound(
          'reconnect failed: TimeoutException after 0:01:30.000000',
        ),
        'reconnect failed: TimeoutException after 0:01:30.000000',
      );
    });

    // The lookbehind is narrow on purpose: it excludes `H:MM:` and not every
    // colon, or a labelled coordinate would survive.
    test('a coordinate after a colon still goes', () {
      expect(Scrub.outbound('lat:50.4501'), 'lat:<coord>');
    });

    // `-?` is the only part of the pattern outside both lookbehinds, which
    // makes it the part most likely to break when somebody edits them - and
    // half the planet has a negative coordinate. Nothing covered it.
    test('a negative coordinate goes, on its own and after a digit', () {
      expect(Scrub.outbound('lat:-50.4501'), 'lat:<coord>');
      expect(
        Scrub.outbound('-50.4501 is the latitude'),
        '<coord> is the '
        'latitude',
      );
      expect(Scrub.outbound('bbox=10,-50.4501'), 'bbox=10,<coord>');
      // A pair written with the sign as the separator: `replaceAll` restarts
      // at the `-`, the first lookbehind rejects there, and the second half
      // then matches without its sign. Both go; only the minus survives.
      expect(Scrub.outbound('50.4501-30.5234'), '<coord>-<coord>');
    });

    // One line pinning both halves at once: the duration survives and the
    // coordinates beside it do not. This is the shape a real timeout on the
    // map would take, and it is the case that would catch the duration
    // exclusion leaking into the rest of the line.
    test('a duration and a coordinate on one line are told apart', () {
      expect(
        Scrub.outbound('after 0:00:30.000000 at 50.4501,30.5234'),
        'after 0:00:30.000000 at <coord>,<coord>',
      );
    });

    // Documented in `scrub.dart` as the cost of `(?<!\d)`, and pinned here so
    // the cost is a decision rather than a surprise. NMEA runs degrees and
    // minutes together, so the integer part is four or five digits and the
    // rule does not reach it. Nothing in the app emits this today - the map
    // parses decimal degrees, which cap at three - and if that changes this
    // test is what says the rule has to change with it.
    test('a four-digit integer part is out of reach, deliberately', () {
      expect(Scrub.outbound('5027.0067,N'), '5027.0067,N');
      // And the thing that change bought: it used to redact the tail of any
      // long decimal, which was never the intent.
      expect(Scrub.outbound('x=1234.5678'), 'x=1234.5678');
    });
  });

  // `group('Flipper names')` stood here, and was deleted rather than
  // inverted. The hex group above could be inverted because its rule matched
  // a *shape* - restore the rule and the assertions go red, which a mutation
  // run confirmed. The name rule matched a *learned set*, empty until
  // `rememberDeviceName` was called, and that API went away with it. So a
  // test that feeds the scrubber a name and expects it back passes against
  // every version of this file that has ever existed, including the one with
  // the rule still in. It read as cover for a guarantee it could not make,
  // which is CLAUDE.md's "trusting that a test fails for the reason its name
  // says" with the reasoning written directly above it.
  //
  // The decision lives in ADR 0013 §6.2 and in `Scrub`'s own doc. A
  // source-level ratchet over `lib/` - no `rememberDeviceName`, no literal
  // `'<device>'` - is the thing that would actually catch a reintroduction,
  // and `test/ratchet.dart` is the machinery for it if that day comes.

  // The home directory, which is every absolute path's first component and the
  // one category that can be taken out mechanically. These tests were in
  // `logging_kept_test.dart` until ADR §1 took the local log away: they used
  // to drive `LogService.error` and read the entry it kept, because that was
  // the thing a user copied into an issue. The rule did not move, so they now
  // drive the rule.
  //
  // Through the seam rather than the real environment: the cases worth pinning
  // are all about environments this machine does not have, and a test that
  // reads `Platform.environment` passes vacuously wherever it is unusual -
  // which is exactly where the bug was.
  group('home directories', () {
    test('one is replaced wherever it appears', () {
      Scrub.debugUseHomes([r'C:\Users\Myte']);

      final out = Scrub.outbound(r'could not clear C:\Users\Myte\Docs\x.ir');

      expect(out, isNot(contains('Myte')));
      expect(out, contains('~'));
    });

    // The case the first version missed. A FileSystemException prints the
    // native path, but a stack frame prints a URI with the separators flipped
    // and the drive behind a scheme - and the messages carrying stacks are the
    // ones most worth reporting.
    test('a Windows home is replaced in a stack frame URI too', () {
      Scrub.debugUseHomes([r'C:\Users\Myte']);

      expect(
        Scrub.outbound(
          'boom\n#0 main (file:///C:/Users/Myte/app/main.dart:7:20)',
        ),
        isNot(contains('Myte')),
      );
    });

    // A HOME of /root is ordinary in a container. Replacing it blind rewrote
    // /rootfs to ~fs and corrupted messages that had no path in them at all.
    test('one that prefixes an unrelated word is left alone', () {
      Scrub.debugUseHomes(['/root']);

      expect(Scrub.outbound('mounting /rootfs failed'), contains('/rootfs'));
    });

    test('and is still replaced when it is a real path', () {
      Scrub.debugUseHomes(['/root']);

      expect(Scrub.outbound('could not clear /root/x.ir'), contains('~/x.ir'));
    });

    // On Windows under Git Bash both environment keys hold the same string.
    // Behaviour cannot show the duplicate - replacing the same thing twice
    // gives the same answer - so the count is the only way to see it.
    test('the same home twice is not scanned for twice', () {
      Scrub.debugUseHomes([r'C:\Users\Myte']);
      final once = Scrub.debugHomePatternCount;

      Scrub.debugUseHomes([r'C:\Users\Myte', r'C:\Users\Myte']);

      expect(Scrub.debugHomePatternCount, once);
    });

    test('one too short to be a home is ignored', () {
      Scrub.debugUseHomes(['/x']);

      expect(Scrub.outbound('reading /x/y'), contains('/x/y'));
    });
  });

  group('nothing is dropped', () {
    test('a message with nothing to redact comes back unchanged', () {
      const line = '[RPC] rx unmatched frame';
      expect(Scrub.outbound(line), line);
    });

    test('an empty message is still a message', () {
      expect(Scrub.outbound(''), '');
    });
  });

  test('one line, three of the rules at once', () {
    // The home directory, the bare filename and the coordinate - not the
    // query string or the quoted filename, which have their own groups. The
    // device name and the block stay, and that is the half this used to lose:
    // what somebody triaging the report actually needs.
    expect(
      Scrub.outbound(
        r'[Archive] reading C:\Users\Myte\cache\/ext/nfc/Office badge.nfc '
        'from Ubl4te failed: block 4 is 04511E2AFFFFFFFF at 50.4501',
      ),
      r'[Archive] reading ~\cache\/ext/nfc/<name>.nfc from Ubl4te failed: '
      'block 4 is 04511E2AFFFFFFFF at <coord>',
    );
  });
}
