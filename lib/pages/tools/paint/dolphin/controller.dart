import '../../../../services/localization/l10n.dart';
import 'dart:async';

import 'package:crypto/crypto.dart';
import 'package:flipperlib/flipperlib.dart';
import 'package:flutter/foundation.dart';

import '../manager/controller.dart' show kDeviceDolphinPath;
import '../project.dart';
import '../virtual_display_session.dart';
import 'dolphin_pack.dart';
import 'manifest.dart';
import '../../../../services/logging.dart';
import '../../../../services/progress_throttle.dart';

/// One selectable animation in the sync screen: a local [PaintProject] paired
/// with its editable [ManifestEntry] (selection + butthurt/level/weight).
class SyncItem {
  SyncItem(this.project, this.entry);
  final PaintProject project;
  final ManifestEntry entry;
}

enum SendPhase { checking, sending }

/// Progress of a running [ManifestSyncController.send].
///
/// While checking, [current]/[total] count animations; while sending they count
/// files and [ratio] is byte-weighted over everything left to write, advanced
/// chunk by chunk from the local buffer as it is handed to the transport.
class SendProgress {
  SendProgress({
    required this.phase,
    required this.current,
    required this.total,
    required this.fileName,
    required this.ratio,
    this.fileProgress,
  });
  final SendPhase phase;
  final int current;
  final int total;
  final String fileName;
  final double ratio;
  final double? fileProgress;
}

class _PendingFile {
  _PendingFile({required this.dir, required this.name, required this.bytes});
  final String dir;
  final String name;
  final List<int> bytes;
}

/// Drives the "send dolphin pack to device" screen.
///
/// Lists every local project as a [SyncItem], seeding selection and per-animation
/// settings from the locally mirrored `manifest.txt`. Tapping a project mirrors
/// it on the device's virtual display; confirming uploads each selected animation
/// (`meta.txt` + `frame_*.bm`) under `/ext/dolphin`, then the combined manifest
/// last.
class ManifestSyncController extends ChangeNotifier {
  ManifestSyncController({FlipperClient? client})
    : _client = client ?? FlipperOneClient().get() {
    _connSub = _client.connectionStream.listen((_) => _notify());
  }

  final FlipperClient _client;
  StreamSubscription<FlipperConnectionState>? _connSub;
  bool _disposed = false;

  List<SyncItem> _items = const [];
  bool _loading = false;
  bool _sending = false;
  SendProgress? _progress;
  String? _error;
  String? _previewId;
  int _previewToken = 0;

  List<SyncItem> get items => _items;
  bool get loading => _loading;
  bool get sending => _sending;
  SendProgress? get progress => _progress;
  String? get error => _error;
  bool get isConnected => _client.isConnected;
  String? get previewId => _previewId;
  int get selectedCount => _items.where((i) => i.entry.selected).length;

  /// Loads the project list and seeds it from the local manifest mirror.
  Future<void> load() async {
    _loading = true;
    _error = null;
    _notify();
    try {
      final projects = await PaintProject.scanAll();
      final manifest = await DolphinManifest.loadLocal();
      _items = [for (final p in projects) SyncItem(p, _entryFor(p, manifest))];
    } catch (e) {
      _error = '$e';
      LogService.log('[ManifestSync] load failed: $e');
    } finally {
      _loading = false;
      _notify();
    }
  }

  /// Builds an entry for [p], reusing the manifest's settings when its device
  /// name is already listed (otherwise unselected with FAM defaults).
  ManifestEntry _entryFor(PaintProject p, Map<String, ManifestEntry> manifest) {
    final name = DolphinPack.deviceName(p);
    final existing = manifest[name];
    if (existing != null) {
      existing.name = name;
      return existing;
    }
    return ManifestEntry(name: name);
  }

  void toggleSelected(SyncItem item) {
    item.entry.selected = !item.entry.selected;
    _notify();
  }

  void selectAll() {
    for (final i in _items) {
      i.entry.selected = true;
    }
    _notify();
  }

  void deselectAll() {
    for (final i in _items) {
      i.entry.selected = false;
    }
    _notify();
  }

  void setWeight(SyncItem item, int value) {
    item.entry.weight = value;
    _notify();
  }

  /// Updates an entry's level/butthurt range, keeping min ≤ max.
  void setLevels(SyncItem item, {int? min, int? max}) {
    final e = item.entry;
    if (min != null) e.minLevel = min.clamp(0, e.maxLevel);
    if (max != null) e.maxLevel = max < e.minLevel ? e.minLevel : max;
    _notify();
  }

  void setButthurt(SyncItem item, {int? min, int? max}) {
    final e = item.entry;
    if (min != null) e.minButthurt = min.clamp(0, e.maxButthurt);
    if (max != null) e.maxButthurt = max < e.minButthurt ? e.minButthurt : max;
    _notify();
  }

  /// Mirrors [item] on the device's external (virtual) display. A second tap on
  /// the same project clears it.
  Future<void> mirror(SyncItem item) async {
    final token = ++_previewToken;
    if (_previewId == item.project.id) {
      _previewId = null;
      VirtualDisplaySession.instance.clearPreview();
      _notify();
      return;
    }
    _previewId = item.project.id;
    _notify();
    try {
      final preview = await item.project.loadDevicePreview();
      if (token != _previewToken || _disposed) return;
      VirtualDisplaySession.instance.setPreview(
        preview.frames,
        preview.delayMs,
      );
    } catch (_) {}
  }

