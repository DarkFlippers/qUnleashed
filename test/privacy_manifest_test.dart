import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'native_sources.dart';
import 'source_files.dart';

/// The iOS privacy manifest, and the three things that keep it true.
///
/// App Store Connect rejects an upload whose privacy manifest does not describe
/// the required reason APIs the app uses - a hard gate since 1 May 2024, not a
/// warning. Nothing in this project can see that gate: no job on a pull request
/// builds iOS, the release job builds an unsigned app, and the first machine
/// that checks is Apple's, after a human has pressed upload. So the manifest is
/// guarded here, where it costs a second.
///
/// **iOS only, deliberately.** Apple's own sentence names the platforms:
/// "Describe the reasons your app or third-party SDK on iOS, iPadOS, tvOS,
/// visionOS, or watchOS uses these APIs" - macOS is absent, and this project
/// ships macOS as a DMG outside the Mac App Store anyway. That premise is what
/// clears two of the four pinned exemptions below.
///
/// 1. **Both manifests, as a token sequence** - every key, string, boolean and
///    array in document order. Not a `contains` per item: a misspelled *key*
///    leaves the values untouched, and renaming `NSPrivacyAccessedAPITypes`
///    alone would hide the whole API half of the file.
/// 2. **That the file is in the Runner target's `Resources` build phase** -
///    scoped to that phase, because the `RunnerTests` phase exists and is
///    empty, and the manifest in it would ship inside `RunnerTests.xctest`
///    with none in the `.app`.
/// 3. **That every use of a required reason API is declared by the manifest of
///    the binary it lands in** - Apple's rule as written, "for each executable
///    or dynamic library in an app that uses a required reason API, the bundle
///    that includes the executable or dynamic library needs to include a
///    privacy manifest file that reports the API". Both Podfiles say
///    `use_frameworks!`, so each pod is its own dynamic framework and answers
///    for itself. Checked twice: over the Apple sources in this checkout, and
///    over every iOS plugin Flutter resolved.
///
/// The last of those is the half that moves. This repository's own Apple code
/// uses exactly one such API and now ships a manifest beside it; the plugin set
/// changes on every dependency bump, which is how the app came to need
/// `CA92.1` at all. Pinning the plugin findings is therefore the part of this
/// file with a future, and it is what justifies the app's conservative entries
/// with something other than prose.
void main() {
  const appManifest = 'ios/Runner/PrivacyInfo.xcprivacy';
  const pbxproj = 'ios/Runner.xcodeproj/project.pbxproj';
  const pluginsFile = '.flutter-plugins-dependencies';

  // Derived from `native_sources.dart`'s path rather than spelled again:
  // "a path added here rather than spelled locally is one fewer place a move
  // has to find", and this file would otherwise be the fourth speller.
  const hardnestedApple = '$hardnestedDir/apple';
  const podResource = 'PrivacyInfo.xcprivacy';
  const hardnestedManifest = '$hardnestedApple/$podResource';
  const hardnestedPodspec = '$hardnestedApple/qunleashed_hardnested.podspec';

  /// Every meaningful element of a plist, in document order.
  ///
  /// Keys, strings, booleans and the shape of the arrays and dicts around
  /// them - which together are the whole of a `.xcprivacy`. Comments are
  /// stripped first, so wrapping a declaration in `<!-- -->` reads as the
  /// deletion it is rather than leaving the token list unchanged.
  ///
  /// Enough of a reader for these files and no more. A plist parser would mean
  /// a new direct dependency: `xml` is in `pubspec.lock` transitively and in
  /// no `pubspec.yaml`, so adding it is a lockfile change under
  /// `--enforce-lockfile`, in a test about a `.plist`.
  List<String> tokensOf(String path) {
    final text = File(path)
        .readAsStringSync()
        .replaceAll(RegExp(r'<!--.*?-->', dotAll: true), '');
    return RegExp(
      r'<(key|string)>(.*?)</\1>|<(dict|array)>|</(dict|array)>|'
      r'<(true|false|array|dict)/>',
    ).allMatches(text).map((m) {
      if (m.group(1) != null) return '${m.group(1)}:${m.group(2)}';
      if (m.group(3) != null) return '${m.group(3)}[';
      if (m.group(4) != null) return '${m.group(4)}]';
      return '${m.group(5)}/';
    }).toList();
  }

  /// Whether [manifest] declares [category] **with at least one reason**.
  ///
  /// The reasons are read from that category's own dict rather than from
  /// anywhere in the file, because a category whose reasons array is empty is
  /// the shipped shape of `device_info_plus`' manifest and satisfies nothing -
  /// and because a file where one category has reasons would otherwise answer
  /// for a second that has none.
  bool declaresCategory(String manifest, String category) {
    if (!File(manifest).existsSync()) return false;
    final tokens = tokensOf(manifest);
    final at = tokens.indexOf('string:NSPrivacyAccessedAPICategory$category');
    if (at == -1) return false;
    final rest = tokens.skip(at + 1).take(3).toList();
    return rest.length == 3 &&
        rest[0] == 'key:NSPrivacyAccessedAPITypeReasons' &&
        rest[1] == 'array[' &&
        rest[2].startsWith('string:');
  }

  /// The no-tracking preamble both manifests open with.
  const noTracking = [
    'key:NSPrivacyTracking',
    'false/',
    'key:NSPrivacyTrackingDomains',
    'array/',
  ];

  /// One collected-data entry: unlinked, never for tracking, one purpose.
  ///
  /// The booleans are the half a value-only assertion misses - a `<true/>` on
  /// `Tracking` would have the file say the app does not track and collects
  /// for tracking at once.
  List<String> collected(String type) => [
    'dict[',
    'key:NSPrivacyCollectedDataType',
    'string:$type',
    'key:NSPrivacyCollectedDataTypeLinked',
    'false/',
    'key:NSPrivacyCollectedDataTypeTracking',
    'false/',
    'key:NSPrivacyCollectedDataTypePurposes',
    'array[',
    'string:NSPrivacyCollectedDataTypePurposeAppFunctionality',
    'array]',
    'dict]',
  ];

  /// One required reason API entry: a category and the reasons for it.
  List<String> accessed(String category, List<String> reasons) => [
    'dict[',
    'key:NSPrivacyAccessedAPIType',
    'string:NSPrivacyAccessedAPICategory$category',
    'key:NSPrivacyAccessedAPITypeReasons',
    'array[',
    ...reasons.map((r) => 'string:$r'),
    'array]',
    'dict]',
  ];

  void expectPlistPrologue(String path) {
    final text = File(path).readAsStringSync();
    expect(text, startsWith('<?xml version="1.0" encoding="UTF-8"?>'));
    expect(text, contains('-//Apple//DTD PLIST 1.0//EN'));
    expect(text, contains('<plist version="1.0">'));
  }

  group('the app manifest', () {
    test('is exactly what the audit found, keys and booleans included', () {
      expect(tokensOf(appManifest), [
        'dict[',
        // No tracking, and so no domains: there is no advertising or
        // attribution SDK here, and `firebase_messaging` is push only.
        ...noTracking,

        'key:NSPrivacyCollectedDataTypes',
        'array[',
        // Sentry, on by default with one switch that turns it off
        // (ADR 0013 §1). Unlinked because there are no accounts and
        // `sendDefaultPii` is false (§6.1).
        ...collected('NSPrivacyCollectedDataTypeCrashData'),
        // `tracesSampleRate = 1.0` (telemetry/options.dart).
        ...collected('NSPrivacyCollectedDataTypePerformanceData'),
        // Breadcrumbs, the log stream, and the session replay §6.4 masks.
        ...collected('NSPrivacyCollectedDataTypeOtherDiagnosticData'),
        // Firebase's installation id, which `firebase_core` init alone sends,
        // and the FCM token if iOS ever gains a push entitlement - it has
        // none today, and no `remote-notification` background mode either.
        ...collected('NSPrivacyCollectedDataTypeDeviceID'),
        // Precise location is deliberately absent: the app reads it and never
        // sends it. `docs/releasing.md` carries the argument.
        'array]',

        'key:NSPrivacyAccessedAPITypes',
        'array[',
        // CA92.1, information only this app can read, and not 1C8F.1, which
        // is the App Group variant - this app has no entitlements file at
        // all. Justified by two of the plugin findings pinned below.
        ...accessed('UserDefaults', ['CA92.1']),
        // 35F9.1, elapsed time between events within the app, whose exception
        // is what permits sending a duration off-device. The call this
        // repository owns is declared in hardnested's own manifest; this entry
        // is conservative cover for the engine, which declares 35F9.1 itself,
        // and for Sentry's Cocoa SDK, which CocoaPods downloads and nothing
        // here can read.
        ...accessed('SystemBootTime', ['35F9.1']),
        // C617.1, metadata of files inside the app container. Conservative in
        // the same way: the first-party `File.stat()` reads call through
        // `Flutter.framework`, which declares this category itself, so the
        // symbol is in the engine's binary and not ours. Not DDA9.1, which
        // forbids sending anything derived off-device - a promise a log line
        // cannot keep. 0A2A.1 is not available to an app at all: Apple allows
        // it only to third-party SDKs, which is how the engine may declare it
        // and this app may not.
        ...accessed('FileTimestamp', ['C617.1']),
        'array]',
        'dict]',
      ]);
    });

    test('is a plist Apple will open', () => expectPlistPrologue(appManifest));
  });

  test('the manifest is copied into the app, not into the test bundle', () {
    const fileRef = '51AB00000000000000000090 /* PrivacyInfo.xcprivacy */';
    const buildFile =
        '51AB00000000000000000091 /* PrivacyInfo.xcprivacy in Resources */';
    const runnerResources = '97C146EC1CF9000F007C117D';
    const runnerTarget = '97C146ED1CF9000F007C117D';
    const runnerGroup = '97C146F01CF9000F007C117D';
    const testResources = '331C807F294A63A400263BE5';

    final project = File(pbxproj).readAsStringSync();

    /// The body of one `project.pbxproj` object, `{` to its matching `};`.
    ///
    /// The ` = {` is what makes it the definition: without it the first match
    /// is the *reference* to the same id from a target's `buildPhases` list,
    /// which is one line long and contains no entries. Scoped rather than
    /// searched whole because every assertion here is about which object
    /// holds the entry, and a file-wide `contains` cannot tell the app
    /// target's Resources phase from the test bundle's.
    String bodyOf(String id) {
      final open = RegExp('\\t\\t$id /\\*.*?\\*/ = \\{').firstMatch(project);
      expect(open, isNotNull, reason: 'no object $id defined in $pbxproj');
      final end = project.indexOf('\n\t\t};', open!.start);
      expect(end, isNot(-1), reason: 'object $id is not closed');
      return project.substring(open.start, end);
    }

    int timesIn(String body, String entry) => entry.allMatches(body).length;

    // The load-bearing pair: the entry is in that phase, and that phase is
    // the app target's.
    expect(
      timesIn(bodyOf(runnerResources), '$buildFile,'),
      1,
      reason: "the Runner target's Resources phase must copy it exactly once",
    );
    expect(
      bodyOf(runnerTarget),
      contains('$runnerResources /* Resources */'),
      reason: "that phase must be in the Runner target's buildPhases",
    );
    expect(
      bodyOf(testResources),
      isNot(contains(podResource)),
      reason: 'and not in the test bundle, which ships in no .app',
    );

    // The chain the copy walks: build file -> file reference -> a real file.
    // `path` and `sourceTree` in full, because the enclosing group's path is
    // `Runner`, which is what makes a bare path resolve.
    expect(
      project,
      contains('$buildFile = {isa = PBXBuildFile; fileRef = $fileRef; };'),
    );
    expect(
      project,
      contains(
        '$fileRef = {isa = PBXFileReference; '
        'lastKnownFileType = text.xml; path = $podResource; '
        'sourceTree = "<group>"; };',
      ),
    );
    expect(File(appManifest).existsSync(), isTrue);
    // Xcode visibility only, and cosmetic - but scoped for the same reason.
    expect(timesIn(bodyOf(runnerGroup), '$fileRef,'), 1);
  });

  group("hardnested's own framework", () {
    test('declares the boot-time API its binary carries', () {
      expect(tokensOf(hardnestedManifest), [
        'dict[',
        ...noTracking,
        'key:NSPrivacyCollectedDataTypes',
        'array/',
        'key:NSPrivacyAccessedAPITypes',
        'array[',
        ...accessed('SystemBootTime', ['35F9.1']),
        'array]',
        'dict]',
      ]);
      expectPlistPrologue(hardnestedManifest);
    });

    test('ships that manifest as a pod resource that exists', () {
      expect(
        File(hardnestedPodspec).readAsStringSync(),
        contains("'qunleashed_hardnested_privacy' => ['$podResource']"),
      );
      // Deliberately not `hardnestedManifest`, although the two spell the same
      // path today: this pins where CocoaPods resolves the podspec's own bare
      // relative path, whatever the constant above is later pointed at.
      expect(
        File('$hardnestedApple/$podResource').existsSync(),
        isTrue,
        reason: 'CocoaPods resolves $podResource beside the podspec',
      );
    });
  });

  /// Apple's symbol lists, from `describing-use-of-required-reason-api`.
  ///
  /// Trimmed to what can plausibly appear in this tree's C, Swift and Rust,
  /// and spelled with the opening parenthesis where the bare word would match
  /// something else: `stat(` so that `status` and `state` do not, and
  /// `statfs(` separately because Apple files it under disk space rather than
  /// file timestamps. `getattrlist`, `fgetattrlist` and `getattrlistat` are on
  /// both of Apple's lists and map to `FileTimestamp` here; `getattrlistbulk`
  /// is on the file-timestamp list only. A hit on any of them is worth reading
  /// by hand rather than taking this mapping's word.
  const categoryOf = <String, String>{
    'mach_absolute_time': 'SystemBootTime',
    'systemUptime': 'SystemBootTime',
    'UserDefaults': 'UserDefaults',
    'activeInputModes': 'ActiveKeyboards',
    'statfs(': 'DiskSpace',
    'statvfs(': 'DiskSpace',
    'fstatfs(': 'DiskSpace',
    'fstatvfs(': 'DiskSpace',
    'volumeAvailableCapacity': 'DiskSpace',
    'volumeTotalCapacityKey': 'DiskSpace',
    'systemFreeSize': 'DiskSpace',
    'NSFileSystemSize': 'DiskSpace',
    'NSFileSystemFreeSize': 'DiskSpace',
    'getattrlist': 'FileTimestamp',
    'fgetattrlist': 'FileTimestamp',
    'getattrlistat': 'FileTimestamp',
    'getattrlistbulk': 'FileTimestamp',
    'creationDate': 'FileTimestamp',
    'modificationDate': 'FileTimestamp',
    'contentModificationDateKey': 'FileTimestamp',
    'creationDateKey': 'FileTimestamp',
    'stat(': 'FileTimestamp',
    'fstat(': 'FileTimestamp',
    'lstat(': 'FileTimestamp',
    'fstatat(': 'FileTimestamp',
  };

  const appleExtensions = ['.c', '.h', '.m', '.mm', '.swift', '.rs'];

  /// Every (file, symbol, category) a text search finds in [paths].
  List<({String path, String symbol, String category})> hitsIn(
    Iterable<String> paths,
  ) {
    final hits = <({String path, String symbol, String category})>[];
    for (final path in paths) {
      final text = File(path).readAsStringSync();
      for (final MapEntry(key: symbol, value: category) in categoryOf.entries) {
        if (text.contains(symbol)) {
          hits.add((path: path, symbol: symbol, category: category));
        }
      }
    }
    return hits;
  }

  group('required reason APIs in the Apple sources here', () {
    /// Hits that never reach the iOS app, each pinned with its own reason.
    ///
    /// A list and not a path pattern: every one of these needed a different
    /// fact to clear it, and a pattern would have encoded the guess instead of
    /// the fact. `expect(exempt, expectedExempt)` below makes a pin fail once
    /// it stops being found, so none can outlive its reason.
    const expectedExempt = {
      // libusb's Darwin backend. Not an iOS risk because flipperlib's iOS
      // podspec declares no `source_files` at all - "No vendored native code
      // on iOS: BLE goes through universal_ble and there is no raw-USB DFU
      // path" - so this reaches the macOS pod only.
      'lib/modules/flipperlib/src/libusb/libusb/os/darwin_usb.c:'
          'mach_absolute_time',
      // libusb's Linux backend, which no Apple target compiles.
      'lib/modules/flipperlib/src/libusb/libusb/os/linux_usbfs.c:statfs(',
      // super_native_extensions' drag timestamps, under `darwin/macos`.
      'lib/modules/extensions/super_native_extensions/rust/src/darwin/macos/'
          'drag.rs:systemUptime',
      // And its Windows file stream, under `win32`.
      'lib/modules/extensions/super_native_extensions/rust/src/win32/'
          'virtual_file_stream.rs:stat(',
    };

    /// Which manifest answers for a source file.
    ///
    /// Two outcomes, because two are all this can decide. The hardnested pod
    /// is its own dynamic framework. Everything else git lists under `ios/`,
    /// `macos/` or `lib/modules/cpp/` is the app's own binary - the mfkey32
    /// and nested bridges are in the Runner target's `Sources` phase rather
    /// than in any pod, so they genuinely are. A submodule hit is neither: it
    /// belongs to a framework this repository does not build, so it has to be
    /// pinned above with a reason or fail - which is also the only honest
    /// remedy, a pull request there plus a submodule bump here. A third pod
    /// under `lib/modules/cpp/` would need a branch here the day its podspec
    /// lands.
    String manifestFor(String path) =>
        path.startsWith('$hardnestedDir/') ? hardnestedManifest : appManifest;

    test('are declared by the manifest of the binary they land in', () {
      // Two `git ls-files` calls rather than nine, and no walk of the
      // submodule directories from disk: that walk picked up gitignored build
      // output - `.cxx/*/CMakeCCompilerId.c`, on a machine that had built the
      // Android library - so what the scan covered depended on what the
      // developer had last compiled.
      final ours = gitVisibleFilesIn(['lib/modules/cpp/*', 'ios/*', 'macos/*'])
          .where((p) => appleExtensions.any(p.endsWith));
      final vendored = gitTrackedFilesRecursing([
        'lib/modules/flipperlib/*',
        'lib/modules/extensions/*',
        'lib/modules/irondash/*',
        'lib/modules/cpp/nfc-tools/*',
        'lib/modules/dartufbt/*',
      ]).where((p) => appleExtensions.any(p.endsWith));

      final sources = [...ours, ...vendored];
      // A floor rather than `isNotEmpty`, for the reason `ratchet.dart`'s
      // `atLeast` exists: a guard that looked at one file would otherwise
      // pass while its name claims the Apple sources of a whole checkout.
      expect(
        sources,
        hasLength(greaterThan(300)),
        reason:
            'only ${sources.length} Apple sources found - the pathspecs '
            'or the submodule checkout are not what this expects',
      );

      final exempt = <String>{};
      final undeclared = <String>[];
      final found = <String, String>{};
      for (final hit in hitsIn(sources)) {
        final key = '${hit.path}:${hit.symbol}';
        final manifest = manifestFor(hit.path);
        if (expectedExempt.contains(key)) {
          exempt.add(key);
        } else if (declaresCategory(manifest, hit.category)) {
          found[key] = manifest;
        } else {
          undeclared.add('$key (${hit.category}) not declared in $manifest');
        }
      }

      expect(undeclared, isEmpty);
      // Positive, not just the absence of a complaint. Deleting
      // `mach_absolute_time` from `categoryOf`, or pointing `manifestFor` at
      // the app manifest - which declares the same category and would hide
      // it - left every other assertion in this file green.
      expect(
        found,
        containsPair(
          '$hardnestedDir/util_posix.c:mach_absolute_time',
          hardnestedManifest,
        ),
      );
      expect(exempt, expectedExempt);
    });
  });

  group('required reason APIs in the plugins Flutter resolved', () {
    /// A plugin that uses a required reason API and declares none itself.
    ///
    /// This is the half of the requirement that moves. The app's own Apple
    /// code uses one such API and ships a manifest beside it, while this set
    /// changes whenever a dependency does - `CA92.1` is in the app's manifest
    /// because of two entries here, and neither was anybody's decision.
    ///
    /// Apple says a third-party SDK "can't rely on the privacy manifest files
    /// for apps that link the third-party SDK", so strictly each of these is
    /// its author's to fix. The app declares the category anyway where it
    /// honestly can, because a rejection names our upload and not their
    /// package.
    const expectedFindings = {
      // Covered by the app's `CA92.1`.
      'flutter_foreground_task:UserDefaults',
      'universal_ble:UserDefaults',
      // Not covered, and deliberately: `FPPDeviceInfoPlusPlugin.m` reads
      // `NSFileSystemSize` unconditionally, and none of Apple's four
      // disk-space reasons describes fetching a number and discarding it,
      // which is what this app does with it. `docs/releasing.md` names the
      // three ways out.
      'device_info_plus:DiskSpace',
    };

    /// The categories the app's manifest answers for, so that a finding it
    /// covers is distinguished from one left open.
    const coveredByApp = {'UserDefaults', 'SystemBootTime', 'FileTimestamp'};

    /// A plugin's other platforms are not in its iOS framework, and its
    /// example app and tests are in no framework at all.
    ///
    /// This matters more for the three plugins that are paths into this
    /// repository than for the hosted ones: their root is a whole submodule,
    /// so without the platform directories excluded, flipperlib's vendored
    /// libusb and super_native_extensions' `darwin/macos` and `win32` Rust
    /// all read as iOS code. Those are the same four calls the repository
    /// scan above pins as exempt, arriving a second time wearing a plugin's
    /// name.
    bool inTheIosFramework(String path) =>
        !const [
          '/example/',
          '/test/',
          '/android/',
          '/windows/',
          '/win32/',
          '/linux/',
          '/macos/',
          '/.dart_tool/',
        ].any(path.contains) &&
        // `Package.swift` is a SwiftPM build manifest, run at resolve time and
        // never compiled. It was the only `FileTimestamp` hit in
        // `permission_handler_apple`.
        !path.endsWith('/Package.swift');

    /// Whether this plugin's iOS pod compiles any sources at all.
    ///
    /// Read from the podspec rather than pinned by name: flipperlib's iOS
    /// podspec declares no `source_files` - "No vendored native code on
    /// iOS" - so its pod carries no code, and the day it gains some its uses
    /// appear as findings instead of staying invisible.
    bool compilesForIos(Iterable<String> podspecs) {
      // The `ios/` podspec specifically, when there is one, because a plugin
      // with both can compile on macOS and not on iOS - which is exactly
      // flipperlib's shape. A `darwin/` podspec serves both, and is the
      // fallback.
      final ios = podspecs.where((p) => p.contains('/ios/'));
      final deciding = ios.isNotEmpty ? ios : podspecs;
      return deciding.isEmpty ||
          deciding.any(
            (p) => File(p).readAsStringSync().contains(
              RegExp(r'^\s*s\.(ios\.)?source_files', multiLine: true),
            ),
          );
    }

    test('are a known set, and the app declares the ones it can', () {
      // Written by `flutter pub get`, which every job that runs this test has
      // already run. The precedent for reading a resolved package from a test
      // is `flutter_map_tile_error_guard_test.dart`.
      final pluginsJson = File(pluginsFile);
      expect(
        pluginsJson.existsSync(),
        isTrue,
        reason:
            '$pluginsFile is missing; run `flutter pub get` or this guard '
            'checked nothing',
      );
      final plugins =
          ((jsonDecode(pluginsJson.readAsStringSync())
                      as Map<String, dynamic>)['plugins']
                  as Map<String, dynamic>)['ios']
              as List<dynamic>;
      expect(plugins, hasLength(greaterThan(10)));

      final findings = <String>{};
      for (final plugin in plugins.cast<Map<String, dynamic>>()) {
        if (plugin['native_build'] == false) continue;
        final name = plugin['name'] as String;
        final root = Directory(
          (plugin['path'] as String).replaceAll(r'\', '/'),
        );
        if (!root.existsSync()) continue;

        final files = root
            .listSync(recursive: true, followLinks: false)
            .whereType<File>()
            .map((f) => f.path.replaceAll(r'\', '/'))
            .where(inTheIosFramework)
            .toList();
        if (!compilesForIos(files.where((p) => p.endsWith('.podspec')))) {
          continue;
        }

        final declared = files
            .where((p) => p.endsWith('.xcprivacy'))
            .expand(tokensOf)
            .where((t) => t.startsWith('string:NSPrivacyAccessedAPICategory'))
            .map((t) => t.split('NSPrivacyAccessedAPICategory').last)
            .toSet();
        for (final hit in hitsIn(
          files.where((p) => appleExtensions.any(p.endsWith)),
        )) {
          if (!declared.contains(hit.category)) {
            findings.add('$name:${hit.category}');
          }
        }
      }

      expect(
        findings,
        expectedFindings,
        reason:
            'a plugin started or stopped using a required reason API '
            'without declaring it. Decide whether the app manifest should '
            'cover it, and say so in docs/releasing.md',
      );
      // And every finding this set claims the app covers really is covered.
      for (final finding in expectedFindings) {
        final category = finding.split(':').last;
        if (!coveredByApp.contains(category)) continue;
        expect(
          declaresCategory(appManifest, category),
          isTrue,
          reason: '$finding is listed as covered by the app manifest',
        );
      }
    });
  });
}
