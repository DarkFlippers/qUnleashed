import 'dart:io';

import 'core/ufbt_paths.dart';
import 'core/ufbt_state.dart';
import 'log/logger.dart';
import 'net/file_fetcher.dart';
import 'sdk/deploy_task.dart';
import 'sdk/sdk_deployer.dart';
import 'sdk/sdk_loader.dart';
import 'toolchain/toolchain_deployer.dart';

class UfbtStatus {
  const UfbtStatus({
    required this.stateDir,
    required this.downloadDir,
    required this.toolchainDir,
    required this.sdkDir,
    required this.previousTask,
    required this.toolchain,
  });

  static const Map<String, String> statusFields = {
    'ufbt_version': 'uFBT version',
    'state_dir': 'State dir',
    'download_dir': 'Download dir',
    'toolchain_dir': 'Toolchain dir',
    'sdk_dir': 'SDK dir',
    'target': 'Target',
    'mode': 'Mode',
    'version': 'Version',
    'details': 'Details',
    'error': 'Error',
  };

  final String stateDir;
  final String downloadDir;
  final String toolchainDir;
  final String sdkDir;
  final SdkDeployTask? previousTask;
  final UfbtToolchainInfo toolchain;

  bool get sdkDeployed => previousTask != null;

  String? get target => previousTask?.hwTarget;

  String? get mode => previousTask?.mode;

  String? get version => previousTask?.params['version'];

  String? get indexUrl => previousTask?.params['json_index'];

  String? get error => sdkDeployed ? null : 'SDK is not deployed';

  bool get isReady => sdkDeployed && toolchain.isUpToDate;

  Map<String, Object> toMap() => {
    'ufbt_version': UfbtInstaller.packageVersion,
    'state_dir': stateDir,
    'download_dir': downloadDir,
    'sdk_dir': sdkDir,
    'toolchain_dir': toolchainDir,
    if (previousTask case final task?) ...{
      'target': task.hwTarget ?? '',
      'mode': task.mode ?? '',
      'version': task.params['version'] ?? UfbtSdkLoader.versionUnknown,
      'details': task.params,
    } else
      'error': 'SDK is not deployed',
  };
}

class UfbtUpdateCheck {
  const UfbtUpdateCheck({
    required this.currentVersion,
    required this.latestVersion,
    required this.target,
  });

  final String? currentVersion;
  final String latestVersion;
  final String target;

  bool get updateAvailable => currentVersion != latestVersion;
}

class UfbtInstaller {
  UfbtInstaller({
    required this.logger,
    UfbtPaths? paths,
    UfbtFileFetcher? fetcher,
  }) : paths = paths ?? UfbtPaths.resolve(),
       _fetcher = fetcher ?? UfbtFileFetcher(logger: logger);

  static const String packageVersion = '0.1.0';

  final UfbtLogger logger;
  final UfbtPaths paths;
  final UfbtFileFetcher _fetcher;

  void close() => _fetcher.close();

  UfbtSdkDeployer get sdkDeployer =>
      UfbtSdkDeployer(logger: logger, paths: paths, fetcher: _fetcher);

  UfbtToolchainDeployer get toolchainDeployer =>
      UfbtToolchainDeployer(logger: logger, paths: paths, fetcher: _fetcher);

  SdkDeployTask resolveTask([SdkDeployTask? request]) {
    final task = sdkDeployer.previousTask() ?? SdkDeployTask.defaults();
    if (request != null) task.updateFrom(request);
    return task;
  }

  UfbtStatus status() {
    return UfbtStatus(
      stateDir: paths.stateDir.path,
      downloadDir: paths.downloadDir.path,
      toolchainDir: paths.toolchainDir.path,
      sdkDir: paths.currentSdkDir.path,
      previousTask: sdkDeployer.previousTask(),
      toolchain: toolchainDeployer.status(),
    );
  }

  Future<UfbtUpdateCheck> checkForUpdate([SdkDeployTask? request]) async {
    final task = resolveTask(request);
    final loader = sdkDeployer.createLoader(task);
    await loader.load();
    return UfbtUpdateCheck(
      currentVersion: UfbtState.read(paths.stateFile)?.version,
      latestVersion: loader.metadata['version'] ?? UfbtSdkLoader.versionUnknown,
      target: task.hwTarget ?? SdkDeployTask.defaultHwTarget,
    );
  }

  Future<bool> installSdk([SdkDeployTask? request]) =>
      sdkDeployer.deploy(resolveTask(request));

  Future<bool> installToolchain({bool force = false}) =>
      toolchainDeployer.deploy(force: force);

  Future<bool> install([SdkDeployTask? request]) async {
    if (!await installSdk(request)) return false;
    return installToolchain(force: request?.force ?? false);
  }

  Future<bool> clean({bool downloads = false, bool purge = false}) async {
    logger.info(
      "If you want to clean build artifacts, use 'ufbt -c', not 'clean'",
    );
    if (purge) {
      logger.info('Cleaning complete ufbt state in ${paths.stateDir.path}');
      _remove(paths.stateDir);
      logger.info('Done');
      return true;
    }
    if (downloads) {
      logger.info('Cleaning download dir ${paths.downloadDir.path}');
      _remove(paths.downloadDir);
    } else {
      logger.info('Cleaning SDK state in ${paths.currentSdkDir.path}');
      _remove(paths.currentSdkDir);
    }
    logger.info('Done');
    return true;
  }

  static void _remove(Directory dir) {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  }
}
