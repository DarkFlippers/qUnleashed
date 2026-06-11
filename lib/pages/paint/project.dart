import 'dart:io' as io;
import 'dart:typed_data';
import 'dart:ui' as ui;

import '../../services/repository/app.dart';
import 'codec.dart';
import 'constants.dart';
import 'dolphin_animation.dart';

/// The kinds of project the Pixel Draw manager can list and open.
enum PaintProjectType { drawing, gif, dolphin }

/// Decoded preview frames for a project, plus the per-frame delay used to
/// animate them.
class PaintPreviewFrames {
  PaintPreviewFrames(this.frames, this.delayMs);
  final List<ui.Image> frames;
  final int delayMs;
}

/// A unified "project" entry surfaced by the manager: a saved drawing (PNG),
/// a saved GIF animation, a dolphin animation folder (exported or imported from
/// a device), or an autosaved draft (a dolphin-format folder under `.drafts`).
class PaintProject {
  PaintProject({
    required this.id,
    required this.name,
    required this.type,
    required this.path,
    required this.isDraft,
    required this.modified,
    required this.frameCount,
    this.isDeviceImport = false,
    this.dolphin,
  });

  /// Stable identifier (file or folder name).
  final String id;
  final String name;
  final PaintProjectType type;

  /// File path for [PaintProjectType.drawing]/[PaintProjectType.gif];
  /// directory path for [PaintProjectType.dolphin].
  final String path;

  final bool isDraft;
  final bool isDeviceImport;
  final DateTime modified;
  final int frameCount;

  /// Non-null for [PaintProjectType.dolphin] (and drafts), enabling frame
  /// decoding for previews and editor loading.
  final DolphinAnimation? dolphin;

  String get badge {
    if (isDraft) return 'DRAFT';
    return switch (type) {
      PaintProjectType.drawing => 'DRAWING',
      PaintProjectType.gif => 'GIF',
      PaintProjectType.dolphin => isDeviceImport ? 'DEVICE' : 'DOLPHIN',
    };
  }

  bool get isAnimated {
    if (type == PaintProjectType.gif) return frameCount != 1;
    final d = dolphin;
    if (d != null) return d.fullOrder.length > 1;
    return false;
  }

  /// `meta.txt` path for dolphin projects (used when opening in the editor).
  String? get metaPath =>
      type == PaintProjectType.dolphin ? pathJoin([path, 'meta.txt']) : null;

  /// Decodes preview frames. For dolphin projects, [full] selects the complete
  /// frame order (expanded view) versus just the passive/idle loop (thumbnail).
  Future<PaintPreviewFrames> loadPreview({required bool full}) async {
    switch (type) {
      case PaintProjectType.drawing:
        final img = await _decodeImageFile(path);
        return PaintPreviewFrames(img == null ? const [] : [img], 200);
      case PaintProjectType.gif:
        return _decodeGif(path);
      case PaintProjectType.dolphin:
        final d = dolphin;
        if (d == null) return PaintPreviewFrames(const [], 200);
        final order = full ? d.fullOrder : d.passiveOrder;
        final imgs = await d.loadImages(order);
        final list = <ui.Image>[
          for (final i in order)
            if (imgs[i] != null) imgs[i]!,
        ];
        return PaintPreviewFrames(list, (d.secondsPerFrame * 1000).round());
    }
  }

  // ── Scanning ───────────────────────────────────────────────────────────────

  /// Enumerates every project: saved drawings (`Drawings/*.png`), saved GIFs
  /// (`Animations/*.gif`), dolphin folders (`Animations/<name>/`), device
  /// imports (`Animations/dolphin/<name>/`) and drafts (`Animations/.drafts/`).
  /// Sorted newest-first.
  static Future<List<PaintProject>> scanAll() async {
    final out = <PaintProject>[];

    final drawingsDir = await appDrawingsDirectory();
    if (await drawingsDir.exists()) {
      await for (final e in drawingsDir.list(followLinks: false)) {
        if (e is! io.File) continue;
        final name = _baseName(e.path);
        if (!name.toLowerCase().endsWith('.png')) continue;
        final st = await e.stat();
        out.add(
          PaintProject(
            id: name,
            name: _stripExt(name),
            type: PaintProjectType.drawing,
            path: e.path,
            isDraft: false,
            modified: st.modified,
            frameCount: 1,
          ),
        );
      }
    }

    final animDir = await appAnimationsDirectory();
    if (await animDir.exists()) {
      await for (final e in animDir.list(followLinks: false)) {
        final name = _baseName(e.path);
        if (e is io.File && name.toLowerCase().endsWith('.gif')) {
          final st = await e.stat();
          out.add(
            PaintProject(
              id: name,
              name: _stripExt(name),
              type: PaintProjectType.gif,
              path: e.path,
              isDraft: false,
              modified: st.modified,
              frameCount: 0,
            ),
          );
        } else if (e is io.Directory) {
          if (name == '.drafts') {
            out.addAll(await _scanDolphinTree(e, isDraft: true));
          } else if (name == kDolphinAnimationsFolderName) {
            out.addAll(await _scanDolphinTree(e, isDeviceImport: true));
          } else {
            final p = await _dolphinFromDir(e);
            if (p != null) out.add(p);
          }
        }
      }
    }

    out.sort((a, b) => b.modified.compareTo(a.modified));
    return out;
  }

