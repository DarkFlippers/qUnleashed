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
///
/// The reader only knows what there is to say. Whether it gets said, at what
/// level, and whether it has been said already all belong to `FirmwareParser`,
/// so those cases are at the bottom, through a real fetch.
void main() {
  // resetFirmwareState reaches the theme controller, which reads
  // WidgetsBinding.instance in its constructor.
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(resetFirmwareState);

  /// Reads [json] and hands back both halves: what was decoded, and what the
  /// read had to say for itself ('' when it was clean).
  ({FirmwareDirectory directory, String said}) read(Object? json) {
    final reader = FirmwareDirectoryReader();
    final directory = reader.read(json);
    return (directory: directory, said: reader.summary?.said ?? '');
  }

  Map<String, dynamic> fileJson({
    Object? url = 'https://example.invalid/f.tgz',
    Object? target = 'f7',
    Object? type = 'update_tgz',
    Object? sha256 = 'abc',
  }) => {'url': url, 'target': target, 'type': type, 'sha256': sha256};

  // Every case below is built to be dropped, so none of them asserts the
  // values a decoded entry carries. Without this one, a decode that blanked
  // every `sha256` would pass — and an empty checksum is exactly how
  // RemoteFirmwareSource is told not to verify the archive it is about to
  // flash.
  test('a well-formed feed arrives whole', () {
    final result = read(
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
                // Ahead of the update package on purpose: `updatePackageFor`
                // matches on type as well as target, and a raw image handed to
                // the installer as an update archive is flashed as one.
                {
                  'url': 'https://x.invalid/full.bin',
                  'target': 'f7',
                  'type': 'full_bin',
                  'sha256': 'def',
                },
                {
                  'url': 'https://x.invalid/flipper-z-f7-update-1.2.3.tgz',
                  'target': 'f7',
                  'type': 'update_tgz',
                  'sha256': 'abc',
                },
              ],
            },
            versionJson('1.2.2'),
          ],
        },
        channelJson('development', [versionJson('dev')]),
      ]),
    );

    final directory = result.directory;
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
    expect(release.latest!.files.map((f) => f.type), [
      'full_bin',
      'update_tgz',
    ], reason: 'in the order the feed lists them');

    final package = release.latest!.updatePackageFor('f7')!;
    expect(
      package.type,
      'update_tgz',
      reason: 'not the full image listed first for the same target',
    );
    expect(package.url, 'https://x.invalid/flipper-z-f7-update-1.2.3.tgz');
    expect(package.target, 'f7');
    expect(
      package.sha256,
      'abc',
      reason: 'an empty one tells the installer not to check the download',
    );
    expect(result.said, isEmpty);
  });

  group('a version that will not read', () {
    test('does not take the rest of its channel with it', () {
      final result = read(
        feed([
          channelJson('release', [
            {'version': 1, 'changelog': 'bad'},
            versionJson('1.0.0'),
          ]),
        ]),
      );

      final release = result.directory.channelById('release')!;
      expect(release.versions.map((v) => v.version), ['1.0.0']);
    });

    test('is named by where it sat', () {
      final result = read(
        feed([
          channelJson('release', [
            {'version': 1, 'changelog': 'bad'},
            versionJson('1.0.0'),
          ]),
        ]),
      );

      expect(
        result.said,
        contains('channels[0](release).versions[0]: no version'),
      );
      expect(result.said, contains('1 unreadable entry'));
    });

    test('is one whose version string is blank', () {
      final result = read(
        feed([
          channelJson('release', [
            {'version': ''},
            versionJson('1.0.0'),
          ]),
        ]),
      );

      expect(result.directory.channelById('release')!.versions, hasLength(1));
      expect(
        result.said,
        contains('channels[0](release).versions[0]: no version'),
      );
    });

    test('is one that stopped being an object', () {
      final result = read(
        feed([
          channelJson('release', ['1.0.0', versionJson('1.0.1')]),
        ]),
      );

      expect(result.directory.channelById('release')!.versions, hasLength(1));
      expect(
        result.said,
        contains('channels[0](release).versions[0]: not an object'),
        reason: 'or nothing says the entries are now strings',
      );
    });
  });

  group('a channel that will not read', () {
    test('does not take the other channels with it', () {
      final result = read(
        feed([
          {'title': 'no id here'},
          channelJson('release', [versionJson('1.0.0')]),
        ]),
      );

      expect(result.directory.channels.map((c) => c.id), ['release']);
    });

    // An empty list is an answer: the feed is saying this channel has no
    // builds. Nothing was lost, so there is nothing to say.
    test('is not one that genuinely carries none', () {
      final result = read(
        feed([
          channelJson('release', []),
          channelJson('development', [versionJson('1.0.0')]),
        ]),
      );

      expect(result.directory.channels.map((c) => c.id), [
        'release',
        'development',
      ]);
      expect(result.directory.channelById('release')!.hasVersions, isFalse);
      expect(result.said, isEmpty, reason: 'nothing was lost');
    });

    // The unleashed feed ships `"versions": null` on release-candidate today,
    // so this is not a hypothetical shape.
    test('is not one whose versions the feed set to null', () {
      final result = read(
        feed([
          {
            'id': 'release-candidate',
            'title': 'Release Candidate',
            'description': '',
            'versions': null,
          },
          channelJson('development', [versionJson('1.0.0')]),
        ]),
      );

      expect(result.directory.channels.map((c) => c.id), [
        'release-candidate',
        'development',
      ]);
      expect(result.said, isEmpty, reason: 'nothing was lost');
    });

    // Absent is not null. A key the feed stopped sending is a key the feed
    // renamed, which used to reach the card as a channel with no builds.
    test('is one whose versions key is missing', () {
      final result = read(
        feed([
          {'id': 'development'},
          channelJson('release', [versionJson('1.0.0')]),
        ]),
      );

      expect(result.directory.channels.map((c) => c.id), ['release']);
      expect(result.said, contains('channels[0](development).versions'));
      expect(result.said, contains('missing'));
    });

    test('is one whose versions stopped being a list', () {
      final result = read(
        feed([
          {'id': 'development', 'versions': 'nope'},
          channelJson('release', [versionJson('1.0.0')]),
        ]),
      );

      expect(result.directory.channels.map((c) => c.id), ['release']);
      expect(
        result.said,
        contains('channels[0](development).versions: not a list'),
      );
    });

    test('is one whose id is blank', () {
      final result = read(
        feed([
          channelJson('', [versionJson('1.0.0')]),
          channelJson('release', [versionJson('1.0.0')]),
        ]),
      );

      expect(result.directory.channels.map((c) => c.id), ['release']);
      expect(result.said, contains('channels[0]: no id'));
    });

    test('is one whose versions all failed', () {
      final result = read(
        feed([
          channelJson('development', [
            {'version': 1},
          ]),
          channelJson('release', [versionJson('1.0.0')]),
        ]),
      );

      expect(result.directory.channels.map((c) => c.id), ['release']);
      expect(
        result.said,
        contains('channels[0](development): no version in it could be read'),
      );
    });
  });

  group('a file that will not read', () {
    // Not degradation: a version with no installable file makes the unleashed
    // display version null while the fetch still counts as a success, and the
    // card then reads NO UPDATE — the claim #118 removed for a failed fetch.
    test('takes its version with it when it was the only one', () {
      final result = read(
        feed([
          channelJson('release', [
            versionJson('1.0.0', files: [fileJson(target: 1)]),
            versionJson('0.9.0', files: [fileJson()]),
          ]),
        ]),
      );

      final release = result.directory.channelById('release')!;
      expect(release.versions.map((v) => v.version), ['0.9.0']);
      expect(
        result.said,
        contains('channels[0](release).versions[0](1.0.0): no file'),
      );
      expect(
        result.said,
        contains('bad target'),
        reason:
            'dropping the version must not discard why its files failed - '
            'that name is the only thing a maintainer can diff the feed with',
      );
    });

    test('leaves a version that still has another file', () {
      final result = read(
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

      final latest = result.directory.channelById('release')!.latest!;
      expect(latest.files.map((f) => f.target), ['f18']);
      expect(latest.updatePackageFor('f7'), isNull);
      expect(
        result.said,
        contains('channels[0](release).versions[0](1.0.0).files[1]: bad type'),
      );
    });

    // An empty list is the feed saying so, which the app already answers with
    // a localized "no package for this target" when someone presses install.
    test('is not a version the feed gave an empty files list', () {
      final result = read(
        feed([
          channelJson('release', [versionJson('1.0.0')]),
        ]),
      );

      expect(result.directory.channelById('release')!.latest!.files, isEmpty);
      expect(result.said, isEmpty, reason: 'nothing was lost');
    });

    test('is one whose files key is missing', () {
      final result = read(
        feed([
          channelJson('release', [
            {'version': '1.0.0', 'changelog': 'notes'},
            versionJson('0.9.0', files: [fileJson()]),
          ]),
        ]),
      );

      expect(
        result.directory.channelById('release')!.versions.map((v) => v.version),
        ['0.9.0'],
      );
      expect(
        result.said,
        contains('channels[0](release).versions[0](1.0.0).files'),
      );
      expect(result.said, contains('missing'));
    });

    test('is one that stopped being an object', () {
      final result = read(
        feed([
          channelJson('release', [
            versionJson('1.0.0', files: ['a file', fileJson()]),
          ]),
        ]),
      );

      expect(
        result.directory.channelById('release')!.latest!.files,
        hasLength(1),
      );
      expect(
        result.said,
        contains(
          'channels[0](release).versions[0](1.0.0).files[0]: not an object',
        ),
      );
    });

    // Each of the four has to be present and non-blank on its own: a file that
    // is whole but for one blank field is the shape a serializer change
    // produces, and it passes every type check.
    for (final blank in const ['url', 'target', 'type', 'sha256']) {
      test('is one whose $blank is an empty string', () {
        final result = read(
          feed([
            channelJson('release', [
              versionJson(
                '1.0.0',
                files: [
                  {...fileJson(), blank: ''},
                  fileJson(url: 'https://example.invalid/other.tgz'),
                ],
              ),
            ]),
          ]),
        );

        expect(
          result.directory.channelById('release')!.latest!.files,
          hasLength(1),
        );
        expect(result.said, contains('bad $blank'));
      });
    }

    // RemoteFirmwareSource trims before it decides, so a checksum of spaces
    // reads there as "this build publishes none" and the archive is flashed
    // without being checked. Two guards for one rule have to agree.
    test('is one whose checksum is only spaces', () {
      final result = read(
        feed([
          channelJson('release', [
            versionJson(
              '1.0.0',
              files: [
                fileJson(sha256: '   '),
                fileJson(url: 'https://example.invalid/other.tgz'),
              ],
            ),
          ]),
        ]),
      );

      expect(
        result.directory.channelById('release')!.latest!.files,
        hasLength(1),
      );
      expect(result.said, contains('bad sha256'));
    });

    test('names which of its fields were bad', () {
      final result = read(
        feed([
          channelJson('release', [
            versionJson(
              '1.0.0',
              files: [
                fileJson(url: '', sha256: null),
                fileJson(url: 'https://example.invalid/other.tgz'),
              ],
            ),
          ]),
        ]),
      );

      expect(
        result.said,
        contains(
          'channels[0](release).versions[0](1.0.0).files[0]: bad url, sha256',
        ),
      );
    });
  });

  group('a field that is only presentation', () {
    test('falls back rather than costing the channel', () {
      final result = read(
        feed([
          {
            'id': 'release',
            'versions': [versionJson('1.0.0')],
          },
        ]),
      );

      final release = result.directory.channelById('release')!;
      expect(release.title, 'release', reason: 'the id stands in');
      expect(release.description, isEmpty);
      expect(
        result.said,
        isNot(contains('unreadable')),
        reason: 'nothing was dropped - the channel is entirely usable',
      );
    });

    // A renamed field arrives as an absent one, and both live feeds send all
    // three on every entry today. `changelog` decides whether the card offers
    // a What's New button at all, so losing it in silence leaves nothing to
    // find.
    test('is named when the feed stopped sending it', () {
      final result = read(
        feed([
          {
            'id': 'release',
            'versions': [
              {'version': '1.0.0', 'files': <dynamic>[]},
            ],
          },
        ]),
      );

      expect(result.said, contains('3 fields fell back'));
      expect(result.said, contains('channels[0](release).title'));
      expect(result.said, contains('channels[0](release).description'));
      expect(
        result.said,
        contains('channels[0](release).versions[0](1.0.0).changelog'),
      );
    });

    test('is named, and still falls back, when its type changed', () {
      final result = read(
        feed([
          {
            'id': 'release',
            'title': 7,
            'description': <String>[],
            'versions': [
              {'version': '1.0.0', 'changelog': 42, 'files': <dynamic>[]},
            ],
          },
        ]),
      );

      final release = result.directory.channelById('release')!;
      expect(release.title, 'release', reason: 'not the number 7');
      expect(release.description, isEmpty, reason: 'not "[]"');
      expect(release.latest!.changelog, isEmpty);
      expect(result.said, contains('not a string'));
      expect(result.said, contains('channels[0](release).title'));
    });

    test('stands in for a title the feed blanked, not just a missing one', () {
      final result = read(
        feed([
          {
            'id': 'release',
            'title': '',
            'description': '',
            'versions': [versionJson('1.0.0')],
          },
        ]),
      );

      expect(result.directory.channelById('release')!.title, 'release');
      expect(
        result.said,
        isEmpty,
        reason: 'a blank description is the same value either way',
      );
    });

    test('costs nothing on a version either', () {
      final result = read(
        feed([
          channelJson('release', [
            {
              'version': '1.0.0',
              'changelog': 'notes',
              'timestamp': 'yesterday',
              'files': <dynamic>[],
            },
          ]),
        ]),
      );

      expect(result.directory.channelById('release')!.latest!.timestamp, 0);
    });
  });

  group('a document that yields nothing', () {
    // An empty directory reaches the card as a success: the channel list falls
    // through to the custom one, the button offers "pick a file to install",
    // and the empty result is cached and stamped fresh, so nothing is fetched
    // again for ten minutes at a time. It has to arrive as a failure instead.
    test('carries what it dropped, uncapped, and says a grouped summary', () {
      try {
        read(
          feed([
            for (var i = 0; i < 25; i++) {'title': 'no id $i'},
          ]),
        );
        fail('expected FirmwareDirectoryUnreadable');
      } on FirmwareDirectoryUnreadable catch (e) {
        expect(e.skipped, hasLength(25), reason: 'the detail is all there');
        expect(e.skipped.first, 'channels[0]: no id');
        // toString is what FirmwareRepository logs and keeps as the reason it
        // compares every later failure against, so it is the grouped form -
        // and this is the only path on which it runs.
        expect(e.toString(), contains('25 skipped'));
        expect(e.toString(), contains('no id x25'));
        expect(e.toString(), contains('first: channels[0]'));
        expect(e.toString(), isNot(contains('channels[24]')));
      }
    });

    // A feed that genuinely has no channels is a different answer from one
    // this cannot read, and only the second is a failure.
    test('is not a feed that simply has none', () {
      expect(read(feed([])).directory.channels, isEmpty);
      expect(
        read(<String, dynamic>{'channels': null}).directory.channels,
        isEmpty,
      );
      expect(LogService.history, isEmpty);
    });

    // #133 one level up: the whole field renamed. This used to reach the card
    // as an empty directory, which is the one outcome it must never produce.
    test('is one whose channels key is missing', () {
      expect(
        () => read(<String, dynamic>{'channelList': <dynamic>[]}),
        throwsA(
          isA<FirmwareDirectoryUnreadable>().having(
            (e) => e.skipped,
            'skipped',
            ['channels: missing'],
          ),
        ),
      );
      expect(
        () => read(<String, dynamic>{}),
        throwsA(isA<FirmwareDirectoryUnreadable>()),
      );
    });

    test('is one whose channels stopped being a list', () {
      expect(
        () => read(<String, dynamic>{'channels': 'nope'}),
        throwsA(
          isA<FirmwareDirectoryUnreadable>().having(
            (e) => e.skipped,
            'skipped',
            ['channels: not a list'],
          ),
        ),
      );
    });

    test('is one whose channels stopped being objects', () {
      expect(
        () => read(feed(['release', 'development'])),
        throwsA(
          isA<FirmwareDirectoryUnreadable>().having(
            (e) => e.skipped,
            'skipped',
            ['channels[0]: not an object', 'channels[1]: not an object'],
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
          () => read(body),
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

    // The sharp one. A channel kept empty by `"versions": null` is the live
    // feed's own shape, and it still counts in the channel list — so asking
    // whether that list is empty lets it stand in for every channel that was
    // lost beside it, and the card reads "pick a file to install" instead of
    // CAN'T CHECK.
    test('is one where the only channel left carries nothing', () {
      expect(
        () => read(
          feed([
            {'id': 'release-candidate', 'versions': null},
            channelJson('release', [
              {'version': 1},
            ]),
          ]),
        ),
        throwsA(isA<FirmwareDirectoryUnreadable>()),
      );
    });
  });

  group('what the summary says', () {
    // One renamed field is renamed in every entry that carries it. Ungrouped,
    // those identical records filled the whole message and pushed out the one
    // structural record that said which channel had gone.
    test('groups one problem in many places into one count', () {
      final result = read(
        feed([
          channelJson('release', [
            versionJson(
              '1.0.0',
              files: [for (var i = 0; i < 25; i++) fileJson(sha256: null)],
            ),
            versionJson('0.9.0', files: [fileJson()]),
          ]),
          {'id': 'development', 'versions': 'nope'},
        ]),
      );

      expect(result.said, contains('bad sha256 x25'));
      expect(
        result.said,
        contains('channels[1](development).versions: not a list'),
        reason: 'the structural record must survive the repetitive ones',
      );
    });

    test('names a handful of places in full', () {
      final result = read(
        feed([
          {'id': 'development', 'title': 'Dev', 'description': ''},
          {'id': 'release-candidate', 'title': 'RC', 'description': ''},
          channelJson('release', [versionJson('1.0.0')]),
        ]),
      );

      expect(
        result.said,
        contains(
          'missing: channels[0](development).versions, '
          'channels[1](release-candidate).versions',
        ),
        reason: 'two places are worth naming; eighty-four would not be',
      );
    });

    // channelById answers with the first of two, so without the index in the
    // name there is no way to tell which of them broke.
    test('tells two channels with the same id apart', () {
      final result = read(
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

      expect(result.said, contains('channels[0](release).versions[0]'));
      expect(result.said, contains('channels[1](release).versions[0]'));
    });

    // A title that fell back costs nothing a user can see. Counting it as an
    // unreadable entry sends a maintainer looking for a missing channel.
    test('counts fields that fell back apart from entries that were lost', () {
      final result = read(
        feed([
          {
            'id': 'release',
            'versions': [
              {'version': 1, 'files': <dynamic>[]},
              versionJson('1.0.0'),
            ],
          },
        ]),
      );

      expect(result.said, contains('skipped 1 unreadable entry'));
      expect(
        result.said,
        contains('2 fields fell back'),
        reason:
            'the channel title and description - the dropped version '
            'never got as far as its changelog',
      );
    });
  });

  // Everything above reads through the reader, which only knows what there is
  // to say. Whether it is said, at what level, and whether it has been said
  // already belong to FirmwareParser — and nothing else would notice if that
  // wiring went away.
  group('through a real fetch', () {
    Map<String, dynamic> oneBadVersion() => feed([
      channelJson('release', [
        {'version': 1},
        versionJson('1.0.0'),
      ]),
    ]);

    Future<void> fetchUnleashed() async {
      parserForEntry(unleashed).clearCache();
      await FirmwareRepository.instance.ensure(unleashed);
    }

    test('a partial read reaches the log at error, naming its feed', () async {
      feedEvery((_) async => oneBadVersion());

      await FirmwareRepository.instance.ensure(unleashed);

      expect(
        FirmwareRepository.instance.failedFor(unleashed),
        isFalse,
        reason: 'the good version still arrived',
      );
      final kept = keptAbout('skipped');
      expect(kept, hasLength(1));
      expect(kept.single, contains('[error]'));
      expect(
        kept.single,
        contains('[Firmware] ${parserForEntry(unleashed).directoryUrl}'),
        reason: 'or two firmwares are indistinguishable in the log',
      );
    });

    test('says the same thing once', () async {
      feedEvery((_) async => oneBadVersion());

      await fetchUnleashed();
      await fetchUnleashed();

      expect(keptAbout('unleashedflip'), hasLength(1));
    });

    test('says it again once the feed breaks differently', () async {
      feedEvery((_) async => oneBadVersion());
      await fetchUnleashed();

      feedEvery(
        (_) async => feed([
          {'title': 'no id here'},
          channelJson('release', [versionJson('1.0.0')]),
        ]),
      );
      await fetchUnleashed();

      expect(keptAbout('unleashedflip'), hasLength(2));
    });

    // The memory has to forget on a healthy read, or a fault that returns
    // after a recovery is silent. FirmwareRepository._recordFailure clears
    // _failed on a success for exactly this reason.
    test('says it again after a recovery and one more break', () async {
      feedEvery((_) async => oneBadVersion());
      await fetchUnleashed();

      feedWorks();
      await fetchUnleashed();

      feedEvery((_) async => oneBadVersion());
      await fetchUnleashed();

      // One line, not two: the healthy read says nothing, so the two reports
      // are consecutive and `LogService._remember` collapses identical
      // consecutive bodies into a multiplier. The multiplier is the evidence.
      expect(keptAbout('unleashedflip').single, contains('(2'));
    });

    // The cache is assigned on every fetch, not filled in once. A refresh that
    // fetched a new directory and kept the old one would leave the card
    // showing the first directory of the session for as long as the app is
    // open.
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
  });
}
