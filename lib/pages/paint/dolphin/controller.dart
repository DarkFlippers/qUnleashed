import 'dart:async';

import 'package:flipperlib/flipperlib.dart';
import 'package:flutter/foundation.dart';

import '../manager/controller.dart' show kDeviceDolphinPath;
import '../project.dart';
import '../virtual_display_session.dart';
import 'dolphin_pack.dart';
import 'manifest.dart';

/// One selectable animation in the sync screen: a local [PaintProject] paired
/// with its editable [ManifestEntry] (selection + butthurt/level/weight).
class SyncItem {
  SyncItem(this.project, this.entry);
  final PaintProject project;
  final ManifestEntry entry;
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
  double? _progress;
  String? _status;
  String? _error;
  String? _previewId;
  int _previewToken = 0;

  List<SyncItem> get items => _items;
  bool get loading => _loading;
  bool get sending => _sending;
  double? get progress => _progress;
  String? get status => _status;
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
      _items = [
        for (final p in projects)
          SyncItem(p, _entryFor(p, manifest)),
      ];
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
      VirtualDisplaySession.instance.setPreview(preview.frames, preview.delayMs);
    } catch (_) {}
  }

  /// Uploads the selected animations and, finally, the combined manifest.
  ///
  /// The virtual display is suspended first so the RPC link is free for the
  /// transfer; it is resumed when the upload settles.
  Future<void> send() async {
    if (_sending) return;
    if (!_client.isConnected) {
      _error = 'No device connected';
      _notify();
      return;
    }
    final selected = _items.where((i) => i.entry.selected).toList();
    if (selected.isEmpty) {
      _error = 'Select at least one animation';
      _notify();
      return;
    }

    _sending = true;
    _error = null;
    _progress = 0;
    _status = 'Preparing…';
    _previewId = null;
    _notify();

    await VirtualDisplaySession.instance.suspend();

    try {
      final total = selected.length + 1; // animations + the final manifest
      for (var i = 0; i < selected.length; i++) {
        final item = selected[i];
        final name = item.entry.name;
        _status = 'Sending $name (${i + 1}/${selected.length})';
        _progress = i / total;
        _notify();

        final files = await DolphinPack.buildFiles(item.project);
        if (files.isEmpty) continue;

        final dir = '$kDeviceDolphinPath/$name';
        await _mkdirIgnoreExisting(dir);
        for (final f in files) {
          await _client.storageWriteChunked('$dir/${f.name}', f.bytes);
        }
      }

      _status = 'Writing manifest…';
      _progress = selected.length / total;
      _notify();
      final manifestText = DolphinManifest.build(
        selected.map((i) => i.entry),
      );
      await _client.storageWriteChunked(
        '$kDeviceDolphinPath/manifest.txt',
        manifestText.codeUnits,
      );

      _progress = 1;
      _status = 'Done';
      _notify();
    } catch (e) {
      _error = 'Send failed: $e';
      LogService.log('[ManifestSync] send failed: $e');
    } finally {
      _sending = false;
      _status = null;
      _progress = null;
      VirtualDisplaySession.instance.resume();
      _notify();
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
