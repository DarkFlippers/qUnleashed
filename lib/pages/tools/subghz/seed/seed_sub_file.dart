import '../../../../components/name_rule.dart';
import '../../../../components/path.dart';
import 'seed_models.dart';

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
    var frame = (BigInt.from(fix) << 32) | BigInt.from(frameHop);
    if (manufacturer.protocol.framesAreBitReversed) frame = _reverse64(frame);
    final buffer = StringBuffer()
      ..writeln('Filetype: Flipper SubGhz Key File')
      ..writeln('Version: 1')
      ..writeln('Frequency: $frequencyHz')
      ..writeln('Preset: ${preset ?? defaultPreset}')
      ..writeln('Protocol: ${manufacturer.protocol.inFile}')
      ..writeln('Bit: 64')
      ..writeln('Key: ${_bytes(frame, 8)}')
      ..writeln('Seed: ${_bytes(BigInt.from(seed), 4)}');

    // Faac reads a zero seed as "unknown" unless the file says otherwise. The
    // one case where an absent-looking value is a real one.
    if (manufacturer.protocol == SeedProtocol.faacSlh && seed == 0) {
      buffer.writeln('AllowZeroSeed: true');
    }
    buffer.writeln('Manufacture: ${manufacturer.inFile}');
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
  /// Counted in bytes, which no accepted name can now distinguish from
  /// characters - [checkBaseName] refuses everything outside ASCII first, so
  /// nothing observes the difference and no test can pin it. Kept in bytes
  /// because relaxing the ASCII rule would make the two differ again, and
  /// `length` got that wrong once at 126 bytes. What is pinned is this
  /// constant's value, which is what a wrong edit reaches a device through.
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

  /// What a name for one of these files may be.
  ///
  /// The rule is the Flipper's storage - [deviceNameProblem] - because the
  /// character set, the dot rule and the counting are its, not Sub-GHz's.
  /// While this feature held them, four prompts in the file manager and the
  /// archive wrote user-typed names to the device with no check at all, and a
  /// fifth with a weak one. #277
  ///
  /// What is Sub-GHz's is [maxBaseNameLength], and this is the one place that
  /// binds the two: the page hands it to the prompt and the controller asks it
  /// about a name, where before there were two expressions saying the same
  /// thing in one folder. It judges the name *without* the extension;
  /// [fileExtension] is added after.
  static const nameRule = NameRule.ofBytes(maxBaseNameLength);

  /// Everything a generated name leaves out. Tidiness, not a storage rule -
  /// [checkBaseName] accepts a space from a user, and "FAAC SLH" has one.
  static final _outsideLabel = RegExp(r'[^A-Za-z0-9]');

  /// The frame turned round, for the protocols that are stored that way - see
  /// [SeedProtocol.framesAreBitReversed] for why.
  ///
  /// Over all 64 bits, which is the only width these files carry: [render]
  /// writes `Bit: 64` as a literal and is the only thing that writes one of
  /// these. The firmware reverses whatever count the file declares, so the two
  /// have to stay in step.
  static BigInt _reverse64(BigInt value) {
    var out = BigInt.zero;
    for (var i = 0; i < 64; i++) {
      out = (out << 1) | ((value >> i) & BigInt.one);
    }
    return out;
  }

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
