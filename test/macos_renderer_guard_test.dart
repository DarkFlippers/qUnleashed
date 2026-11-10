// A guard on the macOS renderer policy, which no build this project runs on a
// pull request can check.
//
// Flutter 3.47 made Impeller the default macOS renderer. On Intel Macs it
// tears transitions and draws stray atlas glyphs in place of letters
// (flutter/flutter#191538, seen on Ventura 13.7.8). So
// `macos/Runner/MainFlutterWindow.swift` hands the engine its own
// `FlutterDartProject` subclass, which overrides `enableImpeller` to put Intel
// Macs back on Skia and leave Apple silicon on Impeller.
//
// Three things make that workaround fragile in a way nothing else in the tree
// notices:
//
//  * `enableImpeller` is declared only in the engine's private
//    FlutterDartProject_Internal.h. Swift cannot see it, so there is no
//    `override` keyword and no compiler check that the override still lands.
//  * The whole payload is one argument at one call site. Revert
//    `FlutterViewController(project:)` to `FlutterViewController()` - a merge
//    conflict resolved the wrong way, or `flutter create .` rewriting the
//    template - and `flutter analyze`, `flutter test` and the release build all
//    stay green while every Intel Mac goes back to tearing.
//  * `macos/RunnerTests/RunnerTests.swift` asserts the policy, and nothing runs
//    it. No workflow invokes `xcodebuild test`, and `flutter build macos`
//    builds the Runner target, not the test target. Those six cases are a check
//    for whoever next opens Xcode, which is this repository's own phrase for
//    how a guard becomes decoration.
//
// Hence this file, in the shape `ffi_export_test.dart` already uses for the
// Apple project: the cheap half runs on Linux on every pull request and pins
// the *inputs*, while the thing that can only be seen on the hardware stays a
// manual check. It reads Swift and a plist as text from Dart, which is the only
// way a PR job sees either.
//
// The load-bearing assertion is the SDK pin. The upstream fix landed on
// Flutter's `main` after 3.47, so the expected end of this workaround is a
// Flutter upgrade - and "Revisit on the next Flutter upgrade", which is what
// the Swift comment says today, is a prose rule with no mechanism. Pinning the
// version turns it into a test that fails in review, in front of the person
// doing the upgrade, naming what to re-check.
//
// What it cannot see:
//
//  * Whether the override still reaches the engine. An engine that keeps the
//    selector and stops consulting it passes every assertion here and in
//    RunnerTests. Only the SDK pin forces someone to look.
//  * Whether Intel rendering is actually fixed. That needs an Intel Mac, which
//    this project does not have in CI and GitHub no longer offers.
//  * A second engine built by a plugin, or a second window. The wiring
//    assertion covers the one construction site that exists.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The file the renderer policy lives in.
const _window = 'macos/Runner/MainFlutterWindow.swift';

/// The SDK pin every job in the repository builds on.
const _action = '.github/actions/setup-flutter/action.yml';

/// The Flutter version whose Intel regression this workaround exists for.
///
/// Bumping the pin without re-reading `MainFlutterWindow.swift` is the thing
/// this guard exists to stop, so the version is spelled out here rather than
/// derived from anything.
const _pinnedFlutter = '3.47.1';

/// Files that could carry `FLTEnableImpeller` into the built app.
///
/// The engine reads that key from the main bundle's Info.plist, and the policy
/// honours it deliberately so a build can still force either renderer. The
/// consequence is that a value committed to any of these decides for *every*
/// Mac and the per-machine choice stops happening.
const _plistCarriers = <String>[
  'macos/Runner/Info.plist',
  'macos/Flutter/Flutter-Debug.xcconfig',
  'macos/Flutter/Flutter-Release.xcconfig',
];

String _read(String path) {
  final file = File(path);
  expect(
    file.existsSync(),
    isTrue,
    reason: '$path is missing, so this guard checked nothing',
  );
  return file.readAsStringSync();
}

