part of flipper_client_impl;

extension FlipperGpioApi on FlipperClient {
  Future<List<Main>> gpioSetPinMode(
    SetPinMode request, {
    Duration timeout = const Duration(seconds: 8),
  }) {
    return callRpcFrames(
      Main(gpioSetPinMode: request),
      timeout: timeout,
    );
  }

  Future<List<Main>> gpioSetInputPull(
    SetInputPull request, {
    Duration timeout = const Duration(seconds: 8),
  }) {
    return callRpcFrames(
      Main(gpioSetInputPull: request),
      timeout: timeout,
    );
  }

  Future<FlipperRpcBatch<GetPinModeResponse>> gpioGetPinMode(
    GetPinMode request, {
    Duration timeout = const Duration(seconds: 8),
  }) {
    return callRpc(
      Main(gpioGetPinMode: request),
      (frame) => frame.hasGpioGetPinModeResponse()
          ? frame.gpioGetPinModeResponse
          : null,
      timeout: timeout,
    );
  }

  Future<FlipperRpcBatch<ReadPinResponse>> gpioReadPin(
    ReadPin request, {
    Duration timeout = const Duration(seconds: 8),
  }) {
    return callRpc(
      Main(gpioReadPin: request),
      (frame) => frame.hasGpioReadPinResponse() ? frame.gpioReadPinResponse : null,
      timeout: timeout,
    );
  }

  Future<List<Main>> gpioWritePin(
    WritePin request, {
    Duration timeout = const Duration(seconds: 8),
  }) {
    return callRpcFrames(
      Main(gpioWritePin: request),
      timeout: timeout,
    );
  }

  Future<FlipperRpcBatch<GetOtgModeResponse>> gpioGetOtgMode({
    Duration timeout = const Duration(seconds: 8),
  }) {
    return callRpc(
      Main(gpioGetOtgMode: GetOtgMode()),
      (frame) => frame.hasGpioGetOtgModeResponse()
          ? frame.gpioGetOtgModeResponse
          : null,
      timeout: timeout,
    );
  }

  Future<List<Main>> gpioSetOtgMode(
    SetOtgMode request, {
    Duration timeout = const Duration(seconds: 8),
  }) {
    return callRpcFrames(
      Main(gpioSetOtgMode: request),
      timeout: timeout,
    );
  }
}
