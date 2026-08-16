import 'dart:io';

import 'package:dartufbt/dartufbt.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'backend_mode.dart';
import 'remote_build_service.dart';

export 'backend_mode.dart';

const String kOfficialIndexUrl =
    'https://update.flipperzero.one/firmware/directory.json';
const String kUnleashedIndexUrl = 'https://up.unleashedflip.com/directory.json';

enum AssemblerSdkSource {
  unleashed(kUnleashedIndexUrl),
  official(kOfficialIndexUrl),
  custom(null);

  const AssemblerSdkSource(this.url);

  final String? url;
}

final StringBuffer _terminalLine = StringBuffer();

/// Mirrors the ufbt log into the Dart console the way a terminal shows it:
/// whole lines only, and of a redrawn progress bar just its last frame.
void _mirrorToTerminal(String text) {
  final parts = text.split('\n');
  for (var i = 0; i < parts.length - 1; i++) {
    _terminalLine.write(parts[i]);
    final line = _terminalLine.toString();
    _terminalLine.clear();
    final redraw = line.lastIndexOf('\r');
    debugPrint(redraw < 0 ? line : line.substring(redraw + 1));
  }
  _terminalLine.write(parts.last);
}

enum AssemblerLineKind { message, build, raw }

class AssemblerLine {
  AssemblerLine(this.text, this.kind, [this.level]);

  String text;
  final AssemblerLineKind kind;
  final UfbtLogLevel? level;
}

enum AssemblerJob { none, sdk, toolchain, build }

class AssemblerController extends ChangeNotifier {
  AssemblerController._() {
    _logger.addSink(_onEvent);
    _logger.addSink(UfbtConsoleSink(output: _mirrorToTerminal).call);
  }

  static final AssemblerController instance = AssemblerController._();

  static const int maxLines = 3000;

  static bool get isSupported =>
      Platform.isMacOS || Platform.isLinux || Platform.isWindows;

  final UfbtLogger _logger = UfbtLogger();
  final List<AssemblerLine> lines = [];

  UfbtInstaller? _installer;
  UfbtStatus? _status;
  UfbtProgress? _progress;
  AssemblerJob _job = AssemblerJob.none;
  UfbtUpdateChannel _channel = UfbtUpdateChannel.release;
  AssemblerSdkSource _sdkSource = AssemblerSdkSource.unleashed;
  String _customIndexUrl = '';
  AssemblerBackendPreference _preference = AssemblerBackendPreference.auto;
  bool _localFaulted = false;
  bool _pendingNewline = false;

  static const String _prefSdkSource = 'assembler_sdk_source';
  static const String _prefCustomIndexUrl = 'assembler_custom_index_url';
  static const String _prefBackend = 'assembler_backend';

  UfbtLogger get logger => _logger;
  UfbtStatus? get status => _status;
  UfbtProgress? get progress => _progress;
  AssemblerJob get job => _job;
  bool get busy => _job != AssemblerJob.none;
  UfbtUpdateChannel get channel => _channel;
  AssemblerSdkSource get sdkSource => _sdkSource;
  String get customIndexUrl => _customIndexUrl;
  bool get verbose => _logger.verbose;

  AssemblerBackendPreference get preference => _preference;

  /// Whether this computer can compile right now: the platform runs ufbt and
  /// its SDK and toolchain are both deployed. Read from [refreshStatus], so a
  /// state folder deleted behind the app's back shows up on the next check.
  bool get localReady => isSupported && (_status?.isReady ?? false);

  /// Where source builds run, resolved from the facts on every read: this
  /// computer while its toolchain works, the build server otherwise.
  AssemblerBackendChoice get backendChoice => resolveAssemblerBackend(
    platformSupported: isSupported,
    localReady: localReady,
    localFaulted: _localFaulted,
    preference: _preference,
  );

  AssemblerBackend get backend => backendChoice.backend;
  bool get usesServerBuild => backend == AssemblerBackend.server;

  String? get indexUrl => _sdkSource == AssemblerSdkSource.custom
      ? (_customIndexUrl.isEmpty ? null : _customIndexUrl)
      : _sdkSource.url;

  UfbtInstaller get installer =>
      _installer ??= UfbtInstaller(logger: _logger, paths: UfbtPaths.resolve());

  void setChannel(UfbtUpdateChannel value) {
    if (_channel == value || busy) return;
    _channel = value;
    notifyListeners();
  }

