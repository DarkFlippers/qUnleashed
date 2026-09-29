// A ratchet on failures caught and then not written down anywhere.
//
// `catch (_) {}` is the shape: something failed, the catch ran, and nothing
// survives it - no log, no state, no exception. Whatever the UI was waiting on
// is still waiting, and a bug report has nothing in it. #118 was three
// firmware surfaces latched on "Checking…" until the app restarted, each
// behind one of these.
//
// This exists as much for what it stops as for what it counts. The log budget
// in `log_level_budget_test.dart` counts failures reported only at a level a
// release build drops, and its own header records the hole: deleting a counted
// log leaves a bare catch behind and lowers that number, so the cheapest way
// to go green was to make the code worse. It is not any more - the log falls,
// this rises, and the run is red either way. #117 asked for exactly this.
//
// ADR 0008 is the decision, and it is worth repeating here because the number
// invites the wrong reading: the target is the catches that leave a screen
// unresolved, not the count. A `mkdir` of a directory that already exists and
// a temp-file cleanup are both fine, and both are in the figures below.
//
// What it cannot see:
//
//  * A catch that logs at `info` and nothing else. That is a failure lost in a
//    release build just as surely, and it is the other ratchet's number.
//  * A catch that writes into a field nobody reads, or one the failure itself
//    prevents anyone from reaching. #110 is a whole area of those.
//  * `onError:` callbacks, `.catchError((_) => null)` and a `Future` simply
//    dropped. None of them is a catch clause, and all of them lose a failure.
//  * A `try` with no catch at all around something that cannot throw today.
//
// And one that makes it a shape rather than a measure: a body holding only a
// comment is empty to the parser. `pages/tools/infrared/local_repo.dart:612`
// is one, and its comment is the reason it is deliberate - a directory that
// cannot be created fails the files inside it, and those are counted where
// they are written.
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:flutter_test/flutter_test.dart';

import 'ratchet.dart';

/// What each area held when the ratchet went in. Lower one when a slice lands.
///
/// No triage behind these yet, unlike the log budget's. They are a ceiling
/// taken on the day, and the first pass through them is #118's shape: a catch
/// on a path the UI is waiting on.
const Map<String, int> kBudget = {
  // Was 21, then 17. Four went from `archive/storage.dart` - the last device
  // and the two favourites lists are the user's own choices, and each used to
  // vanish between launches with nothing said anywhere. Three more went from
  // `http/app_http.dart`: reading the cache, writing it, and the legacy file
  // left behind by a migration.
  //
  // The two that stay in each are the ones the code earns. An icon is fetched
  // again when it is missing; a 304 re-stamp that fails costs one revalidation
  // round trip and the body on disk is valid either way; and the temp file a
  // failed store tries to clean up is already being reported by the rethrow
  // above it.
  //
  // Then three more from `storage/paths.dart`: the walk behind Settings ->
  // Storage reported a size short by whatever it could not read, and the
  // clear beside it reported success over files it had left. Both count and
  // say so once now.
  //
  // What is left is eleven, and two of them are as deliberate as a bare catch
  // gets. `localization/controller.dart` adds a `WidgetsBinding` observer
  // that a plain unit test has no binding for, and reporting it would fire in
  // every one of them. `storage/fap_icons.dart` caches an app icon that is
  // fetched again when it is missing - the same trade the archive's icon
  // cache makes.
  // And three from `assembler/remote_build_service.dart`: a cancel the server
  // never heard, a reply that could not be read, and a refusal the server
  // would not explain. The user was told a build failed in all three; what
  // was missing every time was why.
  //
  // Five left, and none is a screen left waiting: the two above, two in
  // `logging.dart` that cannot report a failure to report, and the temp file
  // a failed cache write tries to clean up, which its own rethrow already
  // covers.
  'services': 8,
  // Was 12. Five went: a display that would not come up and said nothing
  // while the screen sat blank, a preview that failed the same way, a draft
  // folder left behind by "save as" and listed beside its own copy, and a
  // recording saved but not copied to the clipboard the user pressed for.
  //
  // The seven left are cleanup and retries, and each says so where it sits:
  // closing an API client before rebuilding it, two temp files deleted in a
  // `finally`, a `mkdir` of a folder that already exists, a directory that
  // could not be created and is counted where its files are written, and two
  // media-remote calls whose own bridge already logs.
  'pages/tools': 7,
  // The apps catalog and installer. Was 11 - the cached-catalogue loop in
  // `manifest_registry.dart` reads entry by entry now and says what it
  // dropped, which is the first half of #138. The four all-or-nothing list
  // decodes in `catalog_api.dart` are the other half and are not these.
  'pages/apps': 10,
  'pages/archive': 3,
  // #118 was this area and has been dealt with; what is left is not that
  // shape.
  'pages/devices': 2,
  'pages/flibler': 1,
  'components': 1,
};

