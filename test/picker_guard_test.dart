// A guard on picker calls whose rejection has nowhere to land. Budget zero
// everywhere.
//
// No ordinal. The last three ratchets each claimed one and each was wrong -
// `picker_bytes_guard_test.dart` says "the eighth" and is the eleventh, and
// `ratchet.dart`'s header carried one that was also wrong until #375 took it
// out - because nothing checks a number that is only ever read by a human. The
// checkable claim is the one in `main`: `budget: const <String, int>{}`.
//
// QUNLEASHED-K: the file browser's "Upload files" called
// `FilePicker.platform.pickFiles` with no `try` around it, from a
// `ListTile.onTap` that did not await the future either. Android's picker
// answered `unknown_path` - the chosen item's provider handed back no stream,
// so `FilePickerDelegate` failed the whole pick rather than returning a file
// with a null path - and `_getPath` in `file_picker_io.dart` rethrows a
// `PlatformException` for that. With no `try` at the call site and no listener
// on the future, the rejection reached the zone: `PlatformDispatcher.onError`,
// reported fatal, app gone, behind a picker the user was still looking at.
//
// Three more sites had the same shape the day this went in - all three of them
// folder picks - and the pixel editor's was the instructive one: its three
// export entry points each have a `try`, and each awaited `_pickDestination()`
// one line *above* it.
//
// A guard rather than a budget, because this one has no legacy to drain. Ten
// `FilePicker.platform` calls sat under `lib/` when it went in, in seven
// files; six already caught for themselves and the four that did not moved in
// the same change, so zero was both the current count and the target.
//
// **#353 made it six calls in six files.** The five folder picks are one call
// now, in `components/folder_pick.dart`: the plugin's `getDirectoryPath`
// catches its own `PlatformException` on Android and iOS and answers null, so
// a refusal and a cancellation were the same value at every one of those
// sites, and the shim reaches past that Dart layer to the plugin's own method
// channel. It satisfies all four conditions below - the channel call and the
// delegation to the plugin are both awaited inside one unqualified catch that
// reports and does not rethrow - and what it hands its callers is null, never
// a rejection, which is why none of them has a `try` any more.
//
// **It holds the four things that put a listener on the rejection**, because
// any one of them missing is the incident again:
//
//  1. the call is awaited, so the enclosing `try` is on the stack when the
//     future rejects;
//  2. it is lexically inside a `try` body, in the same function;
//  3. that `try` has a clause that catches everything;
//  4. and that clause does not `rethrow`.
//
// Every one of those was a false negative in the first version of this file,
// which asked only (2). Reviews drove them out from a probe: `.then(g)` in a
// non-`async` body, `unawaited(...)`, a `finally` with no catch, and `on
// FormatException catch` each read as guarded while a `PlatformException` went
// straight to the zone - and the first of those is what a refactor to a `void`
// tap handler produces, which is how the incident was reached in the first
// place. The `finally` case is the codebase's own idiom one method over
// (`firmware_update_button.dart:201`), so it was the likeliest next write.
// (4) is about a function that reports and then answers null, where a
// `rethrow` reads as correct and is not; `rethrows`' own doc has which one and
// what moved after #353.
//
// **What it still does not hold is the handling.** That the catch says or keeps
// anything is not expressible here - `test/bare_catch_budget_test.dart`
// notices a catch that keeps nothing, and `test/caught_budget_test.dart` keeps
// the record from becoming noise. `test/unguarded_pick_test.dart` is what
// asserts a real site's catch produces a line and a sentence.
//
// An AST walk and not a regex, per ADR 0004: all three conditions are
// questions about nesting, and the site that made this worth writing was a call
// *next to* a `try` in a method that reads, line-wise, exactly like one inside
// it.
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:flutter_test/flutter_test.dart';

import 'ratchet.dart';

/// Whether [node] is a call on `FilePicker.platform`, however it was imported.
///
/// The prefixed form is why this is a predicate rather than a name check: one
/// `import 'package:file_picker/file_picker.dart' as fp;` would take a whole
/// file out of the count, and nobody adding that import would connect it to a
/// ratchet.
///
/// Deliberately not shared with `picker_bytes_guard_test.dart`, which matches
/// `pickFiles` by name with no target check and has unit tests pinning that.
/// This is the stricter of the two and belongs beside `isLogServiceCall` in
/// `ratchet.dart` the moment a second ratchet asks for it - which is that
/// file's own rule: extracted when the second and third arrive, not before.
bool isPickerCall(MethodInvocation node) {
  final target = node.target;
  if (target is PrefixedIdentifier) {
    return target.identifier.name == 'platform' &&
        target.prefix.name == 'FilePicker';
  }
  if (target is PropertyAccess) {
    final inner = target.target;
    return target.propertyName.name == 'platform' &&
        inner is PrefixedIdentifier &&
        inner.identifier.name == 'FilePicker';
  }
  return false;
}

