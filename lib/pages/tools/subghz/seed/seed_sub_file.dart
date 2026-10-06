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

  /// The preset the capture app records and the one these remotes use.
  static const preset = 'FuriHalSubGhzPresetOok650Async';

  /// Renders the file.
  ///
  /// [frameHop] is the *rebuilt* rolling half, not the captured one: the engine
  /// re-encrypts it from the fixed code and the counter under the recovered
  /// key, and only reports [SeedOutcome.found] when that reproduces the last
  /// captured hop. A caller must therefore write this only on that outcome -
  /// which is why the engine makes it a status rather than a flag.
  static String render({
    required SeedManufacturer manufacturer,
    required int fix,
    required int frameHop,
    required int seed,
    required int frequencyHz,
  }) {
    final frame = (BigInt.from(fix) << 32) | BigInt.from(frameHop);
    final buffer = StringBuffer()
      ..writeln('Filetype: Flipper SubGhz Key File')
      ..writeln('Version: 1')
      ..writeln('Frequency: $frequencyHz')
      ..writeln('Preset: $preset')
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

  /// A name that says what the file is without colliding with the next one.
  ///
  /// The fixed code is in it because that is what identifies the remote, and
  /// two recoveries of the same remote should land on the same name rather than
  /// accumulating copies.
  static String fileName({
    required SeedManufacturer manufacturer,
    required int fix,
  }) {
    final label = manufacturer.label.replaceAll(RegExp(r'[^A-Za-z0-9]'), '');
    return '${label}_${_hex(fix, 8)}.sub';
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

  static String _hex(int value, int digits) =>
      value.toRadixString(16).toUpperCase().padLeft(digits, '0');
}
