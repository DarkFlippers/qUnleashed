// Where the device tab's link state went.
//
// The tab used to carry the state *as its label*, and #429 is what that cost:
// a status is a sentence in several locales - German's
// `deviceStateConnecting` is "Verbindung wird hergestellt" - so `TabLabel`
// drew it shrunk to whatever a quarter of the bar allowed, and a raised
// text-size setting then bought that one label almost nothing. It raised the
// size the label was *measured* at, not the size it was *drawn* at:
// `nav_bar_label_fit_test.dart`'s "barely moves when the scaler does" asserts
// exactly that, deliberately.
//
// So the label is `navDevice` now, a noun, and the state is two other things:
//
//  * a dot on the tab's icon, in four classes rather than eight, drawn inside
//    the icon's own 42x24 box so that it costs no width at any text size -
//    which is the claim "the state costs nothing at any scaler" below;
//  * the tab's semantics label, which is where all eight survive in full.
//
// What the dot cannot do is carry eight meanings, and it does not try. The
// eight sentences are still built by `_AppShellState._deviceLabel` and still
// pinned, branch by branch, in `shell_device_label_test.dart` - that file
// reads `FlipperRootScaffold.deviceLabel` as a property and is untouched by
// this change.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qunleashed/app/nav_bar.dart';
import 'package:qunleashed/services/localization/gen/l10n_generated.dart';
import 'package:qunleashed/theme/theme.dart';

import 'view_size.dart';

final ThemeData _theme = buildAppTheme(
  Brightness.dark,
  const Color(0xFFCC241D),
);

void main() {
  Future<void> pumpBar(
    WidgetTester tester, {
    required DeviceTabStatus status,
    String deviceLabel = 'Synced',
    double textScale = 1,
    Locale? locale,
  }) async {
    await tester.pumpWidget(const SizedBox.shrink());
    sizeView(tester, const Size(360, 720));
    await tester.pumpWidget(
      MaterialApp(
        theme: _theme,
        locale: locale,
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: FlipperRootScaffold(
          currentTab: FlipperRootTab.device,
          onTabSelected: (_) {},
          deviceLabel: deviceLabel,
          deviceStatus: status,
          railGroups: const [],
          child: const SizedBox.shrink(),
        ),
      ),
    );
  }

  Color dotColor(WidgetTester tester) {
    final box = tester.widget<Container>(find.byKey(deviceStatusDotKey));
    return (box.decoration! as BoxDecoration).color!;
  }

  QAppColors colors(WidgetTester tester) =>
      tester.element(find.byType(FlipperRootScaffold)).appColors;

  testWidgets('the tab is labelled with a noun, not the state', (tester) async {
    await pumpBar(tester, status: DeviceTabStatus.ready);
    final strings = lookupL10n(const Locale('en'));

    expect(find.text(strings.navDevice), findsOneWidget);
    // The whole of #429 in one assertion: the sentence is not drawn.
    expect(find.text('Synced'), findsNothing);
  });

  testWidgets('the state is announced in full', (tester) async {
    await pumpBar(
      tester,
      status: DeviceTabStatus.working,
      deviceLabel: 'Syncing',
    );
    final strings = lookupL10n(const Locale('en'));

    // The noun and the sentence together, because the dot is four classes and
    // the states are eight: "working" cannot say whether this is a connect, a
    // recovery or a sync, and a screen reader has to be told.
    expect(
      find.bySemanticsLabel('${strings.navDevice}, Syncing'),
      findsOneWidget,
    );
  });

  testWidgets('each class draws its own colour', (tester) async {
    for (final (status, pick)
        in <(DeviceTabStatus, Color Function(QAppColors))>[
          (DeviceTabStatus.absent, (c) => c.textMuted),
          (DeviceTabStatus.working, (c) => c.info),
          (DeviceTabStatus.ready, (c) => c.success),
          (DeviceTabStatus.attention, (c) => c.danger),
        ]) {
      await pumpBar(tester, status: status);
      expect(dotColor(tester), pick(colors(tester)), reason: '$status');
    }
  });

  testWidgets('the four colours are four colours', (tester) async {
    // So the case above cannot pass on a palette that answers one colour for
    // two classes - which would make the dot say less than it claims to.
    final seen = <Color>{};
    for (final status in DeviceTabStatus.values) {
      await pumpBar(tester, status: status);
      seen.add(dotColor(tester));
    }
    expect(seen, hasLength(DeviceTabStatus.values.length), reason: '$seen');
  });

  testWidgets('the state costs nothing at any scaler', (tester) async {
    // The point of the dot over a word, and the thing #429 asked for: the
    // state changing moves no layout, at the largest scaler Android offers,
    // in the locale whose nav nouns are longest. A word could not do this -
    // it would take width from the label beside it, or shrink, which is what
    // the old tab did instead of honouring the setting.
    final frames = <DeviceTabStatus, List<Rect>>{};
    for (final status in DeviceTabStatus.values) {
      await pumpBar(
        tester,
        status: status,
        textScale: 3.1,
        locale: const Locale('ru'),
      );
      final strings = lookupL10n(const Locale('ru'));
      frames[status] = [
        for (final label in [
          strings.navDevice,
          strings.navArchive,
          strings.navApps,
          strings.navTools,
        ])
          tester.getRect(find.text(label)),
      ];
    }

    final distinct = frames.values.map((r) => r.toString()).toSet();
    expect(distinct, hasLength(1), reason: '$frames');
  });

  testWidgets('the rail draws no dot', (tester) async {
    // The wide layout is icons with no labels and has never shown the state;
    // #429 is about the bottom bar, and putting the dot on the rail too is a
    // change of its own rather than a consequence of this one.
    await tester.pumpWidget(const SizedBox.shrink());
    sizeView(tester, const Size(900, 450));
    await tester.pumpWidget(
      MaterialApp(
        theme: _theme,
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: const FlipperRootScaffold(
          currentTab: FlipperRootTab.device,
          onTabSelected: _ignore,
          deviceLabel: 'Synced',
          deviceStatus: DeviceTabStatus.ready,
          railGroups: [],
          child: SizedBox.shrink(),
        ),
      ),
    );

    expect(find.byKey(deviceStatusDotKey), findsNothing);
  });
}

void _ignore(FlipperRootTab _) {}
