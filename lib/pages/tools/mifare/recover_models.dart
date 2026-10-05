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
  /// static-encrypted candidate summary and for a [RecoverKind.corruptLog]
  /// run-level entry.
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
  /// — see `CuidDictBody.entries`. Only ever set together with [cuid], since
  /// the row it produces names the file the entries were written to.
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

/// Attacking. Carries the run's unit counter, and - when the phase can say so -
/// how far through the current unit it is.
///
/// One state rather than one per phase. A phase of its own drops the unit
/// counter while it is showing, and leaves its own last reading on screen after
/// it finishes: a hardnested group that ended at 47% sat there through the next
/// group's table decompression, which reports nothing. [label] and [fraction]
/// are cleared by finishing a unit, so staleness cannot outlive the thing it
/// describes.
class RecoverCalculating extends RecoverState {
  const RecoverCalculating({this.label, this.fraction});

  /// What the current unit is doing, when it is not simply "a key". Null for
  /// the attacks that are over in about a second.
  final String? label;

  /// Progress through the current unit, 0..1, when the phase can measure it.
  /// Only the hardnested brute force can; everything else is either quick or
  /// measured in whole units.
  final double? fraction;
}

class RecoverUploading extends RecoverState {
  const RecoverUploading([this.progress]);

  /// Null while the size of the work is not known - the user dictionary is a
  /// read-modify-write of a file small enough that a percentage would be gone
  /// before it was read. The candidate dictionaries are not: a card whose two
  /// sector keys share a nonce yields no cross-filter reduction and over a
  /// megabyte of entries, which is minutes over BLE.
  final double? progress;
}

class RecoverSaved extends RecoverState {
  const RecoverSaved({
    required this.keys,
    this.hasCandidates = false,
    this.hasFailures = false,
    this.skippedKnown = 0,
    this.stopped = false,
  });

  /// Keys newly written to the user dictionary this run.
  final List<String> keys;

  /// True when a per-card static-encrypted candidate dictionary was written.
  final bool hasCandidates;

  /// True when a step failed (an attack engine was unavailable, or a candidate
  /// dictionary couldn't be generated or written) even though the run otherwise
  /// completed - so the summary avoids a clean "success" headline.
  final bool hasFailures;

  /// Sector keys the dictionary already held, which were recorded without
  /// being attacked again. Worth saying: it is the difference between a run
  /// that did nothing and one that had nothing left to do.
  final int skippedKnown;

  /// True when the user pressed Stop, so this run ended before it had attacked
  /// everything it planned to.
  ///
  /// A third thing, and it used to render as the first: "No new keys added" is
  /// the same sentence whether twelve sectors were attacked and yielded nothing
  /// or two were attacked and the user stopped. The keys found are kept either
  /// way - that is what Stop is for - but what was *not* tried has to be said,
  /// or the next run looks pointless.
  final bool stopped;
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

  /// Keys were recovered and then could not be written to the device.
  ///
  /// Apart from [readWrite] because the two leave the user somewhere
  /// completely different: that one means nothing happened, this one means the
  /// work was done and is sitting on screen unsaved. Telling them apart is the
  /// difference between "try again" and "try again before you close this".
  saveFailed,
}
