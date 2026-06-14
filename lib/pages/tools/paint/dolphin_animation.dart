import 'dart:io' as io;
import 'dart:typed_data';
import 'dart:ui' as ui;

import '../../../services/repository/app.dart';
import 'codec.dart';
import 'constants.dart';

/// One Flipper dolphin animation: a folder containing `meta.txt` plus
/// `frame_*.bm` (or `.png`) frame files. Mirrors the structure read by
/// FlipperAnimationManager (`.sources/FlipperAnimationManager`).
class DolphinAnimation {
  DolphinAnimation({
    required this.name,
    required this.dirPath,
    required this.metaPath,
    required this.width,
    required this.height,
    required this.passiveFrames,
    required this.activeFrames,
    required this.frameRate,
    required this.duration,
    required this.activeCycles,
    required this.activeCooldown,
    required this.framesOrder,
    required this.frameFileCount,
  });

  /// Folder name (used as the display name).
  final String name;
  final String dirPath;
  final String metaPath;

  /// Source frame dimensions from `meta.txt` (often 128×54, not the full 64).
  final int width;
  final int height;

  final int passiveFrames;
  final int activeFrames;
  final int frameRate;
  final int duration;
  final int activeCycles;
  final int activeCooldown;

  /// Playback order referencing frame file indices.
  final List<int> framesOrder;

  /// Number of distinct `frame_N.bm` files (max index + 1).
  final int frameFileCount;

  int get totalFrames => passiveFrames + activeFrames;
  double get secondsPerFrame => frameRate > 0 ? 1 / frameRate : 0.5;

  /// Frame file indices that make up the passive (idle) loop. Falls back to the
  /// full frame set when the meta omits a passive count.
  List<int> get passiveOrder {
    if (passiveFrames <= 0) return List<int>.generate(frameFileCount, (i) => i);
    final n = passiveFrames.clamp(0, frameFileCount);
    return List<int>.generate(n, (i) => i);
  }

  /// Full playback order (passive + active), as declared by `Frames order:`.
  List<int> get fullOrder =>
      framesOrder.isNotEmpty ? framesOrder : passiveOrder;

  /// Loads and decodes a single `frame_<index>.bm`/`.png` into the shared
  /// 128×64 monochrome pixel buffer. Returns null when the file is missing or
  /// undecodable.
  Future<Uint8List?> loadFramePixels(int fileIndex) async {
    final bm = io.File(pathJoin([dirPath, 'frame_$fileIndex.bm']));
    if (await bm.exists()) {
      final xbm = PaintCodec.decodeBmFile(await bm.readAsBytes());
      if (xbm == null || xbm.length < 16) return null;
      return PaintCodec.xbmToPixels(xbm, srcWidth: width, srcHeight: height);
    }
    return null;
  }

  /// Decodes the given [fileIndices] (deduplicated) into [ui.Image] frames,
  /// keyed by file index. Used to drive animated previews lazily.
  Future<Map<int, ui.Image>> loadImages(Iterable<int> fileIndices) async {
    final out = <int, ui.Image>{};
    for (final idx in fileIndices.toSet()) {
      if (idx < 0) continue;
      final pixels = await loadFramePixels(idx);
      if (pixels == null) continue;
      out[idx] = await PaintCodec.frameToImage(pixels);
    }
    return out;
  }
}

abstract final class DolphinAnimationParser {
  /// Scans [root] for animation folders (each containing a `meta.txt`) and
  /// returns the parsed set, sorted by name. Non-animation entries are skipped.
  static Future<List<DolphinAnimation>> scanDirectory(io.Directory root) async {
    if (!await root.exists()) return const [];
    final out = <DolphinAnimation>[];
    await for (final entity in root.list(followLinks: false)) {
      if (entity is! io.Directory) continue;
      final meta = io.File(pathJoin([entity.path, 'meta.txt']));
      if (!await meta.exists()) continue;
      final anim = await parseFolder(entity, meta);
      if (anim != null) out.add(anim);
    }
    out.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return out;
  }

