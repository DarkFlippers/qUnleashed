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

  group('the sink keeps the message readable', () {
    test(
      'only the account name goes, because the log is read on the phone',
      () {
        // paths() is what runs at the sink. A user debugging their own device
        // needs the filename, the UID and the coordinates; handing them a log
        // about `<name>` failing to read `<hex>` would be useless.
        expect(
          Scrub.paths(
            r'read C:\Users\Myte\x failed: /ext/nfc/Office badge.nfc',
          ),
          r'read ~\x failed: /ext/nfc/Office badge.nfc',
        );
      },
    );
  });

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
      // The name may hold spaces, so the clause separators are what bound it.
      // Without them `nfc failed, see notes` reads as one filename and the
      // whole sentence disappears into `<name>.txt`.
      expect(
        Scrub.outbound('listing /ext/nfc failed, see notes.txt'),
        'listing /ext/nfc failed, see notes.txt',
      );
    });

    test('a path somewhere else is left alone', () {
      // The rule is about the Flipper's two filesystems, not about every
      // slash in every message. `paths()` handles the host's own.
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
