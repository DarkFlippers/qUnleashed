import 'dart:io';

import 'package:dartufbt/dartufbt.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qunleashed/services/assembler/controller.dart';
import 'package:qunleashed/services/localization/controller.dart';
import 'package:qunleashed/services/logging.dart';
import 'package:qunleashed/theme/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'unopenable_prefs.dart';

/// The three preference reads `_initCore` awaits — #124.
///
/// They are not settings stores: no memo, no `loaded`, and each is called
/// once from `_initCore`. What they share is position. A rejection from any
/// of them happens before there is a UI, so it is not a setting that falls
/// back - it is an app that never appears. `main` awaits `_initCore` ahead
/// of `runApp`; `widgetMain` awaits it with no UI at all.
///
/// The error was never lost, exactly: `installUncaughtHandlers` keeps it.
/// But `history` is in memory and there is no log screen without `runApp`,
/// so it died with the process. That is the whole of the fix; the defaults
/// were already sane.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    LogService.clearHistory();
    SharedPreferences.setMockInitialValues(const {});
  });

  group('QAppThemeController.loadThemeMode', () {
    final theme = QAppThemeController.instance;

    test('a stored mode comes back', () async {
      SharedPreferences.setMockInitialValues(const {'theme.mode': 'light'});

      await theme.loadThemeMode();

      expect(theme.themeMode, QThemeMode.light);
      expect(LogService.history, isEmpty);
    });

    test('a store that will not open leaves what it had and says so', () async {
      useUnopenablePrefs();
      final before = theme.themeMode;

      await expectLater(theme.loadThemeMode(), completes);

      expect(theme.themeMode, before);
      final kept = LogService.history
          .where((l) => l.contains('[AppTheme] load failed'))
          .toList();
      expect(kept, hasLength(1));
      expect(kept.single, contains('could not be opened'));
    });

    // An int under a String key. PrefsReader records it and returns null -
    // its widening is int-to-double only, so `0.0 is String` is false and
    // this falls through to the tally. Before, `99 as String?` threw out of
    // the cast and took the launch with it.
    test('a wrong-typed mode is the default, named', () async {
      SharedPreferences.setMockInitialValues(const {'theme.mode': 99});
      final before = theme.themeMode;

      await theme.loadThemeMode();

      expect(theme.themeMode, before);
      final kept = LogService.history
          .where((l) => l.contains('[AppTheme]'))
          .toList();
      expect(kept, hasLength(1));
      expect(kept.single, contains('theme.mode'));
    });
  });

  group('QLocaleController.loadLocale', () {
    final locale = QLocaleController.instance;
    tearDown(() => locale.setLocale(null));

    test('a stored locale comes back', () async {
      SharedPreferences.setMockInitialValues(const {'locale.code': 'ru'});

      await locale.loadLocale();

      expect(locale.locale, const Locale('ru'));
      expect(LogService.history, isEmpty);
    });

    test('a store that will not open leaves what it had and says so', () async {
      useUnopenablePrefs();

      await expectLater(locale.loadLocale(), completes);

      expect(locale.locale, isNull, reason: 'still following the system');
      final kept = LogService.history
          .where((l) => l.contains('[Locale] load failed'))
          .toList();
      expect(kept, hasLength(1));
      expect(kept.single, contains('could not be opened'));
    });

    test('a wrong-typed locale is the default, named', () async {
      SharedPreferences.setMockInitialValues(const {'locale.code': 99});

      await locale.loadLocale();

      expect(locale.locale, isNull);
      final kept = LogService.history
          .where((l) => l.contains('[Locale]'))
          .toList();
      expect(kept, hasLength(1));
      expect(kept.single, contains('locale.code'));
    });
  });

  group('AssemblerController.loadSettings', () {
    final assembler = AssemblerController.instance;

    setUp(() {
      // Otherwise every case below runs refreshStatus against whatever is in
      // this machine's own ~/.ufbt, which is neither deterministic nor the
      // thing being tested.
      assembler.readStatus = () => const UfbtStatus(
        stateDir: '',
        downloadDir: '',
        toolchainDir: '',
        sdkDir: '',
        previousTask: null,
        toolchain: UfbtToolchainInfo(
          archDir: '',
          version: '',
          url: '',
          installedVersion: null,
          isDeployed: false,
        ),
      );
    });

    test('everything stored comes back', () async {
      SharedPreferences.setMockInitialValues(const {
        'assembler_custom_index_url': 'https://index.example/idx.json',
        'assembler_backend': 'server',
      });

      await assembler.loadSettings();

      expect(assembler.customIndexUrl, 'https://index.example/idx.json');
      expect(assembler.preference, AssemblerBackendPreference.server);
      expect(LogService.history, isEmpty);
    });

    test('a store that will not open leaves what it had and says so', () async {
      // None of the three has a reset() - they are read once from main()
      // and never again - so this asserts against what the singleton held
      // coming in rather than against the class defaults.
      final before = (
        assembler.sdkSource,
        assembler.customIndexUrl,
        assembler.preference,
      );
      useUnopenablePrefs();

      await expectLater(assembler.loadSettings(), completes);

      expect(
        (assembler.sdkSource, assembler.customIndexUrl, assembler.preference),
        before,
        reason: 'nothing was touched',
      );
      final kept = LogService.history
          .where((l) => l.contains('[Assembler] load failed'))
          .toList();
      expect(kept, hasLength(1));
      expect(kept.single, contains('could not be opened'));
    });

    // refreshStatus decodes the ufbt state files, reads the toolchain
    // manifests and shells out to `uname`, and loadSettings is awaited by
    // _initCore - so before #124 a half-written state file after a power cut
    // was a launch with no UI, from a file the app itself wrote.
    test(
      'a status probe that throws does not take the launch with it',
      () async {
        assembler.readStatus = () =>
            throw const FileSystemException('ufbt_state.json');

        await expectLater(assembler.loadSettings(), completes);

        final kept = LogService.history
            .where((l) => l.contains('[Assembler] status failed'))
            .toList();
        expect(kept, hasLength(1));
        expect(kept.single, contains('ufbt_state.json'));
      },
    );

    // Three keys, so this is the one that can show the tally counting and
    // naming more than one.
    test('two wrong-typed keys are one entry that names both', () async {
      SharedPreferences.setMockInitialValues(const {
        'assembler_sdk_source': 99,
        'assembler_custom_index_url': 'https://index.example/idx.json',
        'assembler_backend': 99,
      });

      await assembler.loadSettings();

      expect(
        assembler.customIndexUrl,
        'https://index.example/idx.json',
        reason: 'the good key still landed',
      );
      final kept = LogService.history
          .where((l) => l.contains('[Assembler]'))
          .toList();
      expect(kept, hasLength(1));
      expect(kept.single, contains('ignored 2'));
      expect(
        kept.single,
        contains('assembler_sdk_source, assembler_backend'),
        reason: 'named, and in the order they were read',
      );
    });
  });
}
