// A ufbt failure reaches the log, not only the Assembler console — ADR 0013 §3.
//
// The console is a screen in one feature. Before this, an `error` or
// `critical` from dartufbt went there and nowhere else: not to
// `keptLines`, so not to a copied log, so not to a bug report, and
// after 0013 not to Sentry either. A toolchain that will not install is
// exactly the failure somebody files an issue about.
//
// The cut is at `error`. The console is a build log and most of its traffic is
// ordinary toolchain chatter; admitting `warning` and below would churn the
// 500-entry buffer the failure's own context lives in.
import 'package:dartufbt/dartufbt.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qunleashed/services/assembler/controller.dart';

import 'kept_lines.dart';

import 'quiet_log.dart';

void main() {
  setUp(recordKeptLines);

  late UfbtLogger logger;

  setUp(() {
    clearKeptLines();
    logger = AssemblerController.instance.logger;
  });

  List<String> keptFrom(void Function() emit) {
    quietly(emit);
    return keptLines.where((line) => line.contains('[Assembler]')).toList();
  }

  test('an error is kept, labelled', () {
    final kept = keptFrom(() => logger.error('ufbt install failed'));

    expect(kept, hasLength(1));
    expect(kept.single, contains('ufbt install failed'));
    expect(
      kept.single,
      contains('[error]'),
      reason: 'kept at a level a release build does not drop',
    );
  });

  test('a critical is kept too', () {
    // The level above `error`, so a cut written as `== error` would pass the
    // test above and lose the worse one.
    final kept = keptFrom(() => logger.critical('toolchain is unusable'));

    expect(kept, hasLength(1));
    expect(kept.single, contains('toolchain is unusable'));
  });

  test('a warning is not, and neither is info', () {
    final kept = keptFrom(() {
      logger.warning('deprecated api');
      logger.info('fetching sdk');
      logger.debug('spawning');
    });

    expect(
      kept,
      isEmpty,
      reason: 'build-log chatter would churn the buffer the failure lives in',
    );
  });

  test('the console still gets everything', () {
    // The forwarding is in addition to the console, not instead of it: the
    // Assembler screen is where somebody watches a build happen.
    final before = AssemblerController.instance.lines.length;
    quietly(() {
      logger.info('fetching sdk');
      logger.error('ufbt install failed');
    });
    expect(
      AssemblerController.instance.lines.length,
      greaterThanOrEqualTo(before + 2),
    );
  });
}
