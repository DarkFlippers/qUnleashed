import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qunleashed/services/logging.dart';

/// What `debugPrint` received while [body] ran.
///
/// Restored inline rather than through addTearDown, which flutter_test rejects
/// as changing a debug variable.
List<String> printed(void Function() body) {
  final lines = <String>[];
  final previous = debugPrint;
  debugPrint = (String? message, {int? wrapWidth}) {
    if (message != null) lines.add(message);
  };
  try {
    body();
  } finally {
    debugPrint = previous;
  }
  return lines;
}

void main() {
  setUp(LogService.clearHistory);
  tearDown(LogService.clearHistory);

  // The whole point of #89. LogService.enabled is a const that follows the
  // build type, and every guard derived from it folds — so in a shipped build
  // the error branch was shaken out and 19 call sites, 11 of them in catch
  // blocks, reported nowhere at all.
  //
  // Both halves are asserted together on purpose: printing still follows the
  // build, and keeping no longer does. In the default run errorOn is true and
  // this reads as "printed and kept"; under --dart-define=QLOG=false it reads
  // as "kept though nothing printed", which is the case that was broken. CI
  // runs this file both ways.
  test('an error is kept whether or not the build prints anything', () {
    final lines = printed(() => LogService.error('a transport fault'));

    expect(LogService.history.single, contains('a transport fault'));
    expect(
      lines.isEmpty,
      !LogService.errorOn,
      reason: 'printing follows the build; keeping does not',
    );
  });

  test('a warning is kept too', () {
    printed(() => LogService.warn('the port went quiet'));

    expect(LogService.history.single, contains('the port went quiet'));
  });

  // Anything below a warning runs often enough to churn the buffer, which
  // would cost the failure the context the buffer exists to hold.
  test('the chatty levels are not kept', () {
    printed(() {
      LogService.info('opened the archive');
      LogService.log('and again');
      LogService.debug('frame');
      LogService.trace('byte');
    });

    expect(LogService.history, isEmpty);
  });

  test('each line of a multi-line message is kept and stamped', () {
    printed(() => LogService.error('failed: boom\nand the stack'));

    expect(LogService.history, hasLength(2));
    expect(LogService.history.first, contains('failed: boom'));
    expect(LogService.history.last, contains('and the stack'));
    expect(
      LogService.history.every(
        (l) => RegExp(r'^\[\d\d:\d\d:\d\d\] ').hasMatch(l),
      ),
      isTrue,
      reason: 'a line without a time is no use in a bug report',
    );
  });

  test('the oldest lines go when the buffer is full', () {
    printed(() {
      for (var i = 0; i <= LogService.historyLimit; i++) {
        LogService.error('failure $i');
      }
    });

    expect(LogService.history, hasLength(LogService.historyLimit));
    expect(LogService.history.first, contains('failure 1'));
    expect(
      LogService.history.last,
      contains('failure ${LogService.historyLimit}'),
      reason: 'oldest first, so a reader ends at the most recent',
    );
  });

  test('the history cannot be written through', () {
    printed(() => LogService.error('boom'));

    expect(() => LogService.history.add('forged'), throwsUnsupportedError);
  });
}
