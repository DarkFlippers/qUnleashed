import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qunleashed/components/archive/category.dart';
import 'package:qunleashed/components/filelist/columns.dart';
import 'package:qunleashed/components/filelist/table.dart';
import 'package:qunleashed/pages/apps/manager/widgets/apps_table.dart';
import 'package:qunleashed/theme/theme.dart';

/// That a column header fits the row it is given.
///
/// `appsTableColumns` hands out fixed widths, and one of them - 74 for the
/// version column - was smaller than the label it has to hold: "VERSION"
/// renders at 74.2, so the header overflowed its row by 8.2 pixels at *every*
/// window width. Debug paints the striped bar over it; release clips the last
/// column silently. Nothing in `test/` had ever built that widget, which is why
/// it went unseen from the day the column was added.
///
/// A label is a translated string and a column width is a number somebody
/// picked, so no arithmetic keeps the two in step for 30 locales. The header
/// ellipsizes instead, and this file is what says it does: every column set in
/// `lib/` at every width a window can be.
void main() {
  late QAppColors colors;

  setUp(() {
    colors = buildAppTheme(
      Brightness.dark,
      const Color(0xFFCC241D),
    ).extension<QAppColors>()!;
  });

  /// Builds [cols] as a header at [width] and returns whatever it threw.
  Future<Object?> render(
    WidgetTester tester,
    List<SizedColumn> cols,
    double width, {
    String sortKey = 'name',
  }) async {
    await tester.binding.setSurfaceSize(Size(width, 400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ArchiveColumnHeader(
            cols: cols,
            sortKey: sortKey,
            sortAsc: true,
            onSort: (_) {},
            colors: colors,
          ),
        ),
      ),
    );
    return tester.takeException();
  }

  // 320 is the narrowest phone the project declares; the rest are the
  // breakpoints `appsTableColumns` switches on, plus a desktop window.
  const widths = [320.0, 360.0, 461.0, 600.0, 900.0, 1200.0, 1600.0];

  group('the apps table header', () {
    for (final width in widths) {
      testWidgets('fits at $width', (tester) async {
        expect(await render(tester, appsTableColumns(width), width), isNull);
      });
    }

    // The active column carries a sort arrow on top of its label, so it is the
    // one with the least room. Each of them gets a turn.
    for (final key in const ['name', 'folder', 'version', 'size']) {
      testWidgets('fits with $key sorted', (tester) async {
        expect(
          await render(tester, appsTableColumns(600), 600, sortKey: key),
          isNull,
        );
      });
    }
  });

  // Fitting is not the same as being readable: the header ellipsizes now, so a
  // column that is too narrow truncates its label instead of overflowing, and
  // the layout is legal either way. These are what hold the widths in
  // `appsTableColumns` to the labels they have to show - without them the
  // version column could go back to 74 and read "VERSIO...".
  group('the apps table labels', () {
    for (final key in const ['name', 'folder', 'version', 'size']) {
      testWidgets('are whole with $key sorted', (tester) async {
        expect(
          await render(tester, appsTableColumns(900), 900, sortKey: key),
          isNull,
        );

        for (final label in const [
          'NAME / FOLDER',
          'FOLDER',
          'VERSION',
          'SIZE',
        ]) {
          final text = tester.renderObject<RenderParagraph>(find.text(label));
          expect(
            text.didExceedMaxLines,
            isFalse,
            reason: '$label was truncated with $key sorted',
          );
        }
      });
    }
  });

  // These size themselves from the label and the content, so they were never
  // the ones overflowing - kept so the shared header cannot be changed for one
  // caller and broken for the other.
  group('the archive table headers', () {
    for (final category in ArchiveCategory.values) {
      testWidgets('fit for $category', (tester) async {
        for (final width in widths) {
          expect(
            await render(
              tester,
              visibleColumns(category, width, const []),
              width,
            ),
            isNull,
            reason: '$category at $width',
          );
        }
      });
    }
  });
}
