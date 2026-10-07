// Times one hardnested attack against a given DLL, outside the app.
//
// Same inputs the recovery page hands the engine: the nonces come from the
// app's own parser and the encrypted nonce is rebuilt the way
// _recoverHardnested does (nt ^ ks), so this measures the engine and nothing
// else. The attack runs in an isolate, as it does in the app, because the FFI
// call blocks the thread it is made on - polling it from the same isolate would
// read the channel exactly never.
//
// Kept because the number it produces is the only evidence for what the SIMD
// work was worth, and because the next person to touch the engine will want to
// re-measure rather than take 67x on trust. It is a bench, not a test: nothing
// runs it in CI, it needs a real .nested.log and a built DLL, and it asserts
// nothing.
//
// Usage: dart run tool/hn_bench.dart <dll> <.nested.log> [sector] [budget-s]
import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:ffi/ffi.dart';
import 'package:qunleashed/pages/tools/mifare/nested_models.dart';
import 'package:qunleashed/pages/tools/mifare/nested_nonce_parser.dart';
import 'package:qunleashed/services/native.dart';

typedef _RecoverNative =
    Int32 Function(
      Uint32 cuid,
      Pointer<Uint32> ntEnc,
      Pointer<Uint8> parEnc,
      Uint32 count,
      Pointer<Uint64> foundKey,
      Pointer<NativeProgress> progress,
    );
typedef _RecoverDart =
    int Function(
      int cuid,
      Pointer<Uint32> ntEnc,
      Pointer<Uint8> parEnc,
      int count,
      Pointer<Uint64> foundKey,
      Pointer<NativeProgress> progress,
    );

typedef _Job = ({
  String dll,
  int cuid,
  int ntEnc,
  int parEnc,
  int count,
  int foundKey,
  int progress,
});

/// Runs the attack. Its own function so the spawned closure can reach nothing
/// but the payload - the same reason the app has `spawnAttackIsolate`.
int _attack(_Job job) {
  final lib = DynamicLibrary.open(job.dll);
  final recover = lib.lookupFunction<_RecoverNative, _RecoverDart>(
    'qunleashed_hardnested_recover',
  );
  return recover(
    job.cuid,
    Pointer<Uint32>.fromAddress(job.ntEnc),
    Pointer<Uint8>.fromAddress(job.parEnc),
    job.count,
    Pointer<Uint64>.fromAddress(job.foundKey),
    Pointer<NativeProgress>.fromAddress(job.progress),
  );
}

Future<int> _spawn(_Job job) => Isolate.run(() => _attack(job));

Future<void> main(List<String> args) async {
  final dllPath = args[0];
  final logPath = args[1];
  final wantedSector = args.length > 2 ? int.parse(args[2]) : -1;
  final budget = Duration(seconds: args.length > 3 ? int.parse(args[3]) : 0);

  final parsed = NestedNonceParser.parse(File(logPath).readAsStringSync());
  stdout.writeln(
    'parsed ${parsed.nonces.length} nonces, '
    '${parsed.droppedLines} lines dropped',
  );

  // Grouped exactly as splitSingles does: (cuid, sector, key), and only the
  // lines with no `dist` field, which is how the firmware distinguishes a
  // hardnested nonce from a static-encrypted one. Grouping by sector alone
  // mixes two cards' nonces and the engine rejects the pile in two seconds
  // with "No match for the First_Byte_Sum".
  final groups = <String, List<NestedNonce>>{};
  for (final n in parsed.nonces) {
    if (n.hasPair || n.dist != null || n.par == null) continue;
    groups
        .putIfAbsent(
          '${n.cuid.toRadixString(16)}/${n.sector}/${n.keyType.name}',
          () => [],
        )
        .add(n);
  }
  for (final e in groups.entries) {
    stdout.writeln('  group ${e.key}: ${e.value.length} nonces');
  }
  if (groups.isEmpty) {
    stdout.writeln('no single-sample nonce groups; nothing to attack');
    exit(2);
  }

  final chosen = groups.entries
      .where((e) => wantedSector < 0 || e.key.contains('/$wantedSector/'))
      .reduce((a, b) => a.value.length >= b.value.length ? a : b);
  final group = chosen.value;
  stdout.writeln(
    'attacking ${chosen.key}, ${group.length} nonces, dll=$dllPath',
  );

  final ntEnc = calloc<Uint32>(group.length);
  final parEnc = calloc<Uint8>(group.length);
  for (var i = 0; i < group.length; i++) {
    ntEnc[i] = group[i].samples[0].nt ^ group[i].samples[0].ks;
    parEnc[i] = group[i].par!;
  }
  final foundKey = calloc<Uint64>();
  final progress = calloc<NativeProgress>();

  final started = DateTime.now();
  var lastPermille = -1;
  Duration? firstReport;
  final ticker = Timer.periodic(const Duration(milliseconds: 500), (t) {
    final elapsed = DateTime.now().difference(started);
    if (budget > Duration.zero && elapsed > budget) {
      progress.ref.abort = 1;
    }
    if (progress.ref.started == 0) return;
    if (progress.ref.permille == lastPermille) return;
    lastPermille = progress.ref.permille;
    firstReport ??= elapsed;
    stdout.writeln(
      '  ${elapsed.inSeconds}s  ${(lastPermille / 10).toStringAsFixed(1)}%',
    );
  });

  final status = await _spawn((
    dll: dllPath,
    cuid: group.first.cuid,
    ntEnc: ntEnc.address,
    parEnc: parEnc.address,
    count: group.length,
    foundKey: foundKey.address,
    progress: progress.address,
  ));

  ticker.cancel();
  final took = DateTime.now().difference(started);
  stdout.writeln('status=$status after ${took.inSeconds}s');
  if (status == 0) {
    stdout.writeln(
      'KEY ${foundKey.value.toRadixString(16).toUpperCase().padLeft(12, '0')}',
    );
  }
  stdout.writeln(
    'first progress: '
    '${firstReport == null ? "never reported" : "${firstReport!.inMilliseconds} ms"}',
  );
  exit(0);
}
