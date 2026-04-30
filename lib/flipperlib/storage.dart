part of flipper_client_impl;

extension FlipperStorageApi on FlipperClient {
  Future<FlipperRpcBatch<ListResponse>> storageList(
    ListRequest request, {
    Duration timeout = const Duration(seconds: 8),
  }) {
    return callRpc(
      Main(storageListRequest: request),
      (frame) => frame.hasStorageListResponse() ? frame.storageListResponse : null,
      timeout: timeout,
    );
  }

  Future<FlipperRpcBatch<ReadResponse>> storageRead(
    ReadRequest request, {
    Duration timeout = const Duration(seconds: 8),
  }) {
    return callRpc(
      Main(storageReadRequest: request),
      (frame) => frame.hasStorageReadResponse() ? frame.storageReadResponse : null,
      timeout: timeout,
    );
  }

  Future<List<Main>> storageWrite(
    WriteRequest request, {
    Duration timeout = const Duration(seconds: 8),
  }) {
    return callRpcFrames(
      Main(storageWriteRequest: request),
      timeout: timeout,
    );
  }

  Future<List<Main>> storageDelete(
    DeleteRequest request, {
    Duration timeout = const Duration(seconds: 8),
  }) {
    return callRpcFrames(
      Main(storageDeleteRequest: request),
      timeout: timeout,
    );
  }

  Future<List<Main>> storageMkdir(
    MkdirRequest request, {
    Duration timeout = const Duration(seconds: 8),
  }) {
    return callRpcFrames(
      Main(storageMkdirRequest: request),
      timeout: timeout,
    );
  }

  Future<FlipperRpcBatch<Md5sumResponse>> storageMd5sum(
    Md5sumRequest request, {
    Duration timeout = const Duration(seconds: 8),
  }) {
    return callRpc(
      Main(storageMd5sumRequest: request),
      (frame) =>
          frame.hasStorageMd5sumResponse() ? frame.storageMd5sumResponse : null,
      timeout: timeout,
    );
  }

  Future<FlipperRpcBatch<StatResponse>> storageStat(
    StatRequest request, {
    Duration timeout = const Duration(seconds: 8),
  }) {
    return callRpc(
      Main(storageStatRequest: request),
      (frame) => frame.hasStorageStatResponse() ? frame.storageStatResponse : null,
      timeout: timeout,
    );
  }

  Future<FlipperRpcBatch<InfoResponse>> storageInfo(
    InfoRequest request, {
    Duration timeout = const Duration(seconds: 8),
  }) {
    return callRpc(
      Main(storageInfoRequest: request),
      (frame) => frame.hasStorageInfoResponse() ? frame.storageInfoResponse : null,
      timeout: timeout,
    );
  }

  Future<List<Main>> storageRename(
    RenameRequest request, {
    Duration timeout = const Duration(seconds: 8),
  }) {
    return callRpcFrames(
      Main(storageRenameRequest: request),
      timeout: timeout,
    );
  }

  Future<List<Main>> storageBackupCreate(
    BackupCreateRequest request, {
    Duration timeout = const Duration(seconds: 8),
  }) {
    return callRpcFrames(
      Main(storageBackupCreateRequest: request),
      timeout: timeout,
    );
  }

  Future<List<Main>> storageBackupRestore(
    BackupRestoreRequest request, {
    Duration timeout = const Duration(seconds: 8),
  }) {
    return callRpcFrames(
      Main(storageBackupRestoreRequest: request),
      timeout: timeout,
    );
  }

  Future<FlipperRpcBatch<TimestampResponse>> storageTimestamp(
    TimestampRequest request, {
    Duration timeout = const Duration(seconds: 8),
  }) {
    return callRpc(
      Main(storageTimestampRequest: request),
      (frame) => frame.hasStorageTimestampResponse()
          ? frame.storageTimestampResponse
          : null,
      timeout: timeout,
    );
  }

  Future<List<Main>> storageTarExtract(
    TarExtractRequest request, {
    Duration timeout = const Duration(seconds: 8),
  }) {
    return callRpcFrames(
      Main(storageTarExtractRequest: request),
      timeout: timeout,
    );
  }
}
