import 'dart:async';
import 'dart:io' as io;
import 'dart:isolate';

import 'package:archive/archive_io.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../../../components/archive_unpack.dart';
import '../../../components/path.dart';
import '../../../services/http/app_http.dart';
import '../../../services/localization/l10n.dart';
import '../../../services/logging.dart';
import '../../../services/storage/paths.dart';

class IrLibDownloadProgress {
  IrLibDownloadProgress({
    required this.stage,
    this.received = 0,
    this.total = 0,
    this.extracted = 0,
    this.totalFiles = 0,
  });

  final String stage;
  final int received;
  final int total;
  final int extracted;
  final int totalFiles;

  bool get isExtracting => totalFiles > 0;

  double get fraction {
    if (totalFiles > 0) {
      return (extracted / totalFiles).clamp(0.0, 1.0);
    }
    if (total > 0) {
      return (received / total).clamp(0.0, 1.0);
    }
    if (received > 0) {
      final mb = received / (1024 * 1024);
      return (mb / (mb + 8)).clamp(0.02, 0.92);
    }
    return 0.0;
  }
}

class IrLibLocalRepo {
  IrLibLocalRepo();

  static io.Directory? _cachedRoot;

  /// Serialises everything that moves the library or its staging trees.
  ///
  /// A page builds its own controller, so a second page opened during a
  /// refresh brings a second repo along, and these are process-wide
  /// directories. Two refreshes at once shared one staging path, so the later
  /// one deleted the tree the earlier was still unpacking into - and the
  /// unpack does not notice, because its created-directory cache will not
  /// re-make a parent it has already seen, so entries land in `skipped` and,
  /// if few enough clear the tolerance, a truncated library is sworn in as a
  /// whole one. A delete racing a refresh did the same.
  ///
  /// Held across the whole of a refresh or a delete, so they queue rather than
  /// interleave.
  static Future<void> _chain = Future<void>.value();

  /// True while [_exclusive] is running something, so recovery can decline
  /// rather than queue behind a download it would otherwise wait out.
  static bool _busy = false;

  static Future<T> _exclusive<T>(Future<T> Function() body) {
    final previous = _chain;
    final released = Completer<void>();
    _chain = released.future;
    return previous
        .then((_) async {
          _busy = true;
          try {
            return await body();
          } finally {
            _busy = false;
          }
        })
        .whenComplete(released.complete);
  }

  /// Points the library at [dir] for the duration of a test, and clears the
  /// refresh flag so one test cannot strand the next.
  @visibleForTesting
  static void debugUseRoot(io.Directory? dir) {
    _cachedRoot = dir;
    _busy = false;
    _chain = Future<void>.value();
  }

  Future<io.Directory> resolveRoot() async {
    final cached = _cachedRoot;
    if (cached != null) return cached;
    final dir = await irLibRepositoryDirectory();
    _cachedRoot = dir;
    return dir;
  }

  Future<bool> exists() async {
    final dir = await resolveRoot();
    await recoverInterrupted(dir);
    if (!await dir.exists()) return false;
    await for (final _ in dir.list(followLinks: false)) {
      return true;
    }
    return false;
  }

  Future<DateTime?> lastModified() async {
    final dir = await resolveRoot();
    if (!await dir.exists()) return null;
    try {
      final stat = await dir.stat();
      return stat.modified;
    } catch (_) {
      return null;
    }
  }

  Future<void> deleteAll() async {
    final dir = await resolveRoot();
    // Under the lock: a delete that ran beside a refresh took the staging tree
    // out from under its unpack.
    await _exclusive(() => _deleteAll(dir));
  }

  static Future<void> _deleteAll(io.Directory dir) async {
    // Sidecars first, the library last. The other order leaves root missing
    // while .superseded still stands - the exact signature recoverInterrupted
    // reads as an interrupted swap - so anything that stopped the delete part
    // way through would hand the previous library back as though nothing had
    // been asked for.
    for (final target in [
      _sidecar(dir, _kIncomingSuffix),
      ...await _supersededTrees(dir),
      dir,
    ]) {
      if (!await target.exists()) continue;
      try {
        await target.delete(recursive: true);
      } on io.PathNotFoundException {
        continue;
      }
    }
  }

