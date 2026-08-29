import 'mfkey32_models.dart';

/// Where a recovered key's nonces came from.
enum RecoverSource {
  /// `.mfkey32.log` — the key a *reader* used against an emulated card.
  reader,

  /// `.nested.log` — keys read off a physical *tag*.
  tag,
}

/// Which attack / tag type produced an entry. `staticNonce` and `weakNested`
/// both solve with the same crapto1 nested math; they differ only by whether the
/// tag's nonce advances (`dist != 0` = weak, `dist == 0` = static).
enum RecoverKind {
  mfkey32,
  weakNested,
  staticNonce,
  staticEncrypted,
  hardnested,

  /// Not an attack: lines of the tag log that could not be read at all. A
  /// corrupt nonce is dropped rather than guessed at, and this is how the run
  /// says so — otherwise those sector keys go unattacked with nothing on
  /// screen to explain it.
  corruptLog,
}

/// One row of the grouped recovery summary (grouped in the UI by
/// source → card (cuid) → sector/key).
class RecoverEntry {
  const RecoverEntry({
    required this.source,
    required this.kind,
    this.cuid,
    this.sectorName,
    this.keyName,
    this.key,
    this.isNew,
    this.candidateCount,
    this.note,
  });

  final RecoverSource source;
  final RecoverKind kind;

  /// The card this entry is about, or null for a run-level entry that no card
  /// can be attributed to (a tag log that would not parse).
  final int? cuid;

  /// Sector / key labels for a concrete key result. Null for a per-card
  /// static-encrypted candidate summary.
  final String? sectorName;
  final String? keyName;

  /// Recovered 12-hex-digit key, or null when not resolved to one key
  /// (static-encrypted candidates, or a failed / too-few-nonces hardnested group).
  final String? key;

  /// Whether [key] was new to the user + system dictionaries (true) or already
  /// known (false); null when there is no resolved key. Decided at recovery time
  /// so the "new / already in dict" tag is correct during progress, not only in
  /// the final summary.
  final bool? isNew;

  /// Static-encrypted: the entry count of the dictionary written for this card
  /// - see `StaticCandidateDict.count`.
  final int? candidateCount;

  /// Extra context (e.g. "too few nonces — collect more", or a write failure).
  final String? note;

  String? get cuidHex {
    final value = cuid;
    return value == null ? null : formatCuid(value).toUpperCase();
  }
}

/// State machine for the "Recover MIFARE Keys" flow (drives the status header).
sealed class RecoverState {
  const RecoverState();
}

class RecoverWaitingForDevice extends RecoverState {
  const RecoverWaitingForDevice();
}

class RecoverDownloading extends RecoverState {
  const RecoverDownloading([this.progress]);

  final double? progress;
}

class RecoverCalculating extends RecoverState {
  const RecoverCalculating();
}

class RecoverUploading extends RecoverState {
  const RecoverUploading();
}

class RecoverSaved extends RecoverState {
  const RecoverSaved({
    required this.keys,
    this.hasCandidates = false,
    this.hasFailures = false,
  });

  /// Keys newly written to the user dictionary this run.
  final List<String> keys;

  /// True when a per-card static-encrypted candidate dictionary was written.
  final bool hasCandidates;

  /// True when a step failed (an attack engine was unavailable, or a candidate
  /// dictionary couldn't be generated or written) even though the run otherwise
  /// completed - so the summary avoids a clean "success" headline.
  final bool hasFailures;
}

class RecoverError extends RecoverState {
  const RecoverError(this.errorType);

  final RecoverErrorType errorType;
}

enum RecoverErrorType {
  notFoundFile,
  readWrite,
  flipperConnection,
  recoveryFailed,
}