const String kAdr =
    'https://github.com/DarkFlippers/qUnleashed/blob/main/docs/adr/'
    '0008-swallowed-errors.md';

/// Collects catch clauses whose body does nothing.
class _BareCatchVisitor extends RecursiveAstVisitor<void> {
  _BareCatchVisitor(this.unit);

  final CompilationUnit unit;
  final List<int> lines = [];

  @override
  void visitCatchClause(CatchClause node) {
    // The analyzer decides what a catch clause is, which is why this parses.
    // Dart spells an extension target and a mixin constraint `on Type {`,
    // exactly like a typed catch, and a text scan would count those too.
    if (node.body.statements.isEmpty) {
      lines.add(unit.lineInfo.getLocation(node.offset).lineNumber);
    }
    super.visitCatchClause(node);
  }
}

/// The lines of the counted clauses in [unit], in source order.
List<int> bareCatchLines(CompilationUnit unit) {
  final visitor = _BareCatchVisitor(unit);
  unit.accept(visitor);
  return visitor.lines;
}

/// Parses [source] and counts, for the rule's own tests.
List<int> linesIn(String source) => bareCatchLines(parseUnit(source));

void main() {
  group('the rule', () {
    test('is a catch that does nothing', () {
      expect(linesIn('void f() { try { g(); } catch (_) {} }'), hasLength(1));
      expect(linesIn('void f() { try { g(); } catch (e) {} }'), hasLength(1));
      expect(
        linesIn('void f() { try { g(); } on E catch (_) {} }'),
        hasLength(1),
      );
      expect(linesIn('void f() { try { g(); } on E {} }'), hasLength(1));
    });

    test('is not a catch that does something with it', () {
      expect(
        linesIn('void f() { try { g(); } catch (e) { log(e); } }'),
        isEmpty,
      );
      expect(
        linesIn('void f() { try { g(); } catch (_) { return; } }'),
        isEmpty,
      );
      expect(
        linesIn('void f() { try { g(); } catch (_) { rethrow; } }'),
        isEmpty,
      );
    });

    // A comment is not a statement, so a body that only explains itself is
    // empty here. That is the right answer - the explanation is why a budget
    // entry stays, not a reason the failure was recorded.
    test('counts a body that holds only a comment', () {
      expect(
        linesIn('void f() { try { g(); } catch (_) { /* on purpose */ } }'),
        hasLength(1),
      );
    });

    test('is not a finally that does nothing', () {
      expect(
        linesIn('void f() { try { g(); } finally {} }'),
        isEmpty,
        reason: 'a finally catches nothing, so it loses nothing',
      );
    });

    // `on Type {` is also how Dart spells an extension target and a mixin
    // constraint, and both are commonly empty.
    test('is not something that merely reads like one', () {
      expect(linesIn('extension E on S {}'), isEmpty);
      expect(linesIn('mixin M on B {}'), isEmpty);
    });

    test('follows the catch wherever it is nested', () {
      expect(
        linesIn('void f() { h(onTap: () { try { g(); } catch (_) {} }); }'),
        hasLength(1),
      );
      expect(
        linesIn(
          'void f() { try { g(); } catch (_) { try { h(); } catch (_) {} } }',
        ),
        hasLength(1),
        reason: 'the outer one does something: it tries again',
      );
    });

    test('reports the line the catch is on', () {
      expect(linesIn('void f() {\n  try { g(); }\n  catch (_) {}\n}'), [3]);
    });
  });

  test('no area swallows more failures than its budget', () {
    final result = countAcrossLib((unit, _) => bareCatchLines(unit));

    expectWithinBudget(
      counted: result.counted,
      budget: kBudget,
      sites: result.sites,
      budgetFile: 'test/bare_catch_budget_test.dart',
      why:
          'a catch with an empty body loses the failure entirely - no log, no '
          'state, no exception - so whatever the UI was waiting on waits '
          'forever and a bug report has nothing in it.\n'
          'If the failure is worth reporting, use warn or error. If it is '
          'genuinely best-effort, say which in a comment and raise kBudget in '
          'test/bare_catch_budget_test.dart.\n'
          'See $kAdr',
    );
  });
}
