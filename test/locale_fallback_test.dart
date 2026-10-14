// What the app renders in when it cannot speak the device's language.
//
// `basicLocaleListResolution` answers with the first entry of the list it is
// given whenever nothing matches, and again when the device offers no
// preference at all. `gen-l10n` emits `supportedLocales` sorted, so that first
// entry is whichever language sorts first - which was `en` for as long as the
// app spoke English, Russian and Ukrainian, and became `be` the day Belarusian
// arrived from Crowdin. Nothing in the app said so: a device set to Japanese
// would have come up in Belarusian, and the only thing that noticed was a
// service test asserting an English word and getting
// `Серверныя зборкі недаступныя ў гэтай версіі праграмы`.
//
// So the fallback is named, the list handed to any resolver puts it first, and
// this is what keeps both true as languages arrive.
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qunleashed/services/localization/controller.dart';
import 'package:qunleashed/services/localization/l10n.dart';

import 'arb.dart';

void main() {
  test('the fallback is a language the app actually speaks', () {
    expect(
      L10n.supportedLocales,
      contains(QLocaleController.fallback),
      reason:
          'the fallback is offered to the framework as a supported locale, so '
          'a fallback with no ARB behind it would throw in lookupL10n',
    );
  });

  test('the resolution order leads with the fallback', () {
    expect(QLocaleController.resolutionOrder.first, QLocaleController.fallback);
  });

  test('the resolution order is the supported set, reordered', () {
    expect(
      QLocaleController.resolutionOrder.toSet(),
      L10n.supportedLocales.toSet(),
      reason: 'moving the fallback to the front may not drop or add a language',
    );
    expect(
      QLocaleController.resolutionOrder,
      hasLength(L10n.supportedLocales.length),
      reason: 'nor duplicate one',
    );
  });

  test('a language the app does not speak resolves to the fallback', () {
    // Japanese is not a Crowdin target and is not about to become one; what
    // matters is only that it is absent, which the first expectation states.
    const unspoken = Locale('ja');
    expect(L10n.supportedLocales, isNot(contains(unspoken)));
    expect(
      basicLocaleListResolution(const <Locale>[
        unspoken,
      ], QLocaleController.resolutionOrder),
      QLocaleController.fallback,
    );
  });

  // The group above pins the list. These pin that something uses it, which is
  // where the bug actually was: `resolutionOrder` existing changes nothing if
  // the resolver is still handed the sorted one. Reverting the fix leaves
  // every expectation above green.
  group('the controller resolves through it', () {
    final binding = TestWidgetsFlutterBinding.ensureInitialized();

    tearDown(() {
      binding.platformDispatcher.clearLocalesTestValue();
    });

    test('a device language the app does not speak renders the fallback', () {
      binding.platformDispatcher.localesTestValue = const <Locale>[
        Locale('ja'),
        Locale('ko'),
      ];
      expect(QLocaleController.instance.resolved, QLocaleController.fallback);
    });

    test('a device language it does speak is still honoured', () {
      final spoken = L10n.supportedLocales.firstWhere(
        (locale) => locale != QLocaleController.fallback,
      );
      binding.platformDispatcher.localesTestValue = <Locale>[spoken];
      expect(QLocaleController.instance.resolved, spoken);
    });

    test('and the strings it hands a service are in that language', () {
      // The canary that found this: a service test asserting an English word
      // got `Серверныя зборкі недаступныя ў гэтай версіі праграмы`, because
      // `l10n` - which services with no BuildContext read - resolves through
      // the controller. Compared against the template file rather than a
      // literal, so translating `languageName` cannot break this.
      binding.platformDispatcher.localesTestValue = const <Locale>[
        Locale('ja'),
      ];
      expect(
        l10n.languageName,
        arbStrings(File('$kArbDir/app_en.arb'))['languageName'],
      );
    });
  });

  // The framework runs its own resolution for the widget tree, against the
  // list MaterialApp is given - so the controller resolving correctly fixes
  // only half of it. A source read rather than a pumped app, in the style of
  // `dart_define_keys_test.dart`: what is being asserted is which list one
  // line passes, and building the whole shell to see it would test the shell.
  test('MaterialApp is handed the resolution order, not the sorted list', () {
    final source = File('lib/app/app.dart').readAsStringSync();
    expect(
      source,
      contains('supportedLocales: QLocaleController.resolutionOrder'),
      reason:
          'the framework falls back to the first entry of this list, and '
          'gen-l10n sorts L10n.supportedLocales - so passing that one renders '
          'the whole app in whichever language sorts first',
    );
  });

  test('a device with no preference at all resolves to the fallback', () {
    expect(
      basicLocaleListResolution(
        const <Locale>[],
        QLocaleController.resolutionOrder,
      ),
      QLocaleController.fallback,
    );
  });

  test('a language the app does speak still wins over the fallback', () {
    // The point of leading with English is the no-match case only. A device
    // asking for a language that is present must still get it, or this fix
    // would have replaced one wrong language with another.
    final spoken = L10n.supportedLocales.firstWhere(
      (locale) => locale != QLocaleController.fallback,
    );
    expect(
      basicLocaleListResolution(<Locale>[
        spoken,
      ], QLocaleController.resolutionOrder),
      spoken,
    );
  });
}
