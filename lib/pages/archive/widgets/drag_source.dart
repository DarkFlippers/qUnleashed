import 'dart:async';
import 'dart:io' as io;
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:super_clipboard/super_clipboard.dart';
import 'package:super_drag_and_drop/super_drag_and_drop.dart';

import '../../../components/archive/models/key.dart';
import '../../../components/path.dart';
import '../../../services/guarded.dart';
import '../../../services/localization/l10n.dart';
import '../../../services/logging.dart';
import '../../../services/storage/paths.dart';
import '../../../theme/theme.dart';
import '../browser/controller.dart';
import '../browser/widgets/file_row.dart';

/// Produces the bytes of a dragged file once a receiver asks for them.
/// [progress] is the receiver's, when it shows one.
typedef DragFileLoader = Future<List<int>?> Function(WriteProgress? progress);

/// A file the user can drag out of the app: already on disk, or read on
/// demand through [load].
class DragFile {
  const DragFile({
    required this.id,
    required this.name,
    this.localPath,
    this.load,
  }) : assert(localPath != null || load != null);

  DragFile.archiveKey(ArchiveKey key)
    : this(id: key.remotePath, name: key.fileName, localPath: key.localPath);

  final String id;
  final String name;
  final String? localPath;
  final DragFileLoader? load;
}

const _ownPrefix = 'qunleashed.file:';

/// Whether a dropped item is one of this app's own [DragFile]s.
bool isOwnDragItem(Object? localData) =>
    localData is String && localData.startsWith(_ownPrefix);

bool _on(Set<TargetPlatform> platforms) =>
    !kIsWeb && platforms.contains(defaultTargetPlatform);

/// Where the receiver pulls the bytes after the drop, so the drag can start
/// before a thing has been read from the Flipper.
bool get _virtualFiles => _on(const {TargetPlatform.iOS});

/// Where a dropped file is a path the receiver opens itself.
bool get _filePaths => _on(const {
  TargetPlatform.macOS,
  TargetPlatform.windows,
  TargetPlatform.linux,
});

const _anyFile = SimpleFileFormat(
  uniformTypeIdentifiers: ['public.data'],
  mimeTypes: ['application/octet-stream'],
);

const double _dragIcon = 48;

Future<List<int>?> _bytes(DragFile file, WriteProgress? progress) {
  final local = file.localPath;
  if (local != null) return io.File(local).readAsBytes();
  return file.load!(progress);
}

/// Writes [file] into a scratch folder and returns the copy's path, or null
/// when the bytes could not be read.
Future<String?> _copyOut(DragFile file) async {
  final bytes = await _bytes(file, null);
  if (bytes == null) return null;
  final dir = await draggedFilesDirectory();
  final target = io.File(pathJoin([dir.path, sanitizePathSegment(file.name)]));
  await target.writeAsBytes(bytes);
  return target.path;
}

/// The app's FileProvider address of a file under the cache directory, which
/// is the only way another Android app may read it.
Future<Uri> _contentUri(String path) async {
  final cache = (await getTemporaryDirectory()).path;
  final package = (await PackageInfo.fromPlatform()).packageName;
  return Uri(
    scheme: 'content',
    host: '$package.provider',
    pathSegments: ['cache', ...path.substring(cache.length + 1).split('/')],
  );
}

Future<Uri?> _fileUri(DragFile file) async {
  if (_filePaths) {
    final path = file.localPath ?? await _copyOut(file);
    return path == null ? null : Uri.file(path);
  }
  final path = await _copyOut(file);
  return path == null ? null : _contentUri(path);
}

void _provideVirtual(
  DragFile file,
  VirtualFileEventSinkProvider sinkProvider,
  WriteProgress progress,
) {
  unawaited(
    guarded('[Archive] drag out ${file.id}', () async {
      try {
        final bytes = await _bytes(file, progress);
        if (bytes == null) {
          sinkProvider(fileSize: 0)
            ..addError(StateError('${file.id} was not read'))
            ..close();
          return;
        }
        sinkProvider(fileSize: bytes.length)
          ..add(Uint8List.fromList(bytes))
          ..close();
      } catch (e) {
        LogService.warn('[Archive] drag out ${file.id} failed: $e');
        sinkProvider(fileSize: 0)
          ..addError(e)
          ..close();
      }
    }),
  );
}

