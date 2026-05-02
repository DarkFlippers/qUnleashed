import 'firmware_directory.dart';

class UnleashedParser extends FirmwareParser {
  UnleashedParser._();

  static final UnleashedParser instance = UnleashedParser._();

  @override
  String get directoryUrl => 'https://up.unleashedflip.com/directory.json';

  FirmwareFile? getUpdatePackage(FirmwareChannel channel, {String target = 'f7'}) =>
      getLatestVersion(channel)?.updatePackageFor(target);

  List<FirmwareDirectoryChannel> getAvailableChannels() =>
      (cached?.channels ?? []).where((c) => c.versions.isNotEmpty).toList();
}
