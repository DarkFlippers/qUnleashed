import 'dart:convert';

import 'package:flipperlib/flipperlib.dart';
import 'package:flutter/foundation.dart';

import 'existed_keys_storage.dart';
import 'hardnested_recoverer.dart';
import 'key_nonce_parser.dart';
import 'mfkey32_api.dart';
import 'mfkey32_models.dart';
import 'mfkey32_recoverer.dart';
import 'nested_api.dart';
import 'nested_models.dart';
import 'nested_nonce_parser.dart';
import 'nested_recoverer.dart';
import 'recover_models.dart';
import 'static_encrypted_recoverer.dart';

/// A `(cuid, sector, key)` group of single-sample nested nonces with at least
/// this many nonces is a hardened-PRNG (hardnested) collection; exactly one is
/// the static / static-encrypted case (static never yields more than one nonce
/// for the same sector+key). See BUILD_NOTES / the nested-log format.
const int _hardnestedGroupMin = 2;

String _cuidDictPath(int cuid) =>
    '/ext/nfc/assets/mf_classic_dict_${cuid.toRadixString(16).padLeft(8, '0')}.nfc';

/// Unified "Recover MIFARE Keys" flow: pulls whichever of `.mfkey32.log`
/// (reader) and `.nested.log` (tag) exist, auto-routes each entry to the right
/// attack (mfkey32 / weak nested / static-encrypted / hardnested), and syncs
/// every resolved key into the user dictionary. Static-encrypted nonces can't be
/// resolved to one key offline, so they instead produce a per-card candidate
/// dictionary for on-device verification.
class RecoverController extends ChangeNotifier {
  RecoverController({
    FlipperClient? client,
    MfKey32Api? mfApi,
    NestedApi? nestedApi,
    MfKey32Recoverer? mfRecoverer,
    NestedRecoverer? nestedRecoverer,
    StaticEncryptedRecoverer? staticRecoverer,
    HardnestedRecoverer? hardnestedRecoverer,
  }) : _client = client ?? FlipperOneClient().get(),
       _mfApi = mfApi ?? MfKey32ApiImpl(),
       _nestedApi = nestedApi ?? NestedApiImpl(),
       _mfRecoverer = mfRecoverer ?? NativeMfKey32Recoverer(),
       _nestedRecoverer = nestedRecoverer ?? NativeNestedRecoverer(),
       _staticRecoverer = staticRecoverer ?? NativeStaticEncryptedRecoverer(),
       _hardnestedRecoverer =
           hardnestedRecoverer ?? NativeHardnestedRecoverer() {
    _state = const MfKey32Error(MfKey32ErrorType.flipperConnection);
    _storage = ExistedKeysStorage(_client);
  }

  final FlipperClient _client;
  final MfKey32Api _mfApi;
  final NestedApi _nestedApi;
  final MfKey32Recoverer _mfRecoverer;
  final NestedRecoverer _nestedRecoverer;
  final StaticEncryptedRecoverer _staticRecoverer;
  final HardnestedRecoverer _hardnestedRecoverer;
  late final ExistedKeysStorage _storage;

  late MfKey32State _state;
  bool _running = false;
  final List<RecoverEntry> _entries = [];
  Set<String> _addedKeys = const {};

  int _totalUnits = 0;
  int _doneUnits = 0;

  MfKey32State get state => _state;
  bool get running => _running;

  /// Every recovery result gathered this run, in completion order.
  List<RecoverEntry> get entries => List.unmodifiable(_entries);

  /// Keys newly written to the user dictionary this run (i.e. not already in the
  /// user or system dict). Lets the UI tag each key new vs. already-known.
  Set<String> get addedKeys => _addedKeys;

  Future<void> start() async {
    if (_running) return;
    _running = true;
    try {
      await _run();
    } catch (e, st) {
      LogService.log('[Recover] Unexpected failure: $e\n$st');
      _emit(const MfKey32Error(MfKey32ErrorType.recoveryFailed));
    } finally {
      _running = false;
      notifyListeners();
    }
  }

