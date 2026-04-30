part of flipper_client_impl;

extension FlipperDesktopApi on FlipperClient {
  Stream<Status> desktopStatusStream() {
    return select(
      (frame) => frame.hasDesktopStatus() ? frame.desktopStatus : null,
    );
  }

  Future<List<Main>> desktopIsLocked({
    Duration timeout = const Duration(seconds: 8),
  }) {
    return callRpcFrames(
      Main(desktopIsLockedRequest: IsLockedRequest()),
      timeout: timeout,
    );
  }

  Future<List<Main>> desktopUnlock(
    UnlockRequest request, {
    Duration timeout = const Duration(seconds: 8),
  }) {
    return callRpcFrames(
      Main(desktopUnlockRequest: request),
      timeout: timeout,
    );
  }

  Future<List<Main>> desktopStatusSubscribe({
    Duration timeout = const Duration(seconds: 8),
  }) {
    return callRpcFrames(
      Main(desktopStatusSubscribeRequest: StatusSubscribeRequest()),
      timeout: timeout,
    );
  }

  Future<List<Main>> desktopStatusUnsubscribe({
    Duration timeout = const Duration(seconds: 8),
  }) {
    return callRpcFrames(
      Main(desktopStatusUnsubscribeRequest: StatusUnsubscribeRequest()),
      timeout: timeout,
    );
  }
}