  Future<void> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final source = prefs.getString(_prefSdkSource);
    _sdkSource = AssemblerSdkSource.values.firstWhere(
      (value) => value.name == source,
      orElse: () => AssemblerSdkSource.unleashed,
    );
    _customIndexUrl = prefs.getString(_prefCustomIndexUrl) ?? '';
    _preference = AssemblerBackendPreference.parse(
      prefs.getString(_prefBackend),
    );
    refreshStatus();
    notifyListeners();
  }

  Future<void> setPreference(AssemblerBackendPreference value) async {
    if (_preference == value || busy) return;
    _preference = value;
    if (value == AssemblerBackendPreference.auto) {
      _localFaulted = false;
      refreshStatus();
    }
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefBackend, value.name);
  }

  /// Called when a local build could not run at all — a missing toolchain
  /// binary, an unreadable state folder, a process that would not start. The
  /// server takes over until the SDK or the toolchain is deployed again.
  void markLocalFault(Object error) {
    _logger.warning('Local builds are unavailable: $error');
    if (_localFaulted) return;
    _localFaulted = true;
    notifyListeners();
  }

  bool get localFaulted => _localFaulted;

  Future<void> setSdkSource(AssemblerSdkSource value) async {
    if (_sdkSource == value || busy) return;
    _sdkSource = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefSdkSource, value.name);
  }

  Future<void> setCustomIndexUrl(String value) async {
    final url = value.trim();
    if (_customIndexUrl == url) return;
    _customIndexUrl = url;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefCustomIndexUrl, url);
  }

  static const Duration _probeTtl = Duration(minutes: 5);
  static const Duration _probeTimeout = Duration(seconds: 10);

  bool? _serverReachable;
  final Stopwatch _sinceProbe = Stopwatch();
  Future<bool>? _probe;

  /// Whether source builds can run at all: locally when this computer is ready
  /// to compile, otherwise a live answer from the build server that would take
  /// over. The catalog asks on every mode resolution, so the server answer is
  /// cached for [_probeTtl].
  Future<bool> builderAvailable({bool force = false}) {
    refreshStatus();
    if (backend == AssemblerBackend.local) return Future.value(true);
    if (!RemoteBuildService.instance.canBuild) return Future.value(false);
    final cached = _serverReachable;
    if (!force && cached != null && _sinceProbe.elapsed < _probeTtl) {
      return Future.value(cached);
    }
    return _probe ??= _probeServer();
  }

  Future<bool> _probeServer() async {
    var reachable = false;
    try {
      await RemoteBuildService.instance.serverStatus().timeout(_probeTimeout);
      reachable = true;
    } catch (e) {
      debugPrint('[Assembler] build server unreachable: $e');
    }
    _serverReachable = reachable;
    _sinceProbe
      ..reset()
      ..start();
    _probe = null;
    return reachable;
  }

  void setVerbose(bool value) {
    _logger.verbose = value;
    notifyListeners();
  }

  void clearLog() {
    lines.clear();
    _pendingNewline = false;
    notifyListeners();
  }

  String logAsText() => lines.map((line) => line.text).join('\n');

  void refreshStatus() {
    if (!isSupported) return;
    _status = installer.status();
    notifyListeners();
  }

  SdkDeployTask taskForChannel({bool force = false}) => SdkDeployTask.channel(
    channel: _channel,
    indexUrl: indexUrl,
    force: force,
  );

  Future<bool> downloadSdk({bool force = false}) {
    return _run(
      AssemblerJob.sdk,
      () => installer.installSdk(taskForChannel(force: force)),
    );
  }

  Future<bool> downloadToolchain({bool force = false}) {
    return _run(AssemblerJob.toolchain, () async {
      final before = installer.toolchainDeployer.status();
      _logger.info(
        'Checking toolchain: '
        '${before.isDeployed ? 'installed v${before.installedVersion}' : 'not installed'}, '
        'SDK needs v${before.version}',
      );
      final ok = await installer.installToolchain(force: force);
      final after = installer.toolchainDeployer.status();
      if (!ok) {
        _logger.error('Toolchain deploy failed');
      } else if (before.isUpToDate && !force) {
        _logger.info('Toolchain v${after.installedVersion} is up to date');
      } else {
        _logger.info('Toolchain deployed: v${after.installedVersion}');
      }
      return ok;
    });
  }

  String? _buildAlias;

  String? get buildAlias => _buildAlias;

  Future<T> runBuild<T>(String alias, Future<T> Function() action) async {
    if (busy) {
      throw StateError('Assembler is busy: ${_job.name}');
    }
    _job = AssemblerJob.build;
    _buildAlias = alias;
    _progress = null;
    notifyListeners();
    try {
      return await action();
    } finally {
      _job = AssemblerJob.none;
      _buildAlias = null;
      _progress = null;
      notifyListeners();
    }
  }

  Future<bool> _run(AssemblerJob job, Future<bool> Function() action) async {
    if (busy || !isSupported) return false;
    _job = job;
    _progress = null;
    notifyListeners();
    var ok = false;
    try {
      ok = await action();
    } catch (e) {
      _logger.error('Failed to run operation: $e');
    } finally {
      _job = AssemblerJob.none;
      _progress = null;
      _status = installer.status();
      // A fresh SDK or toolchain is the answer to whatever broke the local
      // builds, so they get another chance right away.
      if (ok) _localFaulted = false;
      notifyListeners();
    }
    return ok;
  }

  void _onEvent(UfbtLogEvent event) {
    switch (event) {
      case UfbtMessageEvent():
        _append(
          AssemblerLine(
            event.formatted,
            AssemblerLineKind.message,
            event.level,
          ),
        );
      case UfbtBuildEvent():
        for (final line in event.formatted.split('\n')) {
          _append(AssemblerLine(line, AssemblerLineKind.build));
        }
      case UfbtRawEvent():
        _appendRaw(event.text, event.newline);
      case UfbtProgressEvent():
        _progress = event.progress.isDone ? null : event.progress;
    }
    notifyListeners();
  }

  void _append(AssemblerLine line) {
    _pendingNewline = false;
    lines.add(line);
    if (lines.length > maxLines) lines.removeRange(0, lines.length - maxLines);
  }

  void _appendRaw(String text, bool newline) {
    if (_pendingNewline && lines.isNotEmpty) {
      lines.last.text += text;
    } else {
      lines.add(AssemblerLine(text, AssemblerLineKind.raw));
      if (lines.length > maxLines) {
        lines.removeRange(0, lines.length - maxLines);
      }
    }
    _pendingNewline = !newline;
  }
}