/// Whether [node] is the expression of an `await`.
///
/// Condition (1). Without it the `try` around the call is off the stack by the
/// time the future rejects, so `.then(g)` and `unawaited(...)` inside a `try`
/// read as guarded and are not. `await` through a parenthesis or a cascade is
/// not a spelling any site uses, and treating it as unguarded is the stricter
/// direction.
bool isAwaited(AstNode node) {
  final parent = node.parent;
  return parent is AwaitExpression && parent.expression == node;
}

/// Whether [clause] is a guard: it catches every error and keeps it.
///
/// Conditions (3) and (4), together because neither is worth anything without
/// the other - a clause that catches everything and rethrows leaves the
/// rejection exactly where an `on`-typed clause does.
///
/// On (3): `on PlatformException catch (e)` would be enough for today's
/// Android path and for nothing else: the Linux picker throws a bare
/// `Exception` when no `zenity` is on the path, Windows a `WindowsException`,
/// and a missing plugin a `MissingPluginException`. Those have no common
/// supertype worth naming, so the only clause that can be shown to cover a
/// picker is the unqualified one.
bool guards(CatchClause clause) =>
    clause.exceptionType == null && !rethrows(clause.body);

/// Whether [body] hands the error straight back out again.
///
/// The second half of [guards], and the one a review asked for by name. It was
/// written for `_pickDestination` in the pixel editor, which returned a value
/// into three callers that each read null as "cancelled" - so a `rethrow`
/// there read as correct, because every one of those callers has a `try` of
/// its own one line below, and it would have put the crash back on all three
/// export paths with nothing in the suite noticing: the `try` is still there,
/// the budgets do not move, and no test mounts that page.
///
/// `pickFolder` inherited that contract and widened it to five callers, none
/// of which has a `try` at all now, so a `rethrow` in it is worse than it was
/// there - and no longer invisible either: `folder_pick_test.dart` asserts the
/// answer is null for a refusal on both halves of that function, and a
/// rejection from a `VoidCallback` fails those cases through the zone, while
/// `paint_export_name_test.dart` mounts the editor that nothing used to.
/// This condition is the half that reads the source rather than running it.
///
/// A `rethrow` in a *nested* catch inside the clause counts too, which is a
/// false positive. It is the stricter direction and no site has one.
bool rethrows(AstNode body) {
  final visitor = _RethrowVisitor();
  body.accept(visitor);
  return visitor.found;
}

class _RethrowVisitor extends RecursiveAstVisitor<void> {
  bool found = false;

  @override
  void visitRethrowExpression(RethrowExpression node) => found = true;
}

/// Whether [node] sits in the body of a `try` that guards, in the same
/// function.
///
/// Condition (2), and it asks [guards] for (3) and (4) rather than answering
/// position alone - so a node that *is* inside a try body still counts when
/// every clause on that try is `on`-typed or rethrows. A `catch` or `finally` clause is deliberately not a
/// body: a picker call there is as unguarded as one with no `try` in sight, and
/// it reads as covered. A `try` whose only clause is a `finally` is likewise
/// not a guard - it runs the clause and lets the error past, which
/// `bare_catch_budget_test.dart` states as "a finally catches nothing, so it
/// loses nothing".
///
/// A closure boundary ends the walk. A `try` outside a function expression does
/// not catch what the body throws when somebody calls it later, and the honest
/// answer to "is this one of ours?" for a picker inside a callback is yes. A
/// `try` *inside* the closure still guards, because the walk reaches it first.
///
/// Two blind spots remain, both false negatives, and neither is empty by
/// accident:
///
///  * **A picker reached through a local.** `final p = FilePicker.platform;`
///    then `await p.pickFiles()` is invisible to [isPickerCall], with or
///    without a `try`. Resolving it needs types, and this runs on the parsed
///    unit; the unit test below pins the current answer so the gap is at least
///    written down.
///  * **A picker wrapped one level down**, in a helper that every caller awaits
///    inside a `try`. That is a real way to be safe and this counts it anyway,
///    which is the stricter direction. Zero is reachable because all six sites
///    under `lib/` catch for themselves - `folder_pick.dart`'s included, which
///    is that shape and passes because the catch is in the same function.
bool isInsideTryBody(AstNode node) {
  AstNode child = node;
  for (AstNode? parent = node.parent; parent != null; parent = parent.parent) {
    if (parent is TryStatement && parent.body == child) {
      return parent.catchClauses.any(guards);
    }
    if (parent is FunctionExpression) return false;
    child = parent;
  }
  return false;
}