  /// Uploads the selected animations and, finally, the combined manifest.
  ///
  /// Every file is md5-checked against its counterpart on the device first, so
  /// only the ones that really differ are written.
  ///
  /// The virtual display is suspended first so the RPC link is free for the
  /// transfer; it is resumed when the upload settles.
  Future<void> send() async {
    if (_sending) return;
    if (!_client.isConnected) {
      _error = l10n.paintNoDevice;
      _notify();
      return;
    }
    final selected = _items.where((i) => i.entry.selected).toList();
    if (selected.isEmpty) {
      _error = l10n.paintSelectAnimation;
      _notify();
      return;
    }

    _sending = true;
    _error = null;
    _progress = null;
    _previewId = null;
    _notify();

    await VirtualDisplaySession.instance.suspend();

    try {
      await _writePending(await _planUpload(selected));
    } catch (e) {
      _error = l10n.paintSendFailed('$e');
      LogService.log('[ManifestSync] send failed: $e');
    } finally {
      _sending = false;
      _progress = null;
      VirtualDisplaySession.instance.resume();
      _notify();
    }
  }

  /// Compares every file of every selected animation — and the manifest — with
  /// its md5 on the device, returning only the ones that really differ.
  Future<List<_PendingFile>> _planUpload(List<SyncItem> selected) async {
    final pending = <_PendingFile>[];
    final total = selected.length + 1; // animations + the manifest
    for (var i = 0; i < selected.length; i++) {
      final item = selected[i];
      final name = item.entry.name;
      _publishChecking(i, total, name);

      final files = await DolphinPack.buildFiles(item.project);
      if (files.isEmpty) continue;

      final dir = '$kDeviceDolphinPath/$name';
      final remote = await _remoteMd5s(dir);
      for (final f in files) {
        if (remote[f.name] != _md5(f.bytes)) {
          pending.add(_PendingFile(dir: dir, name: f.name, bytes: f.bytes));
        }
      }
    }

    const manifestName = 'manifest.txt';
    _publishChecking(selected.length, total, manifestName);
    final manifestBytes = DolphinManifest.build(
      selected.map((i) => i.entry),
    ).codeUnits;
    if (await _remoteMd5('$kDeviceDolphinPath/$manifestName') !=
        _md5(manifestBytes)) {
      pending.add(
        _PendingFile(
          dir: kDeviceDolphinPath,
          name: manifestName,
          bytes: manifestBytes,
        ),
      );
    }
    return pending;
  }

  /// Writes [pending] in order, advancing progress per chunk handed to the
  /// transport: the ratio comes from the local buffers alone, so it never waits
  /// on the device to report anything back.
  Future<void> _writePending(List<_PendingFile> pending) async {
    final totalBytes = pending.fold<int>(0, (s, f) => s + f.bytes.length);
    final throttle = ProgressThrottle();
    final created = <String>{};
    var doneBytes = 0;

    for (var i = 0; i < pending.length; i++) {
      final f = pending[i];
      if (f.dir != kDeviceDolphinPath && created.add(f.dir)) {
        await _mkdirIgnoreExisting(f.dir);
      }
      throttle.reset();
      _publishSending(i, pending.length, f, doneBytes, totalBytes, 0);

      await _client.storageWriteChunked(
        '${f.dir}/${f.name}',
        f.bytes,
        onProgress: (p) {
          if (!throttle.shouldEmit(p)) return;
          _publishSending(i, pending.length, f, doneBytes, totalBytes, p);
        },
      );

      _publishSending(i, pending.length, f, doneBytes, totalBytes, 1);
      doneBytes += f.bytes.length;
    }
  }

  void _publishChecking(int current, int total, String fileName) {
    _progress = SendProgress(
      phase: SendPhase.checking,
      current: current,
      total: total,
      fileName: fileName,
      ratio: total == 0 ? 0 : (current / total).clamp(0.0, 1.0),
    );
    _notify();
  }

  void _publishSending(
    int index,
    int total,
    _PendingFile file,
    int doneBytes,
    int totalBytes,
    double fileProgress,
  ) {
    _progress = SendProgress(
      phase: SendPhase.sending,
      current: index + 1,
      total: total,
      fileName: file.name,
      ratio: totalBytes <= 0
          ? 1
          : ((doneBytes + fileProgress * file.bytes.length) / totalBytes).clamp(
              0.0,
              1.0,
            ),
      fileProgress: fileProgress,
    );
    _notify();
  }

  static String _md5(List<int> bytes) =>
      md5.convert(bytes).toString().toLowerCase();

  /// Remote md5 of every file directly inside [dir], keyed by file name. Empty
  /// when the folder does not exist yet or the listing fails.
  Future<Map<String, String>> _remoteMd5s(String dir) async {
    try {
      final batch = await _client.storageList(
        ListRequest(path: dir, includeMd5: true),
        timeout: const Duration(seconds: 30),
      );
      return {
        for (final r in batch.items)
          for (final f in r.file)
            if (f.type == File_FileType.FILE && f.name.isNotEmpty)
              f.name: f.md5sum.trim().toLowerCase(),
      };
    } catch (e) {
      LogService.log('[ManifestSync] md5 list $dir failed: $e');
      return const {};
    }
  }

  Future<String> _remoteMd5(String path) async {
    try {
      final batch = await _client.storageMd5sum(
        Md5sumRequest(path: path),
        timeout: const Duration(seconds: 15),
      );
      return (batch.items.isNotEmpty ? batch.items.first.md5sum : '')
          .trim()
          .toLowerCase();
    } catch (e) {
      LogService.log('[ManifestSync] md5 $path failed: $e');
      return '';
    }
  }

  Future<void> _mkdirIgnoreExisting(String path) async {
    try {
      await _client.storageMkdir(MkdirRequest(path: path));
    } catch (_) {
      // Folder already exists (or another benign error): files are written with
      // CREATE_ALWAYS, so an overwrite proceeds regardless.
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _connSub?.cancel();
    VirtualDisplaySession.instance.clearPreview();
    VirtualDisplaySession.instance.resume();
    super.dispose();
  }
}
