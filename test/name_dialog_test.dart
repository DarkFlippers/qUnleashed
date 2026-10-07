// The shared name prompt, which is the only one in the app that validates.
//
// Before #266 this behaviour lived in a private class inside the seed page, so
// the only cover it had was the seed page's own save chain. That chain did
// test the live check and the disabled confirm, by typing `bad/name` and 70
// characters - what it never reached was the silence on an empty field, the
// trimming of the result, the pre-selection, and the keyboard submit. Those
// four were untested behaviour in a private class; they would now be untested
// behaviour in a shared component with seven callers queued behind it, which
// is why they are here.
//
// Each test is a thing that, if it broke, would hand the caller a name it
// never approved - which for every caller means a file written under it.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qunleashed/components/dialogs/name.dart';
import 'package:qunleashed/services/localization/l10n.dart';
import 'package:qunleashed/theme/theme.dart';

/// An open dialog, and the future it will answer with.
///
/// A class and not a bare `Future<String?>` because an `async` helper flattens
/// a returned future into its own: `await open(...)` would then wait for the
/// dialog nobody has answered yet, which deadlocks every test here.
class Prompt {
  Prompt(this.answer);

  final Future<String?> answer;
}

/// Opens the dialog and hands back the future it will complete with.
///
/// The dialog is pushed from a button rather than built as `home`, because
/// `Navigator.pop` is how it answers and a dialog that is the root has nothing
/// to pop.
Future<Prompt> open(
  WidgetTester tester, {
  String initial = 'suggested',
  String? Function(String)? validate,
  String? helperText,
  String? hintText,
  String? suffixText,
  String? confirmLabel,
  String? cancelLabel,
}) async {
  late Future<String?> result;
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      // The dialog reads the app's colour extension, so a bare MaterialApp
      // renders it as a null check on a missing theme.
      theme: buildAppTheme(Brightness.dark, const Color(0xFFFF8A00)),
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () {
            result = QNameDialog.show(
              context,
              title: 'Name the File',
              initial: initial,
              validate: validate,
              helperText: helperText,
              hintText: hintText,
              suffixText: suffixText,
              confirmLabel: confirmLabel,
              cancelLabel: cancelLabel,
            );
          },
          child: const Text('open'),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return Prompt(result);
}

/// The confirm button, found by its label.
///
/// By label and not by position - which means none of these finders can see
/// the two actions swapped. `_actionOrder` is what covers that.
Finder confirm([String label = 'OK']) => find.widgetWithText(TextButton, label);

Finder cancel() => find.widgetWithText(TextButton, 'Cancel');

bool enabled(WidgetTester tester, Finder button) =>
    tester.widget<TextButton>(button).onPressed != null;

/// The dialog's action labels left to right, which is the only way to see a
/// swap.
///
/// Scoped to the `AlertDialog`: the button that opens it is a `TextButton`
/// too, and an unscoped finder picks it up first.
List<String> actionOrder(WidgetTester tester) => tester
    .widgetList<TextButton>(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextButton),
      ),
    )
    .map((b) => (b.child as Text?)?.data ?? '')
    .where((label) => label.isNotEmpty)
    .toList();

/// Refuses anything with a `?` in it, which is the shape every real caller's
/// rule has: a message, or null.
String? noQuestionMarks(String value) =>
    value.contains('?') ? 'No question marks' : null;

