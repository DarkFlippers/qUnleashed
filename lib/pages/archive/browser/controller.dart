import '../../../services/localization/l10n.dart';

import 'dart:async';
import 'dart:io' as io;

import 'package:crypto/crypto.dart';
import 'package:flipperlib/flipperlib.dart';
import 'package:flutter/foundation.dart';

import '../../../components/path.dart';
import '../../../services/progress_throttle.dart';
import '../../../services/storage/paths.dart';
import '../../../services/logging.dart';

class RemoteEntry {
  RemoteEntry({
    required this.name,
    required this.size,
    required this.isDir,
    this.pending = false,
  });

  final String name;
  final int size;
  final bool isDir;

  /// Still arriving: the row stands for a transfer into this folder and is
  /// not an entry the Flipper has listed yet.
  final bool pending;

  bool get isHidden => name.startsWith('.');

  String get extension {
    final dot = name.lastIndexOf('.');
    return dot < 0 ? '' : name.substring(dot + 1).toLowerCase();
  }
}

/// A file about to be written over one that is already in the destination.
class FileConflict {
  const FileConflict({
    required this.name,
    required this.size,
    required this.existingSize,
    required this.siblings,
  });

  /// Path relative to the destination folder of the transfer.
  final String name;
  final int size;
  final int existingSize;

  /// Names already present in the folder the file lands in, so a new name can
  /// be checked before it is tried.
  final Set<String> siblings;
}

enum ConflictAction { skip, replace, rename }

class ConflictChoice {
  const ConflictChoice.skip() : action = ConflictAction.skip, newName = null;
  const ConflictChoice.replace()
    : action = ConflictAction.replace,
      newName = null;
  const ConflictChoice.rename(String name)
    : action = ConflictAction.rename,
      newName = name;

  final ConflictAction action;
  final String? newName;
}

class ConflictResolution {
  const ConflictResolution({
    required this.choices,
    required this.skipIdentical,
  });

  /// One per conflict, in the order they were asked.
  final List<ConflictChoice> choices;

  /// Leave a file alone when its checksum matches the one being written.
  final bool skipIdentical;
}

/// Asked once per transfer, before anything is written. A null answer skips
/// every conflict.
typedef ConflictResolver = Future<ConflictResolution?> Function(
  String destination,
  int items,
  List<FileConflict> conflicts,
);

typedef _Listing = Map<String, ({bool isDir, int size})>;

class _Job {
  _Job({
    required this.item,
    required this.remote,
    required this.size,
    required this.run,
    this.existing,
    this.sourceMd5,
  });

  /// The entry of the destination folder this file belongs to: the file
  /// itself, or the top-level folder it sits under.
  final String item;
  final String remote;
  final int size;
  final _Listing? existing;
  final Future<String?> Function()? sourceMd5;
  final Future<bool> Function(
    String target,
    void Function(double progress) onProgress,
  )
  run;

  int? get existingSize {
    final hit = existing?[basename(remote)];
    return hit == null || hit.isDir ? null : hit.size;
  }
}

class _Outcome {
  final failed = <String>[];
  final skipped = <String>[];
  final failedItems = <String>{};
  final skippedItems = <String>{};

  void fail(_Job job) {
    failed.add(job.remote);
    failedItems.add(job.item);
  }

  void skip(_Job job) {
    skipped.add(job.remote);
    skippedItems.add(job.item);
  }
}

class _Transfer {
  _Transfer({required this.dir, required this.upload, this.label});

  final String dir;
  final bool upload;
  final Map<String, RemoteEntry> pending = {};
  String? label;
  double progress = 0;
  bool cancelled = false;
  String? busy;
  double busyProgress = 0;
}

/// How directory contents are ordered. Folders are always grouped ahead of
/// files; the mode controls ordering within each group.
enum FileSortMode { name, size, type }

enum FileViewMode { list, grid }

class FileManagerController extends ChangeNotifier {
  FileManagerController({required this._client, String initialPath = '/ext'})
    : _path = initialPath;

  /// How long a cancelled read is given to stop arriving before the firmware
  /// is taken not to know about cancelling at all.
  static const _cancelAcknowledgement = Duration(seconds: 8);

  final FlipperClient _client;
  final _unacknowledged = Expando<bool>();
  final Map<String, Future<String?>> _downloads = {};
  bool _disposed = false;
  String _path;
  bool _loading = false;
  String? _error;
  String? _lastFailure;
  List<RemoteEntry> _entries = const [];
  bool _showHidden = true;
  Future<void> _transfers = Future<void>.value();
  final Set<_Transfer> _active = {};
  _Transfer? _batch;
  FileSortMode _sortMode = FileSortMode.type;
  bool _sortAscending = true;
  FileViewMode _viewMode = FileViewMode.list;
  String _search = '';
  String? _lastRoot;

