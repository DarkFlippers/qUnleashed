import 'package:flutter_test/flutter_test.dart';
import 'package:qunleashed/pages/devices/firmware/directory.dart';
import 'package:qunleashed/pages/devices/firmware/repository.dart';
import 'package:qunleashed/services/logging.dart';

import 'firmware_fixture.dart';

/// What survives a directory feed that changed shape — #133.
///
/// One bad field used to cost the whole document: the decode threw, every
/// channel of every version went with it, and the firmware page died for
/// every user at once. The point of reading each entry on its own is that the
/// rest of the feed still arrives, so most of these cases are about what is
/// *kept*, not what is dropped.
void main() {
  // resetFirmwareState reaches the theme controller, which reads
  // WidgetsBinding.instance in its constructor.
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(resetFirmwareState);

  /// A feed with [channels] verbatim, so a case can be as malformed as it
  /// needs to be.
  Map<String, dynamic> feed(List<dynamic> channels) => {'channels': channels};

  Map<String, dynamic> version(String name) => {
    'version': name,
    'changelog': 'notes',
    'timestamp': 0,
    'files': <dynamic>[],
  };

  Map<String, dynamic> channel(String id, List<dynamic> versions) => {
    'id': id,
    'title': id,
    'description': '',
    'versions': versions,
  };

  FirmwareDirectory read(Map<String, dynamic> json) {
    final reader = FirmwareDirectoryReader();
    final directory = reader.read(json);
    reader.report('https://example.invalid/directory.json');
    return directory;
  }

  group('a version that will not read', () {
    test('does not take the rest of its channel with it', () {
      final directory = read(
        feed([
          channel('release', [
            {'version': 1, 'changelog': 'bad'},
            version('1.0.0'),
          ]),
        ]),
      );

      final release = directory.channelById('release')!;
      expect(release.versions.map((v) => v.version), ['1.0.0']);
    });

    test('is named once, at error', () {
      read(
        feed([
          channel('release', [
            {'version': 1},
            version('1.0.0'),
          ]),
        ]),
      );

      final kept = keptAbout('skipped');
      expect(kept, hasLength(1));
      expect(kept.single, contains('[error]'));
      expect(kept.single, contains('release[0]'));
      expect(kept.single, contains('1 unreadable entry'));
    });
  });

  group('a channel that will not read', () {
    test('does not take the other channels with it', () {
      final directory = read(
        feed([
          {'title': 'no id here'},
          channel('release', [version('1.0.0')]),
        ]),
      );

      expect(directory.channels.map((c) => c.id), ['release']);
    });

    // Otherwise the card shows a channel with nothing in it, which reads as a
    // firmware that has no builds rather than one whose builds could not be
    // read.
    test('is not one that genuinely carries none', () {
      final directory = read(feed([channel('release', [])]));

      expect(directory.channels.map((c) => c.id), ['release']);
      expect(directory.channelById('release')!.hasVersions, isFalse);
      expect(LogService.history, isEmpty, reason: 'nothing was lost');
    });

    test('is one whose id is blank', () {
      final directory = read(
        feed([
          channel('', [version('1.0.0')]),
          channel('release', [version('1.0.0')]),
        ]),
      );

      expect(directory.channels.map((c) => c.id), ['release']);
      expect(keptAbout('no id'), hasLength(1));
    });

    test('is one whose versions all failed', () {
      final directory = read(
        feed([
          channel('development', [
            {'version': 1},
          ]),
          channel('release', [version('1.0.0')]),
        ]),
      );

      expect(directory.channels.map((c) => c.id), ['release']);
      expect(keptAbout('development: no version in it could be read'),
          hasLength(1));
    });
  });

  group('a file that will not read', () {
    test('leaves the version, which simply cannot be installed', () {
      final directory = read(
        feed([
          channel('release', [
            {
              'version': '1.0.0',
              'files': [
                {'url': 'u', 'target': 'f7', 'type': 'update_tgz'},
              ],
            },
          ]),
        ]),
      );

      final latest = directory.channelById('release')!.latest!;
      expect(latest.version, '1.0.0');
      expect(latest.files, isEmpty);
      expect(latest.updatePackageFor('f7'), isNull);
      expect(keptAbout('incomplete'), hasLength(1));
    });
  });

  group('a field that is only presentation', () {
    test('falls back rather than costing the channel', () {
      final directory = read(
        feed([
          {
            'id': 'release',
            'versions': [version('1.0.0')],
          },
        ]),
      );

      final release = directory.channelById('release')!;
      expect(release.title, 'release', reason: 'the id stands in');
      expect(release.description, isEmpty);
      expect(LogService.history, isEmpty, reason: 'nothing was lost');
    });

    test('costs nothing on a version either', () {
      final directory = read(
        feed([
          channel('release', [
            {'version': '1.0.0', 'changelog': 42, 'timestamp': 'yesterday'},
          ]),
        ]),
      );

      final latest = directory.channelById('release')!.latest!;
      expect(latest.changelog, isEmpty);
      expect(latest.timestamp, 0);
    });
  });

  group('a document that yields nothing', () {
    // An empty directory is indistinguishable from a server that answered "no
    // builds": the card would read NO UPDATE and stop retrying. It has to
    // reach the repository as a failure instead.
    test('throws rather than reading as an empty one', () {
      expect(
        () => read(
          feed([
            {'title': 'no id'},
            {'also': 'no id'},
          ]),
        ),
        throwsA(isA<FirmwareDirectoryUnreadable>()),
      );
    });

    test('carries what it dropped', () {
      try {
        read(
          feed([
            {'title': 'no id'},
          ]),
        );
        fail('expected FirmwareDirectoryUnreadable');
      } on FirmwareDirectoryUnreadable catch (e) {
        expect(e.skipped, hasLength(1));
        expect(e.toString(), contains('channels[0]'));
      }
    });

    // A feed that genuinely has no channels is a different answer from one
    // this cannot read, and only the second is a failure.
    test('is not a feed that simply has none', () {
      expect(read(feed([])).channels, isEmpty);
      expect(read(<String, dynamic>{}).channels, isEmpty);
      expect(LogService.history, isEmpty);
    });
  });

  // Everything above reads through the reader directly. This one goes the
  // way the app does, because the report is wired up in FirmwareParser.fetch
  // and nothing else would notice if that call went away.
  test('a partial read reaches the log through a real fetch', () async {
    feedEvery(
      (_) async => feed([
        channel('release', [
          {'version': 1},
          version('1.0.0'),
        ]),
      ]),
    );

    await FirmwareRepository.instance.ensure(unleashed);

    expect(
      FirmwareRepository.instance.failedFor(unleashed),
      isFalse,
      reason: 'the good version still arrived',
    );
    final kept = keptAbout('skipped');
    expect(kept, hasLength(1));
    expect(kept.single, contains('[error]'));
  });

  test('a channels field that is not a list is said, not assumed', () {
    expect(read(<String, dynamic>{'channels': 'nope'}).channels, isEmpty);
    expect(keptAbout('channels: not a list'), hasLength(1));
  });
}