  Future<io.Directory> download({
    required String owner,
    required String repo,
    required String branch,
    String token = '',
    void Function(IrLibDownloadProgress)? onProgress,
  }) async {
    final root = await resolveRoot();
    await recoverInterrupted(root);
    return _exclusive(() async {
      // Built beside the library rather than over it. The old one stays whole
      // and usable until there is a complete replacement to put in its place -
      // a refresh that fails for any reason now costs the user nothing, where
      // before it cost them the library they already had.
      final incoming = _sidecar(root, _kIncomingSuffix);
      // Not redundant with the recovery above: that one logs and carries on when
      // a delete fails, so a tree it could not clear would otherwise be unpacked
      // straight over.
      if (await incoming.exists()) await incoming.delete(recursive: true);
      await incoming.create(recursive: true);

      onProgress?.call(IrLibDownloadProgress(stage: l10n.irDownloading));

      final url = Uri.parse(
        'https://codeload.github.com/$owner/$repo/zip/refs/heads/$branch',
      );
      final tempDir = await getTemporaryDirectory();
      final sep = io.Platform.pathSeparator;
      final tempZip = io.File(
        '${tempDir.path}${sep}irdb-${DateTime.now().millisecondsSinceEpoch}.zip',
      );
      var received = 0;
      var total = 0;
      await AppHttp.downloadToFile(
        url,
        tempZip.path,
        headers: {
          io.HttpHeaders.userAgentHeader: 'qunleashed-irlib',
          if (token.trim().isNotEmpty)
            io.HttpHeaders.authorizationHeader: 'Bearer ${token.trim()}',
        },
        onProgress: (bytes, totalBytes) {
          received = bytes;
          total = totalBytes ?? 0;
          onProgress?.call(
            IrLibDownloadProgress(
              stage: l10n.irDownloading,
              received: received,
              total: total,
            ),
          );
        },
      );

      onProgress?.call(
        IrLibDownloadProgress(
          stage: l10n.irUnpacking,
          received: received,
          total: total,
        ),
      );

      try {
        await _unpackInIsolate(
          zipPath: tempZip.path,
          rootPath: incoming.path,
          sep: sep,
          onProgress: (extracted, totalFiles, done) {
            onProgress?.call(
              IrLibDownloadProgress(
                stage: done ? l10n.irDone : l10n.irUnpacking,
                received: received,
                total: total,
                extracted: extracted,
                totalFiles: totalFiles,
              ),
            );
          },
        );
      } finally {
        if (await tempZip.exists()) {
          try {
            await tempZip.delete();
          } catch (_) {}
        }
      }

      await swapIn(root, incoming);
      return root;
    });
  }

  static const String _kIncomingSuffix = '.incoming';
  static const String _kSupersededPrefix = '.superseded';

  /// A name no other swap will pick.
  ///
  /// One fixed name meant the tree being deleted in the background and the
  /// destination the next swap renames into were the same path. A delete that
  /// failed part way - one locked file is enough, and a blocked recursive
  /// delete removes what it reached before it stopped - then left something
  /// standing there, and every later refresh died renaming onto it. That is
  /// not recoverable by retrying: it wedges the library until someone finds a
  /// hidden directory and removes it by hand. A fresh name each time means a
  /// leftover can only ever be swept up, never collided with.
  static io.Directory _freshSuperseded(io.Directory root) => io.Directory(
    '${root.path}$_kSupersededPrefix.${DateTime.now().microsecondsSinceEpoch}',
  );

  /// Every superseded tree beside the library, newest first.
  static Future<List<io.Directory>> _supersededTrees(io.Directory root) async {
    final parent = root.parent;
    if (!await parent.exists()) return const [];
    final prefix = '${basename(root.path)}$_kSupersededPrefix';
    final found = <io.Directory>[];
    await for (final entity in parent.list(followLinks: false)) {
      if (entity is io.Directory && basename(entity.path).startsWith(prefix)) {
        found.add(entity);
      }
    }
    found.sort((a, b) => b.path.compareTo(a.path));
    return found;
  }

  /// Where the staging trees live: beside the library, never inside it.
  ///
  /// Beside matters. Staging in the OS temp directory would read as tidier and
  /// is the natural thing to reach for, but it can land on a different mount —
  /// plausible on Android — and dart:io's rename does not copy across
  /// filesystems, it fails EXDEV outright. Staging stays on the volume it is
  /// going to land on.
  static io.Directory _sidecar(io.Directory root, String suffix) =>
      io.Directory('${root.path}$suffix');

