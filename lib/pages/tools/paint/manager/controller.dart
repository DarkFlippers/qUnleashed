import '../../../../services/localization/l10n.dart';
import 'dart:async';
import 'dart:io' as io;

import 'package:flipperlib/flipperlib.dart';
import 'package:flutter/foundation.dart';

import '../../../../services/storage/paths.dart';
import '../dolphin/dolphin_pack.dart';
import '../dolphin/importer.dart';
import '../dolphin/manifest.dart';
import '../dolphin/sender.dart';
import '../project.dart';
import '../virtual_display_session.dart';
import '../../../../services/logging.dart';

/// Remote dolphin directory on the Flipper SD card.
const String kDeviceDolphinPath = '/ext/dolphin';

/// One animation in the library: the local project plus its manifest entry
/// (pack membership, weight, level and butthurt ranges).
class PaintItem {
  PaintItem(this.project, this.entry);
  final PaintProject project;
  final ManifestEntry entry;

  String get id => project.id;
}

/// Backs the whole Pixel Draw library screen: lists local projects (drawings,
/// GIFs, dolphin animations and drafts) with their manifest settings, imports
/// the device's animations, and sends the selected pack back to it.
class ProjectManagerController extends ChangeNotifier {
  ProjectManagerController({FlipperClient? client})
    : _client = client ?? FlipperOneClient().get() {
    _connSub = _client.connectionStream.listen((_) => _notify());
    VirtualDisplaySession.instance.enter();
  }

  final FlipperClient _client;
  StreamSubscription<FlipperConnectionState>? _connSub;
  bool _disposed = false;

  List<PaintItem> _items = const [];
  bool _loading = false;
  bool _importing = false;
  bool _sending = false;
  ImportProgress? _importProgress;
  SendProgress? _sendProgress;
  String? _selectedId;
  String? _error;

  List<PaintItem> get items => _items;
  bool get loading => _loading;
  bool get importing => _importing;
  bool get sending => _sending;
  bool get busy => _importing || _sending;
  ImportProgress? get importProgress => _importProgress;
  SendProgress? get sendProgress => _sendProgress;
  String? get error => _error;
  bool get isConnected => _client.isConnected;
  String? get selectedId => _selectedId;
  int get packCount => _items.where((i) => i.entry.selected).length;

  PaintItem? get selected {
    for (final i in _items) {
      if (i.id == _selectedId) return i;
    }
    return null;
  }

  /// Selects an animation: it becomes the one the details pane describes and
  /// the one mirrored on the device's external display.
  void select(String? id) {
    _selectedId = (_selectedId == id) ? null : id;
    _notify();
    _updateDevicePreview();
  }

  int _previewToken = 0;

  Future<void> _updateDevicePreview() async {
    final token = ++_previewToken;
    final project = selected?.project;
    if (project == null) {
      VirtualDisplaySession.instance.clearPreview();
      return;
    }
    try {
      final preview = await project.loadDevicePreview();
      if (token != _previewToken || _disposed) return;
      VirtualDisplaySession.instance.setPreview(
        preview.frames,
        preview.delayMs,
      );
    } catch (_) {}
  }

  /// Scans the local library, seeding each animation's manifest entry from the
  /// mirrored `manifest.txt` — or from the entry already on screen, so a reload
  /// never discards edits that have not been sent yet. When [silent] is true
  /// the loading spinner is suppressed.
  Future<void> loadAll({bool silent = false}) async {
    if (!silent) _loading = true;
    _error = null;
    _notify();
    try {
      final projects = await PaintProject.scanAll();
      final stored = await DolphinManifest.loadLocal();
      final current = {for (final i in _items) i.entry.name: i.entry};
      _items = [
        for (final p in projects) PaintItem(p, _entryFor(p, current, stored)),
      ];
    } catch (e) {
      _error = '$e';
      LogService.log('[PixelDraw] loadAll failed: $e');
    } finally {
      _loading = false;
      _notify();
    }
  }

  ManifestEntry _entryFor(
    PaintProject p,
    Map<String, ManifestEntry> current,
    Map<String, ManifestEntry> stored,
  ) {
    final name = DolphinPack.deviceName(p);
    final existing = current[name] ?? stored[name];
    if (existing != null) {
      existing.name = name;
      return existing;
    }
    return ManifestEntry(name: name);
  }

