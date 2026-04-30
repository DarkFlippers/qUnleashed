part of flipper_client_impl;

extension FlipperAppApi on FlipperClient {
  Future<List<Main>> appStart(
    StartRequest request, {
    Duration timeout = const Duration(seconds: 8),
  }) {
    return callRpcFrames(
      Main(appStartRequest: request),
      timeout: timeout,
    );
  }

  Future<FlipperRpcBatch<LockStatusResponse>> appLockStatus({
    Duration timeout = const Duration(seconds: 8),
  }) {
    return callRpc(
      Main(appLockStatusRequest: LockStatusRequest()),
      (frame) => frame.hasAppLockStatusResponse() ? frame.appLockStatusResponse : null,
      timeout: timeout,
    );
  }

  Future<List<Main>> appExit(
    AppExitRequest request, {
    Duration timeout = const Duration(seconds: 8),
  }) {
    return callRpcFrames(
      Main(appExitRequest: request),
      timeout: timeout,
    );
  }

  Future<List<Main>> appLoadFile(
    AppLoadFileRequest request, {
    Duration timeout = const Duration(seconds: 8),
  }) {
    return callRpcFrames(
      Main(appLoadFileRequest: request),
      timeout: timeout,
    );
  }

  Future<List<Main>> appButtonPress(
    AppButtonPressRequest request, {
    Duration timeout = const Duration(seconds: 8),
  }) {
    return callRpcFrames(
      Main(appButtonPressRequest: request),
      timeout: timeout,
    );
  }

  Future<List<Main>> appButtonRelease(
    AppButtonReleaseRequest request, {
    Duration timeout = const Duration(seconds: 8),
  }) {
    return callRpcFrames(
      Main(appButtonReleaseRequest: request),
      timeout: timeout,
    );
  }

  Future<List<Main>> appButtonPressRelease(
    AppButtonPressReleaseRequest request, {
    Duration timeout = const Duration(seconds: 8),
  }) {
    return callRpcFrames(
      Main(appButtonPressReleaseRequest: request),
      timeout: timeout,
    );
  }

  Stream<AppStateResponse> appStateStream() {
    return select(
      (frame) => frame.hasAppStateResponse() ? frame.appStateResponse : null,
    );
  }

  Future<FlipperRpcBatch<GetErrorResponse>> appGetError({
    Duration timeout = const Duration(seconds: 8),
  }) {
    return callRpc(
      Main(appGetErrorRequest: GetErrorRequest()),
      (frame) => frame.hasAppGetErrorResponse() ? frame.appGetErrorResponse : null,
      timeout: timeout,
    );
  }

  Future<List<Main>> appDataExchange(
    DataExchangeRequest request, {
    Duration timeout = const Duration(seconds: 8),
  }) {
    return callRpcFrames(
      Main(appDataExchangeRequest: request),
      timeout: timeout,
    );
  }
}