  static Future<List<PaintProject>> _scanDolphinTree(
    io.Directory root, {
    bool isDraft = false,
    bool isDeviceImport = false,
  }) async {
    final out = <PaintProject>[];
    if (!await root.exists()) return out;
    await for (final e in root.list(followLinks: false)) {
      if (e is! io.Directory) continue;
      final p = await _dolphinFromDir(
        e,
        isDraft: isDraft,
        isDeviceImport: isDeviceImport,
      );
      if (p != null) out.add(p);
    }
    return out;
  }

  static Future<PaintProject?> _dolphinFromDir(
    io.Directory dir, {
    bool isDraft = false,
    bool isDeviceImport = false,
  }) async {
    final meta = io.File(pathJoin([dir.path, 'meta.txt']));
    if (!await meta.exists()) return null;
    final anim = await DolphinAnimationParser.parseFolder(dir, meta);
    if (anim == null) return null;
    final st = await meta.stat();
    return PaintProject(
      id: anim.name,
      name: anim.name,
      type: PaintProjectType.dolphin,
      path: dir.path,
      isDraft: isDraft,
      isDeviceImport: isDeviceImport,
      modified: st.modified,
      frameCount: anim.frameFileCount,
      dolphin: anim,
    );
  }
}

/// Location and lifecycle helpers for editor autosave drafts. Drafts are stored
/// as dolphin-format folders under `Animations/.drafts/`.
abstract final class PaintDraftStore {
  static const String draftsFolderName = '.drafts';

  static String newDraftId() => 'draft_${DateTime.now().millisecondsSinceEpoch}';

  static Future<io.Directory> draftsDir() async {
    final anim = await appAnimationsDirectory();
    final dir = io.Directory(pathJoin([anim.path, draftsFolderName]));
    await dir.create(recursive: true);
    return dir;
  }

  static Future<String> dirPathForDraft(String id) async {
    final root = await draftsDir();
    return pathJoin([root.path, id]);
  }
}

Future<ui.Image?> _decodeImageFile(String path) async {
  try {
    final bytes = await io.File(path).readAsBytes();
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    return frame.image;
  } catch (_) {
    return null;
  }
}

Future<PaintPreviewFrames> _decodeGif(String path) async {
  try {
    final bytes = await io.File(path).readAsBytes();
    final codec = await ui.instantiateImageCodec(bytes);
    final frames = <ui.Image>[];
    var delay = 100;
    for (int i = 0; i < codec.frameCount; i++) {
      final f = await codec.getNextFrame();
      frames.add(f.image);
      if (i == 0 && f.duration.inMilliseconds > 0) {
        delay = f.duration.inMilliseconds;
      }
    }
    return PaintPreviewFrames(frames, delay.clamp(33, 2000));
  } catch (_) {
    return PaintPreviewFrames(const [], 100);
  }
}

/// Decodes a PNG into the shared 128×64 monochrome pixel buffer (luminance
/// thresholded), for loading a saved drawing into the editor.
Future<Uint8List> decodePngToPixels(Uint8List bytes) async {
  final codec = await ui.instantiateImageCodec(
    bytes,
    targetWidth: kCanvasWidth,
    targetHeight: kCanvasHeight,
  );
  final frame = await codec.getNextFrame();
  final img = frame.image;
  final bd = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
  img.dispose();
  final pix = Uint8List(kCanvasWidth * kCanvasHeight);
  if (bd != null) PaintCodec.rgbaToPixels(bd.buffer.asUint8List(), pix);
  return pix;
}

String _baseName(String path) {
  final norm = path.replaceAll('\\', '/');
  final idx = norm.lastIndexOf('/');
  return idx < 0 ? norm : norm.substring(idx + 1);
}

String _stripExt(String name) {
  final idx = name.lastIndexOf('.');
  return idx <= 0 ? name : name.substring(0, idx);
}
