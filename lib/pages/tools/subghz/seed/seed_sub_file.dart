import 'dart:convert';

import '../../../../components/path.dart';
import 'seed_models.dart';

/// Why a name the user typed cannot be used.
///
/// An enum rather than a message, so the page can say it in the user's language
/// and the set stays exhaustive - the same reason `SeedFailure` is one.
enum SeedNameProblem {
  empty,
  tooLong,

  /// One of the nine `reservedNameChars`. Separate from [controlCharacter]
  /// because the message for this one can list what it refuses and the message
  /// for that one cannot.
  illegalCharacter,

  /// A C0 control character or DEL, which a paste can carry in and a keyboard
  /// cannot type.
  controlCharacter,
  dotEdge,
}

/// Where the Flipper keeps transmittable Sub-GHz files. A recovered remote
/// written anywhere else is a number on a screen; written here it appears under
/// Sub-GHz -> Saved and can be sent.
const seedSubGhzDir = '/ext/subghz';

/// Builds the Flipper key file for a recovered remote.
///
/// The layout is what `subghz_block_generic_serialize()` produces plus the
/// extra keys each protocol reads back. What makes the file transmittable
/// rather than a replay is `Seed`: without it the firmware treats the remote as
/// unknown and will not roll the counter forward.
class SeedSubFile {
  const SeedSubFile._();

  /// What these remotes use, for a capture whose file did not say.
  static const defaultPreset = 'FuriHalSubGhzPresetOok650Async';

  /// Renders the file for a verified recovery.
  ///
  /// Takes the result rather than loose numbers, and refuses anything that is
  /// not [SeedOutcome.found]. The engine went to the trouble of making that a
  /// *status* rather than a flag precisely so a caller "cannot get it wrong by
  /// forgetting" - and a function taking five bare ints with the obligation
  /// stated only in a doc comment hands that forgettability straight back. The
  /// product of forgetting is a file the firmware accepts and will not
  /// transmit, which the user experiences as a gate that does not open.
  ///
  /// `frameHop` is the *rebuilt* rolling half, not the captured one: the engine
  /// re-encrypts it from the fixed code and the counter under the recovered
  /// key, and only reports found when that reproduces the last captured hop.
  static String render({
    required SeedResult result,
    required SeedManufacturer manufacturer,
    required int fix,
    required int frequencyHz,
    String? preset,
  }) {
    if (result.outcome != SeedOutcome.found) {
      throw ArgumentError.value(
        result.outcome,
        'result.outcome',
        'only a verified recovery may be written as a .sub',
      );
    }
    final frameHop = result.frameHop!;
    final seed = result.seed!;
    final frame = (BigInt.from(fix) << 32) | BigInt.from(frameHop);
    final buffer = StringBuffer()
      ..writeln('Filetype: Flipper SubGhz Key File')
      ..writeln('Version: 1')
      ..writeln('Frequency: $frequencyHz')
      ..writeln('Preset: ${preset ?? defaultPreset}')
      ..writeln('Protocol: ${manufacturer.protocol}')
      ..writeln('Bit: 64')
      ..writeln('Key: ${_bytes(frame, 8)}')
      ..writeln('Seed: ${_bytes(BigInt.from(seed), 4)}');

    // Faac reads a zero seed as "unknown" unless the file says otherwise. The
    // one case where an absent-looking value is a real one.
    if (manufacturer.protocol == 'Faac SLH' && seed == 0) {
      buffer.writeln('AllowZeroSeed: true');
    }
    buffer.writeln('Manufacture: ${manufacturer.label}');
    return buffer.toString();
  }

  /// What the firmware recognises a transmittable Sub-GHz file by.
  ///
  /// Appended rather than typed: a user who renames the file to `gate` gets one
  /// the Sub-GHz app does not list, and one who types `gate.sub` into a field
  /// that also appends would get `gate.sub.sub`.
  static const fileExtension = '.sub';

