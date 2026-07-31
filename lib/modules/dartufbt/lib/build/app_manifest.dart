import 'dart:io';

import 'fam_parser.dart';

class FlipperManifestException implements Exception {
  const FlipperManifestException(this.message);

  final String message;

  @override
  String toString() => message;
}

enum FlipperAppType {
  service('Service'),
  system('System'),
  app('App'),
  debug('Debug'),
  archive('Archive'),
  settings('Settings'),
  startup('StartupHook'),
  external('External'),
  menuExternal('MenuExternal'),
  metapackage('Package'),
  plugin('Plugin');

  const FlipperAppType(this.value);

  final String value;

  static FlipperAppType? byMemberName(String name) => switch (name) {
    'SERVICE' => service,
    'SYSTEM' => system,
    'APP' => app,
    'DEBUG' => debug,
    'ARCHIVE' => archive,
    'SETTINGS' => settings,
    'STARTUP' => startup,
    'EXTERNAL' => external,
    'MENUEXTERNAL' => menuExternal,
    'METAPACKAGE' => metapackage,
    'PLUGIN' => plugin,
    _ => null,
  };
}

class FlipperLibrary {
  const FlipperLibrary({
    required this.name,
    required this.fapIncludePaths,
    required this.sources,
    required this.cflags,
    required this.cdefines,
    required this.cincludes,
  });

  final String name;
  final List<String> fapIncludePaths;
  final List<String> sources;
  final List<String> cflags;
  final List<String> cdefines;
  final List<String> cincludes;

  static FlipperLibrary fromCall(FamCall call) {
    return FlipperLibrary(
      name: _string(call['name']) ?? '',
      fapIncludePaths: _strings(call['fap_include_paths']) ?? const ['.'],
      sources: _strings(call['sources']) ?? const ['*.c*'],
      cflags: _strings(call['cflags']) ?? const [],
      cdefines: _strings(call['cdefines']) ?? const [],
      cincludes: _strings(call['cincludes']) ?? const [],
    );
  }
}

class FlipperApplication {
  FlipperApplication({
    required this.appid,
    required this.apptype,
    required this.name,
    required this.entryPoint,
    required this.stackSize,
    required this.sources,
    required this.fapVersion,
    required this.fapIcon,
    required this.fapLibs,
    required this.fapCategory,
    required this.cdefines,
    required this.fapIconAssets,
    required this.fapIconAssetsSymbol,
    required this.fapPrivateLibs,
    required this.fapFileAssets,
    required this.targets,
    required this.requires,
    required this.appDir,
  });

  static final RegExp appIdRegex = RegExp(r'^[a-z0-9_]+$');
  static const String manifestName = 'application.fam';

  final String appid;
  final FlipperAppType apptype;
  final String name;
  final String? entryPoint;
  final int stackSize;
  final List<String> sources;
  final List<int> fapVersion;
  final String? fapIcon;
  final List<String> fapLibs;
  final String fapCategory;
  final List<String> cdefines;
  final String? fapIconAssets;
  final String? fapIconAssetsSymbol;
  final List<FlipperLibrary> fapPrivateLibs;
  final String? fapFileAssets;
  final List<String> targets;
  final List<String> requires;
  final Directory appDir;

  bool get isExternal =>
      apptype == FlipperAppType.external ||
      apptype == FlipperAppType.menuExternal ||
      apptype == FlipperAppType.plugin;

  bool get doStrictImportChecks => apptype != FlipperAppType.plugin;

  String get artifactExtension =>
      apptype == FlipperAppType.plugin ? 'fal' : 'fap';

  bool supportsHardwareTarget(String target) =>
      targets.contains(target) || targets.contains('all');

  int get versionAsInt =>
      ((fapVersion[0] & 0xFFFF) << 16) | (fapVersion[1] & 0xFFFF);

  static List<FlipperApplication> loadManifest(Directory appDir) {
    final file = File('${appDir.path}${Platform.pathSeparator}$manifestName');
    if (!file.existsSync()) {
      throw FlipperManifestException('App manifest not found at ${file.path}');
    }

    final calls = FamParser.parseCalls(file.readAsStringSync(), const {'App'});
    if (calls.isEmpty) {
      throw FlipperManifestException('No App() found in ${file.path}');
    }
    return calls.map((call) => fromCall(call, appDir)).toList();
  }

  static FlipperApplication fromCall(FamCall call, Directory appDir) {
    final appid = _string(call['appid']);
    if (appid == null || !appIdRegex.hasMatch(appid)) {
      throw FlipperManifestException(
        "Invalid appid '$appid'. Must match regex '${appIdRegex.pattern}'",
      );
    }

    final typeValue = call['apptype'];
    final apptype = typeValue is FamName
        ? FlipperAppType.byMemberName(typeValue.tail)
        : null;
    if (apptype == null) {
      throw FlipperManifestException('Unknown apptype for $appid');
    }

    final libs = <FlipperLibrary>[];
    final rawLibs = call['fap_private_libs'];
    if (rawLibs is List) {
      for (final lib in rawLibs) {
        if (lib is FamCall) libs.add(FlipperLibrary.fromCall(lib));
      }
    }

    return FlipperApplication(
      appid: appid,
      apptype: apptype,
      name: _string(call['name']) ?? '',
      entryPoint: _string(call['entry_point']),
      stackSize: apptype == FlipperAppType.plugin
          ? 0
          : _int(call['stack_size']) ?? 2048,
      sources: _strings(call['sources']) ?? const ['*.c*'],
      fapVersion: _version(call['fap_version'], appid),
      fapIcon: _string(call['fap_icon']),
      fapLibs: _strings(call['fap_libs']) ?? const [],
      fapCategory: _string(call['fap_category']) ?? '',
      cdefines: _strings(call['cdefines']) ?? const [],
      fapIconAssets: _string(call['fap_icon_assets']),
      fapIconAssetsSymbol: _string(call['fap_icon_assets_symbol']),
      fapPrivateLibs: libs,
      fapFileAssets: _string(call['fap_file_assets']),
      targets: _strings(call['targets']) ?? const ['all'],
      requires: _strings(call['requires']) ?? const [],
      appDir: appDir,
    );
  }

  static List<int> _version(Object? raw, String appid) {
    if (raw is List) {
      final parts = raw.whereType<int>().toList();
      if (parts.length >= 2) return parts;
    }
    final text = _string(raw) ?? '0.1';
    final parts = <int>[];
    for (final part in text.split('.')) {
      final value = int.tryParse(part.trim());
      if (value == null) {
        throw FlipperManifestException(
          "Invalid version '$text'. Must be in the form 'major.minor'",
        );
      }
      parts.add(value);
    }
    if (parts.length < 2) {
      throw FlipperManifestException(
        "Invalid version '$text'. Not enough version components",
      );
    }
    return parts;
  }
}

String? _string(Object? value) => value is String ? value : null;

int? _int(Object? value) => value is int ? value : null;

List<String>? _strings(Object? value) {
  if (value is String) return [value];
  if (value is! List) return null;
  return value.whereType<String>().toList();
}