  /// Puts the superseded tree back where the library belongs.
  ///
  /// Returns whether it landed. Both the rollback inside [swapIn] and the
  /// repair in [recoverInterrupted] are this same move, and the caller has to
  /// know whether it worked: at that moment the superseded tree is the only
  /// copy of the library there is.
  static Future<bool> _restoreSuperseded(
    io.Directory root,
    io.Directory superseded,
  ) async {
    try {
      await superseded.rename(root.path);
      return true;
    } catch (e) {
      LogService.error('[IrLib] could not put the library back: $e');
      return false;
    }
  }

  /// Puts a freshly unpacked tree in place of the library.
  ///
  /// Three renames rather than the one this reads like it should need: no
  /// platform will rename a directory onto a populated one. Windows throws
  /// PathExistsException — for an empty destination as well — and POSIX
  /// `rename(2)` replaces only an empty directory and fails ENOTEMPTY
  /// otherwise, which is exactly the state the old library is in. So the old
  /// tree is moved aside first, and all three are metadata operations.
  ///
  /// Deleting the superseded tree is the expensive part, and it is what used
  /// to be on the critical path. It runs unawaited afterwards, and a run that
  /// dies before it finishes leaves a directory [recoverInterrupted] clears
  /// next time.
  static Future<void> swapIn(io.Directory root, io.Directory incoming) async {
    // Named for this swap alone, so it cannot be the tree a previous swap is
    // still deleting in the background. Nothing has to be cleared first.
    final superseded = _freshSuperseded(root);

    final hadLibrary = await root.exists();
    if (hadLibrary) await root.rename(superseded.path);
    try {
      await incoming.rename(root.path);
    } catch (_) {
      // The only moment there is no library at all. Put the old one back
      // rather than leave the user with nothing, and let the original failure
      // be the one that surfaces.
      if (hadLibrary && !await root.exists()) {
        await _restoreSuperseded(root, superseded);
      }
      rethrow;
    }

    if (!hadLibrary) return;
    unawaited(
      superseded.delete(recursive: true).catchError(
        (Object e) {
          // Costs disk, not correctness: the tree is named for this swap, so
          // a leftover is swept up by the next recovery rather than collided
          // with. Failing a finished download over it would be worse.
          LogService.error('[IrLib] could not remove the old library: $e');
          return superseded;
        },
        // Narrow, so a fault in this path is not quietly turned into a no-op
        // by a handler meant for the filesystem refusing a delete.
        test: (Object e) => e is io.FileSystemException,
      ),
    );
  }

  /// Repairs whatever a process that died mid-refresh left behind.
  ///
  /// The swap is only as atomic as two renames back to back, so there is a
  /// window — short, but not nothing — where the library has been moved aside
  /// and its replacement is not yet in place. Dying there is the one case that
  /// loses data, so it is the one checked first.
  static Future<void> recoverInterrupted(io.Directory root) async {
    // Nothing beside the library is leftover while something is using it.
    if (_busy) return;

    final incoming = _sidecar(root, _kIncomingSuffix);
    final superseded = await _supersededTrees(root);

    // The newest is the one the interrupted swap set aside; anything older is
    // a background delete that never finished.
    var kept = <io.Directory>[];
    if (!await root.exists() && superseded.isNotEmpty) {
      final live = superseded.first;
      if (await _restoreSuperseded(root, live)) {
        LogService.log(
          '[IrLib] put the library back after an interrupted swap',
        );
      } else {
        // It is the only copy of the library there is, which is the whole
        // reason the restore was being attempted. Leaving it costs disk and
        // the next run tries again; deleting it is the one thing this routine
        // must never do - and a failed recursive delete is not a no-op either,
        // since one locked file stops it having already removed what it
        // reached first.
        kept = [live];
      }
    }

    final leftovers = [
      incoming,
      for (final tree in superseded)
        if (!kept.contains(tree)) tree,
    ];

    // A restore consumes the tree it moved, so it is gone by now.
    for (final leftover in leftovers) {
      if (!await leftover.exists()) continue;
      try {
        await leftover.delete(recursive: true);
      } catch (e) {
        LogService.error('[IrLib] could not clear ${leftover.path}: $e');
      }
    }
  }

