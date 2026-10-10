// The seventh ratchet, and the only one whose budget is zero everywhere but
// one directory.
//
// ADR 0013 §2 makes `lib/services/telemetry/` the only place in the app that
// imports the Sentry SDK: everything above keeps calling `LogService`,
// `guarded` and the connection classifier, and that folder turns what they
// record into events. The reason to hold it mechanically is that the import is
// the easy thing to reach for - `Sentry.captureException` at a catch site
// looks like less work than routing one more failure through a chokepoint, and
// the ADR rejected exactly that on the grounds of several hundred judgement
// calls.
//
// A guard rather than a budget, because unlike the other six this one has no
// legacy to drain: the dependency arrived with the folder, so zero is both the
// current count and the target. `expectWithinBudget` is still what reports it,
// so the failure names every offending file the way the others do.
//
// Scope is `lib/` only. A test that drives the SDK's own types has to import
// them - `scrubEvent` takes a `SentryEvent` - and `test/` carrying the
// dependency costs nothing: it ships in no binary and reaches no user.
import 'package:analyzer/dart/ast/ast.dart';
import 'package:flutter_test/flutter_test.dart';

import 'ratchet.dart';

/// The one directory allowed to import the SDK, as a path prefix.
const String telemetryDir = 'lib/services/telemetry/';

/// Any `package:sentry`, `package:sentry_flutter`, or anything else the vendor
/// publishes under that name.
///
/// Matched on the shape rather than the one package name in the pubspec, so a
/// later `sentry_dart_plugin` or `sentry_drift` is covered the day it is added
/// rather than the day somebody remembers this file. The separator is part of
/// both patterns so the match cannot run on into an unrelated package whose
/// name merely starts the same way.
bool importsSentry(String uri) =>
    uri.startsWith('package:sentry/') || uri.startsWith('package:sentry_');

/// Where [unit] brings the SDK in, or nothing.
///
/// `export` counts as well as `import`. A one-line re-export outside the
/// folder would hand the SDK's whole API to every file importing it, and the
/// importer would be clean.
List<int> _sentryImportsIn(CompilationUnit unit, String path) {
  if (path.startsWith(telemetryDir)) return const [];
  return [
    for (final directive in unit.directives)
      if (directive is NamespaceDirective &&
          importsSentry(directive.uri.stringValue ?? ''))
        unit.lineInfo.getLocation(directive.offset).lineNumber,
  ];
}

void main() {
  test('only lib/services/telemetry imports the Sentry SDK', () {
    final found = countAcrossLib(_sentryImportsIn);
    expectWithinBudget(
      counted: found.counted,
      budget: const <String, int>{},
      sites: found.sites,
      budgetFile: 'test/sentry_import_guard_test.dart',
      why:
          'ADR 0013 §2: the SDK is imported in lib/services/telemetry/ and '
          'nowhere else. Route the failure through LogService, guarded or '
          'classifyConnectError and let telemetry/ turn it into an event.',
    );
  });

  group('what counts as the SDK', () {
    test('the two packages in the pubspec, and what the vendor adds later', () {
      expect(importsSentry('package:sentry/sentry.dart'), isTrue);
      expect(
        importsSentry('package:sentry_flutter/sentry_flutter.dart'),
        isTrue,
      );
      expect(importsSentry('package:sentry_dart_plugin/anything.dart'), isTrue);
    });

    test('not a package whose name merely starts the same way', () {
      expect(importsSentry('package:sentrypedia/sentrypedia.dart'), isFalse);
    });

    test('not a package that merely begins the same way', () {
      // The prefix is deliberately broad, so the one thing worth pinning is
      // that it does not reach past the vendor's namespace into the app's own
      // or the SDK's relative imports.
      expect(
        importsSentry('package:qunleashed/services/telemetry/scrub.dart'),
        isFalse,
      );
      expect(importsSentry('scrub.dart'), isFalse);
      expect(importsSentry('dart:io'), isFalse);
    });
  });

  test('the exemption covers the folder and not its parent', () {
    // The only direction this guard can widen in silently. Narrowing it so it
    // matches nothing fails loudly and the test below catches that - but
    // widening `lib/services/telemetry/` to `lib/services/` would exempt the
    // SDK across every service while every assertion here stayed green.
    const sentry = "import 'package:sentry/sentry.dart';";
    expect(
      _sentryImportsIn(parseUnit(sentry), 'lib/services/x.dart'),
      hasLength(1),
      reason: 'a service outside the folder is still counted',
    );
    expect(
      _sentryImportsIn(parseUnit(sentry), '${telemetryDir}x.dart'),
      isEmpty,
      reason: 'and the folder itself is still exempt',
    );
  });

  test('the folder it allows is the folder that exists', () {
    // Renaming the folder without renaming it here would turn the guard into
    // a guard over nothing: every file would be outside the exemption, the
    // test would fail loudly, and the obvious fix is to update the prefix.
    // The failure that is *not* loud is the opposite - an exemption pointing
    // at a path nothing matches passes while the SDK spreads anywhere.
    final telemetry = gitVisibleFiles('$telemetryDir*.dart');
    expect(
      telemetry,
      isNotEmpty,
      reason:
          '$telemetryDir holds no Dart files, so the exemption above covers '
          'nothing. If the folder moved, move this constant with it.',
    );
  });
}
