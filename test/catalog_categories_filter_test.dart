import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qunleashed/pages/apps/catalog/widgets/categories_filter.dart';
import 'package:qunleashed/pages/apps/catalog/widgets/category_chip.dart';
import 'package:qunleashed/pages/apps/data/models/category.dart';
import 'package:qunleashed/services/localization/gen/l10n_generated.dart';
import 'package:qunleashed/theme/theme.dart';

AppCategory cat(String id, {String? parent}) => AppCategory(
  id: id,
  name: id.split('/').last,
  color: '98CEFE',
  parentId: parent,
);

final categories = nestCategories([
  cat('nfc'),
  cat('nfc/Access', parent: 'nfc'),
  cat('nfc/Gaming', parent: 'nfc'),
  cat('subghz'),
  cat('subghz/Analyzers', parent: 'subghz'),
  // Its parent never arrived: it has to stay reachable.
  cat('orphan', parent: 'gone'),
]);

Future<void> pump(WidgetTester t, AppCategory? current) => t.pumpWidget(
  MaterialApp(
    theme: buildAppTheme(Brightness.dark, const Color(0xFFFF8200)),
    localizationsDelegates: L10n.localizationsDelegates,
    supportedLocales: L10n.supportedLocales,
    home: Scaffold(
      body: CategoriesFilter(
        categories: categories,
        current: current,
        onSelect: (_) {},
      ),
    ),
  ),
);

Map<String, bool> chips(WidgetTester t) => {
  for (final chip in t.widgetList<CategoryChip>(find.byType(CategoryChip)))
    chip.category.name: chip.selected,
};

AppCategory byId(String id) => categories.firstWhere((c) => c.id == id);

void main() {
  testWidgets('with nothing picked, only top-level categories show', (t) async {
    await pump(t, null);
    expect(chips(t).keys, ['All apps', 'nfc', 'subghz', 'orphan']);
    expect(chips(t).values, everyElement(isTrue));
  });

  testWidgets('a picked category opens its own folders, all lit', (t) async {
    await pump(t, byId('nfc'));
    expect(chips(t), {
      'All apps': false,
      'nfc': true,
      'subghz': false,
      'orphan': false,
      'Access': true,
      'Gaming': true,
    });
  });

  testWidgets('a picked folder keeps its siblings and its category lit', (
    t,
  ) async {
    await pump(t, byId('nfc/Gaming'));
    expect(chips(t), {
      'All apps': false,
      'nfc': true,
      'subghz': false,
      'orphan': false,
      'Access': false,
      'Gaming': true,
    });
  });
}
