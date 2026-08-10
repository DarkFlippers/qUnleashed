import 'package:flipperlib/flipperlib.dart';

const pathNestedLog = '/ext/nfc/.nested.log';

abstract class NestedApi {
  Future<bool> nonceFileExists(FlipperClient client);
}

class NestedApiImpl implements NestedApi {
  @override
  Future<bool> nonceFileExists(FlipperClient client) async {
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
