// A ceiling on `LogService.caught`, the level ADR 0013 §5 adds.
//
// Unlike every other budget here, this number is meant to *rise*. §5's
// re-ruling of the `info`-in-a-catch sites was the bulk of it and has landed;
// what rises after is one site at a time, each judged against §5's own rule
// and named in the comment on the number. It counts something the project
// wants a bounded amount of rather than less of, which is why the failure
// message asks a different question.
//
// It exists because `caught` is a legitimate way to lower
// `log_level_budget_test.dart`: moving a genuine failure off `info` makes that
// failure survive a release build. Moving *commentary* lowers it by exactly as
// much and puts noise in a 500-entry buffer whose purpose is to still hold a
// failure's context when someone goes looking. CLAUDE.md lists the deletion
// version of that trade as an anti-pattern; this is the same trade with a
// different lever, and without a number nothing would notice.
//
// The rule a new entry passes is the one on `LogService.caught`: an operation
// did not do what was asked.
//
// Blind spots, shared with every per-file syntactic ratchet here: a `caught`
// behind a one-line wrapper, or inside an `onError:` closure rather than a
// catch clause. #103 holds those.
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:flutter_test/flutter_test.dart';

import 'ratchet.dart';

/// What each area may record at `caught`.
///
/// §5's re-ruling has landed: 23 of the 42 `LogService.info`-inside-a-catch
/// sites moved; the other 19 stayed, each on a volume argument its own
/// comment makes. A rise after it is one site with its reason written here.
///
/// `services` is 9: the two `build_identity.dart` sites and the two in
/// `telemetry.dart` that were here before, plus a launcher refusing a
/// home-widget pin and an HTTP request the network responder could not carry.
/// The relay reply beside that second one runs per frame and stayed at `info`,
/// which is the distinction the level is for.
///
/// The seventh is the replay switch's restart in `telemetry.dart`, and it is
/// not a failure at all - it is the one line that makes a deliberate gap in
/// reporting visible. 9.30.1 has no app-facing pause API, so applying a
/// replay rate means taking the SDK down and bringing it back, and in that
/// window all four sinks are off and the native handler is down. A crash lost
/// there is indistinguishable from no crash, so the gap is named once, at
/// `caught`, and shows up in the timeline of the next report. Once per tap on
/// one switch, which is as bounded as this level gets.
///
/// The eighth is `RemoteBuildService.ensureClientId`, which rose it from 7:
/// the client id was not remembered for the next launch, because the store
/// would not open or would not take it. That is an operation that did not do
/// what was asked, and deliberately not the `warn` `persistSetting` would
/// have logged - the id is returned either way and serves the session, so
/// there is nothing for anyone to do about it and the cost is a fresh id next
/// launch. One line whichever of the two happened, and once per process,
/// since the field is set on the way out regardless. #313.
///
/// Two sites in `pages/archive` did **not** move: the per-node `list` of a
/// whole-SD walk, and the per-file `md5 check`, which §5 excludes by name
/// because the per-sync summary at `warn` already covers it (#194).
///
/// `pages/tools` is 5: the IR library's download, delete and search, and the
/// pixel editor's load and send. The two Dolphin walks stayed — one entry per
/// folder wants a tally at the caller, not a level here.
///
/// It rose to 8 for the two import pickers, after QUNLEASHED-E. All three are
/// failures of a file the user chose, which is the user's environment rather
/// than a defect, so none of them is worth an alert — and none of them had
/// any record at all before. The plotter counts two: a read or a pick that
/// threw, and a pick that came back with no path, which every target this app
/// ships does supply. They show the user the same sentence, so the log line
/// is the only thing that can tell a report about one from a report about the
/// other. Pixel Draw counts one, for the same `catch` reaching the same kind
/// of failure; its toast prints the exception and kept nothing.
///
/// It rose to 10 for the two listings the IR library cannot make of its own
/// folder, after QUNLEASHED-J. Android answers `exists()` on a shared-storage
/// folder and then refuses the listing with errno 1 when
/// MANAGE_EXTERNAL_STORAGE is not granted, and both sites used to let that
/// out: the recovery pass, where `guarded` reported a permission the user
/// declined as a failure of the IR library - and where the same rejection,
/// awaited by `IrLibController.initialize` with no catch of its own, left the
/// IR page in its initial state for the session - and `exists()`, a query
/// returning `bool` that the page awaits and that has no third answer. Both
/// now read as "nothing here this process can get at", which is the one state
/// where the library the user can see and the library the app can use differ.
/// Each line carries the errno, because that is the whole of what tells a
/// report about an absent library from a report about a declined permission.
///
/// Neither is once per process, and the fold does not save them: the startup
/// pass is memoised, but `download()` and `deleteAll()` reach the same listing
/// outside it, and the two bodies name different folders, so a refresh
/// alternates them and each breaks the other's run. What bounds them is that
/// every one of those is a tap - `initialize`, `updateSettings`, a refresh, a
/// delete - so the ceiling is two lines per thing the user asked for, nothing
/// like the burst Section 5 of the ADR was written for.
///
/// A third site was deliberately not added. `_supersededTrees` throws the
/// refusal rather than answering it, because `_deleteAll` needs it to: a short
/// list there takes the library out while leaving the trees that make the next
/// recovery pass hand it back. Only `_recoverInterrupted` catches, and only
/// `PathAccessException` - ENOTDIR, EIO and a descriptor leak reach the same
/// `list`, are not a declined permission, and still belong in a report.
///
/// `pages/apps` is 1 and `pages/archive` 17 for the same operation: a launch
/// refused because one of the same app is already in flight (#244). The tap
/// did nothing, and the page deliberately shows nothing for it - so without a
/// line kept in every build, a tap that was swallowed cannot be told from one
/// that was never delivered, which is the question a bug report about a dead
/// button asks. Its six other `pages/apps` sites are one-per-app loops or a
/// cancel the user asked for, and none of them moved.
///
/// `pages/archive` also counts every `list`, `write`, `delete`, `mkdir`,
/// `rename` and `appStart` the user asked for, plus `refresh`, `sync` and
/// `syncCategory`. The per-file `read` inside a sync is **no longer one of
/// them** - §5's table carries the amendment and the reason, which is that
/// that one site produced 94% of the project's entire log volume and the burst
/// evicted error events out of the SDK's cache. A `read` the user asked for by
/// opening one file is still counted.
///
/// It rose to 18 for the line that records a whole scope reading as deleted.
/// That is not a failure at all: an absent directory is now treated as the
/// empty listing it is, which is right, and the consequence is that every
/// local key under it is marked `deleted` - #109's outcome, reinstated
/// deliberately for one status code. The argument rests on
/// `ERROR_STORAGE_NOT_EXIST` meaning the firmware looked, and these codes are
/// a firmware contract this repo does not own while the app ships against
/// forks. One line, in a build that does not print, is the difference between
/// diagnosing a fork that answers the wrong code and guessing at it. Once per
/// walk, and only when keys actually moved.
///
/// The ninth is ADR 0013 §2's connect-failure hook: reporting runs inside a
/// `catch` that still has a user waiting, so the call is wrapped, and the one
/// line is what keeps a lost report from being silent. `connect_report.dart`
/// has which two things in there can throw.
///
/// The tenth through thirteenth are the pickers that had no `try` at all,
/// after QUNLEASHED-K - two in `pages/archive`, one in `pages/tools`, and the
/// new `pages/flibler`. They are one rule, not four judgements: a picker the
/// user opened answered with an error instead of a selection, so the upload,
/// the save or the export never started. That is an operation that did not do
/// what was asked, and it is the user's environment rather than a defect, so
/// none of them is worth an alert - and none of them had any record at all
/// before, because the rejection was going to the zone as a fatal instead.
///
/// The cause differs by site and by platform, which is why the line carries
/// `describe` rather than a sentence of its own. The file pick is Android's
/// `unknown_path`, the one in the incident. The three folder picks cannot be:
/// `getDirectoryPath` swallows its own `PlatformException` on Android and iOS
/// and answers null, so what reaches them is a desktop refusal - no `zenity`
/// on the path - or a missing plugin.
///
/// The line is also the only thing that can tell those apart, because all four
/// show `commonPickFailed` and it deliberately does not guess at a cause. The
/// four bodies differ, so no two sites fold into each other. **What the fold
/// does drop is a repeat at one site** - the same tap, the same broken
/// provider, twice - and nothing counts the drop. That is acceptable here
/// because the second line would say exactly what the first one said.
///
/// `test/unguarded_pick_test.dart` does assert `hasLength(1)` on this area's
/// lines, which is CLAUDE.md's named anti-pattern everywhere the fold is live -
/// and is safe there for one reason worth writing down: the fold is a static
/// that `test/flutter_test_config.dart` resets before every test, so inside one
/// test a count of one means said once. It would not be safe across two.
///
/// Six pickers already caught before this and were left alone. Three of them
/// record nothing - two in the file browser and the archive's save dialog -
/// and that is a smaller fault than a crash and not this issue's. The other
/// three do keep a line, and one of them disagrees with these four:
/// `firmware_update_button.dart` records the same mechanism at `error` and
/// shows the user the exception. Under §5's rule these four are right and that
/// one is the outlier, but moving it is its own change - it would lower
/// `log_level_budget_test.dart` and raise this, and the sentence it shows the
/// user would have to change with it.
///
/// Then #351, which is the block below. It landed against the four pickers
/// above rather than before them, so `pages/tools` carries one from each: the
/// infrared search walk here, and the pixel editor's export pick there.
/// `services` rose from 9 to 17 for #351, and every one of the eight is an
/// operation that did not do what was asked. They are listed because the
/// number invites the wrong reading: this is a permission layer whose whole
/// job is to stop a failure being absorbed, so the places it cannot get an
/// answer are exactly the places worth a kept line.
///
/// None is `warn`. In every case the app still works and what the user is
/// told is true — it is the *completeness* or the *timeliness* that suffers,
/// which is what `caught` is for. And none is `info`: the whole defect #351
/// fixes is a failure reported nowhere, and `info` const-folds away in a
/// release build, so it would reproduce the bug inside its own fix.
///
///  * `permissions/center.dart` ×2 — the dismissal store refusing to open
///    (every dismissible notice then returns at the next launch, for the life
///    of the install), and a permission that could not be re-read on resume
///    (its notice will not clear when the user grants it, which is the half of
///    #351 the widget cannot supply).
///  * `storage/asked_store.dart` — the asked flag unreadable. While that
///    fails, a standing storage denial cannot be reported at all, so three
///    screens stay silent about a permission the user refused.
///  * `storage/permissions.dart` ×3 — the Android version read, the
///    permission status read, and the prompt itself. Each used to be a bare
///    catch folded into "not granted", and the caller then reported that as a
///    *refusal*: a plugin hiccup during startup put a non-dismissible gate on
///    three screens and disabled the IR download button.
///  * `connection/foreground_service.dart` ×2 — the location read (it was a
///    `catch (_)` to false; the service started without
///    `ForegroundServiceTypes.location` and nothing said why) and the
///    notification prompt, which moved up *from* `info` because its outcome
///    stopped being ignored. On the `widgetMain()` path that throw is routine,
///    and after it the background link can die with the user told nothing.
///
/// `pages/tools` rose to 11 for `infrared/api.dart`'s search walk. A folder
/// that will not list prunes its entire subtree, so one failure near the root
/// can cost most of the library, and the `catch (_) { continue; }` it replaces
/// handed the short result back as though it were whole. One line after the
/// walk with the count and the first cause, not one per folder — a line per
/// folder is a log burst, and bodies differing by path defeat `LogService`'s
/// consecutive fold.
///
/// Both replaced catches had non-empty bodies (`return false;` and
/// `continue;`), so neither was ever counted by `bare_catch_budget_test.dart`
/// and its figures do not move. The exchange that file's header describes is
/// between itself and `log_level_budget_test.dart`; this is not that trade.
const Map<String, int> kBudget = {
  'services': 17,
  'pages/archive': 20,
  'pages/tools': 12,
  'pages/flibler': 1,
  'pages/apps': 1,
};