  FlipperClient get client => _client;
  String get path => _path;
  bool get loading => _loading;
  String? get error => _error;

  /// Why the last operation failed, in the device's own words.
  ///
  /// Separate from [error] because the two have different lifetimes. [error]
  /// describes the listing on screen, and a refresh replaces it. This
  /// describes something the user asked for - a delete, a rename, an upload -
  /// and a refresh is the *first* thing that follows one, so a field the
  /// refresh clears is one the page can never read. #110.
  ///
  /// Kept until the next failure. The page reads it beside the count it has
  /// already got, which is where the action ends.
  String? get lastFailure => _lastFailure;

  bool get showHidden => _showHidden;
  double get transferProgress => _batch?.progress ?? 0;
  String? get transferLabel => _batch?.label;
  bool get transferIsUpload => _batch?.upload ?? false;
  bool get cancelRequested => _batch?.cancelled ?? false;

  /// Whether the Flipper actually stopped the transfer that threw [e]. False
  /// when it went on sending past [_cancelAcknowledgement]: the transfer is
  /// then dropped from the screen without a word, since the firmware will
  /// finish it regardless and "cancelled" would be a lie. Asked of the
  /// exception rather than kept in a field, because transfers run side by
  /// side and each ends in its own cancel.
  bool cancelAcknowledged(FlipperCancelledException e) =>
      _unacknowledged[e] != true;

  void cancelTransfer() => _cancel(_batch);

  void cancelEntry(String name) => _cancel(_onEntry(name));

  bool entryCancelling(String name) => _onEntry(name)?.cancelled ?? false;

  /// Inline transfer progress (0..1) for the entry named [name] in the current
  /// directory while a transfer is working on it, or null when idle.
  double? entryProgress(String name) => _onEntry(name)?.busyProgress;

  void _cancel(_Transfer? transfer) {
    if (transfer == null || transfer.cancelled) return;
    transfer.cancelled = true;
    _notify();
  }

  _Transfer? _onEntry(String name) {
    for (final t in _active) {
      if (t.dir == _path && t.busy == name) return t;
    }
    return null;
  }

  FileSortMode get sortMode => _sortMode;
  bool get sortAscending => _sortAscending;
  FileViewMode get viewMode => _viewMode;
  bool get isSearching => _search.trim().isNotEmpty;

  /// The storage root (`/ext`, `/int`, …) that the current path lives under.
  String get _storageRoot {
    final trimmed = _path.startsWith('/') ? _path.substring(1) : _path;
    final slash = trimmed.indexOf('/');
    final first = slash < 0 ? trimmed : trimmed.substring(0, slash);
    return first.isEmpty ? '/' : '/$first';
  }

  int _compare(RemoteEntry a, RemoteEntry b) {
    final dir = _sortAscending ? 1 : -1;
    switch (_sortMode) {
      case FileSortMode.size:
        final c = a.size.compareTo(b.size);
        return (c != 0
                ? c
                : a.name.toLowerCase().compareTo(b.name.toLowerCase())) *
            dir;
      case FileSortMode.type:
        final c = a.extension.compareTo(b.extension);
        return (c != 0
                ? c
                : a.name.toLowerCase().compareTo(b.name.toLowerCase())) *
            dir;
      case FileSortMode.name:
        return a.name.toLowerCase().compareTo(b.name.toLowerCase()) * dir;
    }
  }

  List<RemoteEntry> _filtered(bool Function(RemoteEntry) test) {
    final q = _search.trim().toLowerCase();
    final listed = _entries.map((e) => e.name).toSet();
    final all = [
      ..._entries,
      for (final t in _active)
        if (t.dir == _path)
          ...t.pending.values.where((e) => !listed.contains(e.name)),
    ];
    final list = all.where((e) {
      if (!_showHidden && e.isHidden) return false;
      if (q.isNotEmpty && !e.name.toLowerCase().contains(q)) return false;
      return test(e);
    }).toList()..sort(_compare);
    return list;
  }

  /// Directories in the current folder, filtered + sorted.
  List<RemoteEntry> get _folders => _filtered((e) => e.isDir);

  /// Files in the current folder, filtered + sorted.
  List<RemoteEntry> get _files => _filtered((e) => !e.isDir);

  /// Folders followed by files.
  List<RemoteEntry> get entries => [..._folders, ..._files];

  bool get canGoUp => _path.length > 1 && _path != '/';

  void setSortMode(FileSortMode mode) {
    if (_sortMode == mode) {
      _sortAscending = !_sortAscending;
    } else {
      _sortMode = mode;
      _sortAscending = true;
    }
    _notify();
  }