  Future<void> _run() async {
    _entries.clear();
    _addedKeys = const {};
    _totalUnits = 0;
    _doneUnits = 0;

    if (!_client.isConnected) {
      _emit(const MfKey32Error(MfKey32ErrorType.flipperConnection));
      return;
    }

    _emit(const MfKey32WaitingForFlipper());

    await _mfApi.checkBruteforceFileExist(_client);
    final hasReaderLog = _mfApi.isBruteforceFileExist;
    final hasTagLog = await _nestedApi.nonceFileExists(_client);
    if (!hasReaderLog && !hasTagLog) {
      _emit(const MfKey32Error(MfKey32ErrorType.notFoundFile));
      return;
    }

    _emit(const MfKey32DownloadingRawFile(0));
    final readerText = hasReaderLog ? await _download(pathNonceLog) : null;
    final tagText = hasTagLog ? await _download(pathNestedLog) : null;
    if (readerText == null && tagText == null) {
      _emit(const MfKey32Error(MfKey32ErrorType.notFoundFile));
      return;
    }

    try {
      await _storage.load();
    } catch (e) {
      LogService.log('[Recover] load keys failed: $e');
      _emit(const MfKey32Error(MfKey32ErrorType.readWrite));
      return;
    }

    // Plan the work up front so progress is meaningful across both logs.
    final readerNonces = readerText == null
        ? const <MfKey32Nonce>[]
        : _dedupeReader(KeyNonceParser.parse(readerText));
    final tagNonces = tagText == null
        ? const <NestedNonce>[]
        : NestedNonceParser.parse(tagText);
    final weak = _dedupeWeak(tagNonces.where((n) => n.hasPair));
    final (staticSingles, hardGroups) = _splitSingles(
      tagNonces.where((n) => !n.hasPair),
    );
    _totalUnits =
        readerNonces.length +
        weak.length +
        hardGroups.length +
        (staticSingles.isEmpty ? 0 : 1);
    _emit(const MfKey32Calculating(0));

    await _recoverReader(readerNonces);
    await _recoverWeak(weak);
    for (final group in hardGroups) {
      await _recoverHardnested(group);
    }
    if (staticSingles.isNotEmpty) await _recoverStatic(staticSingles);

    _emit(const MfKey32Uploading());
    try {
      _addedKeys = (await _storage.upload()).toSet();
    } catch (e) {
      LogService.log('[Recover] save keys failed: $e');
      _emit(const MfKey32Error(MfKey32ErrorType.readWrite));
      return;
    }

    _emit(MfKey32Saved(_addedKeys.toList()));
  }

  // ---- reader (mfkey32) ----

  List<MfKey32Nonce> _dedupeReader(List<MfKey32Nonce> nonces) {
    final byKey = <String, MfKey32Nonce>{};
    for (final n in nonces) {
      byKey.putIfAbsent('${n.uid}-${n.sectorName}-${n.keyName}', () => n);
    }
    return byKey.values.toList(growable: false);
  }

  Future<void> _recoverReader(List<MfKey32Nonce> nonces) async {
    for (final n in nonces) {
      final key = await _mfRecoverer.bruteforceKey(n);
      final keyHex = key == null ? null : formatMifareKey(key.toInt());
      _storage.onNewKey(
        FoundedKey(sectorName: n.sectorName, keyName: n.keyName, key: keyHex),
      );
      _entries.add(
        RecoverEntry(
          source: RecoverSource.reader,
          kind: RecoverKind.mfkey32,
          cuid: n.uid,
          sectorName: n.sectorName,
          keyName: n.keyName,
          key: keyHex,
        ),
      );
      _tick();
    }
  }

  // ---- tag: weak nested ----

  List<NestedNonce> _dedupeWeak(Iterable<NestedNonce> pairs) {
    final byKey = <String, NestedNonce>{};
    for (final n in pairs) {
      byKey.putIfAbsent('${n.cuid}-${n.sector}-${n.keyType}', () => n);
    }
    return byKey.values.toList(growable: false);
  }

  Future<void> _recoverWeak(List<NestedNonce> weak) async {
    // Recovery is memory-heavy (~50 MB per isolate); cap concurrency.
    const maxConcurrent = 4;
    for (var i = 0; i < weak.length; i += maxConcurrent) {
      await Future.wait(
        weak.skip(i).take(maxConcurrent).map((n) async {
          final key = await _nestedRecoverer.recoverKey(n);
          final keyHex = key == null ? null : formatMifareKey(key.toInt());
          _storage.onNewKey(
            FoundedKey(
              sectorName: n.sectorName,
              keyName: n.keyName,
              key: keyHex,
            ),
          );
          _entries.add(
            RecoverEntry(
              source: RecoverSource.tag,
              kind: RecoverKind.weakNested,
              cuid: n.cuid,
              sectorName: n.sectorName,
              keyName: n.keyName,
              key: keyHex,
            ),
          );
          _tick();
        }),
      );
    }
  }

