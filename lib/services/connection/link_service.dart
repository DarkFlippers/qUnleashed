import 'dart:async';

import 'package:flipperlib/flipperlib.dart' hide DateTime;
import 'package:flutter/foundation.dart';

import '../guarded.dart';
import '../logging.dart';
import '../telemetry/traced.dart';
import 'connect_report.dart';
import 'device_settings.dart';
import 'known_devices.dart';

enum LinkSession { none, connecting, connected, active }

enum LinkActivity { idle, connecting }

/// One row of the connection list: a Flipper the app can reach right now or
/// remembers, with everything the row shows folded in.
class LinkEntry {
  const LinkEntry({
    required this.id,
    required this.link,
    required this.name,
    required this.address,
    required this.session,
    required this.heard,
    required this.activity,
    this.device,
    this.known,
  });

  final String id;
  final FlipperLink link;
  final String name;

  /// Where the device is, in the terms of its own transport: the Bluetooth
  /// address, or the serial port the cable shows up as.
  final String address;
  final FlipperDevice? device;
  final KnownDevice? known;
  final LinkSession session;
  final bool heard;
  final LinkActivity activity;

  bool get isUsb => link == FlipperLink.usb;
  bool get isBle => link == FlipperLink.ble;
  bool get held => session != LinkSession.none;
  bool get busy =>
      activity != LinkActivity.idle || session == LinkSession.connecting;

  String get key => '${link.name}:$id';
}

/// An auto-connect that failed and has not been answered since.
///
/// Auto-connect runs off a debounced timer with no gesture behind it, so
/// there is nothing to hang a dialog on - and popping one for a cable event
/// would be wrong even if there were. The condition also outlives the
/// attempt: the cable stays `_UsbCable.autoTried` while it is present, so the
/// Flipper that just failed is not dialled again until something changes.
/// From the user's side the cable does nothing, forever, with no explanation.
///
/// So the failure is kept rather than only logged, and the device page shows
/// it until it stops being true. #120.
class AutoConnectFailure {
  const AutoConnectFailure({
    required this.key,
    required this.name,
    required this.error,
  });

  /// The `link:id` of the Flipper that was being dialled.
  final String key;

  /// What to call it in the hint.
  final String name;

  /// The thrown object, for [FlipperConnectErrorKind] and for the log.
  final Object error;

  bool get isBle => key.startsWith('ble:');
}

/// Owns every link decision the app makes on its own: which USB Flippers are
/// plugged in, which remembered BLE ones were actually heard, and when to
/// connect without being asked.
///
/// USB presence is event-driven: the OS reports attach and detach, and each
/// report re-enumerates the ports. BLE presence is evidence only: a device
/// starts offline and is shown online once the radio has heard it, through a
/// search or a live link. It is never asked for on its own — a remembered
/// device is dialled by its address, which is both the question and the
/// answer.
/// What is known about one USB cable, and when each answer stops being true.
///
/// The three per-cable questions `LinkService` used to keep as three sets
/// keyed by the same USB device id. They are here as named members with their
/// lifetimes as methods, because reading the wrong one is what shipped #460
/// and #461 and a set named for one question cannot refuse the other. #469.
///
/// Two things deliberately not here. `_userDisconnectedKey` is one slot shared
/// with BLE, so absorbing it would change behaviour - a second cable the user
/// disconnected is forgotten the moment they disconnect another, and whether
/// that is intended is a question of its own rather than part of a refactor.
/// `_CliHold.tried` stays on the hold, which is where #461 put it: it is
/// hold-scoped, not cable-scoped, and a new hold is meant to have tried
/// nothing.
class _UsbCable {
  /// The app is meant to be holding this link.
  ///
  /// Connecting to the cable is that statement, and it outlives the link: a
  /// Flipper that rebooted into the updater or had its cable knocked out is
  /// taken back when it returns, because nobody asked for it to go. Only the
  /// user letting it go clears it, so it survives absence - [forgetPresence]
  /// leaves it alone.
  ///
  /// Whether `autoConnectUsb` gets a say in the take-back depends on
  /// [appFormed], not on this.
  bool held = false;