  void toggleViewMode() {
    _viewMode = _viewMode == FileViewMode.list
        ? FileViewMode.grid
        : FileViewMode.list;
    _notify();
  }

  void setSearch(String value) {
    if (_search == value) return;
    _search = value;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  void toggleHidden() {
    _showHidden = !_showHidden;
    _notify();
  }

  Future<void> open(String newPath) async {
    _path = _normalize(newPath);
    await refresh();
  }

  Future<void> goUp() async {
    if (!canGoUp) return;
    final idx = _path.lastIndexOf('/');
    final parent = idx <= 0 ? '/' : _path.substring(0, idx);
    await open(parent);
  }

  String childPath(String name) => _join(_path, name);

  String _join(String dir, String name) =>
      dir.endsWith('/') ? '$dir$name' : '$dir/$name';

  String _relative(String dir, String remotePath) {
    final prefix = _join(dir, '');
    return remotePath.startsWith(prefix)
        ? remotePath.substring(prefix.length)
        : basename(remotePath);
  }

  /// Runs [body] as one task, bound to the Flipper it starts against.
  ///
  /// Every browse and transfer here is several device calls with waits between
  /// them - list, then read, then write, then list again - and the file tree
  /// they describe belongs to one Flipper. Bound, a copy that spans a device
  /// switch finishes where it began; unbound, its second half would be read
  /// from one Flipper and written to another.
  ///
  /// Not on the single-call operations. One request cannot be split across two
  /// devices: the session is resolved once, when it is sent.
  Future<T> _task<T>(Future<T> Function() body) =>
      _client.runTask(FlipperRequestPriority.background, body);

  /// Runs one transfer. Queued transfers wait for each other and own the
  /// progress bar; an unqueued one - a file opened or shared - runs alongside
  /// and shows only on its own row, so a long batch never blocks a tap.
  Future<T> _transfer<T>({
    required String dir,
    required bool upload,
    required bool batch,
    bool queued = true,
    required Future<T> Function(_Transfer t) body,
  }) {
    Future<T> run() => _task(() async {
      final t = _Transfer(
        dir: dir,
        upload: upload,
        label: batch ? l10n.fmPreparingTransfer : null,
      );
      _active.add(t);
      if (queued) _batch = t;
      _notify();
      try {
        return await body(t);
      } finally {
        _active.remove(t);
        if (identical(_batch, t)) _batch = null;
        _notify();
      }
    });
    if (!queued) return run();
    final previous = _transfers;
    final released = Completer<void>();
    _transfers = released.future;
    return previous.then((_) => run()).whenComplete(released.complete);
  }

  void _throwIfCancelled(_Transfer t, String path) {
    if (!t.cancelled) return;
    throw t.upload
        ? FlipperWriteCancelledException(path)
        : FlipperReadCancelledException(path);
  }

  void _track(_Transfer t, String item, {bool? isDir, int size = 0}) {
    t.busy = item;
    if (isDir != null) {
      t.pending[item] = RemoteEntry(
        name: item,
        size: size,
        isDir: isDir,
        pending: true,
      );
    }
    _notify();
  }

  void _transferFailed(String what, String path, Object e) {
    _error = _lastFailure = '$e';
    LogService.warn('[FileManager] $what $path failed: $e');
    _notify();
  }

  Future<_Outcome> _runJobs(
    _Transfer t,
    List<_Job> jobs, {
    required String Function(String name, int index, int total) label,
    Map<String, bool>? pendingDirs,
    ConflictResolver? resolve,
  }) async {
    final outcome = _Outcome();
    final skipped = <_Job>{};
    final renamed = <_Job, String>{};
    var skipIdentical = false;
    final conflicts = jobs.where((job) => job.existingSize != null).toList();
    if (conflicts.isNotEmpty && resolve != null) {
      final answer = await resolve(t.dir, jobs.length, [
        for (final c in conflicts)
          FileConflict(
            name: _relative(t.dir, c.remote),
            size: c.size,
            existingSize: c.existingSize!,
            siblings: c.existing!.keys.toSet(),
          ),
      ]);
      for (var i = 0; i < conflicts.length; i++) {
        final choice = answer?.choices[i] ?? const ConflictChoice.skip();
        switch (choice.action) {
          case ConflictAction.skip:
            skipped.add(conflicts[i]);
          case ConflictAction.replace:
            break;
          case ConflictAction.rename:
            renamed[conflicts[i]] = _join(
              dirname(conflicts[i].remote),
              choice.newName!,
            );
        }
      }
      skipIdentical = answer?.skipIdentical ?? false;
    }

    final progress = _BatchProgress(jobs);
    final throttle = ProgressThrottle();
    void publish() {
      t.progress = progress.overall;
      t.busyProgress = progress.item;
      if (throttle.shouldEmit(t.progress)) _notify();
    }

    if (jobs.length <= 1) t.label = null;
    for (var i = 0; i < jobs.length; i++) {
      final job = jobs[i];
      _throwIfCancelled(t, job.remote);
      progress.start(job);
      final replacing = job.existingSize != null && !renamed.containsKey(job);
      if (skipped.contains(job) ||
          (replacing && skipIdentical && await _sameContent(job))) {
        outcome.skip(job);
        progress.finish();
        publish();
        continue;
      }
      final target = renamed[job] ?? job.remote;
      final row =
          renamed.containsKey(job) && _relative(t.dir, job.remote) == job.item
          ? basename(target)
          : job.item;
      if (jobs.length > 1) {
        t.label = label(basename(target), i + 1, jobs.length);
      }
      t.busyProgress = progress.item;
      _track(t, row, isDir: pendingDirs?[job.item], size: progress.itemTotal);
      final ok = await job.run(target, (p) {
        progress.file = p;
        publish();
      });
      if (!ok) outcome.fail(job);
      progress.finish();
      publish();
    }
    return outcome;
  }

  Future<bool> _sameContent(_Job job) async {
    final source = await job.sourceMd5?.call();
    if (source == null) return false;
    final existing = await _remoteMd5(job.remote);
    return existing != null && existing == source.toLowerCase();
  }

  Future<String?> _remoteMd5(String remotePath) async {
    try {
      final batch = await _client.storageMd5sum(
        Md5sumRequest(path: remotePath),
        timeout: const Duration(seconds: 15),
      );
      final sum = batch.items.isEmpty
          ? ''
          : batch.items.first.md5sum.trim().toLowerCase();
      return sum.isEmpty ? null : sum;
    } catch (e) {
      LogService.warn('[FileManager] md5 $remotePath failed: $e');
      return null;
    }
  }

  Future<_Listing> _listing(String remoteDir) async {
    try {
      final batch = await _client.storageList(
        ListRequest(path: remoteDir),
        timeout: const Duration(seconds: 30),
      );
      return {
        for (final r in batch.items)
          for (final f in r.file)
            f.name: (isDir: f.type == File_FileType.DIR, size: f.size),
      };
    } catch (e) {
      LogService.warn('[FileManager] list $remoteDir failed: $e');
      return const {};
    }
  }

  /// The listing of [remoteDir] when [parent] already has a folder named
  /// [name] there, so files under it can be checked for conflicts.
  Future<_Listing?> _existingDir(
    _Listing? parent,
    String name,
    String remoteDir,
  ) async => parent?[name]?.isDir == true ? _listing(remoteDir) : null;

  Future<List<int>?> _read(
    _Transfer t,
    String remotePath,
    int expectedSize,
    void Function(double progress) onProgress,
  ) async {
    try {
      return await _client.storageReadChunked(
        remotePath,
        expectedSize: expectedSize,
        onProgress: onProgress,
        isCancelled: () => t.cancelled,
      );
    } on FlipperReadCancelledException catch (e) {
      final drained = await e.drained
          .then((_) => true)
          .timeout(_cancelAcknowledgement, onTimeout: () => false);
      if (!drained) _unacknowledged[e] = true;
      rethrow;
    } catch (e) {
      _transferFailed('read', remotePath, e);
      return null;
    }
  }

  Future<bool> _write(
    _Transfer t,
    String remotePath,
    List<int> data,
    void Function(double progress) onProgress,
  ) async {
    try {
      await _client.storageWriteChunked(
        remotePath,
        data,
        onProgress: onProgress,
        isCancelled: () => t.cancelled,
      );
      return true;
    } on FlipperCancelledException {
      rethrow;
    } catch (e) {
      _transferFailed('write', remotePath, e);
      return false;
    }
  }

  Future<String?> _saveLocal(
    String remotePath,
    List<int> bytes,
    Future<String> Function() localPath,
  ) async {
    try {
      final file = io.File(await localPath());
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes, flush: true);
      return file.path;
    } catch (e) {
      // The half after the device: a folder that cannot be made or a disk
      // with no room threw out of here into callers with no catch, so opening
      // a file in the editor on a full phone produced an unlabelled
      // [uncaught] and an editor that never opened. #110.
      _transferFailed('save', remotePath, e);
      return null;
    }
  }

