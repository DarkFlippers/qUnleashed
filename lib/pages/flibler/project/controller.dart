import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dartufbt/dartufbt.dart';
import 'package:flipperlib/flipperlib.dart' hide File;
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../components/codec/fap.dart';
import '../../../services/progress_throttle.dart';
import '../../../services/assembler/build_service.dart';
import '../../../services/assembler/controller.dart';
import 'git_source.dart';

enum FliblerSourceKind { folder, repository }

const String kFliblerAppsRoot = '/ext/apps';
const String kFliblerFallbackCategory = 'Tools';
const String kFliblerRecentPrefsKey = 'flibler_recent_sources';
const int kFliblerRecentLimit = 5;

class FliblerRecentSource {
  const FliblerRecentSource({
    required this.kind,
    required this.value,
    this.name = '',
  });

  final FliblerSourceKind kind;
  final String value;
  final String name;

  static FliblerRecentSource? decode(String raw) {
    try {
      final map = jsonDecode(raw);
      if (map is! Map<String, dynamic>) return null;
      final value = map['value'];
      if (value is! String || value.isEmpty) return null;
      return FliblerRecentSource(
        kind: map['kind'] == 'folder'
            ? FliblerSourceKind.folder
            : FliblerSourceKind.repository,
        value: value,
        name: map['name'] is String ? map['name'] as String : '',
      );
    } catch (_) {
      return null;
    }
  }

  String encode() => jsonEncode({
    'kind': kind == FliblerSourceKind.folder ? 'folder' : 'repository',
    'value': value,
    'name': name,
  });
}

class FliblerProjectController extends ChangeNotifier {
  FliblerProjectController({FlipperClient? client})
    : _client = client ?? FlipperOneClient().get();

  final FlipperClient _client;
  final AssemblerController _assembler = AssemblerController.instance;

  FliblerSourceKind _kind = FliblerSourceKind.folder;
  String _folderPath = '';
  String _repoUrl = '';
  Directory? _appDir;
  FlipperApplication? _app;
  FlipperImage? _icon;
  List<FapBuildResult> _built = const [];
  FapInfo? _builtInfo;
  List<FliblerRecentSource> _recent = const [];
  String? _error;
  String? _installedPath;
  bool _loading = false;
  bool _uploading = false;
  double _uploadProgress = 0;

  FliblerSourceKind get kind => _kind;
  String get folderPath => _folderPath;
  String get repoUrl => _repoUrl;
  FlipperApplication? get app => _app;
  FlipperImage? get icon => _icon;
  List<FapBuildResult> get built => _built;
  FapInfo? get builtInfo => _builtInfo;
  List<FliblerRecentSource> get recent => _recent;

  FapBuildResult? get result => _built.isEmpty
      ? null
      : _built.firstWhere(
          (result) => result.app?.isExternal ?? false,
          orElse: () => _built.first,
        );
  String? get error => _error;
  String? get installedPath => _installedPath;
  bool get loading => _loading;
  bool get uploading => _uploading;
  double get uploadProgress => _uploadProgress;
  AssemblerController get assembler => _assembler;

  bool get busy => _assembler.busy || _uploading || _loading;

  bool get canLoad =>
      !busy &&
      (_kind == FliblerSourceKind.folder
          ? _folderPath.isNotEmpty
          : _repoUrl.trim().isNotEmpty);

  bool get deviceReady =>
      _client.isConnected && _client.mode == FlipperMode.rpc;

  bool get canBuild => !busy && _appDir != null;

  File? get fap => result?.fap;

  /// Artifacts that belong on the SD card: an embedded plugin has no path of
  /// its own, it already sits inside the assets of its app.
  List<FapBuildResult> get deployable => _built
      .where((result) => result.distPath != null && result.fap != null)
      .toList();

  String get targetPath {
    final main = result;
    if (main?.distPath != null) return '/ext/${main!.distPath}';
    final app = _app;
    if (app == null) return '';
    final category = app.fapCategory.isEmpty
        ? kFliblerFallbackCategory
        : app.fapCategory;
    return '$kFliblerAppsRoot/$category/${app.appid}.fap';
  }

  void setKind(FliblerSourceKind value) {
    if (_kind == value) return;
    _kind = value;
    _forget();
    notifyListeners();
  }

  void setFolder(String path) {
    _folderPath = path;
    _kind = FliblerSourceKind.folder;
    _forget();
    notifyListeners();
  }

  void setRepo(String url) {
    if (_repoUrl == url) return;
    _repoUrl = url;
    _kind = url.trim().isEmpty && _folderPath.isNotEmpty
        ? FliblerSourceKind.folder
        : FliblerSourceKind.repository;
    _forget();
    notifyListeners();
  }

  void _forget() {
    _appDir = null;
    _app = null;
    _icon = null;
    _built = const [];
    _builtInfo = null;
    _installedPath = null;
    _error = null;
  }

