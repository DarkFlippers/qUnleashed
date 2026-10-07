import 'dart:async';
import 'dart:io' as io;

import 'package:flutter/material.dart';
import 'package:super_clipboard/super_clipboard.dart';
import 'package:super_drag_and_drop/super_drag_and_drop.dart';

import '../../../components/path.dart';
import '../../../services/guarded.dart';
import '../../../services/logging.dart';
import '../../../services/storage/paths.dart';
import '../../../theme/theme.dart';

/// Accepts files dragged in from other applications and hands them over as
/// local paths: a dropped path as it is, anything else written to a scratch
/// folder first.
class FileDropRegion extends StatefulWidget {
  const FileDropRegion({
    super.key,
    required this.label,
    required this.onFiles,
    required this.child,
  });

  final String label;
  final void Function(List<String> localPaths) onFiles;
  final Widget child;

  @override
  State<FileDropRegion> createState() => _FileDropRegionState();
}

class _FileDropRegionState extends State<FileDropRegion> {
  bool _over = false;

  void _setOver(bool value) {
    if (_over == value || !mounted) return;
    setState(() => _over = value);
  }

  DropOperation _onDropOver(DropOverEvent event) {
    final accept = event.session.allowedOperations.contains(DropOperation.copy);
    _setOver(accept);
    return accept ? DropOperation.copy : DropOperation.none;
  }

  // Every read is started before this returns: the platform holds the drop
  // open only until then, and a reader asked afterwards has nothing to read.
  Future<void> _performDrop(PerformDropEvent event) async {
    _setOver(false);
    Future<io.Directory>? scratch;
    final paths = <Future<String?>>[
      for (final item in event.session.items)
        if (item.dataReader case final reader?)
          if (reader.canProvide(Formats.fileUri))
            _droppedPath(reader)
          else
            _materialize(reader, scratch ??= droppedFilesDirectory()),
    ];
    if (paths.isEmpty) return;
    unawaited(
      guarded('[FileManager] receive drop', () async {
        final local = (await Future.wait(paths)).nonNulls.toList();
        if (local.isNotEmpty && mounted) widget.onFiles(local);
      }),
    );
  }

  Future<String?> _droppedPath(DataReader reader) {
    final done = Completer<String?>();
    final progress = reader.getValue<Uri>(
      Formats.fileUri,
      (uri) {
        if (!done.isCompleted) done.complete(uri?.toFilePath());
      },
      onError: (e) {
        LogService.warn('[FileManager] dropped item unreadable: $e');
        if (!done.isCompleted) done.complete(null);
      },
    );
    return progress == null ? Future.value() : done.future;
  }

  Future<String?> _materialize(
    DataReader reader,
    Future<io.Directory> scratch,
  ) {
    final done = Completer<String?>();
    final progress = reader.getFile(
      null,
      (file) async {
        try {
          final name =
              file.fileName ?? await reader.getSuggestedName() ?? 'file';
          final target = io.File(
            pathJoin([
              (await scratch).path,
              sanitizePathSegment(basename(name)),
            ]),
          );
          final sink = target.openWrite();
          await sink.addStream(file.getStream());
          await sink.close();
          if (!done.isCompleted) done.complete(target.path);
        } catch (e) {
          LogService.warn('[FileManager] dropped file not saved: $e');
          if (!done.isCompleted) done.complete(null);
        }
      },
      onError: (e) {
        LogService.warn('[FileManager] dropped file unreadable: $e');
        if (!done.isCompleted) done.complete(null);
      },
    );
    return progress == null ? Future.value() : done.future;
  }

  @override
  Widget build(BuildContext context) {
    return DropRegion(
      formats: Formats.standardFormats,
      hitTestBehavior: HitTestBehavior.opaque,
      onDropOver: _onDropOver,
      onDropLeave: (_) => _setOver(false),
      onDropEnded: (_) => _setOver(false),
      onPerformDrop: _performDrop,
      child: Stack(children: [widget.child, _frame(context)]),
    );
  }

  Widget _frame(BuildContext context) {
    final colors = context.appColors;
    return Positioned.fill(
      child: IgnorePointer(
        child: AnimatedOpacity(
          opacity: _over ? 1 : 0,
          duration: const Duration(milliseconds: 120),
          child: Container(
            margin: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: colors.accent.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: colors.accent, width: 2),
            ),
            alignment: Alignment.center,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.file_download_outlined,
                  size: 44,
                  color: colors.accent,
                ),
                const SizedBox(height: 10),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Text(
                    widget.label,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: colors.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
