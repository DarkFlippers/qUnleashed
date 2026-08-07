import 'package:flutter/foundation.dart';

enum NetworkDirection { tx, rx }

class NetworkTrafficSnapshot {
  const NetworkTrafficSnapshot({
    this.txBytes = 0,
    this.rxBytes = 0,
    this.host,
    this.activeConnections = 0,
    this.lastDirection,
    this.sequence = 0,
  });

  final int txBytes; // uplink
  final int rxBytes; // downlink
  final String? host; // Domain

  final int activeConnections;
  final NetworkDirection? lastDirection;
  final int sequence;

  bool get isActive => activeConnections > 0;
}

class NetworkTrafficMonitor {
  NetworkTrafficMonitor._();

  static final NetworkTrafficMonitor instance = NetworkTrafficMonitor._();

  final ValueNotifier<NetworkTrafficSnapshot> snapshot = ValueNotifier(
    const NetworkTrafficSnapshot(),
  );

  int _tx = 0;
  int _rx = 0;
  String? _host;
  int _active = 0;
  int _seq = 0;

  void connectionOpened([String? host]) {
    _active++;
    if (host != null && host.isNotEmpty) _host = host;
    _emit(null);
  }

  void connectionClosed() {
    if (_active > 0) _active--;
    _emit(null);
  }

  void hostUpdated(String host) {
    if (host.isEmpty || host == _host) return;
    _host = host;
    _emit(null);
  }

  void recordTx(int bytes, {String? host}) {
    if (bytes <= 0) return;
    _tx += bytes;
    if (host != null && host.isNotEmpty) _host = host;
    _emit(NetworkDirection.tx);
  }

  void recordRx(int bytes) {
    if (bytes <= 0) return;
    _rx += bytes;
    _emit(NetworkDirection.rx);
  }

  void reset() {
    _tx = 0;
    _rx = 0;
    _host = null;
    _active = 0;
    snapshot.value = const NetworkTrafficSnapshot();
  }

  void _emit(NetworkDirection? direction) {
    snapshot.value = NetworkTrafficSnapshot(
      txBytes: _tx,
      rxBytes: _rx,
      host: _host,
      activeConnections: _active,
      lastDirection: direction,
      sequence: ++_seq,
    );
  }
}