/// Collects the line of every invocation [matches] accepts.
///
/// Shared by the two rules in this file, which differ only in the predicate:
/// one asks whether a picker call is guarded, the other whether a folder pick
/// went round the shim. The offset-to-line conversion was written twice before
/// it was written three times.
class _LineVisitor extends RecursiveAstVisitor<void> {
  _LineVisitor(this.unit, this.matches);

  final CompilationUnit unit;
  final bool Function(MethodInvocation) matches;
  final List<int> lines = [];

  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (matches(node)) {
      lines.add(unit.lineInfo.getLocation(node.offset).lineNumber);
    }
    super.visitMethodInvocation(node);
  }
}

/// The lines in [unit] where [matches] holds.
List<int> linesWhere(
  CompilationUnit unit,
  bool Function(MethodInvocation) matches,
) {
  final visitor = _LineVisitor(unit, matches);
  unit.accept(visitor);
  return visitor.lines;
}

/// The one file allowed to ask the plugin for a folder.
const Set<String> kFolderPickShim = {'components/folder_pick.dart'};

/// Where [unit] asks the plugin for a folder instead of asking the shim.
///
/// The second rule in this file, and the one that keeps the first one's
/// account true. `pickFolder` exists because `getDirectoryPath` catches its
/// own `PlatformException` on Android and iOS and answers null, so a refusal
/// read as a cancellation at five surfaces (#353) - and **a sixth surface
/// written the old way would pass everything else in this suite**: it would be
/// awaited inside its own guarding `try` for the rule above, `caught_budget`
/// does not move for a catch that only shows a sentence, and the refusal would
/// be invisible again at that one site with the whole run green.
///
/// Zero everywhere but `folder_pick.dart`, which is the desktop half of the
/// shim itself. A `budget` rather than an exemption would be the wrong shape:
/// the number that matters is not how many of these there are but whether any
/// is outside the one file that is allowed one.
///
/// [path] is matched on its tail, as `isExempt` does it, so the worktree's
/// prefix does not enter into it.
List<int> pluginFolderPicksIn(CompilationUnit unit, String path) {
  if (isExempt(path, kFolderPickShim)) return const [];
  return linesWhere(unit, isPluginFolderPick);
}

/// Whether [node] asks a platform for a folder rather than asking the shim.
///
/// Two spellings, because the shim demonstrated the second one. The plugin's
/// `getDirectoryPath` is the obvious way, and a `dir` sent straight down a
/// method channel - which is what `folder_pick.dart` does, and what anyone
/// copying it would do - is the other. The channel's *name* is not checked:
/// `dir` on any channel is either this plugin or something that wants the same
/// review, and matching the name would miss a copy that spelt it differently.
bool isPluginFolderPick(MethodInvocation node) {
  if (node.methodName.name == 'getDirectoryPath') return isPickerCall(node);
  if (node.methodName.name != 'invokeMethod') return false;
  final arguments = node.argumentList.arguments;
  final first = arguments.isEmpty ? null : arguments.first;
  return first is SimpleStringLiteral && first.value == 'dir';
}

/// The `what:` tag of every `pickFolder(...)` call in [unit], by line.
///
/// The sentence on screen carries no cause and two of the five surfaces now
/// share it, so the tag is what tells one report from another - and
/// `caught_budget_test.dart` writes that down as the reason the five lines
/// collapsing into one function is not a loss. Two surfaces sharing a tag
/// would cost more than the name: `LogService`'s fold drops a *consecutive*
/// identical body, so a failure at one would hide a failure at the other.
///
/// A tag that is not a plain string literal comes back as null, and the test
/// below fails on it rather than skipping it. Nothing needs to interpolate
/// one, and a tag this cannot read is a tag nothing holds.
Map<int, String?> folderPickTagsIn(CompilationUnit unit) {
  final visitor = _FolderPickTagVisitor(unit);
  unit.accept(visitor);
  return visitor.tags;
}

