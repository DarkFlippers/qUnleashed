part of flipper_client_impl;

extension FlipperSystemApi on FlipperClient {
  Future<FlipperRpcBatch<PingResponse>> ping(
    PingRequest request, {
    Duration timeout = const Duration(seconds: 8),
  }) {
    return callRpc(
      Main(systemPingRequest: request),
      (frame) => frame.hasSystemPingResponse() ? frame.systemPingResponse : null,
      timeout: timeout,
    );
  }

  Future<FlipperRpcBatch<ProtobufVersionResponse>> protobufVersion({
    Duration timeout = const Duration(seconds: 8),
  }) {
    return callRpc(
      Main(systemProtobufVersionRequest: ProtobufVersionRequest()),
      (frame) => frame.hasSystemProtobufVersionResponse()
          ? frame.systemProtobufVersionResponse
          : null,
      timeout: timeout,
    );
  }

  Future<FlipperRpcBatch<DeviceInfoResponse>> deviceInfo({
    Duration timeout = const Duration(seconds: 8),
  }) {
    return callRpc(
      Main(systemDeviceInfoRequest: DeviceInfoRequest()),
      (frame) => frame.hasSystemDeviceInfoResponse()
          ? frame.systemDeviceInfoResponse
          : null,
      timeout: timeout,
    );
  }

  Future<FlipperRpcBatch<PowerInfoResponse>> powerInfo({
    Duration timeout = const Duration(seconds: 8),
  }) {
    return callRpc(
      Main(systemPowerInfoRequest: PowerInfoRequest()),
      (frame) => frame.hasSystemPowerInfoResponse()
          ? frame.systemPowerInfoResponse
          : null,
      timeout: timeout,
    );
  }

  Future<FlipperRpcBatch<GetDateTimeResponse>> getDateTime({
    Duration timeout = const Duration(seconds: 8),
  }) {
    return callRpc(
      Main(systemGetDatetimeRequest: GetDateTimeRequest()),
      (frame) => frame.hasSystemGetDatetimeResponse()
          ? frame.systemGetDatetimeResponse
          : null,
      timeout: timeout,
    );
  }

  Future<List<Main>> setDateTime(
    SetDateTimeRequest request, {
    Duration timeout = const Duration(seconds: 8),
  }) {
    return callRpcFrames(
      Main(systemSetDatetimeRequest: request),
      timeout: timeout,
    );
  }

  Future<List<Main>> reboot(
    RebootRequest request, {
    Duration timeout = const Duration(seconds: 8),
  }) {
    return callRpcFrames(
      Main(systemRebootRequest: request),
      timeout: timeout,
    );
  }

  Future<List<Main>> update(
    UpdateRequest request, {
    Duration timeout = const Duration(seconds: 8),
  }) {
    return callRpcFrames(
      Main(systemUpdateRequest: request),
      timeout: timeout,
    );
  }

  Future<FlipperRpcBatch<UpdateResponse>> updateStatus({
    Duration timeout = const Duration(seconds: 8),
  }) {
    return callRpc(
      Main(systemUpdateRequest: UpdateRequest()),
      (frame) => frame.hasSystemUpdateResponse() ? frame.systemUpdateResponse : null,
      timeout: timeout,
    );
  }

  Future<List<Main>> factoryReset(
    FactoryResetRequest request, {
    Duration timeout = const Duration(seconds: 8),
  }) {
    return callRpcFrames(
      Main(systemFactoryResetRequest: request),
      timeout: timeout,
    );
  }

  Future<List<Main>> playAudiovisualAlert(
    PlayAudiovisualAlertRequest request, {
    Duration timeout = const Duration(seconds: 8),
  }) {
    return callRpcFrames(
      Main(systemPlayAudiovisualAlertRequest: request),
      timeout: timeout,
    );
  }
}
