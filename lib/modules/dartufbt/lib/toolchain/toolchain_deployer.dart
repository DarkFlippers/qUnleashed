import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';

import '../core/ufbt_paths.dart';
import '../log/logger.dart';
import '../net/file_fetcher.dart';

class UfbtToolchainInfo {
  const UfbtToolchainInfo({
    required this.archDir,
    required this.version,
    required this.url,
    required this.installedVersion,
    required this.isDeployed,
  });

  final String archDir;
  final String version;
  final String url;
  final String? installedVersion;
  final bool isDeployed;

  bool get isUpToDate => isDeployed && installedVersion == version;
}

class UfbtToolchainDeployer {
  UfbtToolchainDeployer({
    required this.logger,
    required this.paths,
    required this.fetcher,
  });

  static const String fallbackVersion = '39';
  static const String urlRoot =
      'https://update.flipperzero.one/builds/toolchain';

  final UfbtLogger logger;
  final UfbtPaths paths;
  final UfbtFileFetcher fetcher;

  String get archDirName {
    if (Platform.isWindows) return 'x86_64-windows';
    final arch = _uname('-m');
    final sys = _uname('-s').toLowerCase();
    return '$arch-$sys';
  }

  String get toolchainVersion {
    final override = Platform.environment['FBT_TOOLCHAIN_VERSION'];
    if (override != null && override.isNotEmpty) return override;

    final script = Platform.isWindows ? paths.fbtenvCmd : paths.fbtenvScript;
    if (script.existsSync()) {
      final pattern = Platform.isWindows
          ? RegExp(r'FLIPPER_TOOLCHAIN_VERSION=(\d+)')
          : RegExp(r'FBT_TOOLCHAIN_VERSION=[^\n]*?"(\d+)"');
      final match = pattern.firstMatch(script.readAsStringSync());
      if (match != null) return match.group(1)!;
    }
    return fallbackVersion;
  }

  String toolchainUrl(String version) {
    final suffix = Platform.isWindows ? 'zip' : 'tar.gz';
    return '$urlRoot/gcc-arm-none-eabi-12.3-$archDirName-flipper-$version'
        '.$suffix';
  }

  Directory get _archiveDir =>
      Platform.isWindows ? paths.currentSdkDir : paths.toolchainDir;

  UfbtToolchainInfo status() {
    final version = toolchainVersion;
    final archDir = paths.toolchainArchDir(archDirName);
    final versionFile = File(UfbtPaths.join(archDir.path, 'VERSION'));
    return UfbtToolchainInfo(
      archDir: archDir.path,
      version: version,
      url: toolchainUrl(version),
      installedVersion: versionFile.existsSync()
          ? versionFile.readAsStringSync().trim()
          : null,
      isDeployed: archDir.existsSync(),
    );
  }

  Future<bool> deploy({bool force = false}) async {
    final info = status();

    if (!force && info.isDeployed && info.installedVersion != null) {
      if (info.isUpToDate) return true;
      if (!Platform.isWindows) {
        logger.raw('FBT: starting toolchain upgrade process..');
      }
    }

    return Platform.isWindows ? _deployWindows(info) : _deployUnix(info);
  }

  Future<bool> _deployUnix(UfbtToolchainInfo info) async {
    if (!await _checkTar()) return false;

    final archiveName = info.url.split('/').last;
    final distDirName = archiveName.replaceAll('-${info.version}.tar.gz', '');
    final archiveFile = File(UfbtPaths.join(_archiveDir.path, archiveName));

    logger.raw('Checking if downloaded toolchain tgz exists..', newline: false);
    if (archiveFile.existsSync()) {
      logger.raw('yes');
    } else {
      logger.raw('no');
      logger.raw('Downloading toolchain:');
      try {
        await fetcher.fetchFile(info.url, _archiveDir, usePartFile: true);
      } catch (_) {
        logger.raw('Failed to download ${info.url}');
        return false;
      }
      logger.raw('done');
    }

    final archDir = Directory(info.archDir);
    logger.raw('Removing old toolchain..', newline: false);
    if (archDir.existsSync()) archDir.deleteSync(recursive: true);
    logger.raw('done');

    logger.raw("Unpacking toolchain to '${paths.toolchainDir.path}':");
    final currentLink = paths.toolchainCurrentLink;
    if (_linkExists(currentLink)) currentLink.deleteSync();

    paths.toolchainDir.createSync(recursive: true);
    if (!await _unpackTar(archiveFile)) return false;

    final distDir = Directory(
      UfbtPaths.join(paths.toolchainDir.path, distDirName),
    );
    if (!distDir.existsSync()) return false;
    distDir.renameSync(archDir.path);

    logger.raw("linking toolchain to 'current'..", newline: false);
    currentLink.createSync(archDir.path);
    logger.raw('done');

    _cleanup();
    return true;
  }

