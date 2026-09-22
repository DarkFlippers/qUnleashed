import 'dart:async';
import 'dart:io';

import 'package:flipperlib/flipperlib.dart' hide DateTime, File;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qunleashed/components/changelog_renderer.dart';
import 'package:qunleashed/components/config.dart';
import 'package:qunleashed/components/progress_button.dart';
import 'package:qunleashed/pages/devices/controllers/device.dart';
import 'package:qunleashed/pages/devices/controllers/firmware.dart';
import 'package:qunleashed/pages/devices/device_scope.dart';
import 'package:qunleashed/pages/devices/firmware/directory.dart';
import 'package:qunleashed/pages/devices/firmware/installer.dart';
import 'package:qunleashed/pages/devices/firmware/repository.dart';
import 'package:qunleashed/pages/devices/firmware/source.dart';
import 'package:qunleashed/pages/devices/firmware/update_settings.dart';
import 'package:qunleashed/pages/devices/firmware/update_state.dart';
import 'package:qunleashed/pages/devices/widgets/firmware_changelog_page.dart';
import 'package:qunleashed/pages/devices/widgets/firmware_update_button.dart';
import 'package:qunleashed/services/localization/l10n.dart';
import 'package:qunleashed/services/logging.dart';
import 'package:qunleashed/theme/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The three firmware surfaces that used to enter a state they never left,
/// and the reasons that went with them — #118.
///
/// What they share is not the failure but its shape: a transitional value — a
/// loading set, an `UpdateWaitingForReconnect`, a `FutureBuilder` with no data
/// — that the failure path left standing. The fix in each is two things, not
/// one: keep the reason, and move the state off the transitional value.
///
/// Two of the three sat behind a catch that discarded the reason; the
/// changelog had no catch at all and simply never asked whether the future had
/// failed. None of them was visible to the ratchet in
/// log_level_budget_test.dart, which counts `LogService.info` inside a catch —
/// a catch with no log lowers that number.

/// Only what the recovery wait touches.
///
/// Everything else throws through [noSuchMethod], so a wait that starts
/// reaching for something new fails here rather than quietly reading a null.
class _FakeClient implements FlipperClient {
  final _connection = StreamController<FlipperConnectionState>.broadcast();

  bool _connected = false;

  /// The device coming back: the flag flips and the stream says so.
  ///
  /// Shaped to what [FirmwareInstaller.awaitReconnect] reads rather than to
  /// what the real client emits — it consults `isConnected` and ignores the
  /// event's contents, and the real payload carries a session this fake has
  /// no way to build.
  void arrive() {
    _connected = true;
    _connection.add(
      const FlipperConnectionState(
        mode: FlipperMode.rpc,
        device: null,
        connected: true,
      ),
    );
  }

  /// Connected, with nothing said on the stream.
  ///
  /// The state the wait can only discover by asking again: it is why the
  /// non-timeout exit reports [isConnected] rather than a flat failure.
  void arriveQuietly() => _connected = true;

  /// A connection event that is not a connection. The stream carries these
  /// too, and a wait that took the first event for the device coming back
  /// would report a recovery that never happened.
  void stir() => _connection.add(
    const FlipperConnectionState(
      mode: FlipperMode.disconnected,
      device: null,
      connected: false,
    ),
  );

  /// The link dropping, with nothing said on the stream.
  void depart() => _connected = false;

  /// The link torn down under the wait — a disposed client, a closed session.
  Future<void> close() => _connection.close();

  /// Whether anything is still listening.
  ///
  /// `Future.timeout` times out the future and cannot reach the work behind
  /// it, so a wait built on `firstWhere().timeout()` left a listener on this
  /// broadcast stream after every deadline - and the stream lives as long as
  /// the client.
  bool get hasListener => _connection.hasListener;

  @override
  bool get isConnected => _connected;

