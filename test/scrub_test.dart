// What a message loses on its way off the device — ADR 0013 §6.2.
//
// The two directions both have a cost and the tests say which is which.
// Under-redaction sends a card dump to a third party, which cannot be taken
// back. Over-redaction sends `<hex> failed on <name>`, which is an event
// nobody can act on - and the whole reason errors are reported at all. So
// every rule here has a case for what it takes out *and* a case for what it
// must leave alone.
import 'package:flutter_test/flutter_test.dart';
import 'package:qunleashed/services/telemetry/scrub.dart';

void main() {
  setUp(() {
    Scrub.debugUseHomes([r'C:\Users\Myte']);
    Scrub.debugForgetDeviceNames();
  });
  tearDown(() {
    Scrub.debugUseHomes(null);
    Scrub.debugForgetDeviceNames();
  });

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

  group('hex runs', () {
    test('a UID goes', () {
      expect(Scrub.outbound('UID 04511E2A'), 'UID <hex>');
    });

    test('a key goes', () {
      expect(
        Scrub.outbound('recovered FFFFFFFFFFFA for sector 3'),
        'recovered <hex> for sector 3',
      );
    });

    test('a timestamp does not, because it is only digits', () {
      // The whole reason a letter is required. Without it this reads
      // `<hex>`, and so does every byte count and every build number.
      expect(
        Scrub.outbound('gave up after 1760000000 ms'),
        'gave up after 1760000000 ms',
      );
    });

    test('a short error code does not', () {
      expect(Scrub.outbound('error code 126'), 'error code 126');
    });

    test('an abbreviated commit survives, a full one does not', () {
      // Seven characters is what git abbreviates to and what the build header
      // carries, so it has to live. A 40-character SHA is over the floor and
      // goes - which costs nothing, because the commit reaches Sentry as a
      // tag and tags do not pass through here.
      expect(Scrub.outbound('built from abc1234'), 'built from abc1234');
      expect(Scrub.outbound('built from ${'a' * 40}'), 'built from <hex>');
    });

    test('a hyphenated value is one value, not two', () {
      // `\\b` treats the hyphen as a boundary and would leave the dash
      // stranded between two replacements.
      expect(Scrub.outbound('a1b2c3d4-e5f6a7b8'), '<hex>-<hex>');
    });

    test('an ordinary word of eight letters is not hex', () {
      expect(Scrub.outbound('transport unavailable'), 'transport unavailable');
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

    test('a duration does not', () {
      expect(Scrub.outbound('took 1.25s'), 'took 1.25s');
    });
  });

  group('Flipper names', () {
    test('a learned name goes', () {
      Scrub.rememberDeviceName('Mykhailo');
      expect(
        Scrub.outbound('[BLE] Mykhailo dropped the link'),
        '[BLE] <device> dropped the link',
      );
    });

    test('a name nobody has seen stays, because nothing can match it', () {
      expect(
        Scrub.outbound('[BLE] Mykhailo dropped the link'),
        '[BLE] Mykhailo dropped the link',
      );
    });

    test('a name too short to be one is refused', () {
      // Three characters would match inside unrelated words and corrupt every
      // message carrying one - and identifies nobody.
      Scrub.rememberDeviceName('Ace');
      expect(
        Scrub.outbound('[BLE] Ace and Facebook'),
        '[BLE] Ace and Facebook',
      );
    });

    test('a common four-letter name does not corrupt every message', () {
      // The replacement was an unanchored `replaceAll`, so a Flipper called
      // `File` turned `FileSystemException` into `<device>SystemException` -
      // degrading exactly the reports that had already failed. The home
      // patterns are anchored for this reason, and the four-character floor's
      // own comment cites that argument without having applied it.
      Scrub.rememberDeviceName('File');
      expect(
        Scrub.outbound('[Archive] FileSystemException on File'),
        '[Archive] FileSystemException on <device>',
      );
    });

    test('a name is still taken when punctuation surrounds it', () {
      // The anchor excludes word characters only, so quotes and brackets do
      // not hide a name from it.
      Scrub.rememberDeviceName('Mykhailo');
      expect(
        Scrub.outbound('[BLE] connect to "Mykhailo" failed'),
        '[BLE] connect to "<device>" failed',
      );
    });

    test('a name that is a prefix of another does not strand the rest', () {
      Scrub.rememberDeviceName('Flip');
      Scrub.rememberDeviceName('Flipper');
      expect(Scrub.outbound('Flipper lost'), '<device> lost');
    });

    test('the same name twice is remembered once', () {
      Scrub.rememberDeviceName('Zero');
      Scrub.rememberDeviceName('Zero');
      expect(Scrub.outbound('Zero Zero'), '<device> <device>');
    });
  });

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

  test('a card dump in a stack trace loses every part of itself', () {
    Scrub.rememberDeviceName('Mykhailo');
    expect(
      Scrub.outbound(
        r'[Archive] reading C:\Users\Myte\cache\/ext/nfc/Office badge.nfc '
        'from Mykhailo failed: block 4 is 04511E2AFFFFFFFF at 50.4501',
      ),
      r'[Archive] reading ~\cache\/ext/nfc/<name>.nfc from <device> failed: '
      'block 4 is <hex> at <coord>',
    );
  });
}
