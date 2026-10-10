// What `traced` records about an operation a user waited on — ADR 0013 §2.
//
// Driven through a real hub with the transport replaced, because the facts
// worth holding are all about what *arrives*: the name, the status when
// nothing threw, the status when something did, the status when the body says
// it failed without throwing, and that the caller's result and exception pass
// through untouched.
//
// Asserted against `toJson()` rather than the object graph. `SentryTransaction`
// keeps its name, status and data behind `tracer`, which is `@internal` - and
// `flutter analyze` treats reaching for it as a warning, which CI treats as
// fatal. The serialized payload is public, and it is also literally what
// Sentry receives, so an assertion on it cannot pass while the wire format
// says something else.
import 'package:flutter_test/flutter_test.dart';
import 'package:qunleashed/services/telemetry/scrub.dart';
import 'package:qunleashed/services/telemetry/traced.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import 'sentry_capture.dart';

void main() {
  setUp(() => Scrub.debugUseHomes([r'C:\Users\Myte']));
  tearDown(() => Scrub.debugUseHomes(null));

  test('a completed operation arrives named, with status ok', () async {
    final sent = await captureTransactions();

    final value = await traced('device.connect', (trace) async => 42);
    await Sentry.close();

    expect(value, 42, reason: "the caller's result passes straight through");
    expect(sent, hasLength(1));
    expect(sent.single.name, 'device.connect');
    expect(sent.single.status, 'ok');
  });

  test('a throw passes through and the operation is marked failed', () async {
    // Nothing in `traced` catches. One that swallowed would be a reporting
    // feature that broke the thing it reports on.
    final sent = await captureTransactions();

    await expectLater(
      traced<void>('firmware.install', (trace) async {
        throw StateError('bundle is corrupt');
      }),
      throwsA(isA<StateError>()),
    );
    await Sentry.close();

    expect(sent, hasLength(1));
    expect(sent.single.status, 'internal_error');
  });

  test('failed() marks it without a throw', () async {
    // The case `FirmwareInstaller.install` needs: it is documented as never
    // throwing, so every fault arrives as a returned value. Without this the
    // transaction would say ok - a real duration with a false verdict.
    final sent = await captureTransactions();

    await traced('firmware.install', (trace) async {
      trace.failed('empty archive');
    });
    await Sentry.close();

    expect(sent.single.status, 'internal_error');
    expect(sent.single.data['failure'], 'empty archive');
  });

  test('note attaches a fact', () async {
    final sent = await captureTransactions();

    await traced('device.connect', (trace) async {
      trace.note('link', 'ble');
      trace.note('held', false);
    });
    await Sentry.close();

    expect(sent.single.data['link'], 'ble');
    expect(sent.single.data['held'], isFalse);
  });

  test('a noted string is scrubbed, a number is left alone', () async {
    // §6: everything sent goes through the scrubber. A count or a flag cannot
    // carry a filename, so only strings are touched - rewriting a number's
    // type would change what the operation means.
    final sent = await captureTransactions();

    await traced('file.transfer', (trace) async {
      trace.note('path', r'C:\Users\Myte\card.nfc');
      trace.note('bytes', 4096);
    });
    await Sentry.close();

    // Both rules land: the home becomes `~`, and the filename goes too.
    expect(sent.single.data['path'], r'~\<name>.nfc');
    expect(sent.single.data['bytes'], 4096);
  });

  test('count reports the total, not each occurrence', () async {
    // §2 asks for this by name: an upload restarts after auto-reconnect, so
    // the duration alone says nothing about what happened.
    final sent = await captureTransactions();

    await traced('file.transfer', (trace) async {
      trace.count('restarts');
      trace.count('restarts');
      trace.count('restarts');
    });
    await Sentry.close();

    expect(sent.single.data['restarts'], 3);
  });

  test('a nested traced is a child span, not a second transaction', () async {
    // How "install" can contain "transfer" without the inner one escaping as
    // an operation of its own.
    final sent = await captureTransactions();

    await traced('firmware.install', (_) async {
      await traced('file.transfer', (_) async {});
    });
    await Sentry.close();

    expect(sent, hasLength(1), reason: 'one transaction');
    expect(sent.single.name, 'firmware.install');
    expect(sent.single.childOperations, ['file.transfer']);
  });

  test('with no hub at all it still runs the body and returns', () async {
    // Every local build and every other test file. `startTransaction` on an
    // unconfigured hub hands back a no-op span, so there is no second code
    // path here - which is the point.
    await Sentry.close();
    var ran = false;
    final value = await traced('device.connect', (trace) async {
      ran = true;
      trace.note('link', 'usb');
      trace.count('restarts');
      trace.failed();
      return 'done';
    });

    expect(ran, isTrue);
    expect(value, 'done');
  });

  test('with no hub a throw still reaches the caller', () async {
    await Sentry.close();
    await expectLater(
      traced<void>('device.connect', (_) async => throw StateError('nope')),
      throwsA(isA<StateError>()),
    );
  });
}