/// Whether [tag] is the `[Area] what it was doing` form `guarded()` uses.
///
/// CLAUDE.md's shape for a kept line, and what makes a report greppable by
/// area. Only the bracket is checked - the area names are not a closed set.
bool isAreaTag(String tag) => tag.startsWith('[') && tag.contains('] ');

class _FolderPickTagVisitor extends RecursiveAstVisitor<void> {
  _FolderPickTagVisitor(this.unit);

  final CompilationUnit unit;
  final Map<int, String?> tags = {};

  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (node.methodName.name == 'pickFolder' && node.target == null) {
      final line = unit.lineInfo.getLocation(node.offset).lineNumber;
      tags[line] = _tagOf(node.argumentList);
    }
    super.visitMethodInvocation(node);
  }

  static String? _tagOf(ArgumentList arguments) {
    final value = namedArgument(arguments, 'what')?.argumentExpression;
    return value is SimpleStringLiteral ? value.value : null;
  }
}

/// Where [unit] calls the picker with no listener on the rejection, or nothing.
///
/// [path] is unused; the signature is [countAcrossLib]'s.
List<int> unguardedPickersIn(CompilationUnit unit, String path) => linesWhere(
  unit,
  (node) => isPickerCall(node) && !(isAwaited(node) && isInsideTryBody(node)),
);

