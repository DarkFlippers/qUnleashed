// Covers the identity a build reports about itself: ADR 0014 §3.
//
// Worth a test of its own because the whole point of the line is that somebody
// pastes it into an issue and a developer reads it back. A format that drops the
// commit, or writes `unknown` where there is simply no tag, costs exactly the
// thing it exists for - and nothing else in the app would fail if it did.
//
// Every case builds its own BuildStamp rather than reading BuildIdentity's
// compiled-in constants, whose three commits are empty under `flutter test` and
// whose channel falls back to `local`, and which cannot be set from here. That
// is why the formatting takes parameters.
//
// The producer side - that `derive_version.sh` emits the define this file's
// subject reads - is covered by `test/dart_define_keys_test.dart`, because a
// renamed key would leave both this suite and the shell suite green while every
// CI build reported `local`.
import 'package:flutter_test/flutter_test.dart';
import 'package:qunleashed/services/build_identity.dart';
import 'package:qunleashed/services/logging.dart';

BuildStamp stamp({
  String version = '0.14.1',
  String build = '14001',
  BuildChannel channel = BuildChannel.dev,
  String commit = 'abc1234def5678',
  String flipperlibCommit = '',
  String dartufbtCommit = '',
}) => BuildStamp(
  version: version,
  build: build,
  channel: channel,
  commit: commit,
  flipperlibCommit: flipperlibCommit,
  dartufbtCommit: dartufbtCommit,
);

void main() {
  // Abbreviation is private now, so it is checked through the getter that uses
  // it rather than directly.
  group('shortCommit', () {
    test('abbreviates to the seven characters git would', () {
      expect(stamp(commit: 'abc1234def5678').shortCommit, 'abc1234');
    });

    // Empty in, empty out: a caller then tests the result instead of testing
    // the input and shortening it afterwards, which is one place for the two to
    // disagree.
    test('leaves a missing commit missing', () {
      expect(stamp(commit: '').shortCommit, isEmpty);
    });

    test('does not pad a commit already shorter than seven', () {
      expect(stamp(commit: 'abc12').shortCommit, 'abc12');
    });
  });

  // The suffix 0014 §2 keeps everywhere a person reads the version, and drops
  // from the two fields a store validates: a build carrying `-dev` in
  // CFBundleShortVersionString fails App Store validation.
  group('displayVersion', () {
    test('a dev build says so', () {
      expect(stamp(channel: BuildChannel.dev).displayVersion, '0.14.1-dev');
    });

    // A bare version already means released, and `-release` is noise on the
    // one build most people are running.
    test('a release says nothing', () {
      expect(stamp(channel: BuildChannel.release).displayVersion, '0.14.1');
    });

    test('a local build says so too', () {
      expect(stamp(channel: BuildChannel.local).displayVersion, '0.14.1-local');
    });

    // `build: ''` as well, because the two come from one platform call and
    // the constructor asserts they go missing together.
    test('keeps the channel when the version is unknown', () {
      expect(
        stamp(version: '', build: '', channel: BuildChannel.dev).displayVersion,
        'unknown-dev',
        reason: 'only the version failed; the channel is compiled in',
      );
    });
  });

  group('line', () {
    test('runs widest to narrowest', () {
      expect(stamp().line, '0.14.1-dev · 14001 · abc1234');
    });

    // The channel is in the version, not a field of its own: `0.14.1-dev · dev`
    // says it twice.
    test('does not name the channel twice', () {
      expect(stamp().line, isNot(contains('· dev ·')));
    });

    // A local `flutter run` has no commit and often no build number. Dropping
    // them reads as a local build; writing `unknown` twice reads as broken.
    test('drops what it does not have', () {
      expect(
        stamp(channel: BuildChannel.local, commit: '', build: '').line,
        '0.14.1-local',
      );
    });
  });

  group('header', () {
    // One line when neither submodule said anything, which is the desktop jobs:
    // a build that does not touch flipperlib or dartufbt still has to copy a
    // log that identifies itself.
    test('is one line when no submodule commit is known', () {
      expect(stamp().header, 'qUnleashed 0.14.1-dev · 14001 · abc1234');
    });

    test('puts the submodules on a second line', () {
      expect(
        stamp(
          flipperlibCommit: 'd2d8f7cc5691306',
          dartufbtCommit: 'c66737ce0cf9',
        ).header,
        'qUnleashed 0.14.1-dev · 14001 · abc1234\n'
        'flipperlib d2d8f7c · dartufbt c66737c',
      );
    });

    test('names only the submodule it knows about', () {
      expect(
        stamp(flipperlibCommit: 'd2d8f7cc5691306').header,
        'qUnleashed 0.14.1-dev · 14001 · abc1234\nflipperlib d2d8f7c',
      );
    });
  });

  // Classification, which is where the failure direction lives. A bare String
  // channel matched neither `dev` nor `local` for anything unexpected, so a
  // typo rendered the bare version and a Sentry release with no suffix - a
  // developer's tree impersonating a shipped build. The shell guard cannot help
  // here; it only runs in CI.
  group('BuildChannel.parse', () {
    test('reads the three it knows', () {
      expect(BuildChannel.parse('dev'), BuildChannel.dev);
      expect(BuildChannel.parse('release'), BuildChannel.release);
      expect(BuildChannel.parse('local'), BuildChannel.local);
    });

    test('anything else is local, not release', () {
      for (final raw in ['prod', 'Dev', 'DEV', 'dev ', '']) {
        expect(
          BuildChannel.parse(raw),
          BuildChannel.local,
          reason: '"$raw" must not be read as a release',
        );
      }
    });

    // An unexpected value is worth a line: a CI build demoting itself to
    // `local` is baffling otherwise. An empty one is not - that is the ordinary
    // absence of a define, which is every `flutter run`.
    test(
      'says so for a value it did not expect, and not for an absent one',
      () {
        LogService.clearHistory();
        BuildChannel.parse('prod');
        expect(
          LogService.history.single,
          contains('[caught] [Build] unknown channel'),
        );

        LogService.clearHistory();
        BuildChannel.parse('');
        expect(LogService.history, isEmpty);
        LogService.clearHistory();
      },
    );
  });

  // Under `flutter test` no define is passed, so this reads the one value CI
  // never sends. Worth asserting because it is what a developer's own run
  // reports, and a wrong default would have every local build claiming to be a
  // release.
  test('an untold build is local', () {
    expect(BuildChannel.parse(BuildIdentity.channelName), BuildChannel.local);
  });
}
