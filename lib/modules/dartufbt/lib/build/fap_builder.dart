import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import '../core/ufbt_paths.dart';
import '../log/logger.dart';
import 'api_symbols.dart';
import 'app_manifest.dart';
import 'elf_manifest.dart';
import 'fastfap.dart';
import 'file_assets.dart';
import 'icon.dart';
import 'icon_assets.dart';
import 'sdk_opts.dart';
import 'source_glob.dart';

class FapBuildException implements Exception {
  const FapBuildException(this.message);

  final String message;

  @override
  String toString() => message;
}

class FapBuildResult {
  const FapBuildResult({
    required this.success,
    required this.app,
    this.fap,
    this.debugElf,
    this.unresolvedSymbols = const [],
    this.error,
  });

  final bool success;
  final FlipperApplication? app;
  final File? fap;
  final File? debugElf;
  final List<String> unresolvedSymbols;
  final String? error;
}

class FapBuilder {
  FapBuilder({required this.logger, required this.paths});

  final UfbtLogger logger;
  final UfbtPaths paths;

  static const String metaSection = '.fapmeta';
  static const String fileAssetsSection = '.fapassets';

  Directory get _sdkDir => paths.currentSdkDir;

  Map<String, dynamic> get _components {
    final file = File(UfbtPaths.join(_sdkDir.path, 'components.json'));
    if (!file.existsSync()) {
      throw const FapBuildException(
        'SDK is not deployed: components.json not found',
      );
    }
    final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    return Map<String, dynamic>.from(json['components'] as Map);
  }

  Directory _component(String key) =>
      Directory(UfbtPaths.join(_sdkDir.path, _components[key] as String));

  String _tool(String name) {
    final path = UfbtPaths.join(
      paths.toolchainDir.path,
      'current',
      'bin${Platform.pathSeparator}arm-none-eabi-$name',
    );
    final file = File(Platform.isWindows ? '$path.exe' : path);
    if (!file.existsSync()) {
      throw FapBuildException('Toolchain binary not found: ${file.path}');
    }
    return file.path;
  }

  Future<FapBuildResult> build({
    required Directory appDir,
    String? appid,
    Directory? outputDir,
  }) async {
    final apps = FlipperApplication.loadManifest(appDir);
    final app = appid == null
        ? apps.firstWhere(
            (candidate) => candidate.isExternal,
            orElse: () => throw const FapBuildException(
              'No external application found in manifest',
            ),
          )
        : apps.firstWhere(
            (candidate) => candidate.appid == appid,
            orElse: () =>
                throw FapBuildException('Application $appid not found'),
          );

    try {
      return await _buildApp(
        app,
        outputDir ?? Directory('${appDir.path}/dist'),
      );
    } on FapBuildException catch (e) {
      logger.error('$e');
      return FapBuildResult(success: false, app: app, error: '$e');
    }
  }