const String kAdr = 'docs/adr/0013-observability-with-sentry.md';

/// Collects `LogService.caught(...)` calls, wherever they are.
///
/// Not restricted to a catch clause, unlike the log budget's visitor. `caught`
/// is *for* a catch, so a call outside one is a misuse this should count rather
/// than overlook - and the analyzer is what decides, for the reason that file
/// gives: `on Type {` is also how Dart spells an extension target.
class _CaughtVisitor extends RecursiveAstVisitor<void> {
  _CaughtVisitor(this.unit);

  final CompilationUnit unit;
  final List<int> lines = [];

  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (node.methodName.name == 'caught' && isLogServiceCall(node)) {
      lines.add(unit.lineInfo.getLocation(node.offset).lineNumber);
    }
    super.visitMethodInvocation(node);
  }
}

/// The lines of the counted calls in [unit], in source order.
List<int> caughtLinesIn(CompilationUnit unit) {
  final visitor = _CaughtVisitor(unit);
  unit.accept(visitor);
  return visitor.lines;
}

/// Parses [source] and counts, for the rule's own tests.
List<int> caughtLines(String source, {String? path}) =>
    caughtLinesIn(parseUnit(source, path: path));

void main() {
  group('the rule', () {
    test('counts a caught call inside a catch', () {
      expect(
        caughtLines(
          "void f() { try { g(); } catch (e) { LogService.caught('x'); } }",
        ),
        hasLength(1),
      );
    });

    // Counted anyway, and deliberately: `caught` outside a catch is a level
    // used for something it is not for, which is what the ceiling is about.
    test('counts one outside a catch too', () {
      expect(caughtLines("void f() { LogService.caught('x'); }"), hasLength(1));
    });

    test('is only LogService.caught, by whatever name it was imported', () {
      expect(
        caughtLines("void f() { log.LogService.caught('x'); }"),
        hasLength(1),
      );
      expect(caughtLines("void f() { Other.caught('x'); }"), isEmpty);
      expect(caughtLines("void f() { caught('x'); }"), isEmpty);
    });

    test('is not another level', () {
      expect(caughtLines("void f() { LogService.warn('x'); }"), isEmpty);
      expect(caughtLines("void f() { LogService.info('x'); }"), isEmpty);
    });

    test('reports the line the call is on', () {
      expect(caughtLines("void f() {\n  g();\n  LogService.caught('x');\n}"), [
        3,
      ]);
    });
  });

  test('no area records more caught failures than its budget', () {
    final result = countAcrossLib((unit, _) => caughtLinesIn(unit));

    expectWithinBudget(
      counted: result.counted,
      budget: kBudget,
      sites: result.sites,
      budgetFile: 'test/caught_budget_test.dart',
      why:
          'LogService.caught is kept in every build, so a commentary line put '
          'here is noise in front of whoever reads a bug report - and it '
          'lowers log_level_budget_test.dart by exactly as much as a real '
          'failure would.\n'
          'If an operation did not do what was asked, raise kBudget in '
          'test/caught_budget_test.dart and say which operation. If it is '
          'commentary, it belongs at info.\n'
          'See $kAdr',
    );
  });
}
