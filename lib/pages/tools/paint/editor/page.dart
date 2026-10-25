import '../../../../services/localization/l10n.dart';

import 'dart:async';
import 'dart:io' as io;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flipperlib/flipperlib.dart' hide DateTime;
import 'package:flutter/material.dart';

import '../../../../components/folder_pick.dart';
import '../../../../components/format.dart';
import '../../../../components/path.dart';
import '../../../../components/picked_file.dart';
import '../../../../services/logging.dart';
import '../../../../services/storage/paths.dart';
import '../../../../theme/theme.dart';
import '../../../../components/notification.dart';
import '../../../../components/codec/gif.dart';
import '../../../../components/codec/bm.dart';
import '../constants.dart';
import '../dolphin_animation.dart';
import '../project.dart';
import 'controller.dart';
import 'widgets/animation_panel.dart';
import 'widgets/canvas_view.dart';
import 'widgets/editor_toolbars.dart';
import 'widgets/editor_widgets.dart';
import 'widgets/frames_strip.dart';

/// The largest single image this page will read from a pick.
///
/// Everything it decodes draws onto the Flipper's 128x64 screen: a `.bm`
/// frame is about a kilobyte, a PNG of that screen a few, and the largest
/// honest input is a multi-frame GIF. 8 MB is well past all of them and well
/// under what decoding one costs, which is the number that matters -
/// `instantiateImageCodec` holds the encoded bytes and the raw RGBA at once.
const int _paintImportLimit = 8 * 1024 * 1024;

/// The largest `meta.txt` this page will read.
///
/// A dolphin manifest is a few lines of text. This is not a cap on the import
/// - the frames around it are bounded separately, where they are read - it is
/// a cap on reading a file that is only called `meta.txt`.
const int _metaTextLimit = 1024 * 1024;

/// The most frames a dolphin manifest may ask for.
///
/// The count derived from `Passive frames` and `Active frames` is already
/// clamped to this; the `Frames order` line was not, so a manifest naming
/// frame 999999999 sent the walk below `stat`-ing its way there one file at a
/// time. Restated here so both ways in land on the same bound.
const int _maxDolphinFrameIdx = 255;

class PaintPage extends StatefulWidget {
  const PaintPage({super.key, this.project, this.remotePath, this.client})
    : assert(project == null || remotePath == null),
      // A drawing on the Flipper cannot be read without one, and the two
      // routes that open one both have a scope to take it from. A local
      // project needs no device at all. ADR 0002.
      assert(remotePath == null || client != null);

  /// Project to load into the canvas when the editor opens. When null the editor
  /// starts a fresh, blank project (which becomes a draft once edited).
  final PaintProject? project;

  /// A single image file on the connected Flipper. Only PNG, GIF and BM files
  /// are supported; a remote meta.txt remains a regular text file and cannot
  /// open a complete Dolphin animation project.
  final String? remotePath;
  final FlipperClient? client;

  @override
  State<PaintPage> createState() => _PaintPageState();
}

class _PaintPageState extends State<PaintPage> {
  late final PaintController _ctrl;

  // Draft autosave: the working frames are persisted to a `.drafts` folder so
  // the project manager can surface unsaved work. [_baselineVersion] marks the
  // controller's pixelVersion at which the canvas is considered "clean".
  String? _draftId;
  String? _draftDir;
  int _baselineVersion = 0;
  Timer? _autosaveTimer;
  bool _savingDraft = false;

  // The saved Dolphin project this editor is bound to (folder + name). Null
  // until the canvas is saved as a project; once set, Save overwrites it
  // without prompting and autosave is redirected there.
  String? _projectDir;
  String? _projectName;

  /// The last name typed into the export prompt.
  ///
  /// Offered back by [_resolveExportName] on every later export prompt, not
  /// only after a pick that did not happen: nothing in the three export paths
  /// binds a project, so `_projectName` stays null and a second export of an
  /// unsaved drawing is the same prompt again. The export that mattered is the
  /// one that was interrupted - the pick is refused or cancelled *after* the
  /// name is typed - and a name offered back after a successful export is the
  /// better default anyway. `_saveProject` does not read this: saving is where
  /// a name becomes the project's own, and it prompts from `_projectName`.
  String? _lastExportName;

