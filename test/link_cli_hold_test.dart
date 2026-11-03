import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flipperlib/flipperlib.dart' hide DateTime;
import 'package:flutter_test/flutter_test.dart';
import 'package:qunleashed/services/connection/device_settings.dart';
import 'package:qunleashed/services/connection/link_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'known_device_ids.dart';
import 'link_autoconnect_test.dart' show FakeDialClient, usb;

/// Keeping a CLI channel across the link, which had no tests at all.
///
/// `grep holdCli test/` returned nothing before this file, in either
/// direction: neither the restore that works nor the one that does not was
/// asserted anywhere, which is most of why #461 reached a default build
/// unnoticed.
///
/// The hold is what the remote CLI page runs inside. It is not a convenience:
/// a channel that dies takes the terminal with it, and the user is looking at
/// a cable that is still plugged in.
/// A channel a test can kill without unplugging anything.
///
/// That distinction is the whole subject here. A Flipper that detaches takes
/// its id out of both USB sets on the next reconcile, and the restore worked
/// on that path all along; a channel that dies while the cable stays in is
/// the one that did not, until #461.
class _FakeChannel implements FlipperCliChannel {
  _FakeChannel(this.device);

  @override
  final FlipperDevice device;

  bool _open = true;

  @override
  bool get isOpen => _open;

  /// A session fault, the firmware closing the CLI, an RPC error - whatever
  /// ended it, the cable is still in.
  void die() => _open = false;

  int closeCalls = 0;

  @override
  Future<void> close({bool backToRpc = true}) async => closeCalls += 1;

  @override
  Future<void> write(Uint8List bytes) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// The dial fake, plus the CLI half this file is about.
///
/// `FakeDialClient` is the shared one - `auto_connect_hint_test.dart` and
/// `connect_transport_labels_test.dart` import it too, the second by
/// subclassing it exactly as this does - and everything here that is not CLI
/// came from it: the four stream controllers, `present`, `sessions`,
/// `dialled`, `plugged()` and `reportSessions()`. Its `connectThrows` and
/// `parkConnect` come along and are never set in this file.
class _FakeCliClient extends FakeDialClient {
  /// Every `openCli`, in order.
  final List<_FakeChannel> opened = [];

  /// Raised by the next `openCli`, for the failure half of the hold.
  Object? cliThrows;

  /// When set, `openCli` waits on it before handing a channel back, so a case
  /// can let the hold go while an open is still in flight.
  Completer<void>? parkOpen;

