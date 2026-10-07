// `NativeProgress`'s real layout - the bytes the engine is actually handed.
//
// Its sibling `native_struct_mirror_test.dart` compares source text, and that
// is the whole of its reach: it matches `@Uint32()`/`@Uint64()` annotations with
// a regex, so a field declared any other way is invisible to it. Inserting
//
//     @Int32()
//     external int reserved;
//
// after `permille` leaves every one of that file's assertions green while
// `sizeOf` goes 16 to 20 and `abort`, `started` and `threadsStarted` each shift
// four bytes. Under faaccrack the release-path size check in
// `faaccrack_recoverer.dart` would refuse the search as an ABI mismatch. Under
// hardnested nothing would: that library exports no size, so Stop would be
// written into a word the engine does not read, the button would do nothing and
// the bar would never move - in release, with no log line.
//
// So this file asks Dart what it built rather than what it was told. It needs no
// native build, no device and no toolchain: `sizeOf` and `calloc` resolve with
// no dynamic library loaded, which is why the gap was worth closing here rather
// than in a platform build nothing runs on a pull request.
//
// The chain this closes, end to end:
//
//  1. the C compiler pins each C struct against its own declaration
//     (`_Static_assert` per offset, in both headers);
//  2. `native_struct_mirror_test.dart` pins those declarations against the
//     asserted sizes, and the Dart mirror's field names and order against them;
//  3. this file pins the Dart mirror's declaration against the layout Dart
//     actually produces.
//
// Only (3) can see a field (2) cannot parse, and only (2) can see a rename.
import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qunleashed/services/native.dart';

/// What `qunleashed_faaccrack_progress_size` returns, and what
/// `_Static_assert(sizeof(struct faaccrack_progress) == 16)` pins in
/// `faaccrack.h`. Written out rather than derived: a figure read from the same
/// header it is checking would agree with itself.
const _faaccrackProgressBytes = 16;

/// What `_Static_assert(sizeof(qunleashed_hn_progress) == 12)` pins. The
/// hardnested engine only ever sees a pointer to three words, so this is the
/// prefix of the mirror it may touch - and the reason the remaining four bytes
/// are slack rather than corruption.
const _hardnestedProgressBytes = 12;

void main() {
  test('the mirror is the size both the bridge and faaccrack.h agree on', () {
    // The faaccrack binding compares this against the bridge's exported size
    // before it reads any result, in release. If this drifts, every seed search
    // is refused as an engine fault - which reads to the user as a broken
    // build, not as a wrong answer, and is the safe half of the failure.
    expect(sizeOf<NativeProgress>(), _faaccrackProgressBytes);
  });

  test('hardnested only ever sees the first three words of it', () {
    // Not a tautology against the test above: it is the arithmetic that makes
    // over-allocating safe. Dart hands the engine 16 bytes where its header
    // declares 12, so the engine reads and writes strictly inside what was
    // allocated. The opposite - under-declaring - would corrupt the heap.
    expect(_hardnestedProgressBytes, lessThan(sizeOf<NativeProgress>()));
    expect(sizeOf<NativeProgress>() - _hardnestedProgressBytes, 4);
  });

  test('each field lands on the offset both headers assert for it', () {
    // Written through the struct and read back as raw words. This is the one
    // check that sees a field the source-text guard cannot parse: anything
    // inserted, widened or padded shifts a later field off its word and the
    // list comes back in the wrong order.
    final channel = calloc<NativeProgress>();
    try {
      channel.ref.permille = 11;
      channel.ref.abort = 22;
      channel.ref.started = 33;
      channel.ref.threadsStarted = 44;
      expect(channel.cast<Uint32>().asTypedList(4), [11, 22, 33, 44]);
    } finally {
      calloc.free(channel);
    }
  });

  test('calloc hands the engine a zeroed channel', () {
    // The channel must arrive zero: both headers state it as a requirement on
    // the caller, not a courtesy. A garbage `abort` stops a search before it
    // starts - reported as a stop nobody asked for - and a garbage `started`
    // makes the poll publish a percentage from an engine that has not begun.
    // Both recoverers and `tool/hn_bench.dart` use `calloc` for this reason;
    // this is what says so in a form that fails.
    final channel = calloc<NativeProgress>();
    try {
      expect(channel.cast<Uint32>().asTypedList(4), [0, 0, 0, 0]);
    } finally {
      calloc.free(channel);
    }
  });
}
