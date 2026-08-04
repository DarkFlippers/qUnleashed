import 'dart:async';

import 'package:flipperlib/flipperlib.dart';

const pathNestedLog = '/ext/nfc/.nested.log';

abstract class NestedApi {
  bool get isNonceFileExist;

  Stream<bool> hasNotification();

  Future<void> checkNonceFileExist(FlipperClient client);
}

class NestedApiImpl implements NestedApi {
  bool _isNonceFileExist = false;
  final _hasNotificationController = StreamController<bool>.broadcast();

  @override
  bool get isNonceFileExist => _isNonceFileExist;

  @override
  Stream<bool> hasNotification() => _hasNotificationController.stream;

  @override
  Future<void> checkNonceFileExist(FlipperClient client) async {
    final exists = await _isMd5Success(client);
    _isNonceFileExist = exists;
    _hasNotificationController.add(exists);
  }

  Future<bool> _isMd5Success(FlipperClient client) async {
    try {
      final batch = await client.storageMd5sum(
        Md5sumRequest(path: pathNestedLog),
        timeout: const Duration(seconds: 15),
      );
      final response = batch.firstOrNull;
      return response != null &&
          response.hasMd5sum() &&
          response.md5sum.isNotEmpty;
    } catch (_) {
      return false;
    }
  }
}