  Future<void> loadRecent() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(kFliblerRecentPrefsKey) ?? const [];
    _recent = [for (final entry in raw) ?FliblerRecentSource.decode(entry)];
    notifyListeners();
  }

  Future<void> removeRecent(FliblerRecentSource entry) async {
    _recent = _recent.where((e) => e.value != entry.value).toList();
    notifyListeners();
    await _saveRecent();
  }

  Future<void> _saveRecent() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(kFliblerRecentPrefsKey, [
      for (final entry in _recent) entry.encode(),
    ]);
  }

  Future<void> _rememberSource() async {
    final app = _app;
    if (app == null) return;
    final entry = FliblerRecentSource(
      kind: _kind,
      value: _kind == FliblerSourceKind.folder ? _folderPath : _repoUrl.trim(),
      name: app.name.isEmpty ? app.appid : app.name,
    );
    if (entry.value.isEmpty) return;
    _recent = [
      entry,
      ..._recent.where((e) => e.value != entry.value),
    ].take(kFliblerRecentLimit).toList();
    notifyListeners();
    await _saveRecent();
  }

  /// Resolves the source, so the app it holds can be shown before a build:
  /// a local folder is read as is, a repository is cloned first.
  Future<bool> loadProject() async {
    if (!canLoad) return false;
    _loading = true;
    _forget();
    notifyListeners();

    try {
      final root = await _resolveSource();
      final appDir = AssemblerBuildService.findAppDir(root);
      if (appDir == null) {
        throw GitSourceException('No application.fam found in ${root.path}');
      }
      _appDir = appDir;
      final apps = FlipperApplication.loadManifest(appDir);
      _app = apps.firstWhere(
        (candidate) => candidate.isExternal,
        orElse: () => apps.first,
      );
      _icon = _loadIcon(_app!);
      _assembler.logger.info(
        'Loaded ${_app!.name.isEmpty ? _app!.appid : _app!.name}'
        '${_app!.fapAuthor.isEmpty ? '' : ' by ${_app!.fapAuthor}'}',
      );
      unawaited(_rememberSource());
      return true;
    } catch (e) {
      _error = '$e';
      _assembler.logger.error('$e');
      return false;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  FlipperImage? _loadIcon(FlipperApplication app) {
    final name = app.fapIcon;
    if (name == null || name.isEmpty) return null;
    try {
      final file = File(UfbtPaths.join(app.appDir.path, name));
      if (!file.existsSync()) return null;
      return const IconCodec().fileToImage(file);
    } catch (e) {
      _assembler.logger.warning('Could not read the app icon: $e');
      return null;
    }
  }

  /// Builds the loaded project and puts it on the device right away.
  Future<bool> build() async {
    final appDir = _appDir;
    if (!canBuild || appDir == null) return false;
    _error = null;
    _built = const [];
    _installedPath = null;
    notifyListeners();

    try {
      _built = await AssemblerBuildService.buildProject(root: appDir);
      _builtInfo = _parseBuilt();
      notifyListeners();
    } catch (e) {
      _error = '$e';
      _assembler.logger.error('$e');
      notifyListeners();
      return false;
    }
    return sendToDevice();
  }

  Future<Directory> _resolveSource() async {
    if (_kind == FliblerSourceKind.folder) {
      final dir = Directory(_folderPath);
      if (!dir.existsSync()) {
        throw GitSourceException('Folder not found: $_folderPath');
      }
      return dir;
    }

    final target = GitSource.parse(_repoUrl);
    _assembler.logger.info(
      'Fetching ${target.remote}'
      '${target.ref == null ? '' : ' @ ${target.ref}'}'
      '${target.subdir.isEmpty ? '' : ' (${target.subdir})'}',
    );
    return GitSource.checkout(
      target: target,
      parent: Directory(
        UfbtPaths.join(_assembler.installer.paths.stateDir.path, 'projects'),
      ),
      logger: _assembler.logger,
    );
  }

  FapInfo? _parseBuilt() {
    final file = result?.fap;
    if (file == null) return null;
    try {
      return FapInfo.parse(file.readAsBytesSync());
    } catch (e) {
      _assembler.logger.warning('Could not parse the built fap: $e');
      return null;
    }
  }

  Future<void> launchOnDevice() async {
    final path = targetPath;
    if (path.isEmpty) throw StateError('Nothing built yet');
    if (!deviceReady) throw StateError('Connect the device first');
    await _client.appStart(
      StartRequest(name: path, args: ''),
      timeout: const Duration(seconds: 15),
    );
  }

  Future<bool> sendToDevice() async {
    final artifacts = deployable;
    if (artifacts.isEmpty || _uploading) return false;
    if (!deviceReady) {
      _error = 'Connect the device first';
      notifyListeners();
      return false;
    }

    _uploading = true;
    _uploadProgress = 0;
    _error = null;
    _installedPath = null;
    notifyListeners();

    try {
      for (final artifact in artifacts) {
        await _sendArtifact('/ext/${artifact.distPath}', artifact.fap!);
      }
      _installedPath = targetPath;
      return true;
    } catch (e) {
      _error = '$e';
      _assembler.logger.error('Failed to send: $e');
      return false;
    } finally {
      _uploading = false;
      _uploadProgress = 0;
      notifyListeners();
    }
  }

  Future<void> _sendArtifact(String path, File file) async {
    final throttle = ProgressThrottle();
    final bytes = file.readAsBytesSync();
    final task = _assembler.logger.progress(
      'Sending ${path.split('/').last}:',
      total: bytes.length,
    );
    try {
      await _mkdirs(path.substring(0, path.lastIndexOf('/')));
      _assembler.logger.build('SEND', path);
      await _client.storageWriteChunked(
        path,
        bytes,
        onProgress: (p) {
          _uploadProgress = p;
          task.update(current: (bytes.length * p).round());
          if (throttle.shouldEmit(p)) notifyListeners();
        },
      );
      task.finish();
      _assembler.logger.info('Sent ${bytes.length} bytes to $path');
    } catch (e) {
      task.fail();
      rethrow;
    }
  }

  Future<void> _mkdirs(String path) async {
    final parts = path.split('/').where((part) => part.isNotEmpty).toList();
    var current = '';
    for (final part in parts) {
      current = '$current/$part';
      try {
        await _client.storageMkdir(MkdirRequest(path: current));
      } catch (_) {}
    }
  }
}