  // ---- tag: split single-sample nonces into static vs hardnested ----

  (List<NestedNonce>, List<List<NestedNonce>>) _splitSingles(
    Iterable<NestedNonce> singles,
  ) {
    final groups = <String, List<NestedNonce>>{};
    for (final n in singles) {
      groups.putIfAbsent('${n.cuid}-${n.sector}-${n.keyType}', () => []).add(n);
    }
    final staticSingles = <NestedNonce>[];
    final hardGroups = <List<NestedNonce>>[];
    for (final group in groups.values) {
      if (group.length < _hardnestedGroupMin) {
        staticSingles.add(group.first);
      } else {
        hardGroups.add(group);
      }
    }
    return (staticSingles, hardGroups);
  }

  // ---- tag: hardnested ----

  Future<void> _recoverHardnested(List<NestedNonce> group) async {
    final first = group.first;
    // For a hardened card the plaintext nonce is unknown (nt=0), so the
    // encrypted nonce is nt ^ ks; par is the encrypted-parity nibble as-is.
    final ntEnc = group
        .map((n) => n.samples[0].nt ^ n.samples[0].ks)
        .toList(growable: false);
    final parEnc = group.map((n) => n.samples[0].par).toList(growable: false);
    final key = await _hardnestedRecoverer.recoverKey(
      cuid: first.cuid,
      ntEnc: ntEnc,
      parEnc: parEnc,
    );
    final keyHex = key == null ? null : formatMifareKey(key.toInt());
    if (keyHex != null) {
      _storage.onNewKey(
        FoundedKey(
          sectorName: first.sectorName,
          keyName: first.keyName,
          key: keyHex,
        ),
      );
    }
    _entries.add(
      RecoverEntry(
        source: RecoverSource.tag,
        kind: RecoverKind.hardnested,
        cuid: first.cuid,
        sectorName: first.sectorName,
        keyName: first.keyName,
        key: keyHex,
        note: keyHex == null
            ? 'Not recovered — likely too few nonces (${group.length}). '
                  'Collect more on the device and retry.'
            : null,
      ),
    );
    _tick();
  }

  // ---- tag: static-encrypted candidate dictionaries ----

  Future<void> _recoverStatic(List<NestedNonce> singles) async {
    final List<StaticCandidateDict> dicts;
    try {
      dicts = await _staticRecoverer.buildCandidateDicts(singles);
    } catch (e, st) {
      LogService.log('[Recover] static candidate gen failed: $e\n$st');
      _entries.add(
        RecoverEntry(
          source: RecoverSource.tag,
          kind: RecoverKind.staticEncrypted,
          cuid: singles.first.cuid,
          note: 'Candidate generation failed (native component unavailable).',
        ),
      );
      _tick();
      return;
    }

    for (final dict in dicts) {
      String? note;
      if (dict.count > 0) {
        try {
          await _client.storageWriteChunked(
            _cuidDictPath(dict.cuid),
            dict.body,
          );
        } catch (e) {
          LogService.log('[Recover] static dict write failed: $e');
          note = 'Could not write the candidate dictionary to the device.';
        }
      }
      _entries.add(
        RecoverEntry(
          source: RecoverSource.tag,
          kind: RecoverKind.staticEncrypted,
          cuid: dict.cuid,
          candidateCount: dict.count,
          note: note,
        ),
      );
    }
    _tick();
  }

  // ---- helpers ----

  Future<String?> _download(String path) async {
    try {
      final bytes = await _client.storageReadChunked(
        path,
        timeout: const Duration(minutes: 5),
      );
      return const Utf8Decoder().convert(bytes);
    } catch (e) {
      LogService.log('[Recover] download $path failed: $e');
      return null;
    }
  }

  void _tick() {
    _doneUnits++;
    if (_state is MfKey32Calculating && _totalUnits > 0) {
      _emit(MfKey32Calculating(_doneUnits / _totalUnits));
    } else {
      notifyListeners();
    }
  }

  void _emit(MfKey32State state) {
    _state = state;
    notifyListeners();
  }
}
