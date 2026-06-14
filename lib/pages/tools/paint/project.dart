import 'dart:io' as io;
import 'dart:typed_data';
import 'dart:ui' as ui;

import '../../../services/repository/app.dart';
import 'dolphin_animation.dart';

/// Decoded preview frames for a project, plus the per-frame delay used to
/// animate them.
class PaintPreviewFrames {
  PaintPreviewFrames(this.frames, this.delayMs);
  final List<ui.Image> frames;
  final int delayMs;
}

/// A Pixel Draw project: always a Flipper dolphin animation folder
/// (`meta.txt` + `frame_*.bm`). It is either a saved project
/// (`Animations/projects/`), a device import (`Animations/dolphin/`) or an
/// autosaved draft (`Animations/.drafts/`).
class PaintProject {
  PaintProject({
    required this.id,
    required this.name,
    required this.path,
    required this.isDraft,
    required this.modified,
    required this.frameCount,
    required this.dolphin,
  });

  /// Stable identifier (folder name).
  final String id;
  final String name;

  /// Directory path of the animation folder.
  final String path;

  final bool isDraft;
  final DateTime modified;
  final int frameCount;

  /// The parsed animation, used for previews and editor loading.
  final DolphinAnimation dolphin;

  bool get isAnimated => dolphin.fullOrder.length > 1;

  /// `meta.txt` path (used when opening in the editor).
  String get metaPath => pathJoin([path, 'meta.txt']);

  /// Decodes preview frames. [full] selects the complete frame order (expanded
  /// view) versus just the passive/idle loop (thumbnail).
  Future<PaintPreviewFrames> loadPreview({required bool full}) async {
    final d = dolphin;
    final order = full ? d.fullOrder : d.passiveOrder;
    final imgs = await d.loadImages(order);
    final list = <ui.Image>[
      for (final i in order)
        if (imgs[i] != null) imgs[i]!,
    ];
    return PaintPreviewFrames(list, (d.secondsPerFrame * 1000).round());
  }

  /// Decodes the project into 128×64 monochrome pixel buffers (full frame order)
  /// plus the per-frame delay, for mirroring on the device's virtual display.
  Future<({List<Uint8List> frames, int delayMs})> loadDevicePreview() async {
    final d = dolphin;
    final cache = <int, Uint8List>{};
    final frames = <Uint8List>[];
    for (final i in d.fullOrder) {
      final px = cache[i] ??=
          (await d.loadFramePixels(i) ??
          Uint8List(dolphinFrameWidth * dolphinFrameHeight));
      frames.add(px);
    }
    return (frames: frames, delayMs: (d.secondsPerFrame * 1000).round());
  }

  /// Enumerates every project under the common `Animations` folder: saved
  /// projects (`Animations/projects/<name>/`), device imports
  /// (`Animations/dolphin/<name>/`) and autosaved drafts
  /// (`Animations/.drafts/<id>/`). Sorted newest-first.
  static Future<List<PaintProject>> scanAll() async {
    final out = <PaintProject>[];

    final animDir = await appAnimationsDirectory();
    if (await animDir.exists()) {
      await for (final e in animDir.list(followLinks: false)) {
        if (e is! io.Directory) continue;
        final name = _baseName(e.path);
        if (name == PaintDraftStore.draftsFolderName) {
          out.addAll(await _scanDolphinTree(e, isDraft: true));
        } else if (name == kDolphinAnimationsFolderName ||
            name == kProjectsFolderName) {
          out.addAll(await _scanDolphinTree(e));
        }
      }
    }

    out.sort((a, b) => b.modified.compareTo(a.modified));
    return out;
  }

  static Future<List<PaintProject>> _scanDolphinTree(
    io.Directory root, {
    bool isDraft = false,
  }) async {
    final out = <PaintProject>[];
    if (!await root.exists()) return out;
    await for (final e in root.list(followLinks: false)) {
      if (e is! io.Directory) continue;
      final p = await _dolphinFromDir(e, isDraft: isDraft);
      if (p != null) out.add(p);
    }
    return out;
  }

  static Future<PaintProject?> _dolphinFromDir(
    io.Directory dir, {
    bool isDraft = false,
  }) async {
    final meta = io.File(pathJoin([dir.path, 'meta.txt']));
    if (!await meta.exists()) return null;
    final anim = await DolphinAnimationParser.parseFolder(dir, meta);
    if (anim == null) return null;
    final st = await meta.stat();
    return PaintProject(
      id: anim.name,
      name: anim.name,
      path: dir.path,
      isDraft: isDraft,
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

  static String newDraftId() =>
      'draft_${DateTime.now().millisecondsSinceEpoch}';

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

String _baseName(String path) {
  final norm = path.replaceAll('\\', '/');
  final idx = norm.lastIndexOf('/');
  return idx < 0 ? norm : norm.substring(idx + 1);
}
