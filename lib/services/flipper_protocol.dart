import 'dart:typed_data';

import 'package:flipperzero/flipperzero.dart';

class FlipperProtocol {
  static int _nextId = 1;
  static int nextCommandId() => _nextId++;

  // Varint-prefixed protobuf frame (Flipper Zero RPC wire format)
  static Uint8List encode(Main msg) {
    final payload = msg.writeToBuffer();
    final header = _encodeVarint(payload.length);
    final out = Uint8List(header.length + payload.length);
    out.setRange(0, header.length, header);
    out.setRange(header.length, out.length, payload);
    return out;
  }

  static List<int> _encodeVarint(int value) {
    final r = <int>[];
    while (value > 0x7F) {
      r.add((value & 0x7F) | 0x80);
      value >>= 7;
    }
    r.add(value & 0x7F);
    return r;
  }

  static Uint8List deviceInfoRequest() => encode(
        Main(commandId: nextCommandId(), hasNext: false,
             systemDeviceInfoRequest: DeviceInfoRequest()));

  static Uint8List powerInfoRequest() => encode(
        Main(commandId: nextCommandId(), hasNext: false,
             systemPowerInfoRequest: PowerInfoRequest()));

  static Uint8List protobufVersionRequest() => encode(
        Main(commandId: nextCommandId(), hasNext: false,
             systemProtobufVersionRequest: ProtobufVersionRequest()));

  static Uint8List getDateTimeRequest() => encode(
        Main(commandId: nextCommandId(), hasNext: false,
             systemGetDatetimeRequest: GetDateTimeRequest()));

  static Uint8List pingRequest() => encode(
        Main(commandId: nextCommandId(), hasNext: false,
             systemPingRequest: PingRequest(data: [0x01, 0x02, 0x03])));
}

// Reassembles length-prefixed frames from a byte stream
class FlipperFrameBuffer {
  final List<int> _buf = [];

  List<Main> push(List<int> bytes) {
    _buf.addAll(bytes);
    final msgs = <Main>[];
    while (true) {
      final m = _tryParse();
      if (m == null) break;
      msgs.add(m);
    }
    return msgs;
  }

  Main? _tryParse() {
    int len = 0, shift = 0, i = 0;
    while (i < _buf.length) {
      final b = _buf[i++];
      len |= (b & 0x7F) << shift;
      shift += 7;
      if ((b & 0x80) == 0) {
        if (_buf.length < i + len) return null;
        final payload = Uint8List.fromList(_buf.sublist(i, i + len));
        _buf.removeRange(0, i + len);
        return Main.fromBuffer(payload);
      }
      if (shift >= 35) { _buf.clear(); return null; }
    }
    return null;
  }

  void clear() => _buf.clear();
}
