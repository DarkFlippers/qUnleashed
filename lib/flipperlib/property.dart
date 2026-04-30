part of flipper_client_impl;

extension FlipperPropertyApi on FlipperClient {
  Future<FlipperRpcBatch<GetResponse>> propertyGet(
    GetRequest request, {
    Duration timeout = const Duration(seconds: 8),
  }) {
    return callRpc(
      Main(propertyGetRequest: request),
      (frame) => frame.hasPropertyGetResponse() ? frame.propertyGetResponse : null,
      timeout: timeout,
    );
  }
}
