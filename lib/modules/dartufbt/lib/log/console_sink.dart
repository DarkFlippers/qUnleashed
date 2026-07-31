import 'dart:io';

import 'log_event.dart';
import 'log_format.dart';
import 'progress.dart';

class UfbtConsoleSink {
  UfbtConsoleSink({
    void Function(String text)? output,
    this.barWidth = UfbtLogFormat.defaultBarWidth,
    this.unitsPerHash = 300,
  }) : _output = output ?? stdout.write;

  final void Function(String text) _output;
  final int barWidth;
  final int unitsPerHash;

  final Map<String, int> _hashes = {};

  void call(UfbtLogEvent event) {
    switch (event) {
      case UfbtMessageEvent():
        _output('${event.formatted}\n');
      case UfbtBuildEvent():
        _output('${event.formatted}\n');
      case UfbtRawEvent():
        _output(event.newline ? '${event.text}\n' : event.text);
      case UfbtProgressEvent():
        _progress(event.progress);
    }
  }

  void _progress(UfbtProgress progress) {
    switch (progress.state) {
      case UfbtProgressState.started:
        _hashes[progress.id] = 0;
        if (progress.title.isNotEmpty) _output('${progress.title}\n');
      case UfbtProgressState.running:
        if (progress.indeterminate) {
          _appendHashes(progress);
        } else {
          _output('\r${UfbtLogFormat.progressBar(progress, width: barWidth)}');
        }
      case UfbtProgressState.finished:
        if (progress.indeterminate) {
          _appendHashes(progress);
          _output(' ${UfbtLogFormat.percent(100)}\n');
        } else {
          _output(
            '\r${UfbtLogFormat.progressBar(progress, width: barWidth)}\n',
          );
        }
        _hashes.remove(progress.id);
      case UfbtProgressState.failed:
        _output('\n');
        _hashes.remove(progress.id);
    }
  }

  void _appendHashes(UfbtProgress progress) {
    final printed = _hashes[progress.id] ?? 0;
    final expected = progress.current ~/ unitsPerHash;
    if (expected <= printed) return;
    _output(UfbtLogFormat.barChar * (expected - printed));
    _hashes[progress.id] = expected;
  }
}