  /// This hold is one the app dialled on its own, until somebody asks for it.
  ///
  /// [held] means *the app is meant to be holding this link*, and the hold
  /// tier honours it ahead of `autoConnectUsb`: a link the user asked for is
  /// not something a setting they flipped afterwards takes back. Since #458
  /// turned that setting on by default the app's own dial became the main
  /// thing setting this, so a cable dialled at launch kept being taken back
  /// after the user turned the setting off - with `trigger: 'holding this
  /// one'`, on behalf of nobody. #460.
  ///
  /// So the hold stays one tier and this records who formed it. One place
  /// sets it - the dial in `_reconcileOnce` that takes a cable nobody asked
  /// about - and three clear it again, each because the answer has stopped
  /// being true rather than as a courtesy:
  ///
  /// - `connect` and `connectDevice`, the two by-hand paths. Pressing either
  ///   is the statement the hold tier exists for, whoever dialled first.
  /// - `awaitUsbReturn`, the install path, and the reason this is an
  ///   endorsement rather than a condition on the setting. The hold has to
  ///   survive a reboot into the updater and that wait has no deadline, so an
  ///   app-formed hold standing down on the return would hang the install for
  ///   good.
  /// - `disconnectDevice`, which is not an endorsement at all: it lets the
  ///   hold go and the origin goes with it, so nothing stale is left to answer
  ///   for a link formed later by some path that sets neither.
  ///
  /// `_restoreCli` forms a link too and deliberately sets nothing. A user with
  /// a terminal open on a Flipper has asked for that link about as plainly as
  /// this app can be asked, so the hold a restore leaves behind is a
  /// user-formed one. Taking a hold back is not a write either: the app is
  /// acting on a statement that is already there, and recording it would turn
  /// every user-formed hold into an app-formed one the first time a cable was
  /// knocked out.
  ///
  /// Reachable with [held] false, which is why this is a field here rather
  /// than a map keyed on holds: the origin is set before the dial, and a dial
  /// that failed leaves it behind with no hold at all.
  bool appFormed = false;

  /// Auto-connect has dialled this cable since it appeared.
  ///
  /// The only one of the three that does not survive absence, and that is the
  /// whole of what makes the next appearance a fresh question rather than one
  /// already answered. `_restoreCli` sets it too, so that a restore which
  /// failed does not leave the USB branch free to dial the same cable into RPC
  /// underneath a user who is asking for a terminal on it.
  bool autoTried = false;

  /// Nothing left to say about this cable, so the entry can go.
  ///
  /// Read by the prune in `_reconcileOnce` after [forgetPresence], so that the
  /// map does not keep an entry for every cable ever plugged into the machine
  /// while the two answers that outlive absence still do.
  bool get isSpent => !held && !appFormed && !autoTried;

  /// Claims the one automatic dial this appearance gets, or says it is taken.
  ///
  /// One call because the caller is a `continue` in a loop: as a separate
  /// check and record it is two statements that have to agree, which is the
  /// shape the set's `add` return value was keeping honest.
  bool claimAutoDial() {
    if (autoTried) return false;
    autoTried = true;
    return true;
  }

  /// The cable is no longer present.
  ///
  /// [autoTried] is the only answer that stops being true. [held] and
  /// [appFormed] surviving this is the point of both of them.
  void forgetPresence() => autoTried = false;
}

class LinkService extends ChangeNotifier {
  LinkService._();

  static final LinkService instance = LinkService._();

  /// A service of its own, already started on [client].
  ///
  /// [instance] stays the one the app uses - ADR 0002 leaves the existing
  /// singletons alone. This exists because [entries] is the list a user picks
  /// a Flipper from and could not be exercised at all: the constructor is
  /// private, and [start] is one-shot, so a second case would have inherited
  /// the first one's client and its sessions.
  @visibleForTesting
  factory LinkService.forTest(FlipperClient client) =>
      LinkService._()..start(client);

  static const Duration _usbDebounce = Duration(milliseconds: 250);

  FlipperClient? _client;
  final KnownDevicesStore _known = KnownDevicesStore.instance;
  final DeviceSettings _settings = DeviceSettings.instance;

  bool _suspended = false;
  List<FlipperDevice> _usbPresent = const [];
  final Set<String> _heardBle = {};
  final Map<String, LinkActivity> _activity = {};
  Set<String> _bleSessionIds = {};

  /// What the service knows about each USB cable, keyed by its device id.
  ///
  /// Three questions that were three sets of the same key type, each with its
  /// own rule for when an entry stops being true and each rule written only in
  /// a paragraph of doc. Both of the previous batch's bugs were one of those
  /// sets answering a question it was not asked - #461 read *auto-connect has
  /// dialled this cable* as *the restore has tried it*, #460 read *the app is
  /// meant to be holding this link* as *the user asked for this link* - so the
  /// rules live on [_UsbCable] as named members and the prune is one pass.
  /// #469.
  ///
  /// Read through [_isHeld] and [_isAppFormed], which answer for a cable
  /// nothing has been said about yet without putting an entry in the map;
  /// [_cable] is the one that creates. An entry that has nothing left to say
  /// is dropped by the prune in [_reconcileOnce], so this holds one entry per
  /// cable with a live hold or a live origin plus the ones present right now.
  final Map<String, _UsbCable> _usbCables = {};

  /// The record for [id], created if this is the first thing to say about it.
  _UsbCable _cable(String id) => _usbCables.putIfAbsent(id, _UsbCable.new);

  /// Whether the app is meant to be holding the USB link on [id].
  bool _isHeld(String id) => _usbCables[id]?.held ?? false;

  /// Whether the hold on [id] is one the app formed by itself.
  bool _isAppFormed(String id) => _usbCables[id]?.appFormed ?? false;

  String? _userDisconnectedKey;

  // Keys whose connect the user called off while it was in flight. The
  // platform reports an aborted connect as a failure like any other, and a
  // cancel that answered with "connection failed" would read as the app
  // refusing to do what it was just told to stop doing.
  final Set<String> _cancelled = {};
  bool _bleAutoTried = false;
  AutoConnectFailure? _autoFailure;
  _CliHold? _cliHold;
  Timer? _usbTimer;
  bool _reconciling = false;
  bool _reconcileAgain = false;

