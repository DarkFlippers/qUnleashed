import 'dart:io';

class UfbtPaths {
  UfbtPaths({required String home, String? toolchainPath})
    : stateDir = Directory(_absolute(home)),
      _toolchainPath = Directory(_absolute(toolchainPath ?? home));

  static const String stateFileName = 'ufbt_state.json';
  static const String toolchainSubdir = 'toolchain';
  static const String envFileName = '.env';

  final Directory stateDir;
  final Directory _toolchainPath;

  static String defaultUfbtHome([Map<String, String>? environment]) {
    final env = environment ?? Platform.environment;
    final home = env['HOME'] ?? env['USERPROFILE'] ?? '';
    return '$home${Platform.pathSeparator}.ufbt';
  }

  static Map<String, String> loadEnvFile([String? directory]) {
    final dir = directory ?? Directory.current.path;
    final file = File('$dir${Platform.pathSeparator}$envFileName');
    if (!file.existsSync()) return const {};
    final vars = <String, String>{};
    for (final raw in file.readAsLinesSync()) {
      final line = raw.trim();
      if (line.isEmpty || line.startsWith('#')) continue;
      final index = line.indexOf('=');
      if (index < 0) continue;
      vars[line.substring(0, index)] = line.substring(index + 1);
    }
    return vars;
  }

  static UfbtPaths resolve({
    String? projectDir,
    Map<String, String>? environment,
  }) {
    final env = <String, String>{
      ...(environment ?? Platform.environment),
      ...loadEnvFile(projectDir),
    };
    final home = env['UFBT_HOME'] ?? defaultUfbtHome(env);
    return UfbtPaths(home: home, toolchainPath: env['FBT_TOOLCHAIN_PATH']);
  }

  static String _absolute(String path) {
    final absolute = Directory(path).absolute.path;
    if (absolute.length <= 1) return absolute;
    return absolute.replaceFirst(RegExp(r'[/\\]$'), '');
  }

  Directory get downloadDir => _sub(stateDir, 'download');

  Directory get currentSdkDir => _sub(stateDir, 'current');

  Directory get toolchainDir => _sub(_toolchainPath, toolchainSubdir);

  File get stateFile => File(join(currentSdkDir.path, stateFileName));

  Directory get sdkScriptsDir => _sub(currentSdkDir, 'scripts');

  File get fbtenvScript =>
      File(join(sdkScriptsDir.path, 'toolchain', 'fbtenv.sh'));

  File get fbtenvCmd =>
      File(join(sdkScriptsDir.path, 'toolchain', 'fbtenv.cmd'));

  Directory toolchainArchDir(String archDir) => _sub(toolchainDir, archDir);

  Link get toolchainCurrentLink => Link(join(toolchainDir.path, 'current'));

  static Directory _sub(Directory parent, String name) =>
      Directory(join(parent.path, name));

  static String join(String a, String b, [String? c]) {
    final sep = Platform.pathSeparator;
    final head = '$a$sep$b';
    return c == null ? head : '$head$sep$c';
  }
}