  @override
  Stream<FlipperConnectionState> get connectionStream => _connection.stream;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// A directory feed of the shape the parsers expect.
Map<String, dynamic> _feed() => {
  'channels': [
    {
      'id': 'release',
      'title': 'Release',
      'description': '',
      'versions': [
        {
          'version': '1.0.0',
          'changelog': 'notes',
          'timestamp': 0,
          'files': <dynamic>[],
        },
      ],
    },
  ],
};

/// The same feed after `version` stopped being a string upstream.
///
/// Every field below the decode casts unguarded (`json['version'] as String`),
/// so this is a real `TypeError` out of `FirmwareDirectory.fromJson` rather
/// than a stand-in thrown by the seam.
Map<String, dynamic> _feedOfTheWrongShape() {
  final json = _feed();
  final channels = json['channels']! as List<dynamic>;
  final versions = (channels.first as Map<String, dynamic>)['versions']!
      as List<dynamic>;
  (versions.first as Map<String, dynamic>)['version'] = 1;
  return json;
}

/// Advances past the 30-second reconnect deadline and settles the frame.
///
/// The short pump first is load-bearing: the wait only starts once _onPressed
/// resumes past the install, and a timer created partway through an elapse is
/// scheduled from the end of that elapse rather than from where it was
/// created - so advancing straight to 31s leaves the deadline in the future.
Future<void> elapsePastReconnectDeadline(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 1));
  await tester.pump(const Duration(seconds: 31));
  await tester.pump();
}

/// Lets the six-second failure toast expire, so no timer outlives the test.
Future<void> drainToast(WidgetTester tester) =>
    tester.pump(const Duration(seconds: 7));