  /// Inflates the IR database zip and writes every entry to disk inside a
  /// background isolate. Unpacking thousands of files must never block the UI
  /// isolate; progress is streamed back over a [SendPort].
  static Future<void> _unpackInIsolate({
    required String zipPath,
    required String rootPath,
    required String sep,
    required void Function(int extracted, int totalFiles, bool done) onProgress,
  }) async {
    final receivePort = ReceivePort();
    final errorPort = ReceivePort();
    final done = Completer<void>();

    receivePort.listen((msg) {
      if (msg is _UnpackTick) {
        onProgress(msg.extracted, msg.totalFiles, false);
        return;
      }
      if (msg is! _UnpackResult || done.isCompleted) return;

      final tally = msg.tally;
      if (tally.skipped > 0 || tally.dropped > 0) {
        LogService.log(
          '[IrLib] unpacked ${tally.extracted}, skipped ${tally.skipped}, '
          'dropped ${tally.dropped} (first: ${tally.firstError})',
        );
      }

      // Deciding here rather than in the isolate: this side owns the Completer
      // and the only localized vocabulary in the flow, so the isolate stays a
      // worker that reports what happened instead of throwing a hardcoded
      // English sentence at the user through StateError.toString().
      final failure = failureFor(tally, msg.totalFiles);
      if (failure != null) {
        done.completeError(StateError(l10n.irUnpackFailed(failure)));
        return;
      }
      onProgress(tally.extracted, msg.totalFiles, true);
      done.complete();
    });
    errorPort.listen((msg) {
      if (done.isCompleted) return;
      final error = (msg is List && msg.isNotEmpty) ? msg.first : msg;
      done.completeError(StateError(l10n.irUnpackFailed('$error')));
    });

    final isolate = await Isolate.spawn(
      _unpackIsolateEntry,
      _UnpackArgs(zipPath, rootPath, sep, receivePort.sendPort),
      onError: errorPort.sendPort,
      errorsAreFatal: true,
      debugName: 'irlib-unpack',
    );

    try {
      await done.future;
    } finally {
      isolate.kill(priority: Isolate.beforeNextEvent);
      receivePort.close();
      errorPort.close();
    }
  }

  /// How many unwritable entries a successful unpack may hide.
  ///
  /// The per-entry handler exists so a few pathological names do not cost the
  /// user the whole library. Past that the cause is systemic - a full disk, a
  /// revoked permission - and the result is a truncated library replacing the
  /// good one [download] already deleted, so it has to fail as loudly as it
  /// used to. Floor and share both matter: a fixed count alone hair-triggers
  /// on a small archive, a share alone lets a big library lose hundreds of
  /// files quietly.
  static const int _skipFloor = 10;
  static const double _skipShare = 0.01;

  /// Why [tally] should be reported as a failure, or null if it succeeded.
  ///
  /// Public so the policy can be tested directly: it is the one piece of this
  /// flow that decides whether the user keeps a library or gets an error, and
  /// it runs on the far side of an isolate boundary from everything else.
  static String? failureFor(UnpackTally tally, int totalFiles) {
    final resolved = tally.extracted + tally.skipped;
    if (resolved == 0) {
      return totalFiles == 0
          ? 'the archive contained no files'
          : 'none of $totalFiles entries resolved inside the library root';
    }
    if (tally.extracted == 0) {
      return 'all $resolved entries failed to write '
          '(first: ${tally.firstError})';
    }
    if (tally.skipped > _skipFloor && tally.skipped > resolved * _skipShare) {
      return '${tally.skipped} of $resolved entries failed to write '
          '(first: ${tally.firstError})';
    }
    return null;
  }

