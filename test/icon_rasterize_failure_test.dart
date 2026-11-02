// A raster that cannot be produced is kept once, at the level its cause earns,
// and does not reach the zone.
//
// `QIcon` asks `_RasterIconCache.resolve` for an image and `resolve` rethrows,
// so the widget is the only place left that can handle the failure. It used to
// attach a one-argument `.then` and nothing else: the error was forwarded to
// the future `.then` returns, which nobody holds, so it reached the root zone
// and `PlatformDispatcher.onError` filed it as a fatal crash - once per `QIcon`
// that was rasterizing, which on a cold start is every icon on screen.
// QUNLEASHED-28 is sixteen of them inside one second, on a two-core Windows box
// where `dart:ui` answered `Exception('operation failed')` for a surface it
// could not allocate.
//
// The failure is provoked here with an asset that does not exist rather than by
// breaking the rasterizer, and that is not a convenience: `picture.toImage`
// failing inside a widget test surfaces through the FFI callback as a
// shell-level unhandled exception that aborts the test process, which no
// `try`/`catch` can intercept. A missing asset throws in `_rasterize` before
// `toImage` is reached, and from `resolve` onward the path is identical to
// production - the `catch`, `_record`, `rethrow`, the `finally` dropping the
// `_pending` entry, and the handler under test.
//
// **Why an uncaught rejection fails this test rather than being asserted on.**
// `testWidgets` reports an unhandled error from its zone as a test failure, so
// the "does not reach the zone" half needs no expectation: with the handler
// removed this file fails on the rejection itself, before any expectation below
// is reached. Both halves were checked against the pre-fix code rather than
// assumed - CLAUDE.md's standing warning is that four tests in this repo have
// passed on a mechanism other than the one they named.
//
// **One fragility, if this file ever starts failing for a reason that is not
// `QIcon`'s.** `flutter_svg`'s `Cache.putIfAbsent` attaches a success-only
// `.then` to its own pending future and never clears the entry on error - the
// very shape being fixed here. It is dormant only because a missing asset
// throws *synchronously* in the test harness, before that pending future is
// assigned. A Flutter release that makes harness asset loading asynchronous
// would make this file fail on a dependency's unhandled rejection. Start there,
// not in `icon.dart`.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qunleashed/components/icon.dart';
import 'package:qunleashed/services/logging.dart';

import 'kept_lines.dart';
import 'quiet_log.dart';

/// Pumps one [QIcon] and lets its rasterize settle.
///
/// The colour is fixed: the asset is what makes each case independent, and
/// varying the tint as well would suggest the tint were load-bearing.
Future<void> _pumpIcon(
  WidgetTester tester,
  String asset, {
  double size = 24,
  Key? key,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Center(
        key: key,
        child: QIcon(asset: asset, color: Colors.red, size: size),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUp(recordKeptLines);

  testWidgets('a missing asset is kept at warn, naming the asset', (
    tester,
  ) async {
    const asset = 'assets/icons/this-asset-does-not-exist.svg';

    await _pumpIcon(tester, asset);

    final failures = keptLines
        .where((line) => line.contains('[QIconCache] rasterize failed'))
        .toList();

    // `isNotEmpty` and not `hasLength(1)`: `LogService` folds a consecutive
    // identical body, so a count here cannot tell "said once" from "said
    // twice". The once-per-key property is pinned below, by a channel the fold
    // does not touch.
    expect(failures, isNotEmpty);
    expect(failures.first, contains('asset=$asset'));
    // The value, not just the key: `size: 24` at the harness's 3.0 device
    // pixel ratio. `contains('pixelSize=')` would pass on any interpolation,
    // including the wrong variable.
    expect(failures.first, contains('pixelSize=72'));
    expect(
      keptLevels[keptLines.indexOf(failures.first)],
      KeptLevel.warning,
      reason:
          'an asset the bundle does not hold is a packaging defect with an '
          'owner - permanent, and the same for every user - so it alerts. The '
          'engine refusing a surface is the environment and stays at caught; '
          'see _RasterIconCache._record',
    );
  });

  testWidgets('the same failing key is recorded once, not once per widget', (
    tester,
  ) async {
    const asset = 'assets/icons/recorded-once.svg';

    // `_debugLog`'s console lines, not `keptLines`: a repeat would log an
    // identical body, which `LogService._isNewLine` folds, so counting kept
    // lines could not tell a second record from a folded one. `_emit` applies
    // the fold to the kept sink only and never to the console, and `debugOn`
    // is true under `flutter test`, so `queued` is countable here.
    final lines = await printedAsync(() async {
      await _pumpIcon(tester, asset);

      clearKeptLines();

      // A second widget with the same key, after the first has failed. This is
      // the retry the cache deliberately still allows: `_ready` never got the
      // key and the `finally` dropped it from `_pending`, so the rasterize runs
      // again - which is what stops one transient refusal poisoning the key for
      // the life of the process (the #118/#134 latching shape).
      await _pumpIcon(tester, asset, key: const ValueKey('second'));
    });

    final queued = lines
        .where((l) => l.contains('[QIconCache] queued') && l.contains(asset))
        .length;
    expect(
      queued,
      2,
      reason: 'the work is re-attempted, so the key does not latch',
    );

    expect(
      keptLines.where((l) => l.contains('[QIconCache] rasterize failed')),
      isEmpty,
      reason:
          'but the record is not repeated: `_recorded` already holds the key, '
          'so a permanent failure costs one line and not one per widget per '
          'rebuild - ADR 0013 §5',
    );
  });

  testWidgets('the icon renders as empty space rather than throwing in build', (
    tester,
  ) async {
    const asset = 'assets/icons/also-missing.svg';

    await _pumpIcon(tester, asset, size: 32);

    // The placeholder `build` returns while `_image` is null. It stays for this
    // widget, because the failure is deliberately not retried for an unchanged
    // key: retrying from `build` is the shape #135/#136 warns about. What a
    // failed icon *should* render is #441 item 3 and is still open - this
    // asserts today's behaviour so that changing it is a deliberate act.
    expect(find.byType(RawImage), findsNothing);
    final box = tester.widget<SizedBox>(
      find.descendant(of: find.byType(QIcon), matching: find.byType(SizedBox)),
    );
    expect(box.width, 32);
    expect(box.height, 32);
  });
}
