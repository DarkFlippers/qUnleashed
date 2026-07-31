enum UfbtFileType {
  sdkZip('sdk_zip'),
  libZip('lib_zip'),
  core2FirmwareTgz('core2_firmware_tgz'),
  resourcesTgz('resources_tgz'),
  scriptsTgz('scripts_tgz'),
  updateTgz('update_tgz'),
  firmwareElf('firmware_elf'),
  fullBin('full_bin'),
  fullDfu('full_dfu'),
  fullJson('full_json'),
  updaterBin('updater_bin'),
  updaterDfu('updater_dfu'),
  updaterElf('updater_elf'),
  updaterJson('updater_json');

  const UfbtFileType(this.id);

  final String id;
}

enum UfbtUpdateChannel {
  dev('development'),
  rc('release-candidate'),
  release('release');

  const UfbtUpdateChannel(this.id);

  final String id;

  String get key => name;

  String get pythonName => name.toUpperCase();

  static UfbtUpdateChannel byKey(String key) {
    return UfbtUpdateChannel.values.firstWhere(
      (channel) => channel.key == key.toLowerCase(),
      orElse: () => throw ArgumentError('Invalid channel: $key'),
    );
  }
}
