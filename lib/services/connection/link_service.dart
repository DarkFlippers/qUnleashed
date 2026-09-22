import 'dart:async';

import 'package:flipperlib/flipperlib.dart' hide DateTime;
import 'package:flutter/foundation.dart';

import '../logging.dart';
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
class LinkService extends ChangeNotifier {
  LinkService._();

  static final LinkService instance = LinkService._();

  static const Duration _usbDebounce = Duration(milliseconds: 250);

  FlipperClient? _client;
  final KnownDevicesStore _known = KnownDevicesStore.instance;
  final DeviceSettings _settings = DeviceSettings.instance;

  bool _suspended = false;
  List<FlipperDevice> _usbPresent = const [];
  final Set<String> _heardBle = {};
  final Map<String, LinkActivity> _activity = {};
  Set<String> _bleSessionIds = {};
  // The USB Flippers the app is meant to be holding a link with. Connecting
  // to one is that statement, and it outlives the link: a Flipper that
  // rebooted into the updater or had its cable knocked out is taken back when
  // it returns, whatever the auto-connect setting says, because nobody asked
  // for it to go. Only the user letting it go clears the entry.
  final Set<String> _holdUsbIds = {};
  String? _userDisconnectedKey;
  final Set<String> _autoTriedUsb = {};
  bool _bleAutoTried = false;
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

  /// Set while a DFU repair holds the USB port; nothing connects on its own
  /// until it is released.
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
    unawaited(_settings.load());
    unawaited(_known.load().whenComplete(_scheduleReconcile));
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
  Future<void> connect(LinkEntry entry) async {
    if (entry.busy || entry.session == LinkSession.active) return;
    _forgiveUserDisconnect(entry.key);
    if (entry.held) {
      await _c.activateById(entry.id, link: entry.link);
      return;
    }
    if (entry.isUsb) {
      final device = entry.device;
      if (device == null) return;
      await _open(device, entry.key);
      return;
    }
    _setActivity(entry.key, LinkActivity.connecting);
    try {
      await _c.connectBleAddress(entry.id, name: entry.name);
      await _c.switchToRpcMode();
    } catch (e) {
      if (classifyConnectError(e) == FlipperConnectErrorKind.deviceUnreachable) {
        _heardBle.remove(entry.id);
      }
      rethrow;
    } finally {
      _setActivity(entry.key, LinkActivity.idle);
    }
  }

  /// Connects to a device the search found. Throws on failure.
  Future<void> connectDevice(FlipperDevice device) async {
    final key = '${device.link.name}:${device.id}';
    _forgiveUserDisconnect(key);
    await _open(device, key);
    if (device.isBle) _heardBle.add(device.id);
    notifyListeners();
  }

  Future<void> _open(FlipperDevice device, String key) async {
    _setActivity(key, LinkActivity.connecting);
    try {
      await _c.connect(device);
      await _c.switchToRpcMode();
    } finally {
      _setActivity(key, LinkActivity.idle);
    }
  }

  Future<void> disconnect(LinkEntry entry) => disconnectDevice(
    entry.device,
    id: entry.id,
    link: entry.link,
  );

  Future<void> disconnectDevice(
    FlipperDevice? device, {
    required String id,
    required FlipperLink link,
  }) async {
    _userDisconnectedKey = '${link.name}:$id';
    if (link == FlipperLink.usb) _holdUsbIds.remove(id);
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

  // ── Events ───────────────────────────────────────────────────────────────

  void _onSessions(List<FlipperSessionInfo> sessions) {
    for (final session in sessions) {
      if (session.device.isUsb && session.connected) {
        _holdUsbIds.add(session.device.id);
      }
    }

    final bleNow = _sessionIds(sessions, FlipperLink.ble);
    for (final s in sessions) {
      if (!s.device.isBle || !s.connected) continue;
      if (_bleSessionIds.contains(s.device.id)) continue;
      _heardBle.add(s.device.id);
      unawaited(_known.remember(s.device));
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
  }

  // ── Auto-connect ─────────────────────────────────────────────────────────

  void _scheduleReconcile() {
    _usbTimer?.cancel();
    _usbTimer = Timer(_usbDebounce, () => unawaited(_reconcile()));
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
    _autoTriedUsb.removeWhere((id) => !presentIds.contains(id));
    final userKey = _userDisconnectedKey;
    if (userKey != null &&
        userKey.startsWith('usb:') &&
        !presentIds.contains(userKey.substring(4))) {
      _userDisconnectedKey = null;
    }

    final held = _c.sessions.any((s) => s.connected || s.connecting);
    // A Flipper the app is holding comes first and comes back whatever the
    // setting says: the user asked for that link and never let it go. The
    // setting adds the ones nobody has asked for yet, which is all it decides
    // — whether the app forms that intent by itself when a cable appears.
    if (!held) {
      final candidates = <FlipperDevice>[
        for (final device in _usbPresent)
          if (_holdUsbIds.contains(device.id)) device,
        if (_settings.autoConnectUsb)
          for (final device in _usbPresent)
            if (!_holdUsbIds.contains(device.id)) device,
      ];
      for (final device in candidates) {
        if (_userDisconnectedKey == 'usb:${device.id}') continue;
        if (!_autoTriedUsb.add(device.id)) continue;
        await _autoConnect(
          device,
          _holdUsbIds.contains(device.id) ? 'holding this one' : 'plugged in',
        );
        return;
      }
    }

    if (held || _bleAutoTried || !_settings.autoConnectBle) return;
    final last = _known.lastDevice;
    if (last == null || _userDisconnectedKey == 'ble:${last.id}') return;
    _bleAutoTried = true;
    LogService.info('[Link] auto-connecting to ${last.name}');
    try {
      await _c.connectBleAddress(last.id, name: last.name);
      await _c.switchToRpcMode();
    } catch (e) {
      LogService.warn('[Link] auto-connect to ${last.name} failed: $e');
    }
  }

  Future<void> _autoConnect(FlipperDevice device, String why) async {
    LogService.info('[Link] auto-connecting to ${device.name} ($why)');
    try {
      await _open(device, 'usb:${device.id}');
    } catch (e) {
      LogService.warn('[Link] auto-connect to ${device.name} failed: $e');
    }
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
