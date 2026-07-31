import 'file_type.dart';
import 'sdk_loader.dart';

class SdkDeployTask {
  SdkDeployTask({
    this.hwTarget,
    this.force = false,
    this.mode,
    Map<String, String>? params,
  }) : params = params ?? <String, String>{};

  static const String defaultHwTarget = 'f7';

  String? hwTarget;
  bool force;
  String? mode;
  final Map<String, String> params;

  static SdkDeployTask defaults() {
    return SdkDeployTask(
      hwTarget: defaultHwTarget,
      mode: UpdateChannelSdkLoader.loaderModeKey,
      params: {'channel': UfbtUpdateChannel.release.key},
    );
  }

  static SdkDeployTask channel({
    UfbtUpdateChannel channel = UfbtUpdateChannel.release,
    String hwTarget = defaultHwTarget,
    String? indexUrl,
    bool force = false,
  }) {
    return SdkDeployTask(
      hwTarget: hwTarget,
      mode: UpdateChannelSdkLoader.loaderModeKey,
      force: force,
      params: {'channel': channel.key, 'json_index': ?indexUrl},
    );
  }

  static SdkDeployTask branch({
    required String branch,
    String hwTarget = defaultHwTarget,
    String? indexUrl,
    bool force = false,
  }) {
    return SdkDeployTask(
      hwTarget: hwTarget,
      mode: BranchSdkLoader.loaderModeKey,
      force: force,
      params: {'branch': branch, 'branch_root': ?indexUrl},
    );
  }

  static SdkDeployTask url({
    required String url,
    required String hwTarget,
    bool force = false,
  }) {
    return SdkDeployTask(
      hwTarget: hwTarget,
      mode: UrlSdkLoader.loaderModeKey,
      force: force,
      params: {'url': url},
    );
  }

  static SdkDeployTask local({
    required String filePath,
    required String hwTarget,
    bool force = false,
  }) {
    return SdkDeployTask(
      hwTarget: hwTarget,
      mode: LocalSdkLoader.loaderModeKey,
      force: force,
      params: {'file_path': filePath},
    );
  }

  static SdkDeployTask fromState(Map<String, dynamic> state) {
    final params = <String, String>{};
    state.forEach((key, value) {
      if (value is String) params[key] = value;
    });
    return SdkDeployTask(
      hwTarget: state['hw_target'] as String?,
      mode: state['mode'] as String?,
      params: params,
    );
  }

  void updateFrom(SdkDeployTask other) {
    if (other.hwTarget != null) hwTarget = other.hwTarget;
    if (other.mode != null) mode = other.mode;
    force = other.force;
    other.params.forEach((key, value) {
      if (value.isNotEmpty) params[key] = value;
    });
  }

  @override
  String toString() =>
      'SdkDeployTask(hw_target: $hwTarget, mode: $mode, force: $force, '
      'params: $params)';
}