  /// Permanently deletes a project's folder, then reloads.
  Future<void> deleteProject(PaintProject project) async {
    try {
      final dir = io.Directory(project.path);
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
      if (_selectedId == project.id) {
        _selectedId = null;
        VirtualDisplaySession.instance.clearPreview();
      }
    } catch (e) {
      _error = l10n.paintDeleteFailed('$e');
      LogService.log('[PixelDraw] delete failed: $e');
    }
    await loadAll(silent: true);
  }

  // ---------------------------------------------------------------- manifest

  void toggleInPack(PaintItem item) {
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

  void setWeight(PaintItem item, int value) {
    item.entry.weight = value;
    _notify();
  }

  /// Updates an entry's level/butthurt range, keeping min ≤ max.
  void setLevels(PaintItem item, {int? min, int? max}) {
    final e = item.entry;
    if (min != null) e.minLevel = min.clamp(0, e.maxLevel);
    if (max != null) e.maxLevel = max < e.minLevel ? e.minLevel : max;
    _notify();
  }

  void setButthurt(PaintItem item, {int? min, int? max}) {
    final e = item.entry;
    if (min != null) e.minButthurt = min.clamp(0, e.maxButthurt);
    if (max != null) e.maxButthurt = max < e.minButthurt ? e.minButthurt : max;
    _notify();
  }

  /// The manifest text as it would be uploaded right now.
  String manifestText() => DolphinManifest.build(
    _items.where((i) => i.entry.selected).map((i) => i.entry),
  );

  /// Applies hand-edited manifest text: every animation listed there joins the
  /// pack with the settings from the text, everything else leaves it. Returns
  /// how many of the listed animations exist locally.
  int applyManifest(String text) {
    final parsed = DolphinManifest.parse(text);
    if (parsed.isEmpty) return 0;
    var applied = 0;
    for (final item in _items) {
      final edited = parsed[item.entry.name];
      if (edited == null) {
        item.entry.selected = false;
        continue;
      }
      item.entry
        ..selected = true
        ..minButthurt = edited.minButthurt
        ..maxButthurt = edited.maxButthurt
        ..minLevel = edited.minLevel
        ..maxLevel = edited.maxLevel
        ..weight = edited.weight;
      applied++;
    }
    _notify();
    return applied;
  }

  // ------------------------------------------------------------------ upload

  /// Uploads the pack and, finally, the combined manifest. The virtual display
  /// is suspended first so the RPC link is free for the transfer.
  Future<void> send() async {
    if (_sending) return;
    if (!_client.isConnected) {
      _error = l10n.paintNoDevice;
      _notify();
      return;
    }
    final selected = [
      for (final i in _items)
        if (i.entry.selected) (i.project, i.entry),
    ];
    if (selected.isEmpty) {
      _error = l10n.paintSelectAnimation;
      _notify();
      return;
    }

    _sending = true;
    _error = null;
    _sendProgress = null;
    _selectedId = null;
    _notify();

    await VirtualDisplaySession.instance.suspend();

    try {
      await DolphinSender.send(
        client: _client,
        selected: selected,
        onProgress: (p) {
          _sendProgress = p;
          _notify();
        },
      );
    } catch (e) {
      _error = l10n.paintSendFailed('$e');
      LogService.log('[PixelDraw] send failed: $e');
    } finally {
      _sending = false;
      _sendProgress = null;
      VirtualDisplaySession.instance.resume();
      _notify();
    }
  }

  // ------------------------------------------------------------------ import

  /// Mirrors the device's `/ext/dolphin` into the local library. Returns how
  /// many files were actually transferred — zero when everything already
  /// matched by md5. The work itself lives in [DolphinImporter]; the controller
  /// only owns the state it publishes.
  Future<int> importFromDevice() async {
    if (_importing) return 0;
    if (!_client.isConnected) {
      _error = l10n.paintNoDevice;
      _notify();
      return 0;
    }
    _importing = true;
    _importProgress = null;
    _error = null;
    _notify();

    var written = 0;
    try {
      final localRoot = await appDolphinAnimationsDirectory();
      written = await DolphinImporter.run(
        client: _client,
        localRoot: localRoot.path,
        onProgress: (p) {
          _importProgress = p;
          _notify();
        },
        onFolder: () => loadAll(silent: true),
      );
    } catch (e) {
      _error = l10n.paintImportFailed('$e');
      LogService.log('[PixelDraw] import failed: $e');
    } finally {
      _importing = false;
      _importProgress = null;
      _notify();
    }

    await loadAll(silent: true);
    return written;
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _connSub?.cancel();
    VirtualDisplaySession.instance.clearPreview();
    VirtualDisplaySession.instance.leave();
    super.dispose();
  }
}
