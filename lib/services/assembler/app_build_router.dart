import 'build_service.dart';
import 'controller.dart';
import 'remote_build_service.dart';

/// What a build is doing right now, in the terms both backends share: the
/// caller maps them onto its own progress stages.
enum AppBuildStage { queued, download, build }

/// Builds a catalog app from source without the caller knowing where. This
/// computer compiles while its ufbt state is complete and working; the build
/// server takes over when it is not, and on anything that says the local
/// toolchain is unusable. A build the toolchain actually ran and failed stops
/// here, because the server would fail the same way.
class AppBuildRouter {
  const AppBuildRouter._();

  static Future<List<int>> build({
    required String alias,
    required String bundleUrl,
    required String target,
    required Future<List<int>> Function(
      void Function(int received, int? total) onProgress,
    )
    fetchBundle,
    String? api,
    String? uid,
    String? versionUid,
    void Function(AppBuildStage stage, double progress)? onStage,
    bool Function()? isCancelled,
  }) async {
    final controller = AssemblerController.instance;
    // The SDK or the toolchain may have been deleted since the last build.
    controller.refreshStatus();

    if (controller.backend == AssemblerBackend.local) {
      try {
        return await _buildHere(
          alias: alias,
          fetchBundle: fetchBundle,
          onStage: onStage,
        );
      } catch (e) {
        if (!isLocalEnvironmentFailure(e)) rethrow;
        controller.markLocalFault(e);
        controller.logger.info('Handing the build over to the build server');
      }
    }

    return _buildOnServer(
      alias: alias,
      bundleUrl: bundleUrl,
      target: target,
      api: api,
      uid: uid,
      versionUid: versionUid,
      onStage: onStage,
      isCancelled: isCancelled,
    );
  }

  static Future<List<int>> _buildHere({
    required String alias,
    required Future<List<int>> Function(
      void Function(int received, int? total) onProgress,
    )
    fetchBundle,
    void Function(AppBuildStage stage, double progress)? onStage,
  }) async {
    AssemblerBuildService.ensureReady();
    final bundle = await fetchBundle((received, total) {
      if (total == null || total <= 0) return;
      onStage?.call(AppBuildStage.download, received / total);
    });
    onStage?.call(AppBuildStage.build, 0);
    final fap = await AssemblerBuildService.buildFromBundle(
      bundle: bundle,
      alias: alias,
    );
    onStage?.call(AppBuildStage.build, 1);
    return fap;
  }

  static Future<List<int>> _buildOnServer({
    required String alias,
    required String bundleUrl,
    required String target,
    String? api,
    String? uid,
    String? versionUid,
    void Function(AppBuildStage stage, double progress)? onStage,
    bool Function()? isCancelled,
  }) {
    onStage?.call(AppBuildStage.queued, 0);
    return RemoteBuildService.instance.build(
      bundleUrl: bundleUrl,
      alias: alias,
      target: target,
      api: api,
      uid: uid,
      versionUid: versionUid,
      isCancelled: isCancelled,
      onPhase: (phase, progress) => onStage?.call(switch (phase) {
        RemoteBuildPhase.queued => AppBuildStage.queued,
        RemoteBuildPhase.building => AppBuildStage.build,
        RemoteBuildPhase.download => AppBuildStage.download,
      }, progress),
    );
  }
}
