// The one way to say how big the window a case renders in is.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Sizes the window at [size] logical pixels, `MediaQuery` included.
///
/// **Not `tester.binding.setSurfaceSize`**, which is the trap #414 is about.
/// That stores a `_surfaceSize` which feeds `createViewConfigurationFor` and
/// so the render view's constraints. `MediaQuery` comes from somewhere else
/// entirely: the `View` widget wraps its child in `MediaQuery.fromView`, and
/// `MediaQueryData.fromView` computes its size as the view's `physicalSize`
/// over its `devicePixelRatio` - nothing on that path consults the surface.
/// So a case that asked for 500x900 laid its tree out at 500x900 while
/// `MediaQuery.sizeOf` went on answering the binding's default 800x600, and
/// anything reading the query ran the wrong layout entirely.
///
/// That is not a hypothetical: `FlipperRootScaffold.isWide` is
/// `MediaQuery.sizeOf(context)`, and 800 by 600 is wide. Every case in
/// `shell_rebuild_test.dart` had been running on the desktop rail, the three
/// named for a narrow window and the one named for a layout flip included -
/// where both sizes read as wide and no flip happened. One of its assertions
/// was wrong under the real narrow layout.
///
/// `flutter_test`'s own doc for `setSurfaceSize` points at
/// `TestFlutterView.physicalSize` too - "Instead of this method, consider
/// setting [TestFlutterView.physicalSize], which works for any view" - but
/// for a different reason, multi-view support, with a `TODO` to deprecate it.
/// The `MediaQuery` half above is this project's own finding and not
/// something the framework says.
///
/// `devicePixelRatio` is the part that is easy to miss and the reason this is
/// a function rather than two lines in a file's own helper: the binding's
/// default is **3**, so a `physicalSize` of 500 without it is a 167 dp
/// window - a phone-width tree in a file whose name says desktop.
///
/// Call it again in the same case to resize; the teardown is idempotent, and
/// a mid-case call is what a layout flip is.
///
/// `test/view_size_budget_test.dart` is what keeps the other spelling out.
void sizeView(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}