  final StreamController<FlipperDevice> _releasedCtrl =
      StreamController<FlipperDevice>.broadcast();
  StreamSubscription<void>? _usbSub;
  StreamSubscription<List<FlipperSessionInfo>>? _sessionsSub;
  StreamSubscription<FlipperConnectionState>? _connectionSub;
  StreamSubscription<FlipperDevice>? _heardSub;

  FlipperClient get _c => _client ?? FlipperOneClient().get();

  /// Fires when the user closed the active link and no other session took
  /// its place: the device page has nothing left to describe.
  Stream<FlipperDevice> get activeReleased => _releasedCtrl.stream;

  bool get scanning => _c.isScanning;

  /// The last auto-connect that failed, while that is still the situation.
  ///
  /// Cleared when the same Flipper comes up, when it goes away, when the user
  /// dials it by hand - the picker reports its own outcome then - and by
  /// [dismissAutoConnectFailure]. Nothing else expires it, because nothing
  /// else changes the answer: see [AutoConnectFailure].
  AutoConnectFailure? get autoConnectFailure => _autoFailure;

  /// Puts the hint away. The condition may well still hold; the user has read
  /// it, and auto-connect does not try again on its own either way.
  void dismissAutoConnectFailure() {
    if (_autoFailure == null) return;
    _autoFailure = null;
    notifyListeners();
  }

  /// Remembers one failed automatic attempt, and reports it - ADR 0013 §2.
  ///
  /// The reporting goes here rather than in the two catches that call it,
  /// because this is already the funnel: [_autoDial] covers both auto-dials
  /// and [_restoreCli] the CLI handoff, all three of them land here, and
  /// [AutoConnectFailure.isBle] already derives the transport from [key] - so
  /// the alternative was the same call twice with the transport spelled two
  /// different ways, one of them hardcoded.
  ///
  /// **A cancel is not reported.** [connect] and [_open] never get this far:
  /// they set an activity, so `disconnectDevice` puts the key in [_cancelled]
  /// and they swallow the abort at [_cancelledAndSaidSo]. The remembered-BLE
  /// dial sets no activity and so cannot be in [_cancelled] at all - it
  /// reaches its catch carrying flipperlib's own `BLE connect aborted`, a
  /// string no needle matches, which over BLE is an issue. One user cancelling
  /// the opening dial would have filed one, in the list §2 keeps for strings
  /// the classifier can learn from. [_restoreCli] had the same hole from the
  /// other side: it *does* set an activity, and its catch does not consult it.
  ///
  /// [_userDisconnectedKey] and not [_cancelled], because
  /// `disconnectDevice` sets it unconditionally and it is the same signal
  /// [_reconcileOnce] refuses to re-dial on - so one condition covers all
  /// three paths.
  ///
  /// The hint still goes up for a cancel, and says "auto-connect failed" when
  /// the user is the one who called it off. That is wrong, predates this, and
  /// wants the remembered dial to grow the activity discipline the other two
  /// have - which moves `LinkEntry.busy` on a connect path and is its own
  /// task, not telemetry's.
  void _recordAutoFailure(
    String key,
    String name,
    Object error,
    StackTrace stack,
  ) {
    _autoFailure = AutoConnectFailure(key: key, name: name, error: error);
    if (_userDisconnectedKey != key) {
      reportConnectFailure(
        error,
        stack,
        attempt: ConnectAttempt.auto,
        isBle: _autoFailure!.isBle,
      );
    }
    notifyListeners();
  }

  void _clearAutoFailure(String key) {
    if (_autoFailure?.key != key) return;
    _autoFailure = null;
    notifyListeners();
  }

  /// Whether anything may connect on its own right now.
  bool get suspended => _suspended;

  /// Set while a DFU repair holds the USB port, and while the app is shutting
  /// down; nothing connects on its own until it is released.
  set suspended(bool value) {
    if (_suspended == value) return;
    _suspended = value;
    if (!value) _scheduleReconcile();
  }

  void start(FlipperClient client) {
    if (_client != null) return;
    _client = client;
    _bleSessionIds = _sessionIds(client.sessions, FlipperLink.ble);
    _usbSub = client.usbEvents.listen((_) => _scheduleReconcile());
    _sessionsSub = client.sessionsStream.listen(_onSessions);
    _connectionSub = client.connectionStream.listen(_onConnection);
    _heardSub = client.bleHeard.listen(_onHeard);
    _known.addListener(notifyListeners);
    _settings.addListener(_scheduleReconcile);
    unawaited(guarded('[Link] load device settings', _settings.load));
    unawaited(
      guarded(
        '[Link] load known devices',
        () => _known.load().whenComplete(_scheduleReconcile),
      ),
    );
  }

  // ── Rows ─────────────────────────────────────────────────────────────────

