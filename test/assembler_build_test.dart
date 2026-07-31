import 'dart:io';
import 'dart:typed_data';

import 'package:dartufbt/dartufbt.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qunleashed/pages/asembler/build_service.dart';
import 'package:qunleashed/pages/asembler/controller.dart';

/// Requires a deployed ufbt state and a catalog source bundle:
///   DARTUFBT_BUNDLE=/path/to/bundle.zip flutter test test/assembler_build_test.dart
void main() {
  final bundlePath = Platform.environment['DARTUFBT_BUNDLE'];
  final controller = AssemblerController.instance;
  final ready =
      AssemblerController.isSupported &&
      bundlePath != null &&
      File(bundlePath).existsSync() &&
      controller.installer.status().isReady;

  test(
    'builds a catalog source bundle into a loadable FAP',
    () async {
      final bytes = await AssemblerBuildService.buildFromBundle(
        bundle: File(bundlePath!).readAsBytesSync(),
        alias: 'assembler_build_test',
      );

      expect(bytes.length, greaterThan(1024));
      expect(bytes.sublist(0, 4), [0x7F, 0x45, 0x4C, 0x46]);

      final elf = ElfFile(Uint8List.fromList(bytes));
      final sections = elf.sections.map((section) => section.name).toList();
      expect(sections, contains('.fapmeta'));
      expect(sections, contains('.symtab'));
      expect(sections.any((name) => name.startsWith('.fast.rel')), isTrue);

      final meta = elf.sections.firstWhere((s) => s.name == '.fapmeta');
      final data = ByteData.sublistView(
        Uint8List.fromList(bytes),
        meta.offset,
        meta.offset + meta.size,
      );
      expect(data.getUint32(0, Endian.little), ElfManifest.magic);
      expect(data.getUint32(4, Endian.little), ElfManifest.manifestVersion);
    },
    timeout: const Timeout(Duration(minutes: 10)),
    skip: ready ? false : 'ufbt state or DARTUFBT_BUNDLE is not available',
  );
}
