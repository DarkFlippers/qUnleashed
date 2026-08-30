import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:dartufbt/dartufbt.dart';

import '../localization/l10n.dart';
import 'controller.dart';

/// The local toolchain cannot run: it is missing, incomplete or unusable on
/// this platform. Nothing was compiled, so the same build may be handed to the
/// build server instead.
class AssemblerNotReadyException implements Exception {
  const AssemblerNotReadyException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// The toolchain ran and the app did not build. Rebuilding it elsewhere would
/// fail the same way, so this one is shown to the user as is.
class AssemblerBuildFailedException implements Exception {
  const AssemblerBuildFailedException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Whether a failed local build says something about this computer rather than
/// about the app: everything here can be retried on the build server.
bool isLocalEnvironmentFailure(Object error) =>
    error is AssemblerNotReadyException ||
    error is FapEnvironmentException ||
    error is FileSystemException ||
    error is ProcessException ||
    error is OSError ||
    error is ArchiveException;

class AssemblerBuildService {
  const AssemblerBuildService._();

  static const String manifestName = 'application.fam';

  static void ensureReady() {
    final controller = AssemblerController.instance;
    if (!AssemblerController.isSupported) {
      throw AssemblerNotReadyException(l10n.buildErrorDesktopOnly);
    }

    final status = controller.installer.status();
    if (!status.sdkDeployed) {
      throw AssemblerNotReadyException(l10n.buildErrorNoSdk);
    }
    if (!status.toolchain.isUpToDate) {
      throw AssemblerNotReadyException(l10n.buildErrorNoToolchain);
    }
  }

  /// Builds a project checked out anywhere on disk, the way `ufbt` does in a
  /// source folder.
  static Future<List<FapBuildResult>> buildProject({
    required Directory root,
    String? alias,
  }) {
    ensureReady();
    final controller = AssemblerController.instance;
    final appDir = findAppDir(root);
    if (appDir == null) {
      throw AssemblerBuildFailedException(
        l10n.buildErrorNoManifestIn(manifestName, root.path),
      );
    }
    return controller.runBuild(alias ?? _name(appDir.path), () async {
      final builder = FapBuilder(
        logger: controller.logger,
        paths: controller.installer.paths,
      );
      final results = await builder.buildAll(
        appDir: appDir,
        outputDir: Directory(UfbtPaths.join(root.path, 'dist')),
      );
      for (final result in results) {
        if (!result.success || result.fap == null) {
          throw AssemblerBuildFailedException(
            result.error ?? l10n.buildErrorFailed,
          );
        }
        controller.logger.info('Built ${result.fap!.path}');
      }
      return results;
    });
  }

  static String _name(String path) =>
      path.split(RegExp(r'[/\\]')).where((p) => p.isNotEmpty).last;

  static Future<List<int>> buildFromBundle({
    required List<int> bundle,
    required String alias,
  }) async {
    ensureReady();
    final controller = AssemblerController.instance;

    return controller.runBuild(alias, () async {
      final paths = controller.installer.paths;
      final root = Directory(
        UfbtPaths.join(paths.stateDir.path, 'bundles', alias),
      );
      if (root.existsSync()) root.deleteSync(recursive: true);
      root.createSync(recursive: true);

      controller.logger.info('Unpacking source bundle for $alias');
      final archive = ZipDecoder().decodeBytes(bundle);
      final task = controller.logger.progress('', total: archive.length);
      var done = 0;
      for (final entry in archive) {
        final path = _safePath(root, entry.name);
        if (path != null) {
          if (entry.isFile) {
            final output = OutputFileStream(path);
            entry.writeContent(output);
            await output.close();
          } else {
            Directory(path).createSync(recursive: true);
          }
        }
        task.update(current: ++done);
        await Future<void>.delayed(Duration.zero);
      }
      task.finish();

      final appDir = findAppDir(root);
      if (appDir == null) {
        throw AssemblerBuildFailedException(
          l10n.buildErrorNoManifestInBundle(manifestName),
        );
      }

      final builder = FapBuilder(logger: controller.logger, paths: paths);
      final result = await builder.build(
        appDir: appDir,
        outputDir: Directory(UfbtPaths.join(root.path, 'dist')),
      );
      if (!result.success || result.fap == null) {
        throw AssemblerBuildFailedException(
          result.error ?? l10n.buildErrorFailed,
        );
      }
      controller.logger.info('Built ${result.fap!.path}');
      return result.fap!.readAsBytesSync();
    });
  }

  static Directory? findAppDir(Directory root) {
    final preferred = Directory(UfbtPaths.join(root.path, 'code'));
    if (File(UfbtPaths.join(preferred.path, manifestName)).existsSync()) {
      return preferred;
    }
    if (File(UfbtPaths.join(root.path, manifestName)).existsSync()) return root;

    for (final entity in root.listSync(recursive: true, followLinks: false)) {
      if (entity is File && entity.uri.pathSegments.last == manifestName) {
        return entity.parent;
      }
    }
    return null;
  }

  static String? _safePath(Directory root, String name) {
    final parts = name.split(RegExp(r'[/\\]'));
    if (parts.any((part) => part == '..' || part == '.')) return null;
    final clean = parts.where((part) => part.isNotEmpty).toList();
    if (clean.isEmpty) return null;
    return [root.path, ...clean].join(Platform.pathSeparator);
  }
}