  List<LinkEntry> get entries {
    final sessions = {
      for (final s in _c.sessions) '${s.device.link.name}:${s.device.id}': s,
    };
    final usb = <LinkEntry>[];
    final seenUsb = <String>{};
    for (final device in _usbPresent) {
      seenUsb.add(device.id);
      usb.add(_usbEntry(device, sessions['usb:${device.id}']));
    }
    for (final s in sessions.values) {
      if (!s.device.isUsb || seenUsb.contains(s.device.id)) continue;
      usb.add(_usbEntry(s.device, s));
    }
    usb.sort((a, b) => a.name.compareTo(b.name));

    final ble = <LinkEntry>[
      for (final known in _known.devices)
        _bleEntry(known, sessions['ble:${known.id}']),
    ];
    return [...usb, ...ble];
  }

  LinkEntry _usbEntry(FlipperDevice device, FlipperSessionInfo? session) {
    final key = 'usb:${device.id}';
    return LinkEntry(
      id: device.id,
      link: FlipperLink.usb,
      name: _c.getNameOf(device) ?? device.name,
      address: _usbAddress(device),
      device: device,
      session: _sessionOf(session),
      heard: true,
      activity: _activity[key] ?? LinkActivity.idle,
    );
  }

  // The port the cable came up as: the COM port or tty path on a desktop, the
  // device node on Android. The plain id is neither on Android, where it is
  // the vendor and product pair.
  static String _usbAddress(FlipperDevice device) {
    final source = device.source;
    if (source is DesktopUsbDiscoveredDevice) return source.portName;
    if (source is AndroidUsbDiscoveredDevice) {
      return source.usbDevice.deviceName;
    }
    return device.id;
  }

  LinkEntry _bleEntry(KnownDevice known, FlipperSessionInfo? session) {
    final key = 'ble:${known.id}';
    final state = _sessionOf(session);
    return LinkEntry(
      id: known.id,
      link: FlipperLink.ble,
      name: known.name,
      address: known.id,
      device: session?.device,
      known: known,
      session: state,
      heard: state != LinkSession.none || _heardBle.contains(known.id),
      activity: _activity[key] ?? LinkActivity.idle,
    );
  }

  static LinkSession _sessionOf(FlipperSessionInfo? session) {
    if (session == null) return LinkSession.none;
    if (session.connecting) return LinkSession.connecting;
    if (!session.connected) return LinkSession.none;
    return session.active ? LinkSession.active : LinkSession.connected;
  }

  // ── Actions ──────────────────────────────────────────────────────────────

  /// Opens or activates the link of [entry]. Throws when it failed.
  ///
  /// A remembered BLE device is dialled straight by its address: the platform
  /// resolves it without discovery, so asking first whether it is in range
  /// would only delay the connect that answers the same question.
  ///
  /// Timed as one operation — ADR 0013 §2 names connect first, because "it
  /// took ages to connect" is the bug report this app gets most and nothing
  /// until now could say over which transport or how long. The transport is
  /// attached because it is the one fact that splits the answer; the device id
  /// is not, and a name least of all.
  ///
  /// [traced] goes **after** the early return. A caller that asks twice while
  /// the first attempt is running is not a second connect, and recording it as
  /// a nil-duration one would put a cloud of empty operations around every
  /// real one.
  Future<void> connect(LinkEntry entry) async {
    if (entry.busy || entry.session == LinkSession.active) return;
    return traced('device.connect', (trace) async {
      trace.note('link', entry.link.name);
      trace.note('held', entry.held);
      _forgiveUserDisconnect(entry.key);
      if (entry.isUsb) _usbLinkAskedFor(entry.id);
      if (entry.held) {
        await _c.activateById(entry.id, link: entry.link);
        return;
      }
      if (entry.isUsb) {
        final device = entry.device;
        if (device == null) return;
        await _open(device, entry.key, trace: trace);
        return;
      }
      _setActivity(entry.key, LinkActivity.connecting);
      try {
        await _c.connectBleAddress(entry.id, name: entry.name);
        await _c.switchToRpcMode();
      } catch (e) {
        if (_cancelledAndSaidSo(entry.key, trace)) return;
        if (classifyConnectError(e) ==
            FlipperConnectErrorKind.deviceUnreachable) {
          _heardBle.remove(entry.id);
        }
        rethrow;
      } finally {
        _cancelled.remove(entry.key);
        _setActivity(entry.key, LinkActivity.idle);
      }
    });
  }

  /// Connects to a device the search found. Throws on failure.
  ///
  /// Timed like [connect], and separately: reaching a device the search just
  /// found is a different thing from dialling a remembered one, and lumping
  /// them under one name would hide which of the two is slow.
  Future<void> connectDevice(FlipperDevice device) async {
    return traced('device.connect.discovered', (trace) async {
      trace.note('link', device.link.name);
      final key = '${device.link.name}:${device.id}';
      _forgiveUserDisconnect(key);
      if (device.isUsb) _usbLinkAskedFor(device.id);
      await _open(device, key, trace: trace);
      if (device.isBle) _heardBle.add(device.id);
      notifyListeners();
    });
  }