  Future<FapBuildResult> _buildApp(
    FlipperApplication app,
    Directory outputDir,
  ) async {
    final headersDir = _component('sdk_headers.dir');
    final libDir = _component('lib.dir');

    _currentAppDir = app.appDir.absolute.path;
    final appsWorkDir = Directory(UfbtPaths.join(paths.stateDir.path, 'build'));
    final workDir = Directory(UfbtPaths.join(appsWorkDir.path, app.appid))
      ..createSync(recursive: true);

    final debugElf = File(
      UfbtPaths.join(appsWorkDir.path, '${app.appid}_d.elf'),
    );

    final opts = SdkOpts.load(
      headersDir,
      appEntry: app.entryPoint ?? '',
      mapFile: debugElf.path,
    );
    final symbols = SdkApiSymbols.load(File(opts.sdkSymbols));

    if (!app.supportsHardwareTarget('f${opts.hardware}')) {
      throw FapBuildException(
        '${app.appid} does not support target f${opts.hardware}',
      );
    }

    final includePaths = <String>[];
    final defines = <String>[
      'FAP_VERSION="${app.fapVersion.join('.')}"',
      ...app.cdefines,
    ];

    File? iconsSource;
    if (app.fapIconAssets != null) {
      final bundleName = '${app.fapIconAssetsSymbol ?? app.appid}_icons';
      logger.build('ICONS', UfbtPaths.join(workDir.path, '$bundleName.c'));
      iconsSource = const IconAssetsCompiler()
          .compile(
            inputDir: Directory(
              UfbtPaths.join(app.appDir.path, app.fapIconAssets!),
            ),
            outputDir: workDir,
            bundleName: bundleName,
          )
          .source;
    }

    final privateLibs = <String>[];
    for (final lib in app.fapPrivateLibs) {
      privateLibs.add(
        await _buildPrivateLib(app, lib, opts, workDir, includePaths),
      );
    }
    includePaths.addAll([workDir.path, app.appDir.path]);

    final sources = SourceGlob.gather(app.appDir, [...app.sources, '!lib']);
    if (sources.isEmpty) {
      throw FapBuildException('No source files found for ${app.appid}');
    }
    if (iconsSource != null &&
        !sources.any((source) => source.path == iconsSource!.path)) {
      sources.add(iconsSource);
    }

    final objects = <String>[];
    final task = logger.progress('', total: sources.length);
    var compiled = 0;
    for (final source in sources) {
      objects.add(
        await _compile(
          source: source,
          workDir: workDir,
          opts: opts,
          includePaths: includePaths,
          defines: defines,
          extraFlags: const [],
        ),
      );
      task.update(current: ++compiled);
    }
    task.finish();

    final linker = sources.any((source) => _isCpp(source.path)) ? 'g++' : 'gcc';

    logger.build('LINK', debugElf.path);
    await _run(_tool(linker), [
      '-o',
      debugElf.path,
      ...opts.linkerArgs,
      ...objects,
      '-L${libDir.path}',
      ...opts.linkerLibs.map((lib) => '-l$lib'),
      ...app.fapLibs.map((lib) => '-l$lib'),
      ...privateLibs,
      ...app.fapLibs.map((lib) => '-l$lib'),
    ]);

    final fap = File(
      UfbtPaths.join(workDir.path, '${app.appid}.${app.artifactExtension}'),
    );

    logger.build('APPMETA', UfbtPaths.join(workDir.path, metaSection));
    final metaFile = File(UfbtPaths.join(workDir.path, metaSection));
    metaFile.writeAsBytesSync(
      ElfManifest.assemble(
        app: app,
        hardwareTarget: int.parse(opts.hardware),
        sdkVersion: symbols.versionAsInt,
        icon: app.fapIcon == null
            ? null
            : ElfManifest.iconBytes(
                const IconCodec().fileToImage(
                  File(UfbtPaths.join(app.appDir.path, app.fapIcon!)),
                ),
              ),
      ),
    );

    final objcopyArgs = <String>[
      '--remove-section',
      '.ARM.attributes',
      '--add-section',
      '$metaSection=${metaFile.path}',
      '--set-section-flags',
      '$metaSection=contents,noload,readonly,data',
    ];

    if (app.fapFileAssets != null) {
      final assetsFile = File(UfbtPaths.join(workDir.path, fileAssetsSection));
      logger.build('APPFILE', assetsFile.path);
      FileBundler([
        Directory(UfbtPaths.join(app.appDir.path, app.fapFileAssets!)),
      ]).export(assetsFile);
      objcopyArgs.addAll([
        '--add-section',
        '$fileAssetsSection=${assetsFile.path}',
        '--set-section-flags',
        '$fileAssetsSection=contents,noload,readonly,data',
      ]);
    }

    logger.build('FAP', fap.path);
    await _run(_tool('objcopy'), [
      ...objcopyArgs,
      '--strip-debug',
      '--strip-unneeded',
      '--add-gnu-debuglink=${debugElf.path}',
      debugElf.path,
      fap.path,
    ]);

    await _fastFap(fap, workDir);

    final unresolved = await _validateImports(fap, symbols, app, opts);

    outputDir.createSync(recursive: true);
    final installed = File(
      UfbtPaths.join(outputDir.path, fap.uri.pathSegments.last),
    );
    fap.copySync(installed.path);

    return FapBuildResult(
      success: true,
      app: app,
      fap: installed,
      debugElf: debugElf,
      unresolvedSymbols: unresolved,
    );
  }

  Future<String> _buildPrivateLib(
    FlipperApplication app,
    FlipperLibrary lib,
    SdkOpts opts,
    Directory workDir,
    List<String> includePaths,
  ) async {
    final libRoot = Directory(UfbtPaths.join(app.appDir.path, 'lib', lib.name));
    if (!libRoot.existsSync()) {
      throw FapBuildException('Private library not found: ${libRoot.path}');
    }

    for (final include in lib.fapIncludePaths) {
      final path = include == '.'
          ? libRoot.path
          : UfbtPaths.join(libRoot.path, include);
      if (!includePaths.contains(path)) includePaths.add(path);
    }

    final sources = SourceGlob.gather(libRoot, lib.sources);
    final compilable = sources
        .where((file) => _isCompilable(file.path))
        .toList();
    if (compilable.isEmpty) {
      throw FapBuildException(
        'No sources gathered for private library ${lib.name}',
      );
    }

    final libIncludes = <String>[
      ...includePaths,
      ...lib.cincludes.map((path) => UfbtPaths.join(app.appDir.path, path)),
    ];

    final objects = <String>[];
    for (final source in compilable) {
      objects.add(
        await _compile(
          source: source,
          workDir: workDir,
          opts: opts,
          includePaths: libIncludes,
          defines: lib.cdefines,
          extraFlags: lib.cflags,
        ),
      );
    }

    final archive = File(UfbtPaths.join(workDir.path, lib.name));
    if (archive.existsSync()) archive.deleteSync();
    logger.build('AR', archive.path);
    await _run(_tool('ar'), ['rc', archive.path, ...objects]);
    logger.build('RANLIB', archive.path);
    await _run(_tool('ranlib'), [archive.path]);
    return archive.path;
  }