Future<DragItem?> _dragItem(DragFile file) async {
  final item = DragItem(
    suggestedName: file.name,
    localData: '$_ownPrefix${file.id}',
  );
  if (_virtualFiles) {
    item.addVirtualFile(
      format: _anyFile,
      provider: (sink, progress) => _provideVirtual(file, sink, progress),
    );
    return item;
  }
  final Uri? uri;
  try {
    uri = await _fileUri(file);
  } catch (e) {
    LogService.warn('[Archive] drag out ${file.id} failed: $e');
    return null;
  }
  if (uri == null) return null;
  item.add(Formats.fileUri(uri));
  return item;
}

/// A one-pixel image for the items that ride along under the first one's
/// picture: the session wants an image per item, and the fan is drawn once.
Future<TargetedWidgetSnapshot> _blankImage(Offset at) async {
  final recorder = ui.PictureRecorder();
  Canvas(recorder);
  final picture = recorder.endRecording();
  final image = await picture.toImage(1, 1);
  picture.dispose();
  return TargetedWidgetSnapshot(
    WidgetSnapshot.image(image),
    Rect.fromCenter(center: at, width: 1, height: 1),
  );
}

/// Always drawn in the light theme: the picture travels over other windows
/// and the desktop, where the dark theme's translucent badges disappear.
Widget _dragImage(BuildContext context, List<DragFile> files) =>
    SnapshotSettings(
      constraintsTransform: (_) => const BoxConstraints(maxWidth: 200),
      translation: (rect, dragPosition) =>
          dragPosition - Offset(rect.center.dx, _dragIcon / 2),
      child: Theme(
        data: buildAppTheme(Brightness.light, context.appColors.accent),
        child: _DragImage(files: files),
      ),
    );

/// Makes [child] draggable out of the app as [file], together with the rest
/// of [group] when there is one.
class FileDragSource extends StatelessWidget {
  const FileDragSource({
    super.key,
    required this.file,
    required this.child,
    this.group,
    this.onDropped,
  });

  final DragFile file;
  final List<DragFile> Function()? group;

  /// Called once a receiver has taken the files.
  final VoidCallback? onDropped;
  final Widget child;

  List<DragFile> _files() => [
    file,
    for (final other in group?.call() ?? const <DragFile>[])
      if (other.id != file.id) other,
  ];

  Future<DragItem?> _item(DragItemRequest request) async {
    final carried = await request.session.getLocalData() ?? const [];
    if (carried.contains('$_ownPrefix${file.id}')) return null;
    return _dragItem(file);
  }

  Future<DragConfiguration> _configure(
    DragConfiguration configuration,
    DragSession session,
  ) async {
    _watchDrop(session);
    final rest = _files().skip(1);
    if (rest.isEmpty) return configuration;
    final anchor = configuration.items.first.image.rect.center;
    final extra = <DragConfigurationItem>[];
    for (final other in rest) {
      final item = await _dragItem(other);
      if (item == null) continue;
      extra.add(
        DragConfigurationItem(item: item, image: await _blankImage(anchor)),
      );
    }
    return DragConfiguration(
      allowedOperations: configuration.allowedOperations,
      options: configuration.options,
      items: [...configuration.items, ...extra],
    );
  }

  void _watchDrop(DragSession session) {
    final dropped = onDropped;
    if (dropped == null) return;
    void done() {
      final operation = session.dragCompleted.value;
      if (operation == null) return;
      session.dragCompleted.removeListener(done);
      if (operation == DropOperation.copy) dropped();
    }

    session.dragCompleted.addListener(done);
  }