  /// Whether [key] was cancelled, and if so says so on [trace].
  ///
  /// The swallow itself is right - a Disconnect pressed mid-dial is not a
  /// fault - and that is what made it a lie once the dial was traced: the body
  /// returned normally, so the span read `ok` and carried the whole duration of
  /// an attempt the user gave up on. Attempts are given up on *because* they
  /// are hanging, so every one of them landed in the tail of the distribution
  /// the operation exists to measure.
  ///
  /// One method for the two places that swallow a cancel, so the word a
  /// dashboard filters on is written once.
  bool _cancelledAndSaidSo(String key, TraceScope trace) {
    if (!_cancelled.contains(key)) return false;
    trace.cancelled();
    return true;
  }

  /// [trace] is the caller's span: all three callers run inside one, and this
  /// is where a cancel is known.
  Future<void> _open(
    FlipperDevice device,
    String key, {
    required TraceScope trace,
  }) async {
    _setActivity(key, LinkActivity.connecting);
    try {
      await _c.connect(device);
      await _c.switchToRpcMode();
    } catch (e) {
      if (_cancelledAndSaidSo(key, trace)) return;
      rethrow;
    } finally {
      _cancelled.remove(key);
      _setActivity(key, LinkActivity.idle);
    }
  }

  /// The user asked for the USB link on [id] by hand, so the app no longer
  /// owns the hold: see [_UsbCable.appFormed], where clearing it *is* the
  /// endorsement. Not to be confused with [disconnectDevice], which lets the
  /// hold go rather than endorsing it.
  ///
  /// Nothing is created for a cable with no record: there is no hold to
  /// endorse, and the dial that would make one sets the origin itself.
  void _usbLinkAskedFor(String id) => _usbCables[id]?.appFormed = false;

  Future<void> disconnect(LinkEntry entry) =>
      disconnectDevice(entry.device, id: entry.id, link: entry.link);

  Future<void> disconnectDevice(
    FlipperDevice? device, {
    required String id,
    required FlipperLink link,
  }) async {
    final key = '${link.name}:$id';
    _userDisconnectedKey = key;
    // Pressed while the attempt is still running, this is a cancel: the
    // teardown below aborts it and the attempt's own failure is swallowed.
    if (_activity[key] == LinkActivity.connecting) _cancelled.add(key);
    if (link == FlipperLink.usb) {
      // Both, and in one place: the origin answers for the hold, so a hold let
      // go with an origin left behind would answer for a link formed later by
      // some path that sets neither. The entry itself goes if the prune finds
      // nothing left on it.
      _usbCables[id]
        ?..held = false
        ..appFormed = false;
    }
    final active = _c.connectedDevice ?? _c.connectingDevice;
    final wasActive = active != null && active.id == id && active.link == link;
    if (wasActive) {
      await _c.disconnect();
    } else {
      await _c.disconnectDevice(id, link: link);
    }
    if (wasActive && !_c.isConnected && !_c.isConnecting) {
      _releasedCtrl.add(device ?? active);
    }
    notifyListeners();
  }

  Future<void> forget(LinkEntry entry) async {
    final known = entry.known;
    if (known == null) return;
    _heardBle.remove(entry.id);
    await _known.forget(known);
  }

  /// Waits for [device] to hold a USB link again after the one it had went
  /// away.
  ///
  /// This device, not whichever Flipper turns up: the link belongs to the one
  /// that was sent away to install, and the app is holding it on the user's
  /// behalf.
  ///
  /// No deadline: a firmware install can run for half an hour, and the port
  /// coming back is the only honest signal that it is over. The wait ends on
  /// the OS event, not on a clock.
  Future<void> awaitUsbReturn(FlipperDevice device) async {
    // Being sent away to install firmware and waited for is the user asking
    // for this link as plainly as pressing Connect, and [_UsbCable.appFormed]
    // says why this one is load-bearing rather than tidy: the wait below has
    // no deadline. For the port it left on, though - a Flipper that
    // re-enumerates as a different port is not matched by `holds` either, and
    // that hole predates this line.
    _usbLinkAskedFor(device.id);
    bool holds(List<FlipperSessionInfo> sessions) => sessions.any(
      (s) => s.connected && s.device.isUsb && s.device.id == device.id,
    );
    final result = Completer<void>();
    var left = !holds(_c.sessions);
    final sub = _c.sessionsStream.listen((sessions) {
      if (!holds(sessions)) {
        left = true;
        return;
      }
      if (!left || result.isCompleted) return;
      result.complete();
    });
    try {
      await result.future;
    } finally {
      await sub.cancel();
    }
  }

  /// Keeps the CLI of [channel] held across the link: when its Flipper
  /// returns after the link went away, or another one is plugged in, it is
  /// taken back in CLI rather than RPC and the new channel goes to
  /// [onChannel]. [releaseCli] lets it go.
  void holdCli(
    FlipperCliChannel channel, {
    required void Function(FlipperCliChannel channel) onChannel,
    required void Function(Object error) onFailure,
  }) {
    // A new hold has tried nothing, which is a property of the object rather
    // than something to remember: a cable a previous hold failed on would
    // otherwise be unreachable to this one for as long as it stays plugged
    // in, the same shape as #461 one hold along.
    _cliHold = _CliHold(channel, onChannel, onFailure);
  }