  Future<bool> _deployWindows(UfbtToolchainInfo info) async {
    final archiveName = info.url.split('/').last;
    final distDirName = archiveName.replaceAll('-${info.version}.zip', '');
    final archiveFile = File(UfbtPaths.join(_archiveDir.path, archiveName));
    final archDir = Directory(info.archDir);
    final currentLink = paths.toolchainCurrentLink;

    if (archDir.existsSync()) {
      logger.raw('Removing old Windows toolchain..', newline: false);
      archDir.deleteSync(recursive: true);
      logger.raw('done!');
    }

    if (_linkExists(currentLink)) {
      logger.raw("Unlinking 'current'..", newline: false);
      currentLink.deleteSync();
      logger.raw('done!');
    }

    if (!archiveFile.existsSync()) {
      logger.raw('Downloading Windows toolchain..', newline: false);
      try {
        await fetcher.fetchFile(info.url, _archiveDir);
      } catch (e) {
        logger.raw('An error occurred');
        logger.raw('$e');
        return false;
      }
      logger.raw('done!');
    }

    paths.toolchainDir.createSync(recursive: true);

    final distDir = Directory(UfbtPaths.join(_archiveDir.path, distDirName));
    if (distDir.existsSync()) {
      logger.raw('Cleaning up temp toolchain path..');
      distDir.deleteSync(recursive: true);
    }

    logger.raw('Extracting Windows toolchain..', newline: false);
    if (!await _unpackZip(archiveFile)) return false;

    logger.raw('moving..', newline: false);
    if (!distDir.existsSync()) return false;
    distDir.renameSync(archDir.path);

    logger.raw("linking to 'current'..", newline: false);
    currentLink.createSync(archDir.path);
    logger.raw('done!');

    logger.raw('Cleaning up temporary files..', newline: false);
    if (archiveFile.existsSync()) archiveFile.deleteSync();
    logger.raw('done!');
    return true;
  }

  Future<bool> _checkTar() async {
    logger.raw('Checking for tar..', newline: false);
    try {
      final result = await Process.run('tar', ['--version']);
      if (result.exitCode != 0) {
        logger.raw('no');
        return false;
      }
    } catch (_) {
      logger.raw('no');
      return false;
    }
    logger.raw('yes');
    return true;
  }

  Future<bool> _unpackTar(File archiveFile) async {
    final task = logger.progress('');

    final process = await Process.start('tar', [
      '-xvf',
      archiveFile.path,
      '-C',
      paths.toolchainDir.path,
    ]);

    void count(Stream<List<int>> stream) {
      stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((_) => task.advance());
    }

    count(process.stdout);
    count(process.stderr);

    final exitCode = await process.exitCode;
    if (exitCode != 0) {
      task.fail(message: 'tar exited with $exitCode');
      return false;
    }
    task.finish();
    return true;
  }

  Future<bool> _unpackZip(File archiveFile) async {
    final task = logger.progress('');
    try {
      await extractFileToDisk(archiveFile.path, _archiveDir.path);
    } catch (e) {
      task.fail(message: '$e');
      return false;
    }
    task.finish();
    return true;
  }

  void _cleanup() {
    logger.raw('Cleaning up..', newline: false);
    final preserve = Platform.environment['FBT_PRESERVE_TAR'];
    if (paths.toolchainDir.existsSync()) {
      for (final entry in paths.toolchainDir.listSync()) {
        if (entry is! File) continue;
        final name = entry.uri.pathSegments.last;
        if (name.endsWith('.part')) {
          entry.deleteSync();
        } else if ((preserve == null || preserve.isEmpty) &&
            name.endsWith('.tar.gz')) {
          entry.deleteSync();
        }
      }
    }
    logger.raw('done');
  }

  static bool _linkExists(Link link) => link.existsSync();

  static String _uname(String flag) {
    final result = Process.runSync('uname', [flag]);
    return (result.stdout as String).trim();
  }
}