  /// The longest base name that survives a rename on the device, in **bytes**.
  ///
  /// `SUBGHZ_MAX_LEN_NAME` is 64, and `subghz_scene_save_name.c` copies the
  /// *extension-less* name into a `char[64]` with `strncpy`. So 63 bytes and
  /// the terminator is what the Sub-GHz app can hold. A longer name writes
  /// fine over RPC and is then truncated the first time the user renames it
  /// there, which is a worse surprise than refusing it here.
  ///
  /// Bytes and not characters, which is not the same count outside the English
  /// alphabet: the firmware's limit is a buffer, and a name is UTF-8 on the
  /// wire, so a Cyrillic letter costs two of these and an emoji four. Counting
  /// Dart's `length` instead let a 63-letter Cyrillic name through at 126
  /// bytes, of which the rename keeps 64 and terminates none - `strncpy` with
  /// `n` equal to the buffer writes no terminator when the source fills it.
  ///
  /// Found while answering #266's question about non-ASCII names rather than
  /// reported by it.
  static const maxBaseNameLength = 63;

  /// The suggested name for a recovery, without the extension.
  ///
  /// The fixed code is in it because that is what identifies the remote, and
  /// two recoveries of the same remote should land on the same name rather than
  /// accumulating copies.
  static String baseName({
    required SeedManufacturer manufacturer,
    required int fix,
  }) {
    final label = manufacturer.label.replaceAll(_outsideLabel, '');
    return '${label}_${seedHex(fix, 8)}';
  }

  /// Where a file called [raw] is written.
  ///
  /// Beside [checkBaseName] because the two have to agree about trimming: the
  /// check judges the trimmed name, so a path built from the untrimmed one
  /// would be a different file from the one that was approved.
  static String pathFor(String raw) =>
      '$seedSubGhzDir/${raw.trim()}$fileExtension';

  /// What is wrong with [raw] as a base name, or null when nothing is.
  ///
  /// These are the storage layer's rules, not the on-screen keyboard's. The
  /// Flipper's own text input offers `a-z`, `A-Z`, `0-9`, `_` and the space
  /// that its shifted `_` produces (`text_input.c`, `char_to_uppercase`), but
  /// a file written over RPC lands on a FAT volume and is listed by a browser
  /// that is perfectly happy with a dash too - so refusing one would be this
  /// app inventing a rule the device does not have. What is refused is what
  /// the volume genuinely cannot carry.
  ///
  /// Non-ASCII is accepted, which is #266's open question and the firmware
  /// answers it: `targets/f7/fatfs/ffconf.h` sets `_LFN_UNICODE 0` and
  /// `_CODE_PAGE 850`, so FatFS takes the path as OEM bytes, and the CP850
  /// table in `lib/fatfs/option/ccsbcs.c` maps all 128 high bytes with no
  /// duplicates. Mapping every byte is why such a name never *fails*; the
  /// table being injective is why it reads back byte-identical over RPC, so
  /// this app shows it correctly. Change `_CODE_PAGE` and both halves of that
  /// need re-checking.
  ///
  /// What it does not do is render on the Flipper's own screen, which shows
  /// mojibake. Refusing it would still be a rule the volume does not have, and
  /// the device's own keyboard cannot type one anyway.
  ///
  /// Takes the name *without* the extension; [fileExtension] is added after.
  static SeedNameProblem? checkBaseName(String raw) {
    final name = raw.trim();
    if (name.isEmpty) return SeedNameProblem.empty;
    if (utf8.encode(name).length > maxBaseNameLength) {
      return SeedNameProblem.tooLong;
    }
    // Before the nine, so that by the time `reservedNameCharsPattern` runs the
    // only thing it can be reporting is a character the message can name.
    if (name.codeUnits.any(isControlNameChar)) {
      return SeedNameProblem.controlCharacter;
    }
    if (reservedNameCharsPattern.hasMatch(name)) {
      return SeedNameProblem.illegalCharacter;
    }
    // FAT32 drops a trailing dot, so a name ending in one is not the name the
    // user will see afterwards; a leading dot hides the file from some browsers,
    // and `.` and `..` are not names at all.
    if (name.startsWith('.') || name.endsWith('.')) {
      return SeedNameProblem.dotEdge;
    }
    return null;
  }

  /// Everything a generated name leaves out. Tidiness, not a storage rule -
  /// [checkBaseName] accepts a space from a user, and "FAAC SLH" has one.
  static final _outsideLabel = RegExp(r'[^A-Za-z0-9]');

  /// Big-endian bytes, space separated and upper case, as the firmware writes
  /// them.
  static String _bytes(BigInt value, int count) => [
    for (var i = count - 1; i >= 0; i--)
      ((value >> (i * 8)) & BigInt.from(0xFF))
          .toRadixString(16)
          .toUpperCase()
          .padLeft(2, '0'),
  ].join(' ');
}