  void releaseCli() => _cliHold = null;

  // ── Events ───────────────────────────────────────────────────────────────

  void _onSessions(List<FlipperSessionInfo> sessions) {
    // Every connected cable, whoever asked - which is why who asked is
    // recorded where the asking happens rather than guessed at here.
    // `_UsbCable.appFormed` is the other half of this answer, and the hold
    // tier in `_reconcileOnce` reads the two together.
    for (final session in sessions) {
      if (session.device.isUsb && session.connected) {
        _cable(session.device.id).held = true;
      }
    }

    // The hint is about a Flipper the app could not reach. One that is now
    // connecting or connected answers it, whoever asked.
    final failure = _autoFailure;
    if (failure != null) {
      for (final session in sessions) {
        if (!(session.connected || session.connecting)) continue;
        final key = '${session.device.link.name}:${session.device.id}';
        if (key == failure.key) {
          _clearAutoFailure(key);
          break;
        }
      }
    }

    final bleNow = _sessionIds(sessions, FlipperLink.ble);
    for (final s in sessions) {
      if (!s.device.isBle || !s.connected) continue;
      if (_bleSessionIds.contains(s.device.id)) continue;
      _heardBle.add(s.device.id);
      unawaited(
        guarded('[Link] remember device', () => _known.remember(s.device)),
      );
    }
    _bleSessionIds = bleNow;

    notifyListeners();
    _scheduleReconcile();
  }

  void _onConnection(FlipperConnectionState state) {
    final device = state.device;
    if (device == null || !device.isBle) return;
    if (state.connected) {
      _heardBle.add(device.id);
    } else if (!state.reconnecting &&
        !state.connecting &&
        state.closeReason != null &&
        _userDisconnectedKey != 'ble:${device.id}') {
      _heardBle.remove(device.id);
    }
    notifyListeners();
  }

  void _onHeard(FlipperDevice device) {
    if (!_known.devices.any((k) => k.matches(device))) return;
    if (_heardBle.add(device.id)) notifyListeners();
  }

  static Set<String> _sessionIds(
    List<FlipperSessionInfo> sessions,
    FlipperLink link,
  ) => {
    for (final s in sessions)
      if (s.device.link == link && (s.connected || s.connecting)) s.device.id,
  };

  void _setActivity(String key, LinkActivity activity) {
    if (activity == LinkActivity.idle) {
      _activity.remove(key);
    } else {
      _activity[key] = activity;
    }
    notifyListeners();
  }

  void _forgiveUserDisconnect(String key) {
    if (_userDisconnectedKey == key) _userDisconnectedKey = null;
    // A hand-dialled connect reports its own outcome in the picker, so the
    // hint about the automatic one has nothing left to say either way.
    _clearAutoFailure(key);
  }

  // ── Auto-connect ─────────────────────────────────────────────────────────

  void _scheduleReconcile() {
    _usbTimer?.cancel();
    _usbTimer = Timer(
      _usbDebounce,
      () => unawaited(guarded('[Link] reconcile', _reconcile)),
    );
  }

  Future<void> _reconcile() async {
    if (_reconciling) {
      _reconcileAgain = true;
      return;
    }
    _reconciling = true;
    try {
      await _reconcileOnce();
    } finally {
      _reconciling = false;
      if (_reconcileAgain) {
        _reconcileAgain = false;
        _scheduleReconcile();
      }
    }
  }