  String _objectPath(File source, Directory workDir) {
    var relative = source.absolute.path;
    for (final root in [workDir.absolute.path, _currentAppDir!]) {
      if (relative.startsWith(root)) {
        relative = relative.substring(root.length);
        break;
      }
    }
    relative = relative.replaceAll(RegExp(r'^[/\\]+'), '');
    final dot = relative.lastIndexOf('.');
    final withoutExtension = dot < 0 ? relative : relative.substring(0, dot);
    return UfbtPaths.join(workDir.path, '$withoutExtension.o');
  }

  String? _currentAppDir;

  Future<String> _compile({
    required File source,
    required Directory workDir,
    required SdkOpts opts,
    required List<String> includePaths,
    required List<String> defines,
    required List<String> extraFlags,
  }) async {
    final isCpp = _isCpp(source.path);
    final object = File(_objectPath(source, workDir));
    object.parent.createSync(recursive: true);

    logger.build(isCpp ? 'CPP' : 'CC', source.path);
    await _run(_tool(isCpp ? 'g++' : 'gcc'), [
      '-o',
      object.path,
      '-c',
      ...(isCpp ? opts.cppArgs : opts.ccArgs),
      ...extraFlags,
      ...defines.map((define) => '-D$define'),
      ...includePaths.map((path) => '-I$path'),
      source.path,
    ]);
    return object.path;
  }

  Future<void> _fastFap(File fap, Directory workDir) async {
    final sections = const FastFap().buildSections(fap);
    if (sections.isEmpty) return;

    logger.build('FASTFAP', fap.path);
    final tempDir = Directory(UfbtPaths.join(workDir.path, 'fastfap'))
      ..createSync(recursive: true);

    for (final section in sections) {
      final name = md5.convert(utf8.encode(section.name)).toString();
      final file = File(UfbtPaths.join(tempDir.path, '$name.bin'))
        ..writeAsBytesSync(section.data);
      await _run(_tool('objcopy'), [
        '--add-section',
        '${section.name}=${file.path}',
        fap.path,
      ]);
    }
    tempDir.deleteSync(recursive: true);
  }

  Future<List<String>> _validateImports(
    File fap,
    SdkApiSymbols symbols,
    FlipperApplication app,
    SdkOpts opts,
  ) async {
    final result = await Process.run(_tool('nm'), ['-P', '-u', fap.path]);
    if (result.exitCode != 0) {
      throw FapBuildException('nm failed: ${result.stderr}');
    }

    final imported = <String>{};
    for (final line in const LineSplitter().convert(result.stdout as String)) {
      final name = line.split(RegExp(r'\s+')).first;
      if (name.isNotEmpty) imported.add(name);
    }

    final unresolved = imported.difference(symbols.valid).toList()..sort();
    logger.build(
      'APPCHK',
      fap.path,
      details: ['Target: ${opts.hardware}, API: ${symbols.version}'],
    );

    if (unresolved.isNotEmpty) {
      final disabled = unresolved.where(symbols.disabled.contains).toList();
      var message =
          '${fap.path}: app may not be runnable. Symbols not resolved '
          'using firmware\'s API: {${unresolved.join(', ')}}';
      if (disabled.isNotEmpty) {
        message += ' (in API, but disabled: {${disabled.join(', ')}})';
      }
      if (app.doStrictImportChecks) {
        throw FapBuildException(message);
      }
      logger.warning(message);
    }
    return unresolved;
  }

  Directory get _scriptRoot =>
      Directory(UfbtPaths.join(paths.sdkScriptsDir.path, 'ufbt'));

  Future<void> _run(String executable, List<String> arguments) async {
    if (logger.verbose) logger.raw('$executable ${arguments.join(' ')}');
    final workingDirectory = _scriptRoot;
    final result = await Process.run(
      executable,
      arguments,
      workingDirectory: workingDirectory.existsSync()
          ? workingDirectory.path
          : null,
    );
    if (result.exitCode == 0) {
      final stderrText = (result.stderr as String).trim();
      if (stderrText.isNotEmpty) {
        for (final line in const LineSplitter().convert(stderrText)) {
          logger.raw(line);
        }
      }
      return;
    }

    final output = [
      (result.stdout as String).trim(),
      (result.stderr as String).trim(),
    ].where((text) => text.isNotEmpty).join('\n');
    for (final line in const LineSplitter().convert(output)) {
      logger.raw(line);
    }
    throw FapBuildException(
      '${executable.split(Platform.pathSeparator).last} failed with exit code '
      '${result.exitCode}',
    );
  }

  static bool _isCpp(String path) =>
      path.endsWith('.cpp') || path.endsWith('.cc') || path.endsWith('.cxx');

  static bool _isCompilable(String path) =>
      path.endsWith('.c') ||
      _isCpp(path) ||
      path.endsWith('.s') ||
      path.endsWith('.S');
}
