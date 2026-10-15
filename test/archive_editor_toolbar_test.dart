import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qunleashed/pages/archive/editor/toolbar.dart';
import 'package:re_editor/re_editor.dart';

/// Where the code field sits, so that a followed menu has a real leader and
/// the rect handed to `show` describes something on screen.
const Rect _fieldRect = Rect.fromLTWH(16, 64, 300, 400);

/// Somewhere inside the field, standing in for the pointer.
const Offset _anchor = Offset(120, 180);

late SelectionToolbarController _toolbar;
late BuildContext _editorContext;
late CodeLineEditingController _editing;
late ValueNotifier<bool> _visibility;
late LayerLink _layerLink;

/// Pumps the tree the editor has around its selection menu.
///
/// Windows rather than the default Android, because the right click this
/// covers only happens on desktop and `AdaptiveTextSelectionToolbar` builds a
/// different widget per `Theme.of(context).platform` - on Android these cases
/// would measure a toolbar no desktop user ever sees.
///
/// [withEditor] false swaps the editor out for something else, the way the
/// page does when the hex view takes over or the route is popped.
Future<void> _pumpEditor(WidgetTester tester, {bool withEditor = true}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(platform: TargetPlatform.windows),
      home: withEditor
          ? EditorSelectionMenuScope(
              builder: (toolbar) {
                _toolbar = toolbar;
                return Builder(
                  builder: (context) {
                    _editorContext = context;
                    return Stack(
                      children: [
                        Positioned(
                          left: _fieldRect.left,
                          top: _fieldRect.top,
                          child: CompositedTransformTarget(
                            link: _layerLink,
                            child: SizedBox(
                              width: _fieldRect.width,
                              height: _fieldRect.height,
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                );
              },
            )
          : const SizedBox.expand(),
    ),
  );
  await tester.pumpAndSettle();
}

/// Opens the menu with the arguments `CodeEditor` hands the controller.
///
/// A null [renderRect] is the desktop overlay's call; a rect is the mobile
/// one's.
Future<void> _show(
  WidgetTester tester,
  Offset anchor, {
  Rect? renderRect,
}) async {
  _toolbar.show(
    context: _editorContext,
    controller: _editing,
    anchors: TextSelectionToolbarAnchors(primaryAnchor: anchor),
    renderRect: renderRect,
    layerLink: _layerLink,
    visibility: _visibility,
  );
  await tester.pumpAndSettle();
}

Finder get _menu => find.byType(DesktopTextSelectionToolbar);

/// Where the menu actually paints.
///
/// Not the toolbar widget: its own box fills the overlay and sits at the
/// origin whatever the anchors say, so measuring that reads the same for
/// every placement.
Finder get _menuBody => find.text('Cut');

/// The opacity of the fade the menu is wrapped in, which is the only
/// [FadeTransition] anywhere above it.
double _opacity(WidgetTester tester) => tester
    .widget<FadeTransition>(
      find.ancestor(of: _menu, matching: find.byType(FadeTransition)),
    )
    .opacity
    .value;

void main() {
  setUp(() {
    _editing = CodeLineEditingController.fromText('one\ntwo');
    _visibility = ValueNotifier<bool>(true);
    _layerLink = LayerLink();
  });

  tearDown(() {
    _editing.dispose();
    _visibility.dispose();
  });

  // The desktop selection overlay in `re_editor` has no render rect to give -
  // a right click arrives here with null - and the package's own controller
  // dereferenced it, so the menu threw while the frame was building
  // (QUNLEASHED-D).
  testWidgets('a right click with no render rect opens the menu', (
    tester,
  ) async {
    await _pumpEditor(tester);
    await _show(tester, _anchor);

    expect(tester.takeException(), isNull);
    expect(_menu, findsOneWidget);
    expect(find.byType(CompositedTransformFollower), findsNothing);

    _toolbar.hide(_editorContext);
    await tester.pump();
    expect(_menu, findsNothing);
  });

  // Not just "a menu appeared": it has to appear under the pointer. The
  // anchors are the only thing placing it, and nothing else in the tree moves
  // between the two openings.
  testWidgets('the menu opens where the anchor says', (tester) async {
    await _pumpEditor(tester);
    await _show(tester, _anchor);
    final first = tester.getTopLeft(_menuBody);

    await _show(tester, _anchor + const Offset(100, 100));

    expect(tester.getTopLeft(_menuBody) - first, const Offset(100, 100));
  });

  // The two branches have to put the menu in the same pixels: with a rect the
  // follower's origin is the code field's top left and the offset cancels it,
  // which is why dropping the follower when there is no rect is a fix and not
  // a guess.
  testWidgets('a render rect lands the menu where no rect does', (
    tester,
  ) async {
    await _pumpEditor(tester);

    await _show(tester, _anchor, renderRect: _fieldRect);
    expect(find.byType(CompositedTransformFollower), findsOneWidget);
    final followed = tester.getTopLeft(_menuBody);

    await _show(tester, _anchor);

    expect(tester.getTopLeft(_menuBody), followed);
  });

  // The menu is built at zero opacity and faded in, so a menu that is never
  // told it is visible is a menu nobody can read - which `find.byType` alone
  // cannot tell apart from a working one.
  testWidgets('the menu is opaque once it has opened', (tester) async {
    await _pumpEditor(tester);
    await _show(tester, _anchor);

    expect(_opacity(tester), 1.0);

    _visibility.value = false;
    await tester.pumpAndSettle();
    expect(_opacity(tester), 0.0);
  });

  // Selecting everything is usually the step before copying it, so this is
  // the one button that does not dismiss.
  testWidgets('select all keeps the menu open', (tester) async {
    await _pumpEditor(tester);
    await _show(tester, _anchor);

    await tester.tap(find.text('Select all'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(_editing.selectedText, 'one\ntwo');
    expect(_menu, findsOneWidget);
  });

  // The menu is an entry in the root overlay, which outlives the editor's
  // route - so nothing but the scope's own teardown takes it down, and the
  // page has several ways out that would each have to remember to.
  testWidgets('the menu goes when the editor does', (tester) async {
    await _pumpEditor(tester);
    await _show(tester, _anchor);
    expect(_menu, findsOneWidget);

    await _pumpEditor(tester, withEditor: false);

    expect(tester.takeException(), isNull);
    expect(_menu, findsNothing);
  });

  // The scope hides the menu on its way out, and may do so when nothing is
  // open; the notifier it was listening to outlives the entry.
  //
  // The pump in the middle is what makes this case bite: the entry leaves the
  // tree on the next frame, so without it the menu is still listening and a
  // leaked listener looks fine.
  testWidgets('hiding twice, then a visibility change, is quiet', (
    tester,
  ) async {
    await _pumpEditor(tester);
    await _show(tester, _anchor);

    _toolbar.hide(_editorContext);
    _toolbar.hide(_editorContext);
    await tester.pump();

    _visibility.value = false;
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(_menu, findsNothing);
  });
}