  Future<void> _reconcileOnce() async {
    if (_client == null) return;
    await _settings.load();
    await _refreshUsb();
    if (_suspended || _c.isConnecting) return;

    final presentIds = {for (final d in _usbPresent) d.id};
    // One pass for the one answer that does not survive absence, and then the
    // entries with nothing left on them at all. `_UsbCable.forgetPresence` is
    // what decides which is which, rather than this loop knowing.
    for (final entry in _usbCables.entries) {
      if (!presentIds.contains(entry.key)) entry.value.forgetPresence();
    }
    _usbCables.removeWhere((_, cable) => cable.isSpent);
    // The same prune for the same reason: a cable that went away and came
    // back is a fresh question for the CLI restore too. The `autoTried`
    // one above is what made the restore work at all before #461 - it was the
    // only thing that ever emptied the set `_restoreCli` filtered on then.
    _cliHold?.tried.removeWhere((id) => !presentIds.contains(id));
    // Unplugged, so there is nothing left to explain - and the same event
    // that clears `autoTried` is what lets the next appearance be dialled
    // again, which is the thing the hint was standing in for.
    final failed = _autoFailure;
    if (failed != null &&
        !failed.isBle &&
        !presentIds.contains(failed.key.substring(4))) {
      _clearAutoFailure(failed.key);
    }
    final userKey = _userDisconnectedKey;
    if (userKey != null &&
        userKey.startsWith('usb:') &&
        !presentIds.contains(userKey.substring(4))) {
      _userDisconnectedKey = null;
    }

    final cli = _cliHold;
    if (cli != null && !cli.channel.isOpen && await _restoreCli(cli)) return;

    final held = _c.sessions.any((s) => s.connected || s.connecting);
    // A Flipper the app is holding comes first, and one the user asked for
    // comes back whatever the setting says: they asked for that link and never
    // let it go. A hold the app formed by itself has no such statement behind
    // it, so it is only taken back while the setting that formed it is still
    // on - `_UsbCable.appFormed` is which is which. The setting also adds the
    // cables nobody has asked for yet, and between those two that is all it
    // decides — whether the app forms that intent by itself when a cable
    // appears.
    // It is **on** by default, so in a default build a cable that is in at
    // launch is dialled here and this method returns before the remembered
    // Bluetooth device below is ever considered. That ordering is the whole
    // of "a cable wins" - and the one case where a cable does not win is a
    // hold the app formed with the setting since turned off, which falls
    // through to the radio exactly as a cable nobody has dialled does, because
    // that is what the setting was turned off to mean. There is no separate
    // check for a cable, and a guard like
    // `if (_usbPresent.isNotEmpty) return;` before the BLE branch is not it.
    // `_usbPresent` is presence, not candidacy: a cable is skipped below for
    // being one the user disconnected, or one already tried, and such a guard
    // would turn each of those into no link at all for as long as it stays in
    // - including making this setting *off* disable Bluetooth auto-connect
    // whenever a cable is plugged in.
    if (!held) {
      final candidates = <FlipperDevice>[
        for (final device in _usbPresent)
          if (_takesHoldBack(device.id)) device,
        if (_settings.autoConnectUsb)
          for (final device in _usbPresent)
            if (!_isHeld(device.id)) device,
      ];
      for (final device in candidates) {
        if (_userDisconnectedKey == 'usb:${device.id}') continue;
        if (!_cable(device.id).claimAutoDial()) continue;
        final holding = _isHeld(device.id);
        // The dial that takes a cable nobody asked about, and the one place
        // that writes the origin. `_restoreCli` forms a link too and leaves
        // this alone on purpose - see the field.
        if (!holding) _cable(device.id).appFormed = true;
        await _autoConnect(device, holding ? 'holding this one' : 'plugged in');
        return;
      }
    }

    if (held || _bleAutoTried || !_settings.autoConnectBle) return;
    final last = _known.lastDevice;
    if (last == null || _userDisconnectedKey == 'ble:${last.id}') return;
    _bleAutoTried = true;
    // `last` is a [KnownDevice] and carries no link of its own, hence the
    // enum.
    await _autoDial(
      key: 'ble:${last.id}',
      name: last.name,
      link: FlipperLink.ble,
      trigger: 'remembered',
      dial: (_) async {
        await _c.connectBleAddress(last.id, name: last.name);
        await _c.switchToRpcMode();
      },
    );
  }

  /// Takes the CLI back on a cable, and says whether it got as far as
  /// trying - which is what ends the reconcile, success or not.
  ///
  /// Filters on the hold's own attempts rather than on [_UsbCable.autoTried] -
  /// `_CliHold.tried` says why that distinction is #461. The filter itself is
  /// not about auto-connect: it is here because this returns true whenever it
  /// has a candidate, so a cable that cannot be reopened would be retried on
  /// every reconcile, and a failed open is itself one of the things that
  /// schedules the next one.
  Future<bool> _restoreCli(_CliHold hold) async {
    final candidates = [
      for (final device in _usbPresent)
        if (_userDisconnectedKey != 'usb:${device.id}' &&
            !hold.tried.contains(device.id))
          device,
    ];
    if (candidates.isEmpty) return false;
    final previous = hold.channel.device.id;
    final device = candidates.firstWhere(
      (d) => d.id == previous,
      orElse: () => candidates.first,
    );
    hold.tried.add(device.id);
    // Still marked auto-tried, so that a restore which fails does not leave
    // the USB branch free to dial the same cable into RPC underneath a user
    // who is asking for a terminal on it. Unchanged by #461, and not the
    // clause that was wrong: what was wrong was *reading* this set here.
    _cable(device.id).autoTried = true;
    final key = 'usb:${device.id}';
    LogService.info('[Link] restoring CLI on ${device.name}');
    _setActivity(key, LinkActivity.connecting);
    try {
      final channel = await _c.openCli(device);
      _clearAutoFailure(key);
      // It opened, so this cable is no longer an attempt that failed. The
      // next time a channel on it dies the restore gets to try again, which
      // is the difference between a hold that survives a fault and one that
      // survives exactly one.
      hold.tried.remove(device.id);
      if (!identical(_cliHold, hold)) {
        await channel.close();
        return true;
      }
      hold.channel = channel;
      hold.onChannel(channel);
    } catch (e, st) {
      LogService.warn('[Link] CLI on ${device.name} failed: $e');
      _recordAutoFailure(key, device.name, e, st);
      if (identical(_cliHold, hold)) hold.onFailure(e);
    } finally {
      _setActivity(key, LinkActivity.idle);
    }
    return true;
  }