  Future<void> _mkdirQuietly(String remotePath) async {
    try {
      await _client.storageMkdir(
        MkdirRequest(path: remotePath),
        timeout: const Duration(seconds: 15),
      );
    } catch (_) {
      // Destination directory may already exist; keep going.
    }
  }

  Future<void> refresh() => _task(_refresh);

  Future<void> _refresh() async {
    // Internal storage (`/int`) holds mostly dot-prefixed system files, so
    // reveal hidden entries automatically when first entering that root. The
    // user can still toggle them off afterwards.
    final root = _storageRoot;
    if (root != _lastRoot) {
      _lastRoot = root;
      if (root == '/int') _showHidden = true;
    }
    _loading = true;
    _error = null;
    _notify();
    try {
      final batch = await _client.storageList(
        ListRequest(path: _path),
        timeout: const Duration(seconds: 30),
      );
      final out = <RemoteEntry>[];
      for (final r in batch.items) {
        for (final f in r.file) {
          out.add(
            RemoteEntry(
              name: f.name,
              size: f.size,
              isDir: f.type == File_FileType.DIR,
            ),
          );
        }
      }
      _entries = out;
    } catch (e) {
      // Not _lastFailure: that one belongs to something the user asked for,
      // and the panel below already renders this one for as long as the
      // listing it describes is on screen.
      _error = '$e';
      _entries = const [];
      LogService.info('[FileManager] list $_path failed: $e');
    } finally {
      _loading = false;
      _notify();
    }
  }