  /// Writes every file entry of [archive] under [rootPath], skipping the ones
  /// the filesystem refuses instead of abandoning the whole library.
  ///
  /// Entries [resolveWrappedArchivePath] declines - the wrapper folder itself,
  /// anything beside it rather than inside it, or a `..` traversal - are
  /// counted as dropped. That is the name check working, not a failure.
  ///
  /// A single entry can fail for reasons no name check can predict: a reserved
  /// device name like `CON` on Windows, a full disk, or a collision with
  /// something the archive itself already wrote there. Any one of those used to
  /// abort the import of the whole library.
  ///
  /// Every file entry the decoder produced is counted, so
  /// `extracted + skipped + dropped` is that number exactly.
  ///
  /// Consumes [archive]: each entry's decompressed bytes are released once
  /// written, so the entries are empty when this returns.
  static UnpackTally unpackWrappedArchiveTo(
    Archive archive,
    String rootPath, {
    required String separator,
    void Function(int extracted)? onProgress,
  }) {
    // createSync(recursive: true) is not free when the directory is already
    // there, and the library holds far more files than folders, so calling it
    // per file spent most calls re-creating directories that existed. Only
    // successful calls are recorded, so a failure that later clears is retried
    // rather than remembered as done.
    final createdDirs = <String>{};
    void ensureDir(String path) {
      if (createdDirs.contains(path)) return;
      io.Directory(path).createSync(recursive: true);
      createdDirs.add(path);
    }

    var extracted = 0;
    var skipped = 0;
    var dropped = 0;
    String? firstError;

    for (final entry in archive.files) {
      final outPath = entry.name.isEmpty
          ? null
          : resolveWrappedArchivePath(
              rootPath,
              entry.name,
              separator: separator,
            );

      if (!entry.isFile) {
        if (outPath == null) continue;
        try {
          ensureDir(outPath);
        } on io.FileSystemException {
          // A directory that cannot be created fails the files inside it, and
          // those are counted where they are written. Counting it here too
          // would put one loss in the tally twice.
        }
        continue;
      }

      // ZipDecoder does not throw on an entry whose local header it cannot
      // read: it yields a nameless, empty ArchiveFile. That is a file lost to
      // corruption, so it is a skip - not a name the check declined - and
      // counting it is what keeps extracted + skipped + dropped equal to the
      // number of file entries the decoder produced.
      if (entry.name.isEmpty) {
        skipped += 1;
        firstError ??= '<unnamed>: the archive entry could not be read';
        continue;
      }
      if (outPath == null) {
        dropped += 1;
        continue;
      }

      var wrote = false;
      try {
        final file = io.File(outPath);
        ensureDir(file.parent.path);
        // Deliberately unflushed. An fsync per file dominated this loop:
        // 2.10ms per entry against 0.33ms without one, measured on Windows
        // over 2,000 files. It bought nothing - the zip is re-downloadable,
        // and an interrupted unpack already leaves a partial tree that the
        // next run deletes outright.
        file.writeAsBytesSync(entry.readBytes()!);
        // readBytes caches the inflated bytes on the entry and nothing frees
        // them, so without this the whole decompressed library is live at once
        // - measured at ~37MB of RSS for a 30MB library, in a spawned isolate,
        // for nothing. clear() only drops the two content references;
        // closeSync() would close the zip's single shared handle and make
        // every later entry read zeros.
        entry.clear();
        extracted += 1;
        wrote = true;
      } on io.FileSystemException catch (e) {
        // Narrow on purpose. Every failure this tolerance is for is a
        // FileSystemException; catching Object here would fold an OOM or a
        // decoder bug into "the filesystem refused it" and keep looping.
        skipped += 1;
        firstError ??= '${entry.name}: $e';
      }
      // Outside the try: a throwing callback is the caller's bug, and counting
      // it as a refusal would put one entry in both totals.
      if (wrote) onProgress?.call(extracted);
    }

    return UnpackTally(
      extracted: extracted,
      skipped: skipped,
      dropped: dropped,
      firstError: firstError,
    );
  }

  static void _unpackIsolateEntry(_UnpackArgs args) {
    final send = args.sendPort;
    final input = InputFileStream(args.zipPath);
    try {
      final archive = ZipDecoder().decodeStream(input);
      final totalFiles = archive.files.where((f) => f.isFile).length;
      send.send(_UnpackTick(0, totalFiles));

      final tally = unpackWrappedArchiveTo(
        archive,
        args.rootPath,
        separator: args.sep,
        onProgress: (extracted) {
          if (extracted % 25 == 0) {
            send.send(_UnpackTick(extracted, totalFiles));
          }
        },
      );

      send.send(_UnpackResult(tally, totalFiles));
    } finally {
      input.close();
    }
  }
}

class _UnpackArgs {
  _UnpackArgs(this.zipPath, this.rootPath, this.sep, this.sendPort);
  final String zipPath;
  final String rootPath;
  final String sep;
  final SendPort sendPort;
}

/// Progress while the loop runs. Deliberately carries nothing about failures:
/// those are only meaningful once the loop has finished, and a type that held
/// them here would invite a reader to trust a count that is always zero.
class _UnpackTick {
  _UnpackTick(this.extracted, this.totalFiles);
  final int extracted;
  final int totalFiles;
}

/// The single terminal message. Its arrival is what completes the operation.
class _UnpackResult {
  _UnpackResult(this.tally, this.totalFiles);
  final UnpackTally tally;
  final int totalFiles;
}