  /// Says what is being dialled, times it, and remembers a failure for the
  /// device page. The shape both auto paths share.
  ///
  /// Timed separately from [connect], for the reason [connectDevice] gives
  /// about the search: a link the app re-formed on its own is not the same
  /// operation as one a user asked for, and one name over both would hide
  /// which of them is slow.
  ///
  /// Traced at all because a validation run found `device.connect` producing
  /// nothing for a session that had plainly connected: both auto paths bypass
  /// it. [trigger] is what tells them apart afterwards, and it is a note rather
  /// than a fourth name because three values at this volume are a dimension,
  /// not three operations. Worth knowing when adding a fifth connect path:
  /// `device.connect` and `device.connect.discovered` split on *how the device
  /// was found*, while this one splits on *who asked* - two axes under one
  /// prefix, which is a wart this did not want to make worse by renaming a
  /// transaction that is already in use.
  ///
  /// One method rather than the same twenty lines twice, which is also what
  /// removes a drift: the BLE caller had to hand-write its own `link` note,
  /// because a [KnownDevice] carries no link, and carried a comment about that
  /// note drifting from this one's.
  ///
  /// [traced] goes **inside** the `try`, so the failure still reaches the catch
  /// below. It rethrows rather than swallowing - its own doc says a `traced`
  /// that swallowed would break the thing it reports on - and marks the
  /// operation failed on the way past, so the span carries the error status and
  /// [_recordAutoFailure] still runs.
  Future<void> _autoDial({
    required String key,
    required String name,
    required FlipperLink link,
    required String trigger,
    required Future<void> Function(TraceScope trace) dial,
  }) async {
    LogService.info('[Link] auto-connecting to $name ($trigger)');
    try {
      await traced('device.connect.auto', (trace) async {
        trace.note('link', link.name);
        // One of three literals from the two callers, not user text.
        trace.note('trigger', trigger);
        await dial(trace);
      });
      _clearAutoFailure(key);
    } catch (e, st) {
      LogService.warn('[Link] auto-connect to $name failed: $e');
      _recordAutoFailure(key, name, e, st);
    }
  }

  /// Whether the hold on [id] is one to take back now.
  ///
  /// Held, and either the user asked for that link - in which case a setting
  /// they flipped afterwards does not take it back - or the setting that
  /// formed it is still on. [_UsbCable.appFormed] is which is which. #460.
  bool _takesHoldBack(String id) =>
      _isHeld(id) && (_settings.autoConnectUsb || !_isAppFormed(id));

  /// The USB half: a cable that appeared, or one the app is holding.
  ///
  /// Fires for a link the app is holding ([_UsbCable.held]) - a cable someone
  /// connected over and never released, which since #458 is as often the app
  /// as the user, hence [_UsbCable.appFormed] - and, while `autoConnectUsb` is
  /// on, for any Flipper on a cable with no session held.
  /// Not flipperlib's `autoReconnect`, which recovers a dropped session in
  /// place and never reaches here.
  Future<void> _autoConnect(FlipperDevice device, String why) async {
    final key = 'usb:${device.id}';
    await _autoDial(
      key: key,
      name: device.name,
      link: device.link,
      trigger: why,
      dial: (trace) => _open(device, key, trace: trace),
    );
  }

  Future<void> _refreshUsb() async {
    try {
      await _c.refreshUsbOnly();
    } catch (e) {
      LogService.warn('[Link] USB enumeration failed: $e');
    }
    _usbPresent = [
      for (final d in _c.devices)
        if (d.isUsb && _c.isFlipperDevice(d)) d,
    ];
    notifyListeners();
  }

  @override
  void dispose() {
    _usbTimer?.cancel();
    _usbSub?.cancel();
    _sessionsSub?.cancel();
    _connectionSub?.cancel();
    _heardSub?.cancel();
    _known.removeListener(notifyListeners);
    _settings.removeListener(_scheduleReconcile);
    _releasedCtrl.close();
    super.dispose();
  }
}

class _CliHold {
  _CliHold(this.channel, this.onChannel, this.onFailure);

  FlipperCliChannel channel;
  final void Function(FlipperCliChannel channel) onChannel;
  final void Function(Object error) onFailure;

  /// The cables [LinkService._restoreCli] has already tried for this hold.
  ///
  /// On the hold rather than on the service, so that two of its four lifetime
  /// rules are structural: a new hold is a new object, and letting one go
  /// drops it. What is left to say is the other two - an entry goes when the
  /// device goes absent, and when a restore *worked*, because a channel that
  /// opens and later dies is a new question rather than a retry of the one
  /// before it.
  ///
  /// What stays is a failed attempt, which is the loop it exists to not
  /// start. Not the same question as `_UsbCable.autoTried`, which asks
  /// whether auto-connect has dialled a cable: #461 was what it cost to have
  /// one set answering both, since the launch dial fills that one and only an
  /// unplug empties it, so a CLI channel that died with its cable still in
  /// found no candidate at all - the restore declined, the USB branch skipped
  /// the same id, and the remembered Bluetooth Flipper was dialled while the
  /// user sat on the CLI page with a cable in hand.
  final Set<String> tried = {};
}
