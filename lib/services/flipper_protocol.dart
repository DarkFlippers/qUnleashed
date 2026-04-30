import 'dart:typed_data';

import 'package:qunleashed/flipperlib/protobuf.dart';

import 'log_service.dart';

class FlipperProtocol {
  static int _nextId = 1;
  static int nextCommandId() => _nextId++;

  /// Encode a Main message with varint length prefix (Flipper Zero RPC framing).
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
}

/// Reassembles varint-length-prefixed protobuf frames from a byte stream.
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
    if (_buf.isEmpty) return null;

    int len = 0, shift = 0, i = 0;
    while (i < _buf.length) {
      final b = _buf[i++];
      len |= (b & 0x7F) << shift;
      shift += 7;
      if ((b & 0x80) == 0) {
        // Varint complete — do we have the full payload?
        if (len > 4096) {
          // Unreasonably large frame: buffer is desynchronised, discard 1 byte and retry
          LogService.log('[FrameBuffer] bad length=$len, dropping 1 byte (0x${_buf[0].toRadixString(16)})');
          _buf.removeAt(0);
          return null;
        }
        if (_buf.length < i + len) return null; // wait for more bytes

        final payload = Uint8List.fromList(_buf.sublist(i, i + len));
        _buf.removeRange(0, i + len);

        try {
          return Main.fromBuffer(payload);
        } catch (e) {
          LogService.log('[FrameBuffer] parse error: $e — skipping $len bytes');
          return null;
        }
      }
      if (shift >= 35) {
        LogService.log('[FrameBuffer] varint overflow, dropping 1 byte');
        _buf.removeAt(0);
        return null;
      }
    }
    return null; // not enough bytes for varint yet
  }

  void clear() => _buf.clear();
}