  Future<List<int>?> readBytes(String remotePath) async {
    try {
      return await _client.storageReadChunked(
        remotePath,
        timeout: const Duration(minutes: 5),
      );
    } catch (e) {
      _error = _lastFailure = '$e';
      LogService.info('[FileManager] read $remotePath failed: $e');
      _notify();
      return null;
    }
  }

  Future<bool> writeBytes(String remotePath, List<int> data) {
    final name = basename(remotePath);
    return _transfer(
      dir: dirname(remotePath),
      upload: true,
      batch: false,
      body: (t) async {
        final outcome = await _runJobs(
          t,
          [
            _Job(
              item: name,
              remote: remotePath,
              size: data.length,
              run: (target, onProgress) => _write(t, target, data, onProgress),
            ),
          ],
          label: l10n.fmUploadingOf,
          pendingDirs: {name: false},
        );
        return outcome.failed.isEmpty;
      },
    );
  }

  Future<bool> delete(String remotePath, {bool recursive = false}) async {
    try {
      await _client.storageDelete(
        DeleteRequest(path: remotePath, recursive: recursive),
        timeout: const Duration(seconds: 60),
      );
      return true;
    } catch (e) {
      _error = _lastFailure = '$e';
      LogService.info('[FileManager] delete $remotePath failed: $e');
      _notify();
      return false;
    }
  }

  Future<bool> mkdir(String name) async {
    final target = childPath(name);
    try {
      await _client.storageMkdir(
        MkdirRequest(path: target),
        timeout: const Duration(seconds: 15),
      );
      return true;
    } catch (e) {
      _error = _lastFailure = '$e';
      LogService.info('[FileManager] mkdir $target failed: $e');
      _notify();
      return false;
    }
  }

  Future<bool> launchFap(String remotePath) async {
    try {
      await _client.appStart(
        StartRequest(name: remotePath, args: ''),
        timeout: const Duration(seconds: 15),
      );
      return true;
    } on FlipperRpcAppSystemLockedException {
      rethrow;
    } on FlipperRpcBusyException {
      rethrow;
    } catch (e) {
      _error = _lastFailure = '$e';
      LogService.info('[FileManager] appStart $remotePath failed: $e');
      _notify();
      return false;
    }
  }

  /// Copies [sources] - files and whole folders from anywhere on the Flipper -
  /// into the current directory, deleting each source afterwards when [move].
  /// Returns the number of sources that did not arrive whole.
  Future<int> copyInto(
    List<({String path, bool isDir, int size})> sources, {
    required bool move,
    ConflictResolver? resolve,
  }) {
    final dir = _path;
    return _transfer(
      dir: dir,
      upload: true,
      batch: sources.length > 1,
      body: (t) async {
        final here = await _listing(dir);
        final dirs = <String>[];
        final jobs = <_Job>[];
        final isDir = <String, bool>{};
        final unlisted = <String>{};
        for (final source in sources) {
          _throwIfCancelled(t, source.path);
          final name = basename(source.path);
          final dest = _join(dir, name);
          isDir[name] = source.isDir;
          if (!source.isDir) {
            jobs.add(
              _copyJob(t, source.path, dest, source.size, name, here, move),
            );
            continue;
          }
          if (sources.length == 1) _track(t, name, isDir: true);
          final existing = await _existingDir(here, name, dest);
          final itemDirs = <String>[];
          final itemJobs = <_Job>[];
          final listed = await _planCopy(
            t,
            source.path,
            dest,
            itemDirs,
            itemJobs,
            name,
            existing,
            move,
          );
          if (listed) {
            dirs.addAll(itemDirs);
            jobs.addAll(itemJobs);
          } else {
            unlisted.add(name);
          }
        }
        for (final d in dirs) {
          _throwIfCancelled(t, d);
          await _mkdirQuietly(d);
        }
        final outcome = await _runJobs(
          t,
          jobs,
          label: l10n.fmCopyingOf,
          pendingDirs: isDir,
          resolve: resolve,
        );
        var failures = unlisted.length + outcome.failedItems.length;
        if (!move) return failures;
        for (final source in sources) {
          final name = basename(source.path);
          if (!source.isDir ||
              unlisted.contains(name) ||
              outcome.failedItems.contains(name) ||
              outcome.skippedItems.contains(name)) {
            continue;
          }
          if (!await delete(source.path, recursive: true)) failures++;
        }
        return failures;
      },
    );
  }

