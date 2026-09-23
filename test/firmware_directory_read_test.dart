import 'package:flutter_test/flutter_test.dart';
import 'package:qunleashed/pages/devices/firmware/directory.dart';
import 'package:qunleashed/pages/devices/firmware/repository.dart';
import 'package:qunleashed/services/logging.dart';

import 'firmware_fixture.dart';

/// What survives a directory feed that changed shape — #133.
///
/// One bad field used to cost the whole document: the decode threw, every
/// version of every channel went with it, and the directory-driven half of the
/// firmware page went away for every user at once. Reading each entry on its
/// own means the rest of the feed still arrives, so about half of these cases
/// are about what is *kept*; the rest are about what is dropped and how it is
/// named.
void main() {
  // resetFirmwareState reaches the theme controller, which reads
  // WidgetsBinding.instance in its constructor.
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(resetFirmwareState);

  const tag = '[Firmware] https://example.invalid/directory.json';

  /// Reads [json] and says what it dropped, the way `FirmwareParser.fetch`
  /// does.
  ///
  /// Named for the report because several cases below assert that nothing was
  /// said, and that only means anything while this really does report.
  FirmwareDirectory readAndReport(Object? json, {String at = tag}) {
    final reader = FirmwareDirectoryReader();
    final directory = reader.read(json);
    reader.report(at);
    return directory;
  }

  // Every case below is built to be dropped, so nothing in them decodes a
  // file, a real title or a real changelog. Without this one, a decode that
  // blanked every `sha256` would pass - and an empty checksum is exactly how
  // RemoteFirmwareSource is told not to verify the archive it is about to
  // flash.
  test('a well-formed feed arrives whole', () {
    final directory = readAndReport(
      feed([
        {
          'id': 'release',
          'title': 'Release',
          'description': 'Stable builds',
          'versions': [
            {
              'version': '1.2.3',
              'changelog': '# notes',
              'timestamp': 1700000000,
              'files': [
                {
                  'url': 'https://x.invalid/flipper-z-f7-update-1.2.3.tgz',
                  'target': 'f7',
                  'type': 'update_tgz',
                  'sha256': 'abc',
                },
                {
                  'url': 'https://x.invalid/full.bin',
                  'target': 'f18',
                  'type': 'full_bin',
                  'sha256': 'def',
                },
              ],
            },
            versionJson('1.2.2'),
          ],
        },
        channelJson('development', [versionJson('dev')]),
      ]),
    );

    expect(directory.channels.map((c) => c.id), ['release', 'development']);
    final release = directory.channels.first;
    expect(release.title, 'Release');
    expect(release.description, 'Stable builds');
    expect(release.versions.map((v) => v.version), ['1.2.3', '1.2.2']);
    expect(
      release.latest!.version,
      '1.2.3',
      reason: 'newest first, the order the feed lists them in',
    );
    expect(release.latest!.changelog, '# notes');
    expect(release.latest!.timestamp, 1700000000);
    expect(release.latest!.files, hasLength(2));

    final package = release.latest!.updatePackageFor('f7')!;
    expect(package.url, 'https://x.invalid/flipper-z-f7-update-1.2.3.tgz');
    expect(package.target, 'f7');
    expect(package.type, 'update_tgz');
    expect(
      package.sha256,
      'abc',
      reason: 'an empty one tells the installer not to check the flash',
    );
    expect(LogService.history, isEmpty);
  });

  group('a version that will not read', () {
    test('does not take the rest of its channel with it', () {
      final directory = readAndReport(
        feed([
          channelJson('release', [
            {'version': 1, 'changelog': 'bad'},
            versionJson('1.0.0'),
          ]),
        ]),
      );

      final release = directory.channelById('release')!;
      expect(release.versions.map((v) => v.version), ['1.0.0']);
    });

    test('is named once, at error, by where it sat', () {
      readAndReport(
        feed([
          channelJson('release', [
            {'version': 1, 'changelog': 'bad'},
            versionJson('1.0.0'),
          ]),
        ]),
      );

      final kept = keptAbout('skipped');
      expect(kept, hasLength(1));
      expect(kept.single, contains('[error]'));
      expect(kept.single, contains('channels[0](release).versions[0]'));
      expect(kept.single, contains('1 unreadable entry'));
      expect(
        kept.single,
        contains(tag),
        reason: 'or two firmwares are indistinguishable in the log',
      );
    });
    test('is one whose version string is blank', () {
      final directory = readAndReport(
        feed([
          channelJson('release', [
            {'version': ''},
            versionJson('1.0.0'),
          ]),
        ]),
      );

      expect(directory.channelById('release')!.versions.map((v) => v.version), [
        '1.0.0',
      ]);
      expect(
        keptAbout('channels[0](release).versions[0]: no version'),
        hasLength(1),
      );
    });
  });

  group('a channel that will not read', () {
    test('does not take the other channels with it', () {
      final directory = readAndReport(
        feed([
          {'title': 'no id here'},
          channelJson('release', [versionJson('1.0.0')]),
        ]),
      );

      expect(directory.channels.map((c) => c.id), ['release']);
    });

    // An empty list is an answer: the feed is saying this channel has no
    // builds. Nothing was lost, so there is nothing to say.
    test('is not one that genuinely carries none', () {
      final directory = readAndReport(feed([channelJson('release', [])]));

      expect(directory.channels.map((c) => c.id), ['release']);
      expect(directory.channelById('release')!.hasVersions, isFalse);
      expect(LogService.history, isEmpty, reason: 'nothing was lost');
    });

    // The unleashed feed ships `"versions": null` on release-candidate today,
    // so this is not a hypothetical shape.
    test('is not one whose versions the feed left out', () {
      final directory = readAndReport(
        feed([
          {'id': 'release-candidate', 'versions': null},
          {'id': 'release'},
        ]),
      );

      expect(directory.channels.map((c) => c.id), [
        'release-candidate',
        'release',
      ]);
      expect(LogService.history, isEmpty, reason: 'nothing was lost');
    });

    // A list that stopped being a list is the feed changing shape, not a
    // channel with nothing in it, and the two must not read the same.
    test('is one whose versions stopped being a list', () {
      final directory = readAndReport(
        feed([
          {'id': 'development', 'versions': 'nope'},
          channelJson('release', [versionJson('1.0.0')]),
        ]),
      );

      expect(directory.channels.map((c) => c.id), ['release']);
      expect(
        keptAbout('channels[0](development).versions: not a list'),
        hasLength(1),
      );
    });

    test('is one whose id is blank', () {
      final directory = readAndReport(
        feed([
          channelJson('', [versionJson('1.0.0')]),
          channelJson('release', [versionJson('1.0.0')]),
        ]),
      );

      expect(directory.channels.map((c) => c.id), ['release']);
      expect(keptAbout('channels[0]: no id'), hasLength(1));
    });

    test('is one whose versions all failed', () {
      final directory = readAndReport(
        feed([
          channelJson('development', [
            {'version': 1},
          ]),
          channelJson('release', [versionJson('1.0.0')]),
        ]),
      );

      expect(directory.channels.map((c) => c.id), ['release']);
      expect(
        keptAbout('channels[0](development): no version in it could be read'),
        hasLength(1),
      );
    });
  });

  group('a file that will not read', () {
    Map<String, dynamic> fileJson({
      String url = 'https://example.invalid/f.tgz',
      Object? target = 'f7',
      Object? type = 'update_tgz',
      Object? sha256 = 'abc',
    }) => {'url': url, 'target': target, 'type': type, 'sha256': sha256};

    // Not degradation: a version with no installable file makes the unleashed
    // display version null while the fetch still counts as a success, and the
    // card then reads NO UPDATE — the claim #118 was filed to remove.
    test('takes its version with it when it was the only one', () {
      final directory = readAndReport(
        feed([
          channelJson('release', [
            versionJson('1.0.0', files: [fileJson(target: 1)]),
            versionJson('0.9.0', files: [fileJson()]),
          ]),
        ]),
      );

      final release = directory.channelById('release')!;
      expect(release.versions.map((v) => v.version), ['0.9.0']);
      expect(
        keptAbout('channels[0](release).versions[0](1.0.0): no file'),
        hasLength(1),
      );
    });

    test('leaves a version that still has another file', () {
      final directory = readAndReport(
        feed([
          channelJson('release', [
            versionJson(
              '1.0.0',
              files: [
                fileJson(target: 'f18'),
                fileJson(type: 1),
              ],
            ),
          ]),
        ]),
      );

      final latest = directory.channelById('release')!.latest!;
      expect(latest.files.map((f) => f.target), ['f18']);
      expect(latest.updatePackageFor('f7'), isNull);
      expect(
        keptAbout('channels[0](release).versions[0](1.0.0).files[1]: bad type'),
        hasLength(1),
      );
    });

    // An empty list is the feed saying so, which the app already answers with
    // a localized "no package for this target" when someone presses install.
    test('is not a version the feed gave no files at all', () {
      final directory = readAndReport(
        feed([
          channelJson('release', [versionJson('1.0.0')]),
        ]),
      );

      expect(directory.channelById('release')!.latest!.files, isEmpty);
      expect(LogService.history, isEmpty, reason: 'nothing was lost');
    });

    // RemoteFirmwareSource reads an empty checksum as "this build publishes
    // none" and skips verifying an archive it is about to flash. Only the
    // variant URLs it mints itself are entitled to that.
    test('is one whose checksum is an empty string', () {
      final directory = readAndReport(
        feed([
          channelJson('release', [
            versionJson(
              '1.0.0',
              files: [
                fileJson(sha256: ''),
                fileJson(),
              ],
            ),
          ]),
        ]),
      );

      expect(directory.channelById('release')!.latest!.files, hasLength(1));
      expect(keptAbout('bad sha256'), hasLength(1));
    });

    // One renamed field is renamed in every file entry of the document, so a
    // single word repeated eighty-four times would say nothing a maintainer
    // could diff a feed against.
    test('names which of its fields were bad', () {
      readAndReport(
        feed([
          channelJson('release', [
            versionJson(
              '1.0.0',
              files: [
                fileJson(url: '', sha256: null),
                fileJson(),
              ],
            ),
          ]),
        ]),
      );

      final kept = keptAbout('bad url, sha256');
      expect(kept, hasLength(1));
      expect(
        kept.single,
        contains('channels[0](release).versions[0](1.0.0).files[0]'),
      );
    });
    // Absent is not the same as an empty list, and neither is a loss.
    test('is not a version with no files field at all', () {
      final directory = readAndReport(
        feed([
          channelJson('release', [
            {'version': '1.0.0'},
          ]),
        ]),
      );

      expect(directory.channelById('release')!.latest!.files, isEmpty);
      expect(LogService.history, isEmpty, reason: 'the feed never had them');
    });
  });

  group('a field that is only presentation', () {
    test('falls back rather than costing the channel', () {
      final directory = readAndReport(
        feed([
          {
            'id': 'release',
            'versions': [versionJson('1.0.0')],
          },
        ]),
      );

      final release = directory.channelById('release')!;
      expect(release.title, 'release', reason: 'the id stands in');
      expect(release.description, isEmpty);
      expect(LogService.history, isEmpty, reason: 'the feed never had them');
    });

    test('costs nothing on a version either', () {
      final directory = readAndReport(
        feed([
          channelJson('release', [
            {'version': '1.0.0', 'changelog': 42, 'timestamp': 'yesterday'},
          ]),
        ]),
      );

      final latest = directory.channelById('release')!.latest!;
      expect(latest.changelog, isEmpty);
      expect(latest.timestamp, 0);
    });

    // A renamed `changelog` deletes the WHAT'S NEW button from the card and a
    // renamed `description` takes text out of the channel picker. Falling back
    // in silence would leave nothing to find either one by.
    test('is still named when the feed changed its type', () {
      readAndReport(
        feed([
          {
            'id': 'release',
            'title': 7,
            'description': <String>[],
            'versions': [
              {'version': '1.0.0', 'changelog': 42},
            ],
          },
        ]),
      );

      expect(
        keptAbout('channels[0](release).title: not a string'),
        hasLength(1),
      );
      expect(
        keptAbout('channels[0](release).description: not a string'),
        hasLength(1),
      );
      expect(
        keptAbout(
          'channels[0](release).versions[0](1.0.0).changelog: not a string',
        ),
        hasLength(1),
      );
    });
  });

  group('a document that yields nothing', () {
    // An empty directory reaches the card as a success: the channel list falls
    // through to the custom one, the button offers "pick a file to install",
    // and the empty result is cached and stamped fresh, so nothing is fetched
    // again for ten minutes at a time. It has to arrive as a failure instead.
    test('throws rather than reading as an empty one', () {
      expect(
        () => readAndReport(
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
        readAndReport(
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
      expect(readAndReport(feed([])).channels, isEmpty);
      expect(readAndReport(<String, dynamic>{}).channels, isEmpty);
      expect(LogService.history, isEmpty);
    });

    // The whole field changing type is #133 in its purest form, and it used to
    // land here as an empty directory - the one outcome this must never
    // produce.
    test('is one whose channels stopped being a list', () {
      expect(
        () => readAndReport(<String, dynamic>{'channels': 'nope'}),
        throwsA(
          isA<FirmwareDirectoryUnreadable>().having(
            (e) => e.skipped,
            'skipped',
            contains('channels: not a list'),
          ),
        ),
      );
    });

    test('is one that is not an object at all', () {
      for (final body in <Object?>[
        <dynamic>['a list'],
        'a string',
        null,
      ]) {
        expect(
          () => readAndReport(body),
          throwsA(
            isA<FirmwareDirectoryUnreadable>().having(
              (e) => e.skipped,
              'skipped',
              ['document: not an object'],
            ),
          ),
          reason: '$body',
        );
      }
    });
    // The shape #133 was filed about, one level down: entries that stopped
    // being objects at all. The skip list is the only diagnostic there is, so
    // it has to name them rather than come out empty.
    test('is one whose channels stopped being objects', () {
      expect(
        () => readAndReport(feed(['release', 'development'])),
        throwsA(
          isA<FirmwareDirectoryUnreadable>().having(
            (e) => e.skipped,
            'skipped',
            ['channels[0]: not an object', 'channels[1]: not an object'],
          ),
        ),
      );
    });
  });

  group('the report', () {
    // `ensure` has many callers and no memory of its own, and pull-to-refresh
    // skips the freshness check entirely. Without this, a feed that is
    // permanently a little odd writes an error line every time anyone looks,
    // and evicts the real failures the history exists to hold.
    void readOneBadVersion({String at = tag}) => readAndReport(
      feed([
        channelJson('release', [
          {'version': 1},
          versionJson('1.0.0'),
        ]),
      ]),
      at: at,
    );

    test('says the same thing once', () {
      readOneBadVersion();
      readOneBadVersion();

      expect(keptAbout('skipped'), hasLength(1));
    });

    test('says it again for a different firmware', () {
      readOneBadVersion(at: '[Firmware] https://one.invalid/directory.json');
      readOneBadVersion(at: '[Firmware] https://two.invalid/directory.json');

      expect(keptAbout('skipped'), hasLength(2));
    });

    test('says it again once the feed breaks differently', () {
      readOneBadVersion();
      readAndReport(
        feed([
          {'title': 'no id here'},
          channelJson('release', [versionJson('1.0.0')]),
        ]),
      );

      expect(keptAbout('skipped'), hasLength(2));
    });

    // One renamed field is renamed in every entry that carries it, and the
    // whole joined string is what the repository keeps as the key it compares
    // every later failure against.
    test('names at most twenty of them and counts the rest', () {
      readAndReport(
        feed([
          channelJson('release', [
            for (var i = 0; i < 30; i++) {'version': i},
            versionJson('1.0.0'),
          ]),
        ]),
      );

      final kept = keptAbout('skipped');
      expect(kept.single, contains('skipped 30 unreadable entries'));
      expect(kept.single, contains('(and 10 more)'));
      expect(kept.single, contains('.versions[19]'));
      expect(kept.single, isNot(contains('.versions[20]')));
    });

    // channelById answers with the first of two, so without the index in the
    // name there is no way to tell which of them broke.
    test('tells two channels with the same id apart', () {
      readAndReport(
        feed([
          channelJson('release', [
            {'version': 1},
            versionJson('1.0.0'),
          ]),
          channelJson('release', [
            {'version': 2},
            versionJson('2.0.0'),
          ]),
        ]),
      );

      final kept = keptAbout('skipped');
      expect(kept.single, contains('channels[0](release).versions[0]'));
      expect(kept.single, contains('channels[1](release).versions[0]'));
    });
  });

  // Every other case here reads through the reader directly. This one goes the
  // way the app does, because the report is wired up in FirmwareParser.fetch
  // and nothing else would notice if that call went away.
  test('a partial read reaches the log through a real fetch', () async {
    feedEvery(
      (_) async => feed([
        channelJson('release', [
          {'version': 1},
          versionJson('1.0.0'),
        ]),
      ]),
    );

    await FirmwareRepository.instance.ensure(unleashed);

    expect(
      FirmwareRepository.instance.failedFor(unleashed),
      isFalse,
      reason: 'the good version still arrived',
    );
    expect(keptAbout('skipped'), hasLength(1));
  });

  // The cache is assigned on every fetch, not filled in once. A refresh that
  // fetched a new directory and kept the old one would leave the card showing
  // the first directory of the session for as long as the app is open.
  test('a second fetch replaces what the first one cached', () async {
    final parser = parserForEntry(unleashed);
    feedEvery(
      (_) async => feed([
        channelJson('release', [versionJson('1.0.0')]),
      ]),
    );
    await parser.fetch();
    expect(parser.cached!.channelById('release')!.latest!.version, '1.0.0');

    feedEvery(
      (_) async => feed([
        channelJson('release', [versionJson('2.0.0')]),
      ]),
    );
    await parser.fetch();

    expect(parser.cached!.channelById('release')!.latest!.version, '2.0.0');
  });
}
