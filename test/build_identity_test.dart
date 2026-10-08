// Covers the identity a build reports about itself: ADR 0014 §3.
//
// Worth a test of its own because the whole point of the line is that somebody
// pastes it into an issue and a developer reads it back. A format that drops the
// commit, or writes `unknown` where there is simply no tag, costs exactly the
// thing it exists for - and nothing else in the app would fail if it did.
//
// Every case builds its own BuildStamp rather than reading BuildIdentity's
// compiled-in constants, which are empty under `flutter test` and cannot be set
// from here. That is why the formatting takes parameters.
import 'package:flutter_test/flutter_test.dart';
import 'package:qunleashed/services/build_identity.dart';

BuildStamp stamp({
  String version = '0.14.1',
  String build = '14001',
  String channel = 'dev',
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
  group('short', () {
    test('abbreviates to the seven characters git would', () {
      expect(BuildStamp.short('abc1234def5678'), 'abc1234');
    });

    // Empty in, empty out: a caller then tests the result instead of testing
    // the input and shortening it afterwards, which is one place for the two to
    // disagree.
    test('leaves a missing commit missing', () {
      expect(BuildStamp.short(''), isEmpty);
    });

    test('does not pad a commit already shorter than seven', () {
      expect(BuildStamp.short('abc12'), 'abc12');
    });
  });

  group('versionWithBuild', () {
    test('joins the version and the build number', () {
      expect(stamp().versionWithBuild, '0.14.1+14001');
    });

    // The platform channel answered with a version and no number. Still worth
    // showing: the version is most of what a reader wants.
    test('is the version alone when there is no build number', () {
      expect(stamp(build: '').versionWithBuild, '0.14.1');
    });

    // PackageInfo threw. Says so rather than rendering `+14001` against
    // nothing, or an empty line that reads as a layout bug.
    test('says unknown when the platform would not answer', () {
      expect(stamp(version: '', build: '').versionWithBuild, 'unknown');
    });
  });

  // The suffix 0014 §2 keeps everywhere a person reads the version, and drops
  // from the two fields a store validates. A build carrying `-dev` in
  // CFBundleShortVersionString fails App Store validation, which is why this
  // is a separate getter from versionWithBuild rather than the only form.
  group('displayVersion', () {
    test('a dev build says so', () {
      expect(stamp(channel: 'dev').displayVersion, '0.14.1-dev');
    });

    // A bare version already means released, and `-release` is noise on the
    // one build most people are running.
    test('a release says nothing', () {
      expect(stamp(channel: 'release').displayVersion, '0.14.1');
    });

    test('a local build says so too', () {
      expect(stamp(channel: 'local').displayVersion, '0.14.1-local');
    });

    test('says unknown when the platform would not answer', () {
      expect(stamp(version: '', channel: 'dev').displayVersion, 'unknown');
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
        stamp(channel: 'local', commit: '', build: '').line,
        '0.14.1-local',
      );
    });
  });

  // 0014 §5. Set explicitly because the SDK's default begins with the bundle
  // ID, which differs per platform and would split one build into five
  // releases.
  group('sentryRelease', () {
    test('carries the suffix and the build number', () {
      expect(stamp().sentryRelease, 'qunleashed@0.14.1-dev+14001');
    });

    test('a release build has no suffix', () {
      expect(
        stamp(channel: 'release').sentryRelease,
        'qunleashed@0.14.1+14001',
      );
    });

    test('drops a build number it does not have', () {
      expect(stamp(build: '').sentryRelease, 'qunleashed@0.14.1-dev');
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

  // The channel is compiled in from the trigger, so under `flutter test` -
  // which passes no define - it is the one value CI never sends. That is the
  // whole assertion available here, and it is worth making: the default is
  // what a developer's own run reports, and a wrong default would have every
  // local build claiming to be a release.
  //
  // The two CI values are covered where they are decided, in
  // .github/scripts/derive_version_test.sh, because a --dart-define cannot be
  // set from inside a test.
  test('an untold build is local', () {
    expect(BuildIdentity.channel, BuildIdentity.localChannel);
  });
}