  Future<bool> _planCopy(
    _Transfer t,
    String fromDir,
    String toDir,
    List<String> dirs,
    List<_Job> jobs,
    String item,
    _Listing? existing,
    bool move,
  ) async {
    dirs.add(toDir);
    try {
      final batch = await _client.storageList(
        ListRequest(path: fromDir),
        timeout: const Duration(seconds: 30),
      );
      for (final r in batch.items) {
        for (final f in r.file) {
          _throwIfCancelled(t, fromDir);
          final from = _join(fromDir, f.name);
          final to = _join(toDir, f.name);
          if (f.type == File_FileType.DIR) {
            final child = await _existingDir(existing, f.name, to);
            final listed = await _planCopy(
              t,
              from,
              to,
              dirs,
              jobs,
              item,
              child,
              move,
            );
            if (!listed) return false;
          } else {
            jobs.add(_copyJob(t, from, to, f.size, item, existing, move));
          }
        }
      }
      return true;
    } on FlipperCancelledException {
      rethrow;
    } catch (e) {
      _transferFailed('list', fromDir, e);
      return false;
    }
  }

  _Job _copyJob(
    _Transfer t,
    String from,
    String to,
    int size,
    String item,
    _Listing? existing,
    bool move,
  ) => _Job(
    item: item,
    remote: to,
    size: size,
    existing: existing,
    sourceMd5: () => _remoteMd5(from),
    run: (target, onProgress) async {
      final bytes = await _read(t, from, size, (p) => onProgress(p / 2));
      if (bytes == null) return false;
      if (!await _write(t, target, bytes, (p) => onProgress(0.5 + p / 2))) {
        return false;
      }
      return !move || await delete(from);
    },
  );

  Future<bool> rename(String oldPath, String newPath) async {
    try {
      await _client.storageRename(
        RenameRequest(oldPath: oldPath, newPath: newPath),
        timeout: const Duration(seconds: 30),
      );
      return true;
    } catch (e) {
      _error = _lastFailure = '$e';
      LogService.info('[FileManager] rename $oldPath failed: $e');
      _notify();
      return false;
    }
  }

  /// Reads [remotePath] for a receiver outside the app - a drag that landed
  /// elsewhere - alongside whatever else is running. Null when the read failed
  /// or [onCancel] fired first.
  Future<List<int>?> exportBytes(
    String remotePath, {
    int expectedSize = 0,
    Listenable? onCancel,
    void Function(double progress)? onProgress,
  }) async {
    try {
      return await _transfer(
        dir: dirname(remotePath),
        upload: false,
        batch: false,
        queued: false,
        body: (t) async {
          void cancel() => _cancel(t);
          onCancel?.addListener(cancel);
          List<int>? bytes;
          try {
            await _runJobs(t, [
              _Job(
                item: basename(remotePath),
                remote: remotePath,
                size: expectedSize,
                run: (_, progress) async {
                  bytes = await _read(t, remotePath, expectedSize, (p) {
                    progress(p);
                    onProgress?.call(p);
                  });
                  return bytes != null;
                },
              ),
            ], label: l10n.fmDownloadingOf);
          } finally {
            onCancel?.removeListener(cancel);
          }
          return bytes;
        },
      );
    } on FlipperCancelledException {
      return null;
    }
  }

  /// Downloads [remotePath] into the share cache. A call for a path already
  /// on its way joins that download: both would write the one cache file, and
  /// either could read it while the other truncates it.
  Future<String?> downloadTo(String remotePath, {int expectedSize = 0}) =>
      _downloads[remotePath] ??= _downloadToCache(remotePath, expectedSize)
          .whenComplete(() {
            // A block, not an arrow: remove() hands back this very future,
            // and whenComplete would then wait on it - on itself - forever.
            _downloads.remove(remotePath);
          });

