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

  group('line', () {
    test('runs widest to narrowest', () {
      expect(stamp().line, '0.14.1+14001 · dev · abc1234');
    });

    // A local `flutter run` has no commit. Dropping it reads as a local build;
    // writing `unknown` beside `local` says the same thing twice and reads as
    // broken.
    test('drops a commit it does not have', () {
      expect(stamp(channel: 'local', commit: '').line, '0.14.1+14001 · local');
    });
  });

  group('header', () {
    // One line when neither submodule said anything, which is the desktop jobs:
    // a build that does not touch flipperlib or dartufbt still has to copy a
    // log that identifies itself.
    test('is one line when no submodule commit is known', () {
      expect(stamp().header, 'qUnleashed 0.14.1+14001 · dev · abc1234');
    });

    test('puts the submodules on a second line', () {
      expect(
        stamp(
          flipperlibCommit: 'd2d8f7cc5691306',
          dartufbtCommit: 'c66737ce0cf9',
        ).header,
        'qUnleashed 0.14.1+14001 · dev · abc1234\n'
        'flipperlib d2d8f7c · dartufbt c66737c',
      );
    });

    test('names only the submodule it knows about', () {
      expect(
        stamp(flipperlibCommit: 'd2d8f7cc5691306').header,
        'qUnleashed 0.14.1+14001 · dev · abc1234\nflipperlib d2d8f7c',
      );
    });
  });

  // Three channels and no more: every build comes off main, `dev` is the
  // automatic one, `release` is cut by hand in GitHub, `local` is a tree
  // nobody else has. ADR 0014 §1.
  group('channelFromTag', () {
    test('a dev tag is the automatic channel', () {
      expect(BuildIdentity.channelFromTag('dev-0.14.1'), 'dev');
    });

    // The prefixes this repository has actually tagged - alpha- (22), beta-
    // (22), wip- (5) - were every one of them cut by hand, so every one of them
    // is a release. Reading the prefix back out would report the tagging
    // convention of the day rather than how the build was made, and the
    // convention has already changed three times.
    test('every hand-cut tag is a release, whatever it was called', () {
      expect(BuildIdentity.channelFromTag('beta-0.11.2'), 'release');
      expect(BuildIdentity.channelFromTag('alpha-0.8.4'), 'release');
      expect(BuildIdentity.channelFromTag('wip-0.3.6'), 'release');
      expect(BuildIdentity.channelFromTag('0.12.1'), 'release');
      expect(BuildIdentity.channelFromTag('v0.6.1'), 'release');
    });

    // `dev` is a prefix and not a substring: a hand-cut `0.14.1-dev-notes`
    // would otherwise claim to be an automatic build.
    test('dev has to be the prefix', () {
      expect(BuildIdentity.channelFromTag('predev-0.1.0'), 'release');
    });

    // Not null, because "which build is this" has an answer for a developer's
    // own run, and it is the answer most worth saying: a report from `local`
    // cannot be reproduced from anything in the repository.
    test('no tag is a local build', () {
      expect(BuildIdentity.channelFromTag(''), 'local');
    });
  });
}
