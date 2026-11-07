import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qunleashed/pages/apps/catalog/widgets/floating_actions.dart';
import 'package:qunleashed/theme/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:qunleashed/pages/apps/catalog/controller.dart';
import 'package:qunleashed/pages/apps/data/apps_backend.dart';

Finder get _top => find.byTooltip('Back to top');

Widget _wrap(
  ScrollController controller, {
  VoidCallback? onBuilder,
  bool enabled = true,
  bool reducedMotion = false,
  Color accent = const Color(0xFFCC241D),
  ShapeBorder? fabShape,
}) => MaterialApp(
  theme: buildAppTheme(Brightness.dark, accent).copyWith(
    floatingActionButtonTheme: FloatingActionButtonThemeData(shape: fabShape),
  ),
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(disableAnimations: reducedMotion),
    child: child!,
  ),
  home: Scaffold(
    body: ListView.builder(
      controller: controller,
      itemExtent: 100,
      itemCount: 100,
      itemBuilder: (_, index) => Text('Item $index'),
    ),
    floatingActionButton: CatalogFloatingActions(
      controller: controller,
      enabled: enabled,
      onOpenBuilder: onBuilder,
    ),
  ),
);

Finder _builderButton() => find.byWidgetPredicate(
  (widget) => widget is FloatingActionButton && widget.tooltip != 'Back to top',
);

void main() {
  testWidgets(
    'both actions keep the app theme shape and accent after scrolling',
    (tester) async {
      final controller = ScrollController();
      addTearDown(controller.dispose);
      const accent = Color(0xFF1984A5);
      const shape = RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(9)),
      );
      await tester.pumpWidget(
        _wrap(controller, onBuilder: () {}, accent: accent, fabShape: shape),
      );
      await tester.pumpAndSettle();
      Material materialFor(Finder button) => tester.widget<Material>(
        find.descendant(
          of: button,
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is Material && widget.type == MaterialType.button,
          ),
        ),
      );
      expect(materialFor(_builderButton()).shape, shape);
      expect(materialFor(_builderButton()).color, accent);
      controller.jumpTo(800);
      await tester.pumpAndSettle();
      for (final action in [_top, _builderButton()]) {
        expect(materialFor(action).shape, shape);
        expect(materialFor(action).color, accent);
      }
    },
  );

  testWidgets(
    'explicit source-build preference keeps Assembler available without a connected device',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        'apps_catalog_mode': 'sourceBuild',
      });
      final backend = AppsBackend.instance;
      backend.mode.value = CatalogMode.normal;
      final catalog = AppsCatalogController();
      addTearDown(catalog.dispose);
      expect(catalog.showsBuilder, isFalse);
      await backend.loadPreference();
      expect(backend.isReady, isFalse);
      expect(backend.mode.value, CatalogMode.normal);
      expect(catalog.showsBuilder, isTrue);
      final controller = ScrollController();
      addTearDown(controller.dispose);
      var opens = 0;
      await tester.pumpWidget(
        _wrap(
          controller,
          onBuilder: catalog.showsBuilder ? () => opens++ : null,
        ),
      );
      await tester.pumpAndSettle();
      expect(_builderButton().hitTestable(), findsOneWidget);
      await tester.tap(_builderButton());
      expect(opens, 1);
    },
  );

  testWidgets(
    'scrolling reveals the top action and smoothly moves and shrinks Flibler',
    (tester) async {
      final controller = ScrollController();
      addTearDown(controller.dispose);
      var opens = 0;
      await tester.pumpWidget(_wrap(controller, onBuilder: () => opens++));
      await tester.pumpAndSettle();
      expect(_top.hitTestable(), findsNothing);
      final original = tester.getRect(_builderButton());
      expect(original.width, 56);

      controller.jumpTo(800);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));
      final halfway = tester.getRect(_builderButton());
      expect(halfway.width, inExclusiveRange(48, 56));
      expect(halfway.center.dy, lessThan(original.center.dy));
      await tester.pumpAndSettle();
      expect(_top.hitTestable(), findsOneWidget);
      final compact = tester.getRect(_builderButton());
      expect(compact.width, 48);
      expect(compact.bottom, lessThan(tester.getRect(_top).top));
      await tester.tap(_builderButton());
      expect(opens, 1);

      await tester.tap(_top);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));
      expect(controller.offset, inExclusiveRange(0, 800));
      await tester.pumpAndSettle();
      expect(controller.offset, controller.position.minScrollExtent);
      expect(_top.hitTestable(), findsNothing);
      expect(tester.getRect(_builderButton()), original);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('works without Flibler and does not flicker near its threshold', (
    tester,
  ) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(_wrap(controller));
    await tester.pumpAndSettle();
    expect(_builderButton(), findsNothing);
    controller.jumpTo(600);
    await tester.pumpAndSettle();
    expect(_top.hitTestable(), findsOneWidget);
    controller.jumpTo(450);
    await tester.pumpAndSettle();
    expect(_top.hitTestable(), findsOneWidget);
    controller.jumpTo(80);
    await tester.pumpAndSettle();
    expect(_top.hitTestable(), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'restored offsets, disabled views and reduced motion are respected',
    (tester) async {
      final controller = ScrollController(initialScrollOffset: 900);
      addTearDown(controller.dispose);
      await tester.pumpWidget(_wrap(controller, reducedMotion: true));
      await tester.pumpAndSettle();
      expect(_top.hitTestable(), findsOneWidget);
      await tester.tap(_top);
      await tester.pump();
      expect(controller.offset, 0);
      controller.jumpTo(900);
      await tester.pumpAndSettle();
      await tester.pumpWidget(
        _wrap(controller, enabled: false, onBuilder: () {}),
      );
      await tester.pumpAndSettle();
      expect(_top.hitTestable(), findsNothing);
      expect(_builderButton(), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
