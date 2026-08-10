import 'dart:io';
import 'dart:typed_data';

import 'package:dartufbt/dartufbt.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qunleashed/services/assembler/build_service.dart';
import 'package:qunleashed/services/assembler/controller.dart';
import 'package:qunleashed/pages/flibler/project/controller.dart';

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

  final projectPath = Platform.environment['DARTUFBT_PROJECT'];
  test(
    'builds a project folder picked in the tool',
    () async {
      final project = FliblerProjectController();
      project.setFolder(projectPath!);

      expect(await project.loadProject(), isTrue, reason: project.error);
      expect(project.app!.appid, isNotEmpty);
      expect(project.icon, isNotNull);
      expect(project.targetPath, startsWith('/ext/apps/'));
      expect(project.targetPath, endsWith('.fap'));

      // Sending needs a device, the build itself must still produce the FAP.
      await project.build();
      expect(project.fap!.existsSync(), isTrue);
    },
    timeout: const Timeout(Duration(minutes: 10)),
    skip:
        AssemblerController.isSupported &&
            projectPath != null &&
            Directory(projectPath).existsSync() &&
            controller.installer.status().isReady
        ? false
        : 'ufbt state or DARTUFBT_PROJECT is not available',
  );

  final repoUrl = Platform.environment['DARTUFBT_REPO'];
  test(
    'clones a repository link and builds it',
    () async {
      final project = FliblerProjectController();
      project.setKind(FliblerSourceKind.repository);
      project.setRepo(repoUrl!);

      expect(await project.loadProject(), isTrue, reason: project.error);
      expect(project.app!.appid, isNotEmpty);

      await project.build();
      expect(project.fap!.existsSync(), isTrue);
    },
    timeout: const Timeout(Duration(minutes: 15)),
    skip:
        AssemblerController.isSupported &&
            repoUrl != null &&
            controller.installer.status().isReady
        ? false
        : 'ufbt state or DARTUFBT_REPO is not available',
  );
}