void main() {
  testWidgets('returns the name that was typed', (tester) async {
    final prompt = await open(tester);

    await tester.enterText(find.byType(TextField), 'garage');
    await tester.pump();
    await tester.tap(confirm());
    await tester.pumpAndSettle();

    expect(await prompt.answer, 'garage');
  });

  testWidgets('returns the suggestion when nothing is typed', (tester) async {
    // The common path for every caller: a suggestion is offered because it is
    // usually the right answer, and confirming it must not need an edit first.
    final prompt = await open(tester);

    await tester.tap(confirm());
    await tester.pumpAndSettle();

    expect(await prompt.answer, 'suggested');
  });

  testWidgets('selects the suggestion so typing replaces it', (tester) async {
    // Filled but not selected means the user who wants their own name has to
    // clear the field first, and the one who does not notice gets
    // `suggestedgarage`.
    await open(tester);

    final field = tester.widget<TextField>(find.byType(TextField));
    expect(
      field.controller!.selection,
      const TextSelection(baseOffset: 0, extentOffset: 'suggested'.length),
    );

    // And the field holds focus without being tapped. These are one feature,
    // not two: without `autofocus` the keyboard does not appear, so the user
    // taps the field, and the tap collapses the selection asserted above - so
    // dropping it defeats the pre-selection while leaving it measurable.
    expect(
      tester.widget<EditableText>(find.byType(EditableText)).focusNode.hasFocus,
      isTrue,
    );
  });

  testWidgets('returns the name trimmed', (tester) async {
    // The value was judged trimmed - `validate` sees the raw text but every
    // real rule trims - so returning the raw text hands back a name that was
    // never the one approved, and writes a file with a trailing space in its
    // name.
    final prompt = await open(tester);

    await tester.enterText(find.byType(TextField), '  garage  ');
    await tester.pump();
    await tester.tap(confirm());
    await tester.pumpAndSettle();

    expect(await prompt.answer, 'garage');
  });

  testWidgets('answers null when dismissed', (tester) async {
    final prompt = await open(tester);

    await tester.tap(cancel());
    await tester.pumpAndSettle();

    expect(await prompt.answer, isNull);
  });

  group('a name the caller refuses', () {
    testWidgets('is said in words and cannot be confirmed', (tester) async {
      await open(tester, validate: noQuestionMarks);

      await tester.enterText(find.byType(TextField), 'what?');
      await tester.pump();

      expect(find.text('No question marks'), findsOneWidget);
      expect(enabled(tester, confirm()), isFalse);
    });

    testWidgets('cannot be submitted from the keyboard either', (tester) async {
      // The disabled button is not the whole gate: the field's own submit
      // bypasses it, which is how a rule gets enforced on screen and not in
      // the result.
      final prompt = await open(tester, validate: noQuestionMarks);

      await tester.enterText(find.byType(TextField), 'what?');
      await tester.pump();
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(find.byType(TextField), findsOneWidget, reason: 'still open');

      // And the dialog is still usable afterwards rather than wedged.
      await tester.enterText(find.byType(TextField), 'fine');
      await tester.pump();
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(await prompt.answer, 'fine');
    });

    testWidgets('becomes confirmable as soon as it is fixed', (tester) async {
      // The check runs on every keystroke, which is the point of the dialog
      // being stateful. A check that ran once on open would leave the button
      // dead for the rest of the dialog's life.
      await open(tester, validate: noQuestionMarks);

      await tester.enterText(find.byType(TextField), 'what?');
      await tester.pump();
      await tester.enterText(find.byType(TextField), 'what');
      await tester.pump();

      expect(find.text('No question marks'), findsNothing);
      expect(enabled(tester, confirm()), isTrue);
    });
  });

  group('an empty field', () {
    testWidgets('cannot be confirmed', (tester) async {
      await open(tester);

      await tester.enterText(find.byType(TextField), '');
      await tester.pump();

      expect(enabled(tester, confirm()), isFalse);
    });

    testWidgets('is refused even when the caller has no rule at all', (
      tester,
    ) async {
      // No `validate`, which is what the seven prompts being converted later
      // will pass. Empty is not a name on any storage this app writes to, so
      // the dialog refuses it rather than each caller having to.
      await open(tester, validate: null);

      await tester.enterText(find.byType(TextField), '   ');
      await tester.pump();

      expect(enabled(tester, confirm()), isFalse);
    });

    testWidgets('is not complained about', (tester) async {
      // An error on a field the user has only just cleared reads as a
      // complaint about their typing. The disabled button already says it.
      await open(tester, validate: (_) => 'always wrong');

      await tester.enterText(find.byType(TextField), '');
      await tester.pump();

      expect(find.text('always wrong'), findsNothing);
      expect(enabled(tester, confirm()), isFalse);
    });

    testWidgets('is never handed to the caller rule', (tester) async {
      // Spelled as a separate test from the one above because the two have
      // different fixes: not showing the message is presentation, not *asking*
      // is what lets every caller's rule skip its own empty case.
      final seen = <String>[];
      await open(
        tester,
        validate: (value) {
          seen.add(value);
          return null;
        },
      );

      await tester.enterText(find.byType(TextField), '  ');
      await tester.pump();

      expect(seen, isNot(contains('  ')));
    });
  });

  testWidgets('shows the extension without putting it in the field', (
    tester,
  ) async {
    // What makes the field hold a *base* name. If the suffix reached the
    // controller the caller would append its own and write `gate.sub.sub`.
    final prompt = await open(tester, suffixText: '.sub', initial: 'gate');

    expect(find.text('.sub'), findsOneWidget);
    await tester.tap(confirm());
    await tester.pumpAndSettle();

    expect(await prompt.answer, 'gate');
  });

  testWidgets('shows the helper text and both caller labels', (tester) async {
    // `show` forwards nine parameters by hand, so each is a place one can be
    // dropped and still compile. `cancelLabel` was the one nothing passed.
    await open(
      tester,
      helperText: 'Saved in /ext/subghz',
      confirmLabel: 'Save to Flipper',
      cancelLabel: 'Keep Looking',
    );

    expect(find.text('Saved in /ext/subghz'), findsOneWidget);
    expect(confirm('Save to Flipper'), findsOneWidget);
    expect(confirm(), findsNothing, reason: 'the default label is replaced');
    expect(confirm('Keep Looking'), findsOneWidget);
    expect(cancel(), findsNothing, reason: 'and so is the cancel label');
  });

  testWidgets('shows the hint inside an empty field', (tester) async {
    // Not used by the seed page, and the reason the shared dialog has it: all
    // seven prompts waiting to adopt this pass one, and `helperText` is not a
    // substitute because it renders underneath rather than inside.
    await open(tester, initial: '', hintText: 'folder name');

    expect(find.text('folder name'), findsOneWidget);
  });

  testWidgets('puts Cancel before the confirm action', (tester) async {
    // Every other finder in this file matches by label, so a swap is invisible
    // to all of them. Worth one assertion: the confirm writes a file.
    await open(tester, confirmLabel: 'Save');

    expect(actionOrder(tester), ['Cancel', 'Save']);
  });

  testWidgets('hands the caller rule the text untrimmed', (tester) async {
    // The documented contract, so a rule may refuse a surrounding space rather
    // than silently accept the tidying `show` does on the way out. No current
    // caller cares, which is exactly why nothing would notice it breaking.
    final seen = <String>[];
    await open(
      tester,
      validate: (value) {
        seen.add(value);
        return null;
      },
    );

    await tester.enterText(find.byType(TextField), ' gate ');
    await tester.pump();

    expect(seen, contains(' gate '));
  });
}