  Future<String?> _downloadToCache(String remotePath, int expectedSize) =>
      _transfer(
        dir: dirname(remotePath),
        upload: false,
        batch: false,
        queued: false,
        body: (t) async {
          String? saved;
          await _runJobs(t, [
            _Job(
              item: basename(remotePath),
              remote: remotePath,
              size: expectedSize,
              run: (_, onProgress) async {
                final bytes = await _read(
                  t,
                  remotePath,
                  expectedSize,
                  onProgress,
                );
                if (bytes == null) return false;
                saved = await _saveLocal(remotePath, bytes, () async {
                  final dir = await _defaultDownloadDir(remotePath);
                  final sep = io.Platform.pathSeparator;
                  return '$dir$sep${basename(remotePath)}';
                });
                return saved != null;
              },
            ),
          ], label: l10n.fmDownloadingOf);
          return saved;
        },
      );

  /// Downloads [entries] from the current directory into [destDir] (files and
  /// whole directory trees, recreated recursively). A first pass enumerates the
  /// tree and sums file sizes so [transferProgress] reflects true byte-level
  /// progress across the whole batch (the read RPC streams frames, observed via
  /// [FlipperStorageApi.storageReadChunked]). Returns the number of files that
  /// failed to download.
  Future<int> downloadEntriesTo(
    List<RemoteEntry> entries, {
    required String destDir,
  }) {
    final dir = _path;
    return _transfer(
      dir: dir,
      upload: false,
      batch: entries.length > 1,
      queued: entries.length != 1 || entries.single.isDir,
      body: (t) async {
        final sep = io.Platform.pathSeparator;
        if (entries.length == 1) _track(t, entries.single.name);
        final jobs = <_Job>[];
        for (final e in entries) {
          final remote = _join(dir, e.name);
          final local = '$destDir$sep${e.name}';
          _throwIfCancelled(t, remote);
          final plan = <(String, String, int)>[];
          if (e.isDir) {
            await _planDownload(t, remote, local, plan);
          } else {
            plan.add((remote, local, e.size));
          }
          for (final (from, to, size) in plan) {
            jobs.add(
              _Job(
                item: e.name,
                remote: from,
                size: size,
                run: (_, onProgress) async {
                  final bytes = await _read(t, from, size, onProgress);
                  if (bytes == null) return false;
                  return await _saveLocal(from, bytes, () async => to) != null;
                },
              ),
            );
          }
        }
        final outcome = await _runJobs(t, jobs, label: l10n.fmDownloadingOf);
        return outcome.failed.length;
      },
    );
  }

  /// Recursively lists [remoteDir], creating local directories (so empty
  /// folders survive) and appending every file to [out] as (remote, local, size).
  Future<void> _planDownload(
    _Transfer t,
    String remoteDir,
    String localDir,
    List<(String, String, int)> out,
  ) async {
    final sep = io.Platform.pathSeparator;
    await io.Directory(localDir).create(recursive: true);
    try {
      final batch = await _client.storageList(
        ListRequest(path: remoteDir),
        timeout: const Duration(seconds: 30),
      );
      for (final r in batch.items) {
        for (final f in r.file) {
          _throwIfCancelled(t, remoteDir);
          final childRemote = _join(remoteDir, f.name);
          final childLocal = '$localDir$sep${f.name}';
          if (f.type == File_FileType.DIR) {
            await _planDownload(t, childRemote, childLocal, out);
          } else {
            out.add((childRemote, childLocal, f.size));
          }
        }
      }
    } on FlipperCancelledException {
      rethrow;
    } catch (e) {
      _transferFailed('list', remoteDir, e);
    }
  }