/// [source] with whole-line `//` and `///` comments dropped.
///
/// The bypass assertion below looks for a bare `FlutterViewController()`, and
/// this file's own doc comments are the most likely place for that spelling to
/// appear in prose - the removal instructions name it. `arb_locale_guard_test`
/// was caught by the same thing from the other side: an assertion satisfied by
/// the comment above the step it meant to pin. Only whole lines are stripped,
/// which is enough here and keeps this readable.
String _codeOnly(String source) => source
    .split('\n')
    .where((line) => !line.trimLeft().startsWith('//'))
    .join('\n');

void main() {
  test('the Flutter pin has not moved under the renderer workaround', () {
    final action = _read(_action);
    final match = RegExp(
      r'^\s*default:\s*"([0-9][0-9A-Za-z.+-]*)"',
      multiLine: true,
    ).firstMatch(action);

    // A regex that stopped matching would otherwise pass this in silence.
    expect(
      match,
      isNotNull,
      reason:
          'no `default: "<version>"` found in $_action, so the pin was '
          'never read - fix this guard before trusting it',
    );

    expect(
      match!.group(1),
      _pinnedFlutter,
      reason:
          '''
The Flutter SDK pin in $_action has moved off $_pinnedFlutter, and
$_window still forces Skia on Intel Macs for a bug in that version.

flutter/flutter#191538 was fixed on Flutter's main after 3.47. Before taking
this bump:

  * Build on an Intel Mac with Impeller and look for torn transitions and
    stray glyphs in text. If they are gone, delete RendererPolicy and
    RendererDartProject, give MainFlutterWindow a plain FlutterViewController()
    again, and delete this guard with them.
  * If they are not gone, re-pin _pinnedFlutter in this file to the new
    version and say in the commit that Intel was re-checked.

Nothing else in CI notices if the workaround outlives the bug: no job compiles
macos/ on a pull request, and no job runs RunnerTests at all.''',
    );
  });

  test('the engine is still handed the renderer policy', () {
    final window = _read(_window);

    // The one argument the whole workaround consists of.
    expect(
      window,
      contains('FlutterViewController(project: RendererDartProject())'),
      reason:
          '$_window no longer passes a RendererDartProject to the engine, '
          'so the renderer policy is computed and discarded and Intel Macs '
          'are back on Impeller. See flutter/flutter#191538.',
    );

    // And nothing bypasses it. A bare `FlutterViewController()` gets the
    // engine's own default, which is Impeller on every Mac.
    expect(
      _codeOnly(window),
      isNot(contains('FlutterViewController()')),
      reason:
          '$_window constructs a FlutterViewController without the '
          'renderer policy, which gets Impeller on Intel Macs regardless of '
          'the policy below it.',
    );
  });

  test('the overridden selector is spelled out for Objective-C', () {
    final window = _read(_window);

    // Swift derives an @objc selector from the property name, and the engine
    // dispatches on the name in its private header. Renaming the Swift
    // property for style would silently stop overriding anything, with no
    // compile error, because Swift cannot see the declaration it overrides.
    expect(
      window,
      contains('@objc(enableImpeller) var enableImpeller'),
      reason:
          'the override in $_window no longer pins its Objective-C '
          'selector with @objc(enableImpeller), so a rename of the Swift '
          'property would detach it from the engine in silence.',
    );
  });

  test('no build commits a renderer choice for every Mac', () {
    var checked = 0;
    for (final path in _plistCarriers) {
      final file = File(path);
      if (!file.existsSync()) continue;
      checked++;
      expect(
        file.readAsStringSync(),
        isNot(contains('FLTEnableImpeller')),
        reason:
            '$path sets FLTEnableImpeller, which decides the renderer on '
            'every Mac and turns off the per-machine choice in $_window. '
            'Remove it, or delete the policy deliberately.',
      );
    }

    // Every path renamed at once would otherwise pass this in silence.
    expect(
      checked,
      greaterThan(0),
      reason: 'none of $_plistCarriers exist, so this guard checked nothing',
    );
  });
}
