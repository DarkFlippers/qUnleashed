/// Tries the keys already in the device's dictionaries against a nonce before
/// anything expensive is attempted on it.
///
/// The nonce logs are never cleared - that is deliberate, they are the user's
/// collected data - so every run re-attacks every nonce ever collected,
/// including the ones whose key is already saved. Cracking a key you already
/// have is the largest avoidable cost in a run, and it grows with how long
/// someone has been using the tool.
///
/// A trial is one crypto1 pass per candidate key. Against the 2^19-state
/// `lfsr_recovery32` it replaces - or, for a static-encrypted card, against
/// generating tens of thousands of candidates and uploading them - it is a
/// rounding error. The whole dictionary is tried in one FFI call per nonce so
/// the per-call overhead is paid once rather than once per key.
library;

import 'dart:ffi';

import 'package:ffi/ffi.dart';

import '../../../services/native.dart';

typedef _KnownNestedNative = Int32 Function(
  Uint32,
  Uint32,
  Uint32,
  Pointer<Uint64>,
  Uint32,
);
typedef _KnownNestedDart = int Function(int, int, int, Pointer<Uint64>, int);

typedef _KnownReaderNative = Int32 Function(
  Uint32,
  Uint32,
  Uint32,
  Uint32,
  Pointer<Uint64>,
  Uint32,
);
typedef _KnownReaderDart = int Function(
  int,
  int,
  int,
  int,
  Pointer<Uint64>,
  int,
);

/// Which already-known key opens a nonce, if any.
abstract class KnownKeyFilter {
  /// The known key that opens this nested/static sample, or null.
  ///
  /// A [BigInt] rather than the dictionary's hex, so a caller can hand it
  /// straight to the same recording path a cracked key takes and get the same
  /// row - including the "already in dict" tag, which the dictionary decides.
  BigInt? nestedMatch({required int cuid, required int nt, required int ks});

  /// The known key that opens this reader (mfkey32) nonce, or null.
  BigInt? readerMatch({
    required int uid,
    required int nt,
    required int nr,
    required int ar,
  });

  void dispose();
}

/// A filter that knows nothing, for a run whose dictionaries could not be read.
///
/// Returning "no match" costs the run nothing but the work it would have done
/// anyway, which is the right way for this to fail: a filter that guessed wrong
/// in the other direction would silently drop a key.
class NoKnownKeys implements KnownKeyFilter {
  const NoKnownKeys();

  @override
  BigInt? nestedMatch({required int cuid, required int nt, required int ks}) =>
      null;

  @override
  BigInt? readerMatch({
    required int uid,
    required int nt,
    required int nr,
    required int ar,
  }) => null;

  @override
  void dispose() {}
}

/// Builds a filter over [keys], which are 12-digit hex as the dictionaries
/// store them.
///
/// Entries that are not a 48-bit hex key are dropped rather than rejected: a
/// dictionary is a user-editable text file, and one bad line should not cost
/// the whole optimisation.
///
/// Returns [NoKnownKeys] when there is nothing to try. **Throws**
/// [NativeEngineUnavailable] when the engine is missing - the caller decides
/// whether to degrade, and in this app it does. A function rather than a
/// factory constructor precisely so it can return the other implementation.
KnownKeyFilter nativeKnownKeyFilter(Iterable<String> keys) {
  final hex = RegExp(r'^[0-9a-fA-F]{12}$');
  final values = <int>[];
  for (final key in keys) {
    if (hex.hasMatch(key)) values.add(int.parse(key, radix: 16));
  }
  if (values.isEmpty) return const NoKnownKeys();

  final library = openMifareNativeLibrary();
  final nested = lookupNativeFunction(
    () => library.lookupFunction<_KnownNestedNative, _KnownNestedDart>(
      'qunleashed_nested_known_key',
    ),
  );
  final reader = lookupNativeFunction(
    () => library.lookupFunction<_KnownReaderNative, _KnownReaderDart>(
      'qunleashed_mfkey32_known_key',
    ),
  );

  final buffer = calloc<Uint64>(values.length);
  buffer.asTypedList(values.length).setAll(0, values);
  return NativeKnownKeyFilter._(values.length, buffer, nested, reader);
}

class NativeKnownKeyFilter implements KnownKeyFilter {
  NativeKnownKeyFilter._(this._count, this._buffer, this._nested, this._reader);

  final int _count;
  final Pointer<Uint64> _buffer;
  final _KnownNestedDart _nested;
  final _KnownReaderDart _reader;
  var _disposed = false;

  @override
  BigInt? nestedMatch({required int cuid, required int nt, required int ks}) {
    if (_disposed) return null;
    return _at(_nested(cuid, nt, ks, _buffer, _count));
  }

  @override
  BigInt? readerMatch({
    required int uid,
    required int nt,
    required int nr,
    required int ar,
  }) {
    if (_disposed) return null;
    return _at(_reader(uid, nt, nr, ar, _buffer, _count));
  }

  /// The index native reported, bounds-checked. A count that stopped agreeing
  /// with the buffer would otherwise throw a RangeError inside a per-nonce
  /// loop and abort the run - for an optimisation whose whole rule is that
  /// degrading here must never cost a key.
  BigInt? _at(int index) =>
      index < 0 || index >= _count ? null : BigInt.from(_buffer[index]);

  /// Native memory is process-scoped, so it outlives the run that took it.
  /// After this the matchers answer null rather than reading freed memory.
  /// Defence in depth: every current caller matches synchronously before its
  /// first await, so none can straddle a disposal - but that is a property of
  /// the call sites, not of this class.
  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    calloc.free(_buffer);
  }
}
