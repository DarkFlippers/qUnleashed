import 'package:flutter_test/flutter_test.dart';
import 'package:qunleashed/pages/archive/map/data/settings.dart';
import 'package:qunleashed/services/home_widget/settings.dart';
import 'package:qunleashed/services/localization/l10n.dart';
import 'package:qunleashed/services/logging.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'unopenable_prefs.dart';

/// What a settings store does with a read it cannot complete — #123.
///
/// Two failures, and they want opposite answers. A store that will not open
/// loses everything, and `load()` memoises, so before #123 the rejection was
/// latched and handed to every later caller for the life of the process. A
/// single key of the wrong type loses one setting, and `getBool` and friends
/// are casts, so before #123 it threw and took every key read after it.
///
/// The second is the one that happens in a shipped build: `_initCore` reads
/// preferences through three other controllers before `runApp`, so a store
/// that will not open stops the app long before these two are reached (#124).
///
/// `DeviceSettings` is the third store with this shape and has its own file.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final map = MapSettings.instance;
  final widgets = HomeWidgetSettings.instance;

  setUp(() {
    LogService.clearHistory();
    SharedPreferences.setMockInitialValues(const {});
    map.reset();
    widgets.reset();
  });

  tearDown(() {
    map.reset();
    widgets.reset();
  });

  group('MapSettings', () {
    // A non-default value for every key the store reads, so a test can tell
    // "this came from disk" from "this is the initialiser".
    const stored = <String, Object>{
      'map.tiles.provider': 'osm',
      'map.tiles.appearance': 'dark',
      'map.tiles.design.carto.light': 'light_all',
      'map.tiles.key.stadia': 'a-key',
      'map.tiles.custom.url': 'https://tiles.example/{z}/{x}/{y}.png',
      'map.tiles.custom.subdomains': 'a,b',
      'map.tiles.custom.max_zoom': 12.0,
      'map.tiles.retina': false,
      'map.follow.auto_center': true,
      'map.follow.track_device': true,
      'map.scan.subfolders': false,
    };

    /// Every field the store publishes, so one matcher covers all of them.
    Map<String, Object?> snapshot() => {
      'provider': map.provider.id,
      'appearance': map.appearance,
      'design': map.designOf(cartoProvider(l10nGlobal), dark: false).id,
      'key': map.keyOf(stadiaProvider(l10nGlobal)),
      'customUrl': map.customUrl,
      'customSubdomains': map.customSubdomains,
      'customMaxZoom': map.customMaxZoom,
      'retina': map.retina,
      'autoCenter': map.autoCenter,
      'trackDevice': map.trackDevice,
      'scanSubfolders': map.scanSubfolders,
    };

    late Map<String, Object?> defaults;
    setUp(() => defaults = snapshot());

    test('everything stored comes back, per-provider keys included', () async {
      SharedPreferences.setMockInitialValues(stored);

      await map.load();

      expect(map.provider.id, 'osm');
      expect(map.appearance, MapAppearance.dark);
      expect(
        map.designOf(cartoProvider(l10nGlobal), dark: false).id,
        'light_all',
      );
      expect(map.keyOf(stadiaProvider(l10nGlobal)), 'a-key');
      expect(map.customUrl, 'https://tiles.example/{z}/{x}/{y}.png');
      expect(map.customSubdomains, 'a,b');
      expect(map.customMaxZoom, 12.0);
      expect(map.retina, isFalse);
      expect(map.autoCenter, isTrue);
      expect(map.trackDevice, isTrue);
      expect(map.scanSubfolders, isFalse);
      expect(map.loaded, isTrue);
      expect(LogService.history, isEmpty, reason: 'a clean read says nothing');
    });

    test('nothing stored is the documented default, not an error', () async {
      await map.load();

      expect(snapshot(), defaults);
      expect(LogService.history, isEmpty);
    });

    // Pins keyOf, not the isNotEmpty guard in _load: an entry holding '' and
    // no entry at all are the same through keyOf, so dropping that guard is
    // invisible here and stays unpinned on purpose.
    test('an empty stored key reads as no key', () async {
      SharedPreferences.setMockInitialValues(const {
        'map.tiles.key.stadia': '',
      });

      await map.load();

      expect(map.keyOf(stadiaProvider(l10nGlobal)), isEmpty);
      expect(map.hasKey(stadiaProvider(l10nGlobal)), isFalse);
    });

    // 12 and 12.0 are the same zoom, and Android's legacy plugin passes a
    // native putInt straight through as an int.
    test('a whole number under a double key is that number', () async {
      SharedPreferences.setMockInitialValues(const {
        'map.tiles.custom.max_zoom': 12,
      });

      await map.load();

      expect(map.customMaxZoom, 12.0);
      expect(LogService.history, isEmpty, reason: 'not a mismatch');
    });

    // The value reaches TileLayer.maxZoom, where 0 draws nothing. A stored
    // 0.0 was always readable; the int widening only adds a second route to
    // it, so this closes an old hole rather than one the widening opened.
    test('a stored zoom outside the accepted range is clamped', () async {
      SharedPreferences.setMockInitialValues(const {
        'map.tiles.custom.max_zoom': 0,
      });

      await map.load();

      expect(map.customMaxZoom, MapSettings.minCustomZoom);
    });

    test('a load notifies, so a page built before it repaints', () async {
      SharedPreferences.setMockInitialValues(stored);
      var notifications = 0;
      void count() => notifications++;
      map.addListener(count);
      addTearDown(() => map.removeListener(count));

      await map.load();

      expect(notifications, 1);
      expect(map.retina, isFalse, reason: 'the listener saw the stored value');
    });

    // One case per key rather than one case overall: whichever order _load
    // reads in, every key gets a turn at being the bad one. A read that
    // stopped at the first mismatch would fail every case but the last.
    //
    // The wrong value is an int wherever the key holds anything but a double,
    // which is what pins the `0.0 is T` half of PrefsReader's widening -
    // without it `99.toDouble() as bool` throws out of the reader and takes
    // the whole store with it, which is the regression the class prevents.
    for (final bad in stored.keys) {
      test('a wrong-typed $bad costs that key and nothing else', () async {
        SharedPreferences.setMockInitialValues(<String, Object>{
          ...stored,
          bad: stored[bad] is double ? 'not-a-number' : 99,
        });

        await map.load();

        final now = snapshot();
        final reverted = _mapFieldFor(bad);
        for (final field in now.keys) {
          expect(
            now[field],
            field == reverted ? defaults[field] : isNot(defaults[field]),
            reason: '$field after a bad $bad',
          );
        }
        expect(map.loaded, isTrue, reason: 'one key, not the read');
        final kept = LogService.history
            .where((l) => l.contains('[MapSettings]'))
            .toList();
        expect(kept, hasLength(1));
        expect(kept.single, contains(bad));
      });
    }

    // The tally is the whole reason PrefsReader collects instead of logging:
    // one entry per load, counted, naming every key, in the order they were
    // read. With one bad key a hard-coded "1" and a .first would both pass.
    test('two wrong-typed keys are one entry that names both', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        ...stored,
        'map.tiles.provider': 99,
        'map.scan.subfolders': 99,
      });

      await map.load();

      final kept = LogService.history
          .where((l) => l.contains('[MapSettings]'))
          .toList();
      expect(kept, hasLength(1));
      expect(kept.single, contains('ignored 2'));
      expect(
        kept.single,
        contains('map.tiles.provider, map.scan.subfolders'),
        reason: 'named, and in the order they were read',
      );
      expect(map.provider.id, defaults['provider']);
      expect(map.scanSubfolders, defaults['scanSubfolders']);
      expect(map.retina, isFalse, reason: 'a third key still landed');
    });

    test(
      'a store that will not open leaves the defaults and says so',
      () async {
        useUnopenablePrefs();

        await expectLater(map.load(), completes);

        expect(snapshot(), defaults);
        expect(map.loaded, isFalse);
        final kept = LogService.history
            .where((l) => l.contains('[MapSettings] load failed'))
            .toList();
        expect(kept, hasLength(1));
        expect(kept.single, contains('could not be opened'));
        // The entry goes through LogService.describe, so it carries whatever
        // stack the rejection had. Here that is the harness's: `flutter test`
        // runs inside a stack_trace chaining zone that supplies one even for a
        // PlatformException, which in the app arrives bare. What this pins is
        // that describe is called at all - swap it for a plain `$e` and the
        // trace disappears for the errors that do carry one.
        expect(kept.single, contains('\n'));
      },
    );

    // Not a wish for a retry, a record that there is none. getInstance
    // memoises success for the process and only drops its own memo on
    // failure, and main() reads preferences through three other controllers
    // before runApp - so a store that fails here means the app did not start.
    // A later change to re-read should be a deliberate one.
    test('a failed read is not retried by the next caller', () async {
      useUnopenablePrefs();

      await map.load();
      LogService.clearHistory();
      SharedPreferences.setMockInitialValues(stored);
      await map.load();

      expect(LogService.history, isEmpty);
      expect(snapshot(), defaults, reason: 'still the defaults, not re-read');
    });

    test('reset puts every field back', () async {
      SharedPreferences.setMockInitialValues(stored);
      await map.load();
      expect(snapshot(), isNot(defaults));

      map.reset();

      expect(snapshot(), defaults);
      expect(map.loaded, isFalse);
    });
  });

  group('HomeWidgetSettings', () {
    const stored = <String, Object>{
      'home_widget.theme': 'material',
      'home_widget.icon_style': 'tinted',
      'home_widget.border': 'accent',
      'home_widget.caption': false,
      'home_widget.caption_size': 'large',
    };

    Map<String, Object?> snapshot() => {
      'theme': widgets.theme,
      'iconStyle': widgets.iconStyle,
      'border': widgets.border,
      'captionShown': widgets.captionShown,
      'captionSize': widgets.captionSize,
    };

    late Map<String, Object?> defaults;
    late List<Map<String, Object>> pushed;

    setUp(() {
      defaults = snapshot();
      pushed = <Map<String, Object>>[];
      widgets.push = (settings) async => pushed.add(settings);
      // reset() puts the real push back, and the file's tearDown runs it.
    });

    test('everything stored comes back', () async {
      SharedPreferences.setMockInitialValues(stored);

      await widgets.load();

      expect(widgets.theme, WidgetTheme.material);
      expect(widgets.iconStyle, WidgetIconStyle.tinted);
      expect(widgets.border, WidgetBorder.accent);
      expect(widgets.captionShown, isFalse);
      expect(widgets.captionSize, WidgetCaptionSize.large);
      expect(widgets.loaded, isTrue, reason: 'which is what sync() gates on');
      expect(LogService.history, isEmpty);
    });

    test('nothing stored is the documented default, not an error', () async {
      await widgets.load();

      expect(snapshot(), defaults);
      expect(LogService.history, isEmpty);
    });

    test('a load notifies', () async {
      SharedPreferences.setMockInitialValues(stored);
      var notifications = 0;
      void count() => notifications++;
      widgets.addListener(count);
      addTearDown(() => widgets.removeListener(count));

      await widgets.load();

      expect(notifications, 1);
      expect(widgets.theme, WidgetTheme.material);
    });

    for (final bad in stored.keys) {
      test('a wrong-typed $bad costs that key and nothing else', () async {
        SharedPreferences.setMockInitialValues(<String, Object>{
          ...stored,
          bad: 99,
        });

        await widgets.load();

        final now = snapshot();
        final reverted = _widgetFieldFor(bad);
        for (final field in now.keys) {
          expect(
            now[field],
            field == reverted ? defaults[field] : isNot(defaults[field]),
            reason: '$field after a bad $bad',
          );
        }
        expect(widgets.loaded, isTrue, reason: 'one key, not the read');
        final kept = LogService.history
            .where((l) => l.contains('[HomeWidgetSettings]'))
            .toList();
        expect(kept, hasLength(1));
        expect(kept.single, contains(bad));
      });
    }

    test('two wrong-typed keys are one entry that names both', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        ...stored,
        'home_widget.theme': 99,
        'home_widget.caption_size': 99,
      });

      await widgets.load();

      final kept = LogService.history
          .where((l) => l.contains('[HomeWidgetSettings]'))
          .toList();
      expect(kept, hasLength(1));
      expect(kept.single, contains('ignored 2'));
      expect(
        kept.single,
        contains('home_widget.theme, home_widget.caption_size'),
      );
      expect(widgets.border, WidgetBorder.accent, reason: 'the rest landed');
    });

    test(
      'a store that will not open leaves the defaults and says so',
      () async {
        useUnopenablePrefs();

        await expectLater(widgets.load(), completes);

        expect(snapshot(), defaults);
        expect(widgets.loaded, isFalse);
        final kept = LogService.history
            .where((l) => l.contains('[HomeWidgetSettings] load failed'))
            .toList();
        expect(kept, hasLength(1));
        expect(kept.single, contains('could not be opened'));
        // The entry goes through LogService.describe, so it carries whatever
        // stack the rejection had. Here that is the harness's: `flutter test`
        // runs inside a stack_trace chaining zone that supplies one even for a
        // PlatformException, which in the app arrives bare. What this pins is
        // that describe is called at all - swap it for a plain `$e` and the
        // trace disappears for the errors that do carry one.
        expect(kept.single, contains('\n'));
      },
    );

    test('a failed read is not retried by the next caller', () async {
      useUnopenablePrefs();

      await widgets.load();
      LogService.clearHistory();
      SharedPreferences.setMockInitialValues(stored);
      await widgets.load();

      expect(LogService.history, isEmpty);
      expect(snapshot(), defaults);
    });

    test('reset puts every field back', () async {
      SharedPreferences.setMockInitialValues(stored);
      await widgets.load();
      expect(snapshot(), isNot(defaults));

      widgets.reset();

      expect(snapshot(), defaults);
      expect(widgets.loaded, isFalse);
    });

    // What the native store is told. It is a second, durable copy that every
    // home-screen widget draws from, so pushing after a lost read replaces a
    // look the user chose with the initialisers - and keeps doing it, since
    // the bad preference persists. Both push sites have to decline.
    group('pushes to the native store', () {
      test('a good read is pushed', () async {
        SharedPreferences.setMockInitialValues(stored);

        await widgets.sync();

        expect(pushed, hasLength(1));
        expect(pushed.single['theme'], 'material');
      });

      test('a read that failed pushes nothing', () async {
        useUnopenablePrefs();

        await widgets.sync();

        expect(pushed, isEmpty);
        expect(widgets.loaded, isFalse);
      });

      test('a setter after a good read pushes the whole look', () async {
        SharedPreferences.setMockInitialValues(stored);
        await widgets.load();
        var notifications = 0;
        void count() => notifications++;
        widgets.addListener(count);
        addTearDown(() => widgets.removeListener(count));

        await widgets.setBorder(WidgetBorder.thin);

        expect(pushed, hasLength(1));
        expect(pushed.single['border'], 'thin');
        expect(pushed.single['theme'], 'material', reason: 'all five fields');
        expect(widgets.border, WidgetBorder.thin);
        expect(notifications, 1, reason: 'the page reads its state from here');
      });

      test(
        'a setter after a failed read changes nothing and says so',
        () async {
          useUnopenablePrefs();
          await widgets.load();
          LogService.clearHistory();

          await widgets.setTheme(WidgetTheme.material);

          expect(pushed, isEmpty);
          expect(widgets.theme, WidgetTheme.categories);
          expect(
            LogService.history.where((l) => l.contains('not applied')),
            hasLength(1),
          );
        },
      );
    });
  });
}

/// Which snapshot field a preference key feeds, so the per-key cases can say
/// "this one reverted and the others did not".
String _mapFieldFor(String key) => switch (key) {
  'map.tiles.provider' => 'provider',
  'map.tiles.appearance' => 'appearance',
  'map.tiles.design.carto.light' => 'design',
  'map.tiles.key.stadia' => 'key',
  'map.tiles.custom.url' => 'customUrl',
  'map.tiles.custom.subdomains' => 'customSubdomains',
  'map.tiles.custom.max_zoom' => 'customMaxZoom',
  'map.tiles.retina' => 'retina',
  'map.follow.auto_center' => 'autoCenter',
  'map.follow.track_device' => 'trackDevice',
  _ => 'scanSubfolders',
};

String _widgetFieldFor(String key) => switch (key) {
  'home_widget.theme' => 'theme',
  'home_widget.icon_style' => 'iconStyle',
  'home_widget.border' => 'border',
  'home_widget.caption' => 'captionShown',
  _ => 'captionSize',
};