  @override
  Widget build(BuildContext context) {
    return DragItemWidget(
      allowedOperations: () => [DropOperation.copy],
      canAddItemToExistingSession: true,
      dragBuilder: (context, _) => _dragImage(context, _files()),
      liftBuilder: (context, _) => _dragImage(context, _files()),
      dragItemProvider: _item,
      child: DraggableWidget(onDragConfiguration: _configure, child: child),
    );
  }
}

/// A key row that drags out as its local file, alone or with the rest of the
/// selection it belongs to. A key with no local copy is not draggable.
class ArchiveKeyDragSource extends StatelessWidget {
  const ArchiveKeyDragSource({
    super.key,
    required this.archiveKey,
    required this.selected,
    required this.selection,
    required this.onDropped,
    required this.child,
  });

  final ArchiveKey archiveKey;
  final bool selected;
  final List<ArchiveKey> Function() selection;
  final VoidCallback onDropped;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!archiveKey.inLocal) return child;
    return FileDragSource(
      file: DragFile.archiveKey(archiveKey),
      group: selected
          ? () => [
              for (final k in selection())
                if (k.inLocal) DragFile.archiveKey(k),
            ]
          : null,
      onDropped: selected ? onDropped : null,
      child: child,
    );
  }
}

/// What rides under the pointer: one file shows its icon and name; several
/// show one icon per format around a ring, and how many files there are.
class _DragImage extends StatelessWidget {
  const _DragImage({required this.files});

  final List<DragFile> files;

  static const double _gap = 4;
  static const double _ringGap = 6;
  static const int _maxKinds = 6;

  RemoteEntry _entry(DragFile file) =>
      RemoteEntry(name: file.name, size: 0, isDir: false);

  Widget _icon(DragFile file) =>
      FileIconBadge(entry: _entry(file), size: _dragIcon);

  Widget _label(String text, QAppColors colors) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(
      color: colors.card,
      borderRadius: BorderRadius.circular(6),
    ),
    child: Text(
      text,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      textAlign: TextAlign.center,
      style: TextStyle(
        color: colors.textPrimary,
        fontSize: 12,
        fontWeight: FontWeight.w600,
      ),
    ),
  );

  /// One icon per format on a ring just wide enough for the squares not to
  /// touch, whichever way their neighbours lie.
  Widget _ring(List<DragFile> kinds) {
    if (kinds.length == 1) return _icon(kinds.single);
    final n = kinds.length;
    final radius = _ringRadius(n);
    final extent = 2 * radius + _dragIcon;
    return SizedBox(
      width: extent,
      height: extent,
      child: Stack(
        children: [
          for (var i = 0; i < n; i++)
            Positioned(
              left: radius * (1 + math.cos(_angle(i, n))),
              top: radius * (1 + math.sin(_angle(i, n))),
              child: _icon(kinds[i]),
            ),
        ],
      ),
    );
  }

  /// Two squares stay [_ringGap] apart once their centres differ by at least
  /// `size + gap` along one axis; a chord that leans diagonally has to be
  /// longer than one that lies flat to manage that.
  double _ringRadius(int n) {
    final apart = _dragIcon + _ringGap;
    var chord = apart;
    for (var i = 0; i < n; i++) {
      final lean = (_angle(i, n) + _angle(i + 1, n)) / 2 + math.pi / 2;
      final flat = math.max(math.cos(lean).abs(), math.sin(lean).abs());
      chord = math.max(chord, apart / flat);
    }
    return chord / (2 * math.sin(math.pi / n));
  }

  double _angle(int index, int count) =>
      -math.pi / 2 + 2 * math.pi * index / count;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final Widget picture;
    final String text;
    if (files.length == 1) {
      picture = _icon(files.single);
      text = files.single.name;
    } else {
      final kinds = <String, DragFile>{};
      for (final file in files) {
        kinds.putIfAbsent(_entry(file).extension, () => file);
      }
      picture = _ring(kinds.values.take(_maxKinds).toList());
      text = context.l10n.fmDragFiles(files.length);
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        picture,
        const SizedBox(height: _gap),
        _label(text, colors),
      ],
    );
  }
}