  static Future<DolphinAnimation?> parseFolder(
    io.Directory dir,
    io.File metaFile,
  ) async {
    try {
      final text = await metaFile.readAsString();

      final passive = PaintCodec.parseDolphinInt(text, 'Passive frames') ?? 0;
      final active = PaintCodec.parseDolphinInt(text, 'Active frames') ?? 0;

      final orderMatch = RegExp(
        r'^Frames order: (.+)$',
        multiLine: true,
      ).firstMatch(text);
      final order = <int>[];
      var maxIdx = (passive + active - 1).clamp(0, 1023);
      final orderStr = orderMatch?.group(1)?.trim() ?? '';
      if (orderStr.isNotEmpty) {
        for (final s in orderStr.split(RegExp(r'\s+'))) {
          final n = int.tryParse(s);
          if (n == null) continue;
          order.add(n);
          if (n > maxIdx) maxIdx = n;
        }
      }

      final name = dir.uri.pathSegments.where((s) => s.isNotEmpty).last;

      return DolphinAnimation(
        name: name,
        dirPath: dir.path,
        metaPath: metaFile.path,
        width: PaintCodec.parseDolphinInt(text, 'Width') ?? kCanvasWidth,
        height: PaintCodec.parseDolphinInt(text, 'Height') ?? kCanvasHeight,
        passiveFrames: passive,
        activeFrames: active,
        frameRate: PaintCodec.parseDolphinInt(text, 'Frame rate') ?? 2,
        duration: PaintCodec.parseDolphinInt(text, 'Duration') ?? 3600,
        activeCycles: PaintCodec.parseDolphinInt(text, 'Active cycles') ?? 1,
        activeCooldown: PaintCodec.parseDolphinInt(text, 'Active cooldown') ?? 7,
        framesOrder: order,
        frameFileCount: maxIdx + 1,
      );
    } catch (_) {
      return null;
    }
  }
}

// Re-export so callers can reference canvas dimensions without importing paint.
const int dolphinFrameWidth = kCanvasWidth;
const int dolphinFrameHeight = kCanvasHeight;

/// Serializes [frames] (128×64 monochrome pixel buffers) into [dir] as a Flipper
/// dolphin animation: `meta.txt` + `frame_<i>.bm`. Stale frame files from a
/// previous, longer animation are removed first. Shared by the editor's Dolphin
/// export and the draft autosave.
Future<void> writeDolphinFolder(
  io.Directory dir, {
  required List<Uint8List> frames,
  required int passiveFrames,
  required int frameRate,
  required int duration,
  required int activeCycles,
  required int activeCooldown,
  bool compress = false,
}) async {
  await dir.create(recursive: true);

  // Drop old frame_*.bm so a shrunk animation doesn't leave orphans behind.
  final framePattern = RegExp(r'(^|/|\\)frame_\d+\.bm$');
  await for (final e in dir.list(followLinks: false)) {
    if (e is io.File && framePattern.hasMatch(e.path)) {
      await e.delete();
    }
  }

  final n = frames.length;
  final passiveN = passiveFrames.clamp(0, n);
  final activeN = n - passiveN;
  final framesOrder = List.generate(n, (i) => '$i').join(' ');
  final meta = [
    'Filetype: Flipper Animation',
    'Version: 1',
    '',
    'Width: $kCanvasWidth',
    'Height: $kCanvasHeight',
    'Passive frames: $passiveN',
    'Active frames: $activeN',
    'Frames order: $framesOrder',
    'Active cycles: $activeCycles',
    'Frame rate: $frameRate',
    'Duration: $duration',
    'Active cooldown: $activeCooldown',
    '',
    'Bubble slots: 0',
    '',
  ].join('\n');

  await io.File(pathJoin([dir.path, 'meta.txt'])).writeAsString(meta);

  for (int i = 0; i < n; i++) {
    final xbm = PaintCodec.encodeXBM(frames[i]);
    final bm = compress
        ? PaintCodec.encodeBmCompressed(xbm)
        : PaintCodec.encodeBmUncompressed(xbm);
    await io.File(pathJoin([dir.path, 'frame_$i.bm'])).writeAsBytes(bm);
  }
}
