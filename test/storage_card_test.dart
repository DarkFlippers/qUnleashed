import 'dart:async';

import 'package:flipperlib/flipperlib.dart' hide DateTime;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qunleashed/pages/archive/browser/widgets/storage_card.dart';
import 'package:qunleashed/theme/theme.dart';

import 'quiet_device_title.dart';

/// The two storage cards on the archive screen, which had no test at all.
///
/// They could not have one: the widget built its own client from
/// `FlipperOneClient()`, so there was nothing to feed it. It takes one as a
/// parameter now (ADR 0002), and everything below follows from that.
///
/// What is worth pinning is the seeding. `storage.*` is fetched once when a
/// session comes up and never re-emits on a timer, so a screen opened after
/// an automatic USB link gets no event at all - the snapshot is the only
/// thing that fills it, and a card that waits for the stream stays blank
/// until the next file is written.
class FakeStorageClient with QuietDeviceTitle implements FlipperClient {
  FakeStorageClient({this.snapshot = const {}});

  final _updates = StreamController<Map<String, String>>.broadcast();

  /// What the session already knows when the widget subscribes.
  Map<String, String> snapshot;

  bool get isListening => _updates.hasListener;

  void emit(Map<String, String> patch) => _updates.add(patch);

  Future<void> close() => _updates.close();

  @override
  Map<String, String> get deviceInfoWatchSnapshot => snapshot;

  @override
  Stream<Map<String, String>> get deviceInfoUpdates => _updates.stream;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late FakeStorageClient client;

  setUp(() => client = FakeStorageClient());
  tearDown(() => client.close());

  Future<void> show(
    WidgetTester tester, {
    required bool enabled,
    FlipperClient? use,
  }) => tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(Brightness.dark, const Color(0xFFCC241D)),
      home: Scaffold(
        body: StorageUsageCards(
          client: use ?? client,
          enabled: enabled,
          onOpenInternal: () {},
          onOpenExternal: () {},
        ),
      ),
    ),
  );

  /// Whether any card is showing [text], however it is laid out.
  ///
  /// The used figure is the part rendered as text; the percentage drives a
  /// fill bar, which is not a string to look for.
  bool shows(WidgetTester tester, String text) =>
      find.textContaining(text).evaluate().isNotEmpty;

  testWidgets('fills from the snapshot, with no event at all', (tester) async {
    client.snapshot = const {'storage.internal.used': '1.2 GiB'};

    await show(tester, enabled: true);
    await tester.pump();

    expect(
      shows(tester, '1.2 GiB'),
      isTrue,
      reason: 'a USB link that came up before this screen emits nothing',
    );
  });

  testWidgets('takes what the stream sends after that', (tester) async {
    await show(tester, enabled: true);

    client.emit(const {'storage.sdcard.used': '7.4 GiB'});
    await tester.pump();

    expect(shows(tester, '7.4 GiB'), isTrue);
  });

  testWidgets('does not subscribe while it is disabled', (tester) async {
    await show(tester, enabled: false);

    expect(client.isListening, isFalse);
  });

  testWidgets('subscribes when it becomes enabled', (tester) async {
    await show(tester, enabled: false);
    await show(tester, enabled: true);

    expect(client.isListening, isTrue);
  });

  testWidgets('lets go, and forgets, when it is disabled again', (
    tester,
  ) async {
    client.snapshot = const {'storage.internal.used': '1.2 GiB'};
    await show(tester, enabled: true);
    await tester.pump();
    expect(shows(tester, '1.2 GiB'), isTrue, reason: 'the starting point');

    await show(tester, enabled: false);
    await tester.pump();

    expect(client.isListening, isFalse);
    expect(
      shows(tester, '1.2 GiB'),
      isFalse,
      reason: 'figures from a device that is gone are not figures',
    );
  });

  // The client can change under this now that it is passed in. A subscription
  // belongs to the one it was opened on, so the old one has to be let go of -
  // otherwise a device swap leaves the card fed by the Flipper that left.
  testWidgets('moves to a client handed in later', (tester) async {
    await show(tester, enabled: true);
    expect(client.isListening, isTrue, reason: 'the starting point');

    final second = FakeStorageClient(
      snapshot: const {'storage.internal.used': '88 MiB'},
    );
    addTearDown(second.close);

    await show(tester, enabled: true, use: second);
    await tester.pump();

    expect(client.isListening, isFalse, reason: 'the old one was let go');
    expect(second.isListening, isTrue);
    expect(shows(tester, '88 MiB'), isTrue);
  });

  testWidgets('stops listening when it goes away', (tester) async {
    await show(tester, enabled: true);
    expect(client.isListening, isTrue, reason: 'the starting point');

    await tester.pumpWidget(const SizedBox());

    expect(client.isListening, isFalse);
  });
}
