part of flipper_client_impl;

extension FlipperGuiApi on FlipperClient {
  Stream<ScreenFrame> screenFrameStream() {
    return select(
      (frame) => frame.hasGuiScreenFrame() ? frame.guiScreenFrame : null,
    );
  }

  Future<List<Main>> startScreenFrameStream({
    Duration timeout = const Duration(seconds: 8),
  }) {
    return callRpcFrames(
      Main(guiStartScreenStreamRequest: StartScreenStreamRequest()),
      timeout: timeout,
    );
  }

  Future<List<Main>> stopScreenFrameStream({
    Duration timeout = const Duration(seconds: 8),
  }) {
    return callRpcFrames(
      Main(guiStopScreenStreamRequest: StopScreenStreamRequest()),
      timeout: timeout,
    );
  }

  StreamSubscription<ScreenFrame> subscribeScreenFrameStream(
    void Function(ScreenFrame frame) onFrame,
  ) {
    return screenFrameStream().listen(onFrame);
  }

  Future<List<Main>> guiStartScreenStream({
    Duration timeout = const Duration(seconds: 8),
  }) {
    return startScreenFrameStream(timeout: timeout);
  }

  Future<List<Main>> guiStopScreenStream({
    Duration timeout = const Duration(seconds: 8),
  }) {
    return stopScreenFrameStream(timeout: timeout);
  }

  Future<List<Main>> guiStartVirtualDisplay(
    StartVirtualDisplayRequest request, {
    Duration timeout = const Duration(seconds: 8),
  }) {
    return callRpcFrames(
      Main(guiStartVirtualDisplayRequest: request),
      timeout: timeout,
    );
  }

  Future<List<Main>> guiStopVirtualDisplay({
    Duration timeout = const Duration(seconds: 8),
  }) {
    return callRpcFrames(
      Main(guiStopVirtualDisplayRequest: StopVirtualDisplayRequest()),
      timeout: timeout,
    );
  }

  Future<List<Main>> guiSendInput(
    SendInputEventRequest request, {
    Duration timeout = const Duration(seconds: 8),
  }) {
    return callRpcFrames(
      Main(guiSendInputEventRequest: request),
      timeout: timeout,
    );
  }
}
