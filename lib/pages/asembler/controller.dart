import 'dart:io';

import 'package:dartufbt/dartufbt.dart';
import 'package:flutter/foundation.dart';

const String kAssemblerIndexUrl = 'https://up.unleashedflip.com/directory.json';

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
  bool _pendingNewline = false;

  UfbtLogger get logger => _logger;
  UfbtStatus? get status => _status;
  UfbtProgress? get progress => _progress;
  AssemblerJob get job => _job;
  bool get busy => _job != AssemblerJob.none;
  UfbtUpdateChannel get channel => _channel;
  bool get verbose => _logger.verbose;

  UfbtInstaller get installer =>
      _installer ??= UfbtInstaller(logger: _logger, paths: UfbtPaths.resolve());

  void setChannel(UfbtUpdateChannel value) {
    if (_channel == value || busy) return;
    _channel = value;
    notifyListeners();
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
    indexUrl: kAssemblerIndexUrl,
    force: force,
  );

  Future<bool> downloadSdk({bool force = false}) {
    return _run(
      AssemblerJob.sdk,
      () => installer.installSdk(taskForChannel(force: force)),
    );
  }

  Future<bool> downloadToolchain({bool force = false}) {
    return _run(
      AssemblerJob.toolchain,
      () => installer.installToolchain(force: force),
    );
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