Widget _wrap(Widget child, DeviceController device) => MaterialApp(
  theme: buildAppTheme(Brightness.dark, const Color(0xFFCC241D)),
  home: DeviceScope(notifier: device, child: child),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// How many directory requests the feed has been asked for.
  var fetchCalls = 0;

  final repo = FirmwareRepository.instance;
  final firmwares = QAppConfig.firmware.firmwares;
  final unleashed = firmwares.firstWhere((f) => f.shortName == 'unlshd');
  final official = firmwares.firstWhere((f) => f.shortName == 'ofw');

  /// Answers every firmware's directory request with [fetch].
  void feedEvery(Future<dynamic> Function(Uri uri) fetch) {
    for (final entry in firmwares) {
      parserForEntry(entry).fetchJson = (uri) {
        fetchCalls++;
        return fetch(uri);
      };
    }
  }

  void feedWorks() => feedEvery((_) async => _feed());
  void feedFails(Object error) => feedEvery((_) async => throw error);

  setUp(() {
    LogService.clearHistory();
    SharedPreferences.setMockInitialValues(const {});
    UpdateSettingsStore.instance.reset();
    repo.reset();
    fetchCalls = 0;
    for (final entry in firmwares) {
      parserForEntry(entry).clearCache();
    }
    // Not every case replaces this, and the ones that do not still build a
    // FirmwareController, whose constructor prefetches every firmware. Left
    // pointing at the network, that is a live request per run and an
    // assertion that depends on what the upstream feed serves that day.
    feedWorks();
  });

  /// A device controller and a client for a widget test, both torn down.
  ///
  /// The controller is real: it constructs fine under `flutter test`, and the
  /// two widgets here both need a `DeviceScope` carrying one.
  (DeviceController, _FakeClient) mountedDevice() {
    final device = DeviceController();
    final client = _FakeClient();
    addTearDown(() async {
      device.dispose();
      await client.close();
    });
    return (device, client);
  }

  List<String> keptAbout(String fragment) =>
      LogService.history.where((l) => l.contains(fragment)).toList();

  group('FirmwareRepository', () {
    // Before anything has been asked for: no directory, no failure, nothing
    // in flight. Still something to wait for rather than a firmware with no
    // update - prefetchAll has simply not reached it yet.
    test('a firmware nobody has asked about yet is checking', () {
      expect(repo.stateFor(unleashed), FirmwareFetchState.loading);
    });

    // A retry reads as checking, not as the failure it is retrying: the card
    // should show progress while it happens and go back to reporting the
    // failure only if the retry fails too. This is the one state where both
    // facts are true at once, and the order they are tested in decides it.
    test('a retry in flight wins over the failure it is retrying', () async {
      feedFails(const SocketException('down'));
      await repo.ensure(unleashed);
      expect(repo.stateFor(unleashed), FirmwareFetchState.failed);

      final gate = Completer<Map<String, dynamic>>();
      feedEvery((_) => gate.future);
      final refreshing = repo.refresh();

      expect(repo.stateFor(unleashed), FirmwareFetchState.loading);
      expect(repo.failedFor(unleashed), isTrue, reason: 'both are true here');

      gate.complete(_feed());
      await refreshing;

      expect(repo.stateFor(unleashed), FirmwareFetchState.ready);
    });

    test('a fetch that failed is no longer a fetch in flight', () async {
      feedFails(const SocketException('no route to host'));

      await repo.ensure(unleashed);

      expect(repo.isLoading(unleashed), isFalse);
      expect(repo.failedFor(unleashed), isTrue);
      expect(repo.directoryFor(unleashed), isNull);
    });

    test('an unreachable server is kept, named, at warn', () async {
      feedFails(const SocketException('no route to host'));

      await repo.ensure(unleashed);

      final kept = keptAbout('directory fetch failed');
      expect(kept, hasLength(1));
      expect(kept.single, contains('[warning]'));
      expect(kept.single, contains('unlshd'));
      expect(kept.single, contains('no route to host'));
    });

    // The bare catch swallowed the decode as well, so a feed that changed
    // shape disabled the firmware page for every user at once with no
    // diagnostic — and filed at warn it would sit unnoticed among a hundred
    // airplane-mode lines.
    test('a feed that changed shape is kept at error, not warn', () async {
      feedEvery((_) async => _feedOfTheWrongShape());

      await repo.ensure(unleashed);

      expect(repo.failedFor(unleashed), isTrue);
      final kept = keptAbout('directory fetch failed');
      expect(kept, hasLength(1));
      expect(kept.single, contains('[error]'));
      expect(
        kept.single,
        contains("type 'int' is not a subtype of type 'String'"),
        reason: 'thrown by fromJson itself, not by the seam',
      );
      expect(
        kept.single,
        contains('FirmwareVersion.fromJson'),
        reason: 'the stack reaches the field that changed',
      );
    });

    test('a fetch that works again clears the failure', () async {
      feedFails(const SocketException('down'));
      await repo.ensure(unleashed);
      expect(repo.failedFor(unleashed), isTrue);

      feedWorks();
      await repo.refresh();

      expect(repo.failedFor(unleashed), isFalse);
      expect(repo.directoryFor(unleashed), isNotNull);
    });

    test('one firmware failing does not mark the other', () async {
      parserForEntry(unleashed).fetchJson = (_) async =>
          throw const SocketException('down');

      await repo.refresh();

      expect(repo.failedFor(unleashed), isTrue);
      expect(repo.failedFor(official), isFalse);
    });

    // A refresh only replaces the directory on success, so a failed one leaves
    // the last good directory standing. That is why failedFor is cleared on
    // success rather than on the way in: it has to keep describing the attempt
    // that just failed, not the one that last got as far as starting.
    test('a failed refresh keeps the directory it had, and is marked', () async {
      await repo.ensure(unleashed);
      expect(repo.directoryFor(unleashed), isNotNull);

      feedFails(const SocketException('down'));
      await repo.refresh();

      expect(repo.directoryFor(unleashed), isNotNull, reason: 'the old one');
      expect(repo.failedFor(unleashed), isTrue);
    });

    // Said once per failure, not once per retry: ensure keeps trying on a
    // cooldown, and a hundred copies of one sentence would push everything
    // else out of a 500-entry history. LogService coalesces only consecutive
    // identical bodies, and two firmwares failing in turn are not consecutive,
    // so it cannot do this job here.
    test('a failure that persists is said once', () async {
      feedFails(const SocketException('down'));

      await repo.refresh();
      await repo.refresh();
      await repo.refresh();

      expect(keptAbout('unlshd directory fetch failed'), hasLength(1));
    });

    test('a failure that comes back after a success is said again', () async {
      feedFails(const SocketException('down'));
      await repo.refresh();
      feedWorks();
      await repo.refresh();

      feedFails(const SocketException('down'));
      await repo.refresh();

      expect(keptAbout('unlshd directory fetch failed'), hasLength(2));
    });

    // FirmwareCard calls ensure from didUpdateWidget, and a connected Flipper
    // rebuilds that subtree every five seconds because device_info_watch polls
    // the battery on that interval. A failed fetch never leaves a fresh cache,
    // so without the cooldown every one of those rebuilds was another request
    // at a server already not answering.
    test('ensure leaves a firmware that just failed alone', () async {
      feedFails(const SocketException('down'));

      await repo.ensure(unleashed);
      expect(fetchCalls, 1);

      await repo.ensure(unleashed);
      await repo.ensure(unleashed);

      expect(fetchCalls, 1, reason: 'still inside the cooldown');
    });

    test('a pull-to-refresh asks again anyway', () async {
      feedFails(const SocketException('down'));

      await repo.ensure(unleashed);
      await repo.refresh();

      expect(fetchCalls, greaterThan(1), reason: 'the gesture means ask again');
    });

    // #118's own bug by a second route, and the one a catch cannot see:
    // AppHttp sets a connection timeout only, so a server that accepts the
    // connection and never answers leaves the request pending for the life of
    // the process. Nothing throws, so nothing is recorded, _loading is never
    // released, and the card reads Checking… until the app restarts.
    testWidgets('a request that never answers still ends', (tester) async {
      feedEvery((_) => Completer<dynamic>().future);

      unawaited(repo.ensure(unleashed));
      await tester.pump();
      expect(repo.isLoading(unleashed), isTrue);

      await tester.pump(const Duration(seconds: 31));

      expect(repo.isLoading(unleashed), isFalse);
      expect(repo.failedFor(unleashed), isTrue);
      final kept = keptAbout('unlshd directory fetch failed');
      expect(kept, hasLength(1));
      expect(kept.single, contains('TimeoutException'));
    });
  });

  group('FirmwareController', () {
    /// Builds a controller and lets the prefetch its constructor starts land.
    ///
    /// That prefetch is not awaited, so anything asserted before it settles is
    /// asserting against the state the controller was born in rather than
    /// against the outcome of the fetch.
    Future<void> withController(
      Future<void> Function(FirmwareController fw) body,
    ) async {
      final fw = FirmwareController();
      await pumpEventQueue();
      try {
        await body(fw);
      } finally {
        fw.dispose();
      }
    }

    // The latch itself. "Checking…" was derived from a missing directory, and
    // a fetch that fails never gets one — so the card's version line and its
    // channel dropdown said so for the rest of the session, on every firmware,
    // with no toast, no error view and nothing in the log to say why.
    //
    // `failed` rather than merely "not loading" is the other half: without it
    // the button has only fwuLabelNoUpdate left to say, which tells someone
    // with no network that their firmware is current.
    test('a fetch that failed reads as failed, not as checking', () async {
      feedFails(const SocketException('down'));

      await withController((fw) async {
        expect(fw.fetchStateFor(unleashed), FirmwareFetchState.failed);
        expect(fw.fetchStateFor(official), FirmwareFetchState.failed);
        expect(fw.latestVersionFor(unleashed), isNull);
      });
    });

    test('a first fetch is checking until it lands', () async {
      final gate = Completer<Map<String, dynamic>>();
      feedEvery((_) => gate.future);

      await withController((fw) async {
        expect(fw.fetchStateFor(unleashed), FirmwareFetchState.loading);

        gate.complete(_feed());
        await pumpEventQueue();

        expect(fw.fetchStateFor(unleashed), FirmwareFetchState.ready);
        expect(repo.directoryFor(unleashed), isNotNull);
      });
    });

    // Pull-to-refresh, and the only state where the loading set carries the
    // answer alone: the directory from the last fetch is still in hand, so
    // nothing else in the expression can tell that a new one is in flight.
    test('a refresh over a directory already in hand is checking', () async {
      await withController((fw) async {
        expect(fw.fetchStateFor(unleashed), FirmwareFetchState.ready);

        final gate = Completer<Map<String, dynamic>>();
        feedEvery((_) => gate.future);
        final refreshing = repo.refresh();

        expect(fw.fetchStateFor(unleashed), FirmwareFetchState.loading);

        gate.complete(_feed());
        await refreshing;

        expect(fw.fetchStateFor(unleashed), FirmwareFetchState.ready);
      });
    });

    // The remedy the fix advertises: airplane mode, then pull to refresh.
    //
    // Asserted against Official rather than Unleashed: Unleashed resolves its
    // display version through UnleashedParser, which looks for a packaged
    // variant among the version's files, and this feed carries none.
    test('a retry after a failure shows a real version', () async {
      feedFails(const SocketException('down'));

      await withController((fw) async {
        expect(fw.fetchStateFor(official), FirmwareFetchState.failed);
        expect(fw.latestVersionFor(official), isNull);

        feedWorks();
        await repo.refresh();

        expect(fw.fetchStateFor(official), FirmwareFetchState.ready);
        expect(fw.latestVersionFor(official), '1.0.0');
      });
    });
  });

  group('FirmwareInstaller.awaitReconnect', () {
    late _FakeClient client;

    setUp(() {
      client = _FakeClient();
      addTearDown(client.close);
    });

    test('a device that comes back is silent', () async {
      final waiting = FirmwareInstaller.awaitReconnect(
        client,
        timeout: const Duration(seconds: 5),
      );
      await pumpEventQueue();
      client.arrive();

      expect(await waiting, isTrue);
      expect(LogService.history, isEmpty);
    });

    // Zero timeout: a device already in hand must not reach the stream at all,
    // and anything that waited for one event first would time out here.
    test('a device already connected is not waited for', () async {
      client.arrive();

      expect(
        await FirmwareInstaller.awaitReconnect(client, timeout: Duration.zero),
        isTrue,
      );
      expect(LogService.history, isEmpty);
    });

    // The worst outcome this app produces: a device that was flashed and did
    // not come back. Before #118 the TimeoutException was caught and dropped,
    // so the one session most worth reading a bug report about held nothing.
    test('a device that never comes back is false, and kept at error', () async {
      final ok = await FirmwareInstaller.awaitReconnect(
        client,
        timeout: const Duration(milliseconds: 50),
      );

      expect(ok, isFalse);
      final kept = keptAbout('did not reconnect after recovery');
      expect(kept, hasLength(1));
      expect(kept.single, contains('[error]'));
      expect(kept.single, contains('TimeoutException'));

      await pumpEventQueue();
      expect(client.hasListener, isFalse, reason: 'the wait let go');
    });

    test('a disconnect event is not the device coming back', () async {
      final waiting = FirmwareInstaller.awaitReconnect(
        client,
        timeout: const Duration(milliseconds: 50),
      );
      await pumpEventQueue();
      client.stir();

      expect(await waiting, isFalse);
    });

    // A link torn down under the wait says nothing about the device, and it
    // arrives milliseconds after the flash rather than half a minute later. An
    // error line claiming the device never came back would be a guess written
    // into the log as a fact, on the most consequential screen in the app.
    test('a link torn down under the wait is not a brick', () async {
      final waiting = FirmwareInstaller.awaitReconnect(
        client,
        timeout: const Duration(seconds: 30),
      );
      await pumpEventQueue();
      await client.close();

      expect(await waiting, isFalse);
      expect(keptAbout('did not reconnect after recovery'), isEmpty);
      final kept = keptAbout('ended without an answer');
      expect(kept, hasLength(1));
      expect(kept.single, contains('[warning]'));
    });

    test('a device present when the link ends is still a success', () async {
      final waiting = FirmwareInstaller.awaitReconnect(
        client,
        timeout: const Duration(seconds: 30),
      );
      await pumpEventQueue();
      client.arriveQuietly();
      await client.close();

      expect(await waiting, isTrue);
    });
  });

  group('FirmwareUpdateButton', () {
    late DeviceController device;
    late _FakeClient client;

    setUp(() => (device, client) = mountedDevice());

    Widget button({
      required Future<void> Function({
        required FirmwareSource source,
        required FlipperClient client,
        required void Function(UpdateState) onState,
      })
      install,
      FirmwareFetchState fetchState = FirmwareFetchState.ready,
      String? latestVersion = '1.0.0',
    }) => _wrap(
      FirmwareUpdateButton(
        entry: unleashed,
        fetchState: fetchState,
        latestVersion: latestVersion,
        deviceVersion: '0.9.0',
        deviceInfo: const {},
        selectedChannelId: 'release',
        selectedVariant: UnleashedVariant.extraPacks,
        client: client,
        install: install,
      ),
      device,
    );

    // A recovery flash whose device does not re-enumerate inside 30s: a bad
    // cable, a device needing a manual power cycle, or one the flash left
    // unable to boot. The early return here used to skip _finishRecovery, so
    // _updateState stayed on UpdateWaitingForReconnect and the button sat
    // disabled on RESTARTING with the reason discarded.
    testWidgets('a device that does not come back re-enables the button', (
      tester,
    ) async {
      device.setDfuPresent(true);
      await tester.pumpWidget(
        button(
          install: ({required source, required client, required onState}) async {
            onState(const UpdateWaitingForReconnect());
          },
        ),
      );

      expect(find.text(l10n.fwuLabelRepair.toUpperCase()), findsOneWidget);

      await tester.tap(find.byType(ProgressButton));
      await tester.pump();
      await tester.pump();

      expect(
        find.text(l10n.fwuLabelRestarting.toUpperCase()),
        findsOneWidget,
        reason: 'waiting for the device',
      );

      await elapsePastReconnectDeadline(tester);

      // Which label replaces it depends on whether the DFU detector still
      // reports a device by then, and that runs on its own clock across a
      // 31-second pump. What #118 is about is that RESTARTING is gone and the
      // reason is on screen.
      expect(
        find.text(l10n.fwuLabelRestarting.toUpperCase()),
        findsNothing,
        reason: 'the transitional state was left',
      );
      expect(
        find.text(l10n.fwuRecoveryNoReconnect),
        findsNWidgets(2),
        reason: 'the button description, and a toast like every other failure',
      );
      expect(keptAbout('did not reconnect after recovery'), hasLength(1));

      await drainToast(tester);
    });

    // install() picks the DFU path from client.isConnected long after the
    // press, so a link that dropped during the download flashed over DFU and
    // emitted UpdateWaitingForReconnect for a press that had predicted an
    // ordinary update. Guarding the wait on that prediction meant the wait
    // never ran and the button never left RESTARTING.
    testWidgets('a recovery nobody predicted is still waited out', (
      tester,
    ) async {
      // Connected at press time, so _dfuOnly is false and the press predicts
      // an ordinary update - then the link drops while the archive downloads,
      // which is what sends install() down the DFU path instead.
      final fake = client;
      fake.arriveQuietly();
      await tester.pumpWidget(
        button(
          install: ({required source, required client, required onState}) async {
            fake.depart();
            onState(const UpdateWaitingForReconnect());
          },
        ),
      );

      await tester.tap(find.byType(ProgressButton));
      await tester.pump();
      await tester.pump();

      expect(find.text(l10n.fwuLabelRestarting.toUpperCase()), findsOneWidget);

      await elapsePastReconnectDeadline(tester);

      expect(find.text(l10n.fwuLabelRestarting.toUpperCase()), findsNothing);
      expect(keptAbout('did not reconnect after recovery'), hasLength(1));

      await drainToast(tester);
    });

    Future<void> pumpIdle(WidgetTester tester, Widget w) async {
      await tester.pumpWidget(w);
      await tester.pump();
    }

    Future<void> noop({
      required FirmwareSource source,
      required FlipperClient client,
      required void Function(UpdateState) onState,
    }) async {}

    // "NO UPDATE" is a claim about what the server answered. After a fetch
    // that failed there was no answer, and saying it anyway tells someone with
    // no network that their firmware is current.
    testWidgets('a directory that could not be fetched does not claim there '
        'is no update', (tester) async {
      client.arriveQuietly();

      await pumpIdle(
        tester,
        button(
          install: noop,
          fetchState: FirmwareFetchState.failed,
          latestVersion: null,
        ),
      );

      expect(find.text(l10n.fwuLabelCantCheck.toUpperCase()), findsOneWidget);
      expect(find.text(l10n.fwuLabelNoUpdate.toUpperCase()), findsNothing);
    });

    testWidgets('a server that answered with nothing newer still says so', (
      tester,
    ) async {
      client.arriveQuietly();

      await pumpIdle(
        tester,
        button(install: noop, latestVersion: null),
      );

      expect(find.text(l10n.fwuLabelNoUpdate.toUpperCase()), findsOneWidget);
    });
  });

  group('FirmwareChangelogPage', () {
    late DeviceController device;
    late _FakeClient client;

    setUp(() => (device, client) = mountedDevice());

    // The page ran the render through `compute` and checked only !hasData, so
    // a render that failed left the spinner turning for as long as the page
    // was open with nothing written down. Nothing else in the app pays for
    // that isolate: pages/apps/catalog/detail_page.dart calls the same
    // function three times from inside `build`.
    testWidgets('a render that fails shows the changelog unstyled', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          FirmwareChangelogPage(
            entry: unleashed,
            version: const FirmwareVersion(
              version: '1.0.0',
              changelog: 'raw **markdown** text',
              timestamp: 0,
              files: [],
            ),
            changelog: 'raw **markdown** text',
            fetchState: FirmwareFetchState.ready,
            latestVersion: '1.0.0',
            deviceVersion: '0.9.0',
            deviceInfo: const {},
            selectedChannelId: 'release',
            selectedVariant: UnleashedVariant.extraPacks,
            client: client,
            renderHtml: (_) => throw const FormatException('bad markdown'),
          ),
          device,
        ),
      );

      // No pump-and-wait: the render is synchronous now, so the first frame
      // is already the answer. That is the whole of the fix for this surface
      // - there is no longer an unsettled state for a failure to strand.
      expect(find.byType(ChangelogRenderer), findsNothing);
      expect(find.text('raw **markdown** text'), findsOneWidget);
      expect(keptAbout('changelog render failed'), hasLength(1));
    });
  });
}