  @override
  Future<FlipperCliChannel> openCli(FlipperDevice device) async {
    final failure = cliThrows;
    if (failure != null) throw failure;
    final park = parkOpen;
    if (park != null) await park.future;
    final channel = _FakeChannel(device);
    opened.add(channel);
    return channel;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeCliClient client;

  setUp(() {
    client = _FakeCliClient();
    addTearDown(() async => client.close());
  });

  /// Builds a service with the two auto-connect settings in force, and a
  /// remembered BLE Flipper on disk.
  ///
  /// The remembered device is not decoration: the BLE branch of
  /// `_reconcileOnce` is where control lands when the CLI restore declines,
  /// so without a `lastDevice` the difference between "the restore worked"
  /// and "nothing happened at all" is invisible.
  ///
  /// `DeviceSettings` is a singleton that caches its load, hence the reset and
  /// the setters - `link_autoconnect_test.dart` says the same thing at more
  /// length, and ADR 0002 is about the day neither has to.
  Future<LinkService> serviceWith({
    bool usbAuto = true,
    bool bleAuto = true,
  }) async {
    SharedPreferences.setMockInitialValues({
      'known_devices_v1': jsonEncode([
        storedEntry(
          reportedById,
          'the remembered one',
          '2026-10-01T10:00:00.000',
        ),
      ]),
    });
    final settings = DeviceSettings.instance..reset();
    await settings.load();
    await settings.setAutoConnectUsb(usbAuto);
    await settings.setAutoConnectBle(bleAuto);

    final service = LinkService.forTest(client);
    addTearDown(service.dispose);
    return service;
  }

  /// Lets the reconcile debounce and the reconcile behind it run.
  Future<void> settle() =>
      Future<void>.delayed(const Duration(milliseconds: 400));

  /// A cable with a CLI opened on it and then held - which is what the remote
  /// CLI page leaves behind.
  ///
  /// [appDials] is whether the app dialled that cable itself on the way, and
  /// it is asserted either way. With `autoConnectUsb` on, the dial is the
  /// premise #461 is about: it is the only observable proof that the id is in
  /// `_autoTriedUsb`. With it off, the *absence* of a dial is the premise
  /// instead, and that case is about the restore consulting no setting.
  ///
  /// Returns the channel the page would be holding. The dial list is cleared
  /// afterwards so a case asserts on what happened *after* the hold, not on
  /// the arrangement.
  Future<
    ({
      _FakeChannel channel,
      List<FlipperCliChannel> handed,
      List<Object> failures,
    })
  >
  heldCliOnDialledCable(LinkService links, {bool appDials = true}) async {
    client.present = [usb('A')];
    client.plugged();
    await settle();
    // The USB dials only. With `appDials` off the setting that would have
    // taken this cable is off, so control reaches the Bluetooth branch and
    // the remembered Flipper is dialled - which is correct, and which the
    // arrangement this replaced hid behind a `dialled.clear()`.
    expect(
      client.dialled.where((d) => d.startsWith('usb:')),
      appDials ? ['usb:A'] : isEmpty,
      reason: appDials
          ? 'premise: the app dialled the cable itself, so A is auto-tried'
          : 'premise: nothing dialled this cable, so A is not auto-tried',
    );

    final channel = _FakeChannel(usb('A'));
    final handed = <FlipperCliChannel>[];
    final failures = <Object>[];
    links.holdCli(channel, onChannel: handed.add, onFailure: failures.add);
    client.dialled.clear();
    return (channel: channel, handed: handed, failures: failures);
  }

  group('a CLI hold whose Flipper went away', () {
    // The path that worked before #461 as well, and the reason it did: the
    // device going absent is what prunes the set the restore filters on, so
    // the cable is a candidate again when it comes back. Pinned first,
    // because the fix for the group below must not cost this one.
    test('is taken back when the cable returns', () async {
      final links = await serviceWith();
      final hold = await heldCliOnDialledCable(links);

      hold.channel.die();
      client.present = const [];
      client.plugged();
      await settle();

      // Cleared here and not before: while the cable is away, dialling the
      // remembered Bluetooth Flipper is the right answer and the service
      // gives it. What this case is about is the reconcile *after* the cable
      // comes back.
      client.dialled.clear();
      client.present = [usb('A')];
      client.plugged();
      await settle();

      expect(hold.handed, hasLength(1));
      expect(hold.handed.single.device.id, 'A');
      expect(
        client.dialled,
        isEmpty,
        reason: 'the CLI restore ends the reconcile before any dial',
      );
    });

    // `_restoreCli` prefers the device the hold was on and falls back to the
    // first candidate, which is `holdCli`'s own promise: "when its Flipper
    // returns after the link went away, **or another one is plugged in**, it
    // is taken back in CLI rather than RPC". Nothing pinned the fallback - the
    // neighbour case in the group below pins the *preference*, which is the
    // opposite end of the same `firstWhere`.
    test('is taken back on a neighbour when its own cable is gone', () async {
      final links = await serviceWith();
      final hold = await heldCliOnDialledCable(links);

      hold.channel.die();
      client.present = [usb('B')];
      client.plugged();
      await settle();

      expect(hold.handed, hasLength(1));
      expect(
        hold.handed.single.device.id,
        'B',
        reason: 'the terminal moves to the Flipper that is actually there',
      );
    });

    // A channel that opens for a hold nobody is holding any more has to be
    // closed, or the Flipper is left in CLI mode with nothing to talk to it -
    // every RPC call then fails until something reopens the mode. The open is
    // parked mid-flight because that is the only way to reach the window:
    // `releaseCli` has to land between `openCli` being called and its channel
    // arriving.
    test('closes a channel that opened after the hold was let go', () async {
      final links = await serviceWith();
      final hold = await heldCliOnDialledCable(links);
      final park = Completer<void>();
      client.parkOpen = park;

      hold.channel.die();
      client.present = const [];
      client.plugged();
      await settle();
      client.present = [usb('A')];
      client.plugged();
      await settle();
      expect(
        client.opened,
        isEmpty,
        reason: 'premise: the open is in flight, not finished',
      );

      links.releaseCli();
      park.complete();
      await settle();

      expect(hold.handed, isEmpty, reason: 'nobody is holding it now');
      expect(client.opened.single.closeCalls, 1);
    });

    test('is let go of by releaseCli', () async {
      final links = await serviceWith();
      final hold = await heldCliOnDialledCable(links);

      links.releaseCli();
      hold.channel.die();
      client.present = const [];
      client.plugged();
      await settle();
      client.present = [usb('A')];
      client.plugged();
      await settle();

      expect(hold.handed, isEmpty);
    });

    // A restore that cannot open tells the holder, which is what lets the CLI
    // page say so rather than sit on a dead terminal.
    test('tells the holder when the CLI will not open', () async {
      final links = await serviceWith();
      final hold = await heldCliOnDialledCable(links);

      client.cliThrows = StateError('no transport');
      hold.channel.die();
      client.present = const [];
      client.plugged();
      await settle();
      client.present = [usb('A')];
      client.plugged();
      await settle();

      expect(hold.failures, hasLength(1));
      expect(hold.handed, isEmpty);
    });
  });

  group('a CLI hold whose channel died with the cable still in', () {
    // #461. The app dialled this cable at launch, so its id is in
    // `_autoTriedUsb` and stays there while the cable is present. The restore
    // used to filter on that set, so it found no candidate, the USB branch
    // skipped the same id, and control fell through to the remembered
    // Bluetooth Flipper - dialled while the user sat on the CLI page with a
    // cable in hand, and with nothing told to the page about why its channel
    // had not come back.
    //
    // The premise is in `heldCliOnDialledCable`, which asserts the launch
    // dial happened: without it this case would pass on a cable that was
    // never auto-tried, which is exactly the state #461 is not about.
    test('is taken back on the cable it was already on', () async {
      final links = await serviceWith();
      final hold = await heldCliOnDialledCable(links);

      hold.channel.die();
      client.plugged();
      await settle();

      expect(hold.handed, hasLength(1));
      expect(hold.handed.single.device.id, 'A');
      expect(
        client.dialled,
        isEmpty,
        reason: 'and Bluetooth is not dialled instead',
      );
    });

    // The restore consults no setting, which is the rule the service states
    // about held links generally: the user asked for this terminal and the
    // hold outranks a preference about forming links by itself.
    //
    // Also the one case in this group that passed before #461, and it is here
    // to say why that is not a contradiction. With `usbAuto: false` nothing
    // ever dialled this cable, so the set the restore used to filter on was
    // empty and it found its candidate anyway. What #461 fixed is the default
    // build, where the launch dial has filled that set - which is the case
    // above.
    test('is taken back with USB auto-connect off', () async {
      final links = await serviceWith(usbAuto: false);
      final hold = await heldCliOnDialledCable(links, appDials: false);

      hold.channel.die();
      client.plugged();
      await settle();

      expect(hold.handed, hasLength(1));
    });

    // Driven by a sessions emission rather than a replug, because that is
    // the trigger production has. A channel stops being open when its session
    // faults or leaves CLI mode, and flipperlib watches each session's
    // connection stream to re-emit sessions - `_emitSessions` - which is what
    // `_onSessions` schedules a reconcile from. No USB attach event happens:
    // the cable never moved. Every other case here calls `plugged()` because
    // it is shorter, and this one is why that shortcut is not load-bearing.
    test('is taken back without a USB event to wake it', () async {
      final links = await serviceWith();
      final hold = await heldCliOnDialledCable(links);

      hold.channel.die();
      client.reportSessions(const []);
      await settle();

      expect(hold.handed, hasLength(1));
      expect(hold.handed.single.device.id, 'A');
    });

    // The guard the filter is actually for, which is why the fix is a second
    // set rather than dropping the clause. `_restoreCli` ends the reconcile
    // whenever it has a candidate, and a failed open is itself one of the
    // things that schedules the next one - so a cable that cannot be reopened
    // would be retried forever.
    test('is tried once, not on every reconcile', () async {
      final links = await serviceWith();
      final hold = await heldCliOnDialledCable(links);

      client.cliThrows = StateError('no transport');
      hold.channel.die();
      client.plugged();
      await settle();
      expect(
        hold.failures,
        hasLength(1),
        reason: 'premise: it tried, and failed',
      );

      client.plugged();
      await settle();
      client.plugged();
      await settle();

      expect(
        hold.failures,
        hasLength(1),
        reason: 'two more reconciles, no second attempt',
      );

      // Measured, and left unasserted on purpose: the reconcile after the
      // failed restore falls through to the remembered Bluetooth Flipper and
      // dials it, once, because `_bleAutoTried` latches. That is not #461's
      // symptom - the restore was attempted and the cable refused - and it is
      // the same thing any cable that cannot be opened does. Pinning it here
      // would make this case fail for a reason it is not about; it is written
      // down because the log of this case shows the dial and the next reader
      // should not have to wonder whether it is the bug.
    });

    // And the other side of that: holding on to the failure would mean a hold
    // survived exactly one fault. A restore that worked clears the cable, so
    // the next death of the channel it handed over is a new question.
    test('is taken back again when the restored channel dies too', () async {
      final links = await serviceWith();
      final hold = await heldCliOnDialledCable(links);

      hold.channel.die();
      client.plugged();
      await settle();
      expect(hold.handed, hasLength(1), reason: 'premise: the first restore');

      (hold.handed.single as _FakeChannel).die();
      client.plugged();
      await settle();

      expect(hold.handed, hasLength(2));
    });

    // `holdCli` clears the attempt set, and this is what that is for. Without
    // it a cable one hold failed on would be unreachable to the next for as
    // long as it stays plugged in - the same shape as #461, one hold along.
    //
    // Defence rather than a path a user walks today, and worth being exact
    // about: the CLI page takes one hold per instance - `holdCli` is called
    // from `_openChannel` only, and a restored channel arrives at
    // `_onChannel`, which attaches without re-holding - and leaving the page
    // calls `releaseCli`, which clears the set anyway. So what this pins is
    // the invariant, which is what the next holder will rely on.
    test('does not inherit the cables a previous hold failed on', () async {
      final links = await serviceWith();
      final hold = await heldCliOnDialledCable(links);

      client.cliThrows = StateError('no transport');
      hold.channel.die();
      client.plugged();
      await settle();
      expect(
        hold.failures,
        hasLength(1),
        reason: 'premise: this hold tried A and failed',
      );

      client.cliThrows = null;
      final second = _FakeChannel(usb('A'));
      final handed = <FlipperCliChannel>[];
      links.holdCli(second, onChannel: handed.add, onFailure: (_) {});

      second.die();
      client.plugged();
      await settle();

      expect(handed, hasLength(1));
    });

    // The absence prune, which nothing else here reaches: the cases above
    // that unplug a cable never got as far as recording an attempt on it, so
    // removing the prune left every one of them green. A *failed* attempt is
    // the only thing the prune has to clear, and a replug is the same fresh
    // question for the restore that it is for auto-connect.
    test(
      'is tried again once that cable has been unplugged and put back',
      () async {
        final links = await serviceWith();
        final hold = await heldCliOnDialledCable(links);

        client.cliThrows = StateError('no transport');
        hold.channel.die();
        client.plugged();
        await settle();
        expect(
          hold.failures,
          hasLength(1),
          reason: 'premise: it tried A, failed, and will not try again',
        );

        client.cliThrows = null;
        client.present = const [];
        client.plugged();
        await settle();
        client.present = [usb('A')];
        client.plugged();
        await settle();

        expect(hold.handed, hasLength(1));
      },
    );

    // The cable is still the one the hold was on, so a second Flipper plugged
    // in beside it is not what gets taken - `_restoreCli` prefers the
    // previous device and only falls back to the first candidate.
    test('is taken back on its own cable, not on a neighbour', () async {
      final links = await serviceWith();
      final hold = await heldCliOnDialledCable(links);

      client.present = [usb('B'), usb('A')];
      hold.channel.die();
      client.plugged();
      await settle();

      expect(hold.handed, hasLength(1));
      expect(hold.handed.single.device.id, 'A');
    });
  });
}
