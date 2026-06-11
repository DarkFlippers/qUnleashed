import 'dart:io' as io;
import 'dart:typed_data';
import 'dart:ui' as ui;

import '../../../services/repository/app.dart';
import '../editor/codec.dart';
import '../editor/constants.dart';

/// One Flipper dolphin animation: a folder containing `meta.txt` plus
/// `frame_*.bm` (or `.png`) frame files. Mirrors the structure read by
/// FlipperAnimationManager (`.sources/FlipperAnimationManager`).
class DolphinAnimation {
  DolphinAnimation({
    required this.name,
    required this.dirPath,
    required this.metaPath,
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
      // xbmToPixels tolerates a short buffer (e.g. 128×51 = 816B): rows beyond
      // the data stay blank. Only fully empty/undecodable frames are rejected.
      if (xbm == null || xbm.length < 16) return null;
      return PaintCodec.xbmToPixels(xbm);
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