  /// Uploads [localPaths] - files and whole folders from this computer - into
  /// the current directory. Returns how many files were written and how many
  /// could not be.
  Future<({int files, int failed})> uploadLocal(
    List<String> localPaths, {
    ConflictResolver? resolve,
  }) {
    final dir = _path;
    return _transfer(
      dir: dir,
      upload: true,
      batch: localPaths.length > 1,
      body: (t) async {
        final here = await _listing(dir);
        final dirs = <String>[];
        final jobs = <_Job>[];
        final isDir = <String, bool>{};
        var missing = 0;
        for (final local in localPaths) {
          _throwIfCancelled(t, local);
          final name = basename(_normalize(local.replaceAll('\\', '/')));
          final remote = _join(dir, name);
          switch (await io.FileSystemEntity.type(local)) {
            case io.FileSystemEntityType.directory:
              isDir[name] = true;
              if (localPaths.length == 1) _track(t, name, isDir: true);
              final existing = await _existingDir(here, name, remote);
              await _planUpload(
                t,
                io.Directory(local),
                remote,
                dirs,
                jobs,
                name,
                existing,
              );
            case io.FileSystemEntityType.file:
              isDir[name] = false;
              final size = await io.File(local).length();
              jobs.add(_uploadJob(t, local, remote, size, name, here));
            default:
              _error = _lastFailure = l10n.fmLocalNotFound(local);
              _notify();
              missing++;
          }
        }
        for (final d in dirs) {
          _throwIfCancelled(t, d);
          await _mkdirQuietly(d);
        }
        final outcome = await _runJobs(
          t,
          jobs,
          label: l10n.fmUploadingOf,
          pendingDirs: isDir,
          resolve: resolve,
        );
        return (
          files: jobs.length - outcome.skipped.length,
          failed: outcome.failed.length + missing,
        );
      },
    );
  }

  Future<void> _planUpload(
    _Transfer t,
    io.Directory localDir,
    String remoteDir,
    List<String> dirs,
    List<_Job> jobs,
    String item,
    _Listing? existing,
  ) async {
    dirs.add(remoteDir);
    await for (final entity in localDir.list(followLinks: false)) {
      _throwIfCancelled(t, remoteDir);
      final name = basename(entity.path.replaceAll('\\', '/'));
      final remote = _join(remoteDir, name);
      if (entity is io.Directory) {
        final child = await _existingDir(existing, name, remote);
        await _planUpload(t, entity, remote, dirs, jobs, item, child);
      } else if (entity is io.File) {
        final size = await entity.length();
        jobs.add(_uploadJob(t, entity.path, remote, size, item, existing));
      }
    }
  }

  _Job _uploadJob(
    _Transfer t,
    String local,
    String remote,
    int size,
    String item,
    _Listing? existing,
  ) => _Job(
    item: item,
    remote: remote,
    size: size,
    existing: existing,
    sourceMd5: () async {
      try {
        return md5.convert(await io.File(local).readAsBytes()).toString();
      } catch (e) {
        LogService.warn('[FileManager] md5 $local failed: $e');
        return null;
      }
    },
    run: (target, onProgress) async {
      final List<int> bytes;
      try {
        bytes = await io.File(local).readAsBytes();
      } catch (e) {
        _transferFailed('read local', local, e);
        return false;
      }
      return _write(t, target, bytes, onProgress);
    },
  );

  Future<String> _defaultDownloadDir(String remotePath) async {
    final sep = io.Platform.pathSeparator;
    final relative = remotePath.startsWith('/')
        ? remotePath.substring(1)
        : remotePath;
    final parent = relative.contains('/')
        ? relative.substring(0, relative.lastIndexOf('/'))
        : '';
    final localParent = parent.replaceAll('/', sep);
    final root = await shareCacheDirectory();
    return pathJoin([root.path, localParent]);
  }

  String _normalize(String p) {
    if (p.isEmpty) return '/';
    while (p.length > 1 && p.endsWith('/')) {
      p = p.substring(0, p.length - 1);
    }
    return p;
  }
}

/// Byte-weighted progress over a batch, and over the entry of the destination
/// folder the current file belongs to.
class _BatchProgress {
  _BatchProgress(List<_Job> jobs) : _count = jobs.length {
    for (final job in jobs) {
      _total += job.size;
      _itemTotals[job.item] = (_itemTotals[job.item] ?? 0) + job.size;
    }
  }

  final int _count;
  int _total = 0;
  final _itemTotals = <String, int>{};
  final _itemDone = <String, int>{};
  int _done = 0;
  int _doneCount = 0;
  _Job? _job;
  double file = 0;

  int get itemTotal => _itemTotals[_job?.item] ?? 0;

  double get overall {
    final size = _job?.size ?? 0;
    if (_total > 0) return ((_done + size * file) / _total).clamp(0.0, 1.0);
    if (_count == 0) return 0;
    return ((_doneCount + file) / _count).clamp(0.0, 1.0);
  }

  double get item {
    final job = _job;
    if (job == null) return 0;
    final total = itemTotal;
    if (total <= 0) return file.clamp(0.0, 1.0);
    final done = _itemDone[job.item] ?? 0;
    return ((done + job.size * file) / total).clamp(0.0, 1.0);
  }

  void start(_Job job) {
    _job = job;
    file = 0;
  }

  void finish() {
    final job = _job;
    if (job == null) return;
    _done += job.size;
    _doneCount++;
    _itemDone[job.item] = (_itemDone[job.item] ?? 0) + job.size;
    file = 0;
  }
}
