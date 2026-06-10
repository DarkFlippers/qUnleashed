import 'dart:async';

import 'package:flipperlib/flipperlib.dart';

const pathNonceLog = '/ext/nfc/.mfkey32.log';

abstract class MfKey32Api {
  bool get isBruteforceFileExist;

  Stream<bool> hasNotification();

  Future<void> checkBruteforceFileExist(FlipperClient client);
}

class MfKey32ApiImpl implements MfKey32Api {
  bool _isBruteforceFileExist = false;
  final _hasNotificationController = StreamController<bool>.broadcast();

  @override
  bool get isBruteforceFileExist => _isBruteforceFileExist;

  @override
  Stream<bool> hasNotification() => _hasNotificationController.stream;

  @override
  Future<void> checkBruteforceFileExist(FlipperClient client) async {
    final isMd5Exists = await _isMd5Success(client);
    _isBruteforceFileExist = isMd5Exists;
    _hasNotificationController.add(isMd5Exists);
  }

  Future<bool> _isMd5Success(FlipperClient client) async {
    try {
      final batch = await client.storageMd5sum(
        Md5sumRequest(path: pathNonceLog),
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