void main() {
  test('every picker call is awaited inside a try that catches', () {
    final found = countAcrossLib(unguardedPickersIn);
    expectWithinBudget(
      counted: found.counted,
      budget: const <String, int>{},
      sites: found.sites,
      budgetFile: 'test/picker_guard_test.dart',
      why:
          'A picker rejects - unknown_path on an Android file pick, a missing '
          'zenity on Linux, a missing plugin anywhere - and these are reached '
          'from taps that do not await, so an uncaught rejection is a fatal '
          'error and the app dies behind the dialog (QUNLEASHED-K). Await the '
          'call inside a try whose catch is unqualified, record the failure at '
          'LogService.caught, and show commonPickFailed. A .then, an '
          'unawaited, a finally with no catch and a narrow `on` clause each '
          'leave the rejection exactly where the incident left it.',
    );
  });

  // The two rules below read the whole of `lib/` once between them, in a
  // `setUpAll`: `countAcrossLib` runs `git ls-files` and parses every file,
  // which is ~400ms a walk, and the tags fall out of the same visit as the
  // call sites. The rule above keeps its own walk - its visitor answers a
  // different question about the same nodes, and merging all three would
  // trade one number in a budget failure for three.
  late ({Map<String, int> counted, Map<String, List<String>> sites}) found;
  late Map<String, List<String>> tags;
  late List<String> unreadableTags;

  setUpAll(() {
    final collected = <String, List<String>>{};
    final unreadable = <String>[];
    found = countAcrossLib((unit, path) {
      folderPickTagsIn(unit).forEach((line, tag) {
        if (tag == null) {
          unreadable.add('$path:$line');
        } else {
          collected.putIfAbsent(tag, () => <String>[]).add('$path:$line');
        }
      });
      return pluginFolderPicksIn(unit, path);
    });
    tags = collected;
    unreadableTags = unreadable;
  });

  test('every folder pick goes through the shim', () {
    expectWithinBudget(
      counted: found.counted,
      budget: const <String, int>{},
      sites: found.sites,
      budgetFile: 'test/picker_guard_test.dart',
      why:
          'The plugin catches its own PlatformException in getDirectoryPath '
          'and answers null on Android and iOS, so a refused folder pick is '
          'indistinguishable from a cancelled one and five surfaces said '
          'nothing at all (#353). components/folder_pick.dart reaches the '
          "plugin's own method channel instead, which sees the refusal, and "
          'it is the only file allowed to call getDirectoryPath. Call '
          'pickFolder(context, what: ..., dialogTitle: ...) - it never '
          'rejects, it records the failure and it shows the sentence, so the '
          'site needs no try of its own.',
    );
  });

  test('and reports under a tag no other surface uses', () {
    expect(
      unreadableTags,
      isEmpty,
      reason:
          'the what: argument has to be a plain string literal, or nothing '
          'can hold that the surfaces stay apart in a report',
    );
    // The vacuity guard. Five sites pick a folder today; this fails on a
    // walk that found none rather than passing over an empty lib/.
    expect(
      tags,
      hasLength(greaterThanOrEqualTo(5)),
      reason: 'expected the five folder picks, found ${tags.length} tags',
    );
    expect(
      {
        for (final entry in tags.entries)
          if (entry.value.length > 1) entry.key: entry.value,
      },
      isEmpty,
      reason:
          'two surfaces sharing a what: tag are one line in a report, and '
          "LogService's fold drops the second of two consecutive identical "
          'bodies - so a failure at one hides a failure at the other',
    );
    expect(
      tags.keys.where((tag) => !isAreaTag(tag)),
      isEmpty,
      reason:
          'a kept line reads "[Area] what it was doing", as guarded() takes '
          'it and CLAUDE.md writes it - that is what makes a report '
          'greppable by area',
    );
  });

  group('what counts as an unguarded picker', () {
    List<int> linesIn(String source) =>
        unguardedPickersIn(parseUnit(source), 'lib/pages/x.dart');

    test('the shape that shipped the bug', () {
      expect(
        linesIn('f() async => FilePicker.platform.pickFiles();'),
        hasLength(1),
      );
    });

    test('every method on the picker, not just the one that crashed', () {
      // Three of the four sites this went in with were folder picks, and the
      // rule covers every method rather than the one that crashed because
      // where each can reject differs by platform: `saveFile` rejects the way
      // `pickFiles` does, while `getDirectoryPath` on Android and iOS catches
      // its own `PlatformException` and answers null. That last one is why
      // `folder_pick.dart` calls the plugin's channel rather than its Dart
      // layer (#353) - but this method is still counted, because the one call
      // left to it is the desktop half of that shim and a second one would
      // most likely be a site going back to the swallow.
      expect(
        linesIn('f() async => FilePicker.platform.getDirectoryPath();'),
        hasLength(1),
      );
      expect(
        linesIn('f() async => FilePicker.platform.saveFile();'),
        hasLength(1),
      );
    });

    test('a prefixed import, which a name check would miss', () {
      expect(
        linesIn('f() async => fp.FilePicker.platform.pickFiles();'),
        hasLength(1),
      );
    });

    test('awaited inside a try that catches, which is the whole point', () {
      expect(
        linesIn(
          'f() async { try { await FilePicker.platform.pickFiles(); }'
          ' catch (e) {} }',
        ),
        isEmpty,
      );
    });

    // The four shapes a review drove out of the first version of this file,
    // which asked only "is it lexically inside a try". Each read as guarded
    // while a PlatformException went straight to the zone.
    test('not awaited is not guarded, whatever wraps it', () {
      // `.then` in a non-async body is what a refactor to a `void` tap
      // handler produces - which is how the incident was reached.
      expect(
        linesIn(
          'f() { try { FilePicker.platform.pickFiles().then(g); }'
          ' catch (e) {} }',
        ),
        hasLength(1),
      );
      expect(
        linesIn(
          'f() { try { unawaited(FilePicker.platform.pickFiles()); }'
          ' catch (e) {} }',
        ),
        hasLength(1),
      );
    });

    test('a try with no catch is not a guard', () {
      // A finally runs its clause and lets the error past. It is also the
      // idiom one method over in firmware_update_button.dart, which releases a
      // flag this way - so it was the likeliest next write.
      expect(
        linesIn(
          'f() async { try { await FilePicker.platform.pickFiles(); }'
          ' finally { g(); } }',
        ),
        hasLength(1),
      );
    });

    test('a catch that rethrows is not a guard', () {
      expect(
        linesIn(
          'f() async { try { await FilePicker.platform.getDirectoryPath(); }'
          ' catch (e) { report(e); rethrow; } }',
        ),
        hasLength(1),
      );
    });

    test('a narrow on clause does not cover a picker', () {
      // The platforms throw four unrelated types, so only the unqualified
      // clause can be shown to catch one.
      expect(
        linesIn(
          'f() async { try { await FilePicker.platform.pickFiles(); }'
          ' on FormatException catch (e) {} }',
        ),
        hasLength(1),
      );
      // Narrow first and catch-all second is the plotter's shape, and counts.
      expect(
        linesIn(
          'f() async { try { await FilePicker.platform.pickFiles(); }'
          ' on FormatException catch (e) {} catch (e) {} }',
        ),
        isEmpty,
      );
    });

    test('a catch or a finally clause is not a guard', () {
      // It reads as covered and is not: a throw from here leaves the same way
      // as one with no try in sight.
      expect(
        linesIn(
          'f() async { try {} catch (e)'
          ' { await FilePicker.platform.pickFiles(); } }',
        ),
        hasLength(1),
      );
      expect(
        linesIn(
          'f() async { try {} finally'
          ' { await FilePicker.platform.pickFiles(); } }',
        ),
        hasLength(1),
      );
    });

    test('a closure inside a try is not covered by it', () {
      // The body runs when somebody calls it, which can be long after the try
      // returned - and the onTap that shipped the bug is exactly this.
      expect(
        linesIn(
          'f() { try { g(() => FilePicker.platform.pickFiles()); }'
          ' catch (e) {} }',
        ),
        hasLength(1),
      );
    });

    test('a nested try still guards', () {
      expect(
        linesIn(
          'f() async { if (x) { try { for (final y in z)'
          ' { await FilePicker.platform.pickFiles(); } } catch (e) {} } }',
        ),
        isEmpty,
      );
    });

    test('a try inside the closure does guard', () {
      // The walk reaches it before the function boundary, which is the right
      // answer: that try is on the stack when the body runs.
      expect(
        linesIn(
          'f() { g(() async { try { await FilePicker.platform.pickFiles(); }'
          ' catch (e) {} }); }',
        ),
        isEmpty,
      );
    });

    test('not a comment, and not another API that picks something', () {
      expect(linesIn('// FilePicker.platform.pickFiles()\nf() {}'), isEmpty);
      expect(linesIn('f() async => FilePicker.pickFiles();'), isEmpty);
    });

    test('the shim is the one file that may ask the plugin', () {
      const call = 'f() async => FilePicker.platform.getDirectoryPath();';
      expect(pluginFolderPicksIn(parseUnit(call), 'lib/pages/x.dart'), [1]);
      expect(
        pluginFolderPicksIn(parseUnit(call), 'lib/components/folder_pick.dart'),
        isEmpty,
      );
      // The other methods are the first rule's business, not this one's.
      expect(
        pluginFolderPicksIn(
          parseUnit('f() async => FilePicker.platform.pickFiles();'),
          'lib/pages/x.dart',
        ),
        isEmpty,
      );
      // A guarded call counts here. Catching a refusal that never arrives is
      // exactly the shape #353 was.
      expect(
        pluginFolderPicksIn(
          parseUnit(
            'f() async { try { await FilePicker.platform.getDirectoryPath(); }'
            ' catch (e) { report(e); } }',
          ),
          'lib/pages/x.dart',
        ),
        hasLength(1),
      );
      // And the shim's own spelling, which is the one a copy would use.
      expect(
        pluginFolderPicksIn(
          parseUnit("f() async => c.invokeMethod<String>('dir', const {});"),
          'lib/pages/x.dart',
        ),
        hasLength(1),
      );
      expect(
        pluginFolderPicksIn(
          parseUnit("f() async => c.invokeMethod<String>('clear');"),
          'lib/pages/x.dart',
        ),
        isEmpty,
      );
    });

    test('a tag is read when it is a literal and refused when it is not', () {
      expect(
        folderPickTagsIn(
          parseUnit("f() => pickFolder(context, what: '[Area] the pick');"),
        ),
        {1: '[Area] the pick'},
      );
      expect(
        folderPickTagsIn(parseUnit('f() => pickFolder(context, what: tag);')),
        {1: null},
      );
      // A method of the same name on something else is not this function.
      expect(
        folderPickTagsIn(parseUnit("f() => x.pickFolder(what: 'a');")),
        isEmpty,
      );
      expect(isAreaTag('[Archive] the folder pick'), isTrue);
      expect(isAreaTag('the folder pick'), isFalse);
      expect(isAreaTag('[Archive]'), isFalse);
    });

    test('a picker reached through a local is invisible, guarded or not', () {
      // Pinned, not endorsed: this is the first blind spot named on
      // `isInsideTryBody`, and resolving it needs types this does not have.
      // Asserted in both directions so the gap cannot be mistaken for a rule
      // about where the call sits.
      expect(linesIn('f() async => p.pickFiles();'), isEmpty);
      expect(
        linesIn(
          'f() async { final p = FilePicker.platform;'
          ' await p.pickFiles(); }',
        ),
        isEmpty,
      );
    });
  });
}