  @override
  void initState() {
    super.initState();
    _ctrl = PaintController();
    _ctrl.addListener(_onControllerChange);
    final project = widget.project;
    if (project != null) {
      if (project.isDraft) {
        // Editing an existing draft → keep writing to the same folder.
        _draftId = project.id;
        _draftDir = project.path;
      } else {
        // Opening a saved project → Save overwrites it in place and autosave
        // writes straight to its folder.
        _projectDir = project.path;
        _projectName = project.name;
        _draftDir = project.path;
      }
    }
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (project != null) {
        await _loadProject(project);
      } else if (widget.remotePath != null) {
        await _loadRemoteFile(widget.remotePath!);
      }
      // Whatever we loaded (or the empty start) is the clean baseline.
      _baselineVersion = _ctrl.pixelVersion;
      // Stream the opening canvas; the session buffers it until the display has
      // started, so the first frame reliably reaches a connected device.
      _ctrl.schedulePush();
    });
  }

  void _onControllerChange() {
    if (mounted) setState(() {});
    _scheduleAutosave();
  }

  Future<void> _loadProject(PaintProject project) async {
    try {
      await _importDolphinFromPath(project.metaPath);
    } catch (e) {
      if (!mounted) return;
      context.showNotification(
        context.l10n.appOpenFailed('$e'),
        type: QNotificationType.error,
      );
    }
  }

  /// What decodes [ext], or null if nothing here does.
  ///
  /// One list rather than three. Both ways into the decoders - a pick and a
  /// file opened from the device - ask this, so a format added here reaches
  /// both, and one added to neither cannot be half-supported.
  Future<void> Function(Uint8List bytes)? _decoderFor(String ext) =>
      switch (ext) {
        'bm' => _importBmSingle,
        'gif' => _importGif,
        'png' => _importPng,
        _ => null,
      };

  Future<void> _loadRemoteFile(String path) async {
    try {
      final bytes = await widget.client!.storageReadChunked(
        path,
        timeout: const Duration(minutes: 5),
      );
      if (bytes.isEmpty) {
        throw StateError(l10n.paintFileEmpty);
      }

      final data = Uint8List.fromList(bytes);
      final decode = _decoderFor(_extensionOf(path));
      if (decode == null) {
        // The global `l10n` and not `context.l10n`, matching `paintFileEmpty`
        // above: both are read after an await, and neither needs the tree.
        throw UnsupportedError(l10n.paintUnsupportedFile);
      }
      await decode(data);
    } catch (e) {
      if (!mounted) return;
      context.showNotification(
        context.l10n.appOpenFailed('$e'),
        type: QNotificationType.error,
      );
    }
  }

  void _scheduleAutosave() {
    if (_ctrl.pixelVersion == _baselineVersion) return; // not dirty
    _autosaveTimer?.cancel();
    _autosaveTimer = Timer(const Duration(milliseconds: 1200), _autosaveDraft);
  }

  Future<void> _autosaveDraft() async {
    if (_savingDraft) return;
    if (_ctrl.pixelVersion == _baselineVersion) return;
    _savingDraft = true;
    try {
      _draftId ??= PaintDraftStore.newDraftId();
      _draftDir ??= await PaintDraftStore.dirPathForDraft(_draftId!);
      await writeDolphinFolder(
        io.Directory(_draftDir!),
        frames: _ctrl.frames.map((f) => Uint8List.fromList(f)).toList(),
        passiveFrames: _ctrl.effectivePassiveCount,
        frameRate: _ctrl.frameRate,
        duration: _ctrl.duration,
        activeCycles: _ctrl.activeCycles,
        activeCooldown: _ctrl.activeCooldown,
        compress: _ctrl.compressBm,
      );
    } catch (e) {
      // The draft is how work survives leaving the editor, so this is the
      // difference between losing the drawing and not. A 1.2s trailing
      // debounce fires it once per pause, and a persistent cause keeps $e
      // stable, so back-to-back failures fold into one counted entry -
      // unless another kept line lands between them.
      LogService.warn('[PaintEditor] autosave draft failed: $e');
    } finally {
      _savingDraft = false;
    }
  }

  @override
  void dispose() {
    _autosaveTimer?.cancel();
    _ctrl.removeListener(_onControllerChange);
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _close() async {
    if (_ctrl.isClosing) return;
    _autosaveTimer?.cancel();
    await _autosaveDraft(); // persist the latest edits as a draft before leaving
    // Awaited so the order is stated rather than incidental: close() stops
    // the timers and leaves the live virtual display before the pop below
    // takes the page away. It has no await of its own today, so this costs a
    // microtask and changes nothing observable - the draft on the line above
    // is what actually reaches disk.
    await _ctrl.close();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).pop();
    });
  }

  /// The Save action (the app bar's save icon): persists the canvas as a
  /// Dolphin project (`meta.txt` + `.bm` frames) inside the app's animations
  /// library. A brand-new project prompts for a folder name once; an already
  /// saved project is overwritten silently.
  Future<void> _saveProject() async {
    // Always confirm the name: pre-filled with the current project's name when
    // saved before. Keeping it saves in place; changing it forks a new folder.
    final name = await _promptProjectName(
      initial: _projectName ?? _suggestedName(),
    );
    if (name == null) return; // cancelled or empty
    try {
      final base = await appProjectsDirectory();
      final dirPath = pathJoin([base.path, name]);

      await _writeDolphinTo(io.Directory(dirPath));
      await _adoptProjectFolder(dirPath, name);
      _baselineVersion = _ctrl.pixelVersion;

      if (!mounted) return;
      context.showNotification(
        context.l10n.paintSaved(name),
        type: QNotificationType.good,
      );
    } catch (e) {
      if (!mounted) return;
      context.showNotification(
        context.l10n.paintSaveFailed('$e'),
        type: QNotificationType.error,
      );
    }
  }

  /// Export entry points (the "Export" sheet): resolve a project name (prompted
  /// only when the project is new), then let the user pick a destination folder
  /// via the system file picker before writing the chosen format there.
  Future<void> _exportDolphin() async {
    final name = await _resolveExportName();
    if (name == null) return;
    final dest = await _pickDestination();
    if (dest == null) return;
    try {
      final animDir = io.Directory(pathJoin([dest, name]));
      await _writeDolphinTo(animDir);
      if (!mounted) return;
      context.showNotification(
        context.l10n.paintDolphinExported(animDir.path),
        type: QNotificationType.good,
      );
    } catch (e) {
      if (!mounted) return;
      context.showNotification(
        context.l10n.paintExportDolphinFailed('$e'),
        type: QNotificationType.error,
      );
    }
  }

  Future<void> _exportGif() async {
    final name = await _resolveExportName();
    if (name == null) return;
    final dest = await _pickDestination();
    if (dest == null) return;
    try {
      final delays = List.filled(_ctrl.frames.length, kAnimFrameDelay);
      final gif = FlipperGifEncoder.encode(
        width: kCanvasWidth,
        height: kCanvasHeight,
        frames: _ctrl.frames.map((f) => Uint8List.fromList(f)).toList(),
        delaysMs: delays,
        color0: const Color(0xFFDFDFDF).toARGB32(),
        color1: const Color(0xFF000000).toARGB32(),
      );
      final file = io.File(pathJoin([dest, '$name.gif']));
      await file.writeAsBytes(gif, flush: true);
      if (!mounted) return;
      context.showNotification(
        context.l10n.paintSavedTo(file.path),
        type: QNotificationType.good,
      );
    } catch (e) {
      if (!mounted) return;
      context.showNotification(
        context.l10n.paintExportGifFailed('$e'),
        type: QNotificationType.error,
      );
    }
  }

  Future<void> _exportPng() async {
    final name = await _resolveExportName();
    if (name == null) return;
    final dest = await _pickDestination();
    if (dest == null) return;
    try {
      final png = await BmCodec.frameToPng(_ctrl.frames[_ctrl.currentFrame]);
      final file = io.File(pathJoin([dest, '$name.png']));
      await file.writeAsBytes(png, flush: true);
      if (!mounted) return;
      context.showNotification(
        context.l10n.paintSavedTo(file.path),
        type: QNotificationType.good,
      );
    } catch (e) {
      if (!mounted) return;
      context.showNotification(
        context.l10n.paintExportPngFailed('$e'),
        type: QNotificationType.error,
      );
    }
  }

  /// Writes the current frames to [dir] as a Dolphin animation.
  Future<void> _writeDolphinTo(io.Directory dir) {
    return writeDolphinFolder(
      dir,
      frames: _ctrl.frames.map((f) => Uint8List.fromList(f)).toList(),
      passiveFrames: _ctrl.effectivePassiveCount,
      frameRate: _ctrl.frameRate,
      duration: _ctrl.duration,
      activeCycles: _ctrl.activeCycles,
      activeCooldown: _ctrl.activeCooldown,
      compress: _ctrl.compressBm,
    );
  }

  /// The export name: the current project name when saved, otherwise prompted.
  ///
  /// A prompted name is kept in [_lastExportName] and offered back the next
  /// time, because the folder pick that follows this can be cancelled or
  /// refused - and until #353 a refusal looked exactly like a cancellation, so
  /// the name the user had just typed was gone with no way to resume it.
  Future<String?> _resolveExportName() async {
    if (_projectName != null) return _projectName;
    final name = await _promptProjectName(
      initial: _lastExportName ?? _suggestedName(),
    );
    if (name != null) _lastExportName = name;
    return name;
  }

  /// Opens the system folder picker; returns null when cancelled and when the
  /// picker refused.
  ///
  /// The three export entry points await this *before* their own `try`, and
  /// each is reached from a sheet entry - so a rejection from here would have
  /// no listener anywhere and would land in the zone as a fatal uncaught
  /// error, which is the mechanism of QUNLEASHED-K. [pickFolder] is where that
  /// is held now: it never rejects, it reports the failure itself, and on
  /// Android and iOS it sees the refusal the plugin's own call swallowed.
  ///
  /// **The two nulls are not distinguishable, and the callers rely on that.**
  /// All three treat null as "cancelled" and return silently, which is right
  /// only because the refusal is reported before it answers. What they do keep
  /// across either one is the name [_resolveExportName] prompted for.
  Future<String?> _pickDestination() async {
    // Mounted first, because this one is reached *after* an await - the three
    // export paths resolve a name through a dialog above it - and the title is
    // read from the context here rather than inside [pickFolder]. On a page
    // the user left while the name prompt was open, `context.l10n` trips
    // `dependOnInheritedWidgetOfExactType`'s active-ancestor assertion, and
    // the three entry points are invoked bare from a sheet entry: nothing
    // would be listening to that throw. The other four sites read their title
    // synchronously from a tap.
    if (!mounted) return null;
    return pickFolder(
      context,
      what: '[Paint] the export folder pick',
      dialogTitle: context.l10n.paintChooseExportLocation,
    );
  }

  /// Binds the editor to [dirPath]/[name] as its project, redirecting autosave
  /// there. The throwaway autosave draft is removed only on the first save
  /// (promotion); a later rename forks a new folder and leaves the previous
  /// project untouched.
  Future<void> _adoptProjectFolder(String dirPath, String name) async {
    final wasUnsaved = _projectDir == null;
    final prevTarget = _draftDir;
    _projectDir = dirPath;
    _projectName = name;
    _draftDir = dirPath;
    if (wasUnsaved && prevTarget != null && prevTarget != dirPath) {
      try {
        final old = io.Directory(prevTarget);
        if (await old.exists()) await old.delete(recursive: true);
      } catch (e) {
        // The project is saved under its new name either way. What is left is
        // the draft it was saved from, which the library then lists beside it
        // as a second, older copy of the same drawing.
        LogService.warn('[Paint] left the draft "$prevTarget" behind: $e');
      }
    }
  }

  String _suggestedName() {
    final n = _ctrl.frames.length;
    return n > 1 ? 'animation_${n}f' : 'drawing';
  }

  /// Prompts for a project (folder) name, sanitizing the result to a safe
  /// folder name. Returns null when cancelled or left empty.
  ///
  /// The field lives in [_NamePrompt] so that its controller is disposed with
  /// the dialog's own route and not here. `showDialog`'s future completes when
  /// the route is *popped*, while its exit transition still has frames to run
  /// and anything that rebuilds this page rebuilds the dialog's subtree inside
  /// them - and `DeviceScope`'s five-second battery poll does exactly that. A
  /// `ctrl.dispose()` after the await therefore threw "A TextEditingController
  /// was used after being disposed" out of `build`, from every dismissal that
  /// a rebuild landed on. `test/paint_export_name_test.dart` is what found it,
  /// by being the first test to mount this page and close this dialog.
  Future<String?> _promptProjectName({String? initial}) async {
    if (!mounted) return null;
    final colors = context.appColors;
    final result = await showDialog<String>(
      context: context,
      barrierColor: colors.dialogBarrier,
      builder: (ctx) => _NamePrompt(initial: initial ?? '', colors: colors),
    );
    if (result == null) return null;
    final name = _sanitizeName(result);
    return name.isEmpty ? null : name;
  }

  static String _sanitizeName(String raw) {
    final cleaned = raw.trim().replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    return cleaned
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
  }

  Future<void> _showExportDialog() async {
    if (!mounted) return;
    final colors = context.appColors;
    final n = _ctrl.frames.length;

    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: colors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Text(
          context.l10n.paintExport,
          style: TextStyle(
            color: colors.textPrimary,
            fontWeight: FontWeight.w700,
          ),
        ),
        contentPadding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AlertTile(
              icon: Icons.folder_zip_outlined,
              title: context.l10n.paintExportDolphinTitle,
              subtitle: context.l10n.paintDolphinFrames(n),
              colors: colors,
              onTap: () {
                Navigator.pop(ctx);
                _exportDolphin();
              },
            ),
            if (n > 1)
              AlertTile(
                icon: Icons.gif_box_outlined,
                title: context.l10n.paintExportGifTitle,
                subtitle: context.l10n.paintGifFrames(n),
                colors: colors,
                onTap: () {
                  Navigator.pop(ctx);
                  _exportGif();
                },
              ),
            AlertTile(
              icon: Icons.image_outlined,
              title: context.l10n.paintExportPngTitle,
              subtitle: context.l10n.paintExportPngSubtitle,
              colors: colors,
              onTap: () {
                Navigator.pop(ctx);
                _exportPng();
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              context.l10n.commonCancel,
              style: TextStyle(color: colors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _onImport() async {
    try {
      // `withData: false` (the default); the bytes are read in Dart. See
      // `readPickedFile` for why. Sentry QUNLEASHED-E.
      final result = await FilePicker.platform.pickFiles(type: FileType.any);
      if (result == null || result.files.isEmpty) return;

      final file = result.files.first;
      final path = file.path;
      // Checked once, for every branch below. Every target this app ships
      // supplies a path.
      if (path == null) {
        if (!mounted) return;
        context.showNotification(
          context.l10n.paintNoFilePath,
          type: QNotificationType.error,
        );
        return;
      }

      if (file.name.toLowerCase() == 'meta.txt') {
        // Only the manifest is measured here. What bounds the import is the
        // frame walk itself, in `_importDolphinFromPath`, because that is
        // where the bytes are - a two-line `meta.txt` can name 256 frames.
        await ensurePickedFileFits(path, limit: _metaTextLimit);
        await _importDolphinFromPath(path);
        return;
      }

      // Decided on the extension before anything is read: there is nothing to
      // gain from pulling a picked video into memory to then turn it down.
      final decode = _decoderFor(file.extension?.toLowerCase() ?? '');
      if (decode == null) {
        if (!mounted) return;
        context.showNotification(
          context.l10n.paintUnsupportedType,
          type: QNotificationType.error,
        );
        return;
      }

      await decode(await readPickedFile(path, limit: _paintImportLimit));
    } on PickedFileTooLarge catch (e) {
      if (!mounted) return;
      context.showNotification(
        context.l10n.commonFileTooLarge(
          formatBytes(e.size),
          formatBytes(e.limit),
        ),
        type: QNotificationType.error,
      );
    } catch (e, st) {
      // The toast carries `$e`, which is the user's only feedback and is not
      // a sentence - and before this it was also the only record anywhere, so
      // a failed import reached nobody who could act on it. Reading the file
      // is now this method's own I/O, so there is more that can land here.
      LogService.caught(
        '[Paint] importing the picked file failed: ${LogService.describe(e, st)}',
      );
      if (!mounted) return;
      context.showNotification(
        context.l10n.paintImportFailed('$e'),
        type: QNotificationType.error,
      );
    }
  }

  Future<void> _importPng(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(
      bytes,
      targetWidth: kCanvasWidth,
      targetHeight: kCanvasHeight,
    );
    final frame = await codec.getNextFrame();
    final img = frame.image;
    final bd = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
    img.dispose();
    if (bd == null) return;

    final pix = Uint8List(kCanvasWidth * kCanvasHeight);
    BmCodec.rgbaToPixels(bd.buffer.asUint8List(), pix);
    _ctrl.importSinglePixelFrame(pix);

    if (!mounted) return;
    context.showNotification(
      context.l10n.paintPngImported,
      type: QNotificationType.good,
    );
  }

  Future<void> _importGif(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(
      bytes,
      targetWidth: kCanvasWidth,
      targetHeight: kCanvasHeight,
    );
    final count = codec.frameCount;
    if (count == 0) return;

    final newFrames = <Uint8List>[];
    for (int i = 0; i < count; i++) {
      final f = await codec.getNextFrame();
      final img = f.image;
      final bd = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
      img.dispose();
      if (bd == null) continue;
      final pix = Uint8List(kCanvasWidth * kCanvasHeight);
      BmCodec.rgbaToPixels(bd.buffer.asUint8List(), pix);
      newFrames.add(pix);
    }
    if (newFrames.isEmpty) return;

    _ctrl.importFramesFromPixels(newFrames);
    if (!mounted) return;
    context.showNotification(
      context.l10n.paintGifImported(newFrames.length),
      type: QNotificationType.good,
    );
  }

  Future<void> _importDolphinFromPath(String path) async {
    try {
      final metaFile = io.File(path);
      final animDir = metaFile.parent;
      final metaText = await metaFile.readAsString();

      final passiveFrames =
          BmCodec.parseDolphinInt(metaText, 'Passive frames') ?? 0;
      final activeFrames =
          BmCodec.parseDolphinInt(metaText, 'Active frames') ?? 0;

      // Frame dimensions can be smaller than our fixed canvas (e.g. 128×54).
      final width = BmCodec.parseDolphinInt(metaText, 'Width') ?? kCanvasWidth;
      final height =
          BmCodec.parseDolphinInt(metaText, 'Height') ?? kCanvasHeight;
      final expectedBytes = ((width + 7) >> 3) * height;

      final orderMatch = RegExp(
        r'^Frames order: (.+)$',
        multiLine: true,
      ).firstMatch(metaText);
      final orderStr = orderMatch?.group(1)?.trim() ?? '';

      int maxFrameIdx = (passiveFrames + activeFrames - 1).clamp(
        0,
        _maxDolphinFrameIdx,
      );
      if (orderStr.isNotEmpty) {
        for (final s in orderStr.split(RegExp(r'\s+'))) {
          final n = int.tryParse(s);
          if (n != null && n > maxFrameIdx) maxFrameIdx = n;
        }
      }
      // The clamp above was on the counted frames only, so a `Frames order`
      // naming frame 999999999 walked to it one `exists()` at a time - with
      // no frame files present the loop below neither finds nor breaks, and
      // the import hangs on a file the user picked. Same bound, both ways in.
      maxFrameIdx = maxFrameIdx.clamp(0, _maxDolphinFrameIdx);

      // What the walk will hold if every frame is there. The frames are the
      // import's real size - this is the cap `_onImport` could not apply to
      // the manifest, applied where the bytes are.
      final projected = expectedBytes * (maxFrameIdx + 1);
      if (projected > _paintImportLimit) {
        throw PickedFileTooLarge(projected, _paintImportLimit);
      }

      final newFrames = <Uint8List>[];
      for (int i = 0; i <= maxFrameIdx; i++) {
        final bmFile = io.File(pathJoin([animDir.path, 'frame_$i.bm']));
        if (!await bmFile.exists()) {
          if (newFrames.isNotEmpty) break;
          continue;
        }
        final bmData = await bmFile.readAsBytes();
        final xbm = BmCodec.decodeBmFile(bmData);
        if (xbm == null || xbm.length < expectedBytes) continue;
        newFrames.add(
          BmCodec.xbmToPixels(xbm, srcWidth: width, srcHeight: height),
        );
      }

      if (newFrames.isEmpty) {
        if (!mounted) return;
        context.showNotification(
          context.l10n.paintNoValidFrames,
          type: QNotificationType.error,
        );
        return;
      }

      _ctrl.importFramesFromPixels(
        newFrames,
        fr: BmCodec.parseDolphinInt(metaText, 'Frame rate') ?? 2,
        dur: BmCodec.parseDolphinInt(metaText, 'Duration') ?? 3600,
        ac: BmCodec.parseDolphinInt(metaText, 'Active cycles') ?? 1,
        acd: BmCodec.parseDolphinInt(metaText, 'Active cooldown') ?? 7,
        pfc: passiveFrames,
      );

      if (!mounted) return;
      context.showNotification(
        context.l10n.paintDolphinImported(newFrames.length),
        type: QNotificationType.good,
      );
    } catch (e) {
      if (!mounted) return;
      context.showNotification(
        context.l10n.paintImportDolphinFailed('$e'),
        type: QNotificationType.error,
      );
    }
  }

  Future<void> _importBmSingle(Uint8List data) async {
    final xbm = BmCodec.decodeBmFile(data);
    // Flipper bitmaps are 128px wide (16 bytes/row); infer the height from the
    // decoded size so non-64px-tall frames (e.g. 128×54) still import.
    const rowBytes = kCanvasWidth ~/ 8;
    if (xbm == null || xbm.length < rowBytes || xbm.length % rowBytes != 0) {
      if (!mounted) return;
      context.showNotification(
        context.l10n.paintInvalidBm,
        type: QNotificationType.error,
      );
      return;
    }
    final height = xbm.length ~/ rowBytes;
    _ctrl.importSinglePixelFrame(
      BmCodec.xbmToPixels(xbm, srcWidth: kCanvasWidth, srcHeight: height),
    );
    if (!mounted) return;
    context.showNotification(
      context.l10n.paintBmImported(_ctrl.currentFrame + 1),
      type: QNotificationType.good,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) => _close(),
      child: Scaffold(
        backgroundColor: colors.background,
        appBar: EditorAppBar(
          ctrl: _ctrl,
          onClose: _close,
          onSave: _saveProject,
          onExport: _showExportDialog,
          onImport: _onImport,
        ),
        body: LayoutBuilder(
          builder: (_, constraints) {
            // The rail + settings column need room of their own; below that the
            // phone stack reads better than three squeezed columns.
            final isWide =
                constraints.maxWidth > constraints.maxHeight &&
                constraints.maxWidth >= 640;
            return isWide
                ? _buildWideLayout(colors)
                : _buildNarrowLayout(colors);
          },
        ),
      ),
    );
  }

  /// Phone layout: the canvas takes every pixel the dock, the timeline and the
  /// animation settings leave it, so nothing scrolls out from under the finger.
  Widget _buildNarrowLayout(QAppColors colors) {
    return Column(
      children: [
        Expanded(child: CanvasView(ctrl: _ctrl)),
        ToolDock(ctrl: _ctrl, colors: colors),
        const SizedBox(height: 6),
        FramesSection(ctrl: _ctrl, colors: colors),
        AnimationPanel(ctrl: _ctrl, colors: colors),
      ],
    );
  }

  /// Desktop: tools down the left edge, the canvas taking the whole middle
  /// with its timeline beneath it, animation settings in a column on the right.
  Widget _buildWideLayout(QAppColors colors) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ToolRail(ctrl: _ctrl, colors: colors),
        VerticalDivider(width: 1, thickness: 1, color: colors.divider),
        Expanded(
          child: Column(
            children: [
              Expanded(child: CanvasView(ctrl: _ctrl)),
              Divider(height: 1, thickness: 1, color: colors.divider),
              FramesSection(ctrl: _ctrl, colors: colors),
            ],
          ),
        ),
        VerticalDivider(width: 1, thickness: 1, color: colors.divider),
        SizedBox(
          width: 300,
          child: SingleChildScrollView(
            child: Column(
              children: [
                AnimationPanel(ctrl: _ctrl, colors: colors),
                FrameActions(ctrl: _ctrl, colors: colors),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// The project-name dialog, which owns the field's controller.
///
/// Stateful for the controller's lifetime alone: a `State`'s `dispose` runs
/// when the route is actually removed, which is after the exit transition that
/// a controller disposed at the `showDialog` call site was still being
/// rebuilt in. [_PaintPageState._promptProjectName] has the failure.
///
/// **A holdout from `components/dialogs/name.dart`**, which is this skeleton
/// extracted (#266/#278) and which already owns its controller this way - the
/// failure above was rediscovered here rather than inherited. Converting is
/// not a refactor, though: `QNameDialog` takes a required device-shaped
/// `NameRule` and *refuses* a name the rule rejects, while this one sanitizes
/// whatever is typed into a folder name, and `name.dart`'s own doc names the
/// paint editor as the caller waiting on a host-shaped rule.
/// `test/name_prompt_budget_test.dart` counts the `showDialog<String>` sites
/// and still reads one for `pages/tools`, which is this.
class _NamePrompt extends StatefulWidget {
  const _NamePrompt({required this.initial, required this.colors});

  /// What the field starts with: the current project's name, the last name
  /// typed into the export prompt, or a suggestion.
  final String initial;

  final QAppColors colors;

  @override
  State<_NamePrompt> createState() => _NamePromptState();
}

class _NamePromptState extends State<_NamePrompt> {
  late final TextEditingController _ctrl = TextEditingController(
    text: widget.initial,
  );

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = widget.colors;
    return AlertDialog(
      backgroundColor: colors.dialogBackground,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      title: Text(
        context.l10n.paintProjectName,
        style: TextStyle(color: colors.dialogText),
      ),
      content: TextField(
        controller: _ctrl,
        autofocus: true,
        style: TextStyle(color: colors.dialogText),
        decoration: InputDecoration(
          hintText: context.l10n.paintProjectNameHint,
          hintStyle: TextStyle(color: colors.dialogMuted),
        ),
        onSubmitted: (v) => Navigator.pop(context, v),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(
            context.l10n.commonCancel,
            style: TextStyle(color: colors.textSecondary),
          ),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, _ctrl.text),
          child: Text(
            context.l10n.commonSave,
            style: TextStyle(color: colors.accent),
          ),
        ),
      ],
    );
  }
}

String _extensionOf(String path) {
  final name = path.replaceAll('\\', '/').split('/').last;
  final dot = name.lastIndexOf('.');
  return dot < 0 ? '' : name.substring(dot + 1).toLowerCase();
}
