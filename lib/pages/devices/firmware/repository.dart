import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../../components/config.dart';
import '../../../services/http/app_http.dart';
import '../../../services/logging.dart';
import 'directory.dart';

/// What is known about a firmware's directory.
///
/// One value rather than the pair of booleans this started as, because three
/// of the four combinations that pair could express were real and the fourth -
/// loading and failed at once - was not, which left every reader to get the
/// precedence right on its own. #118.
enum FirmwareFetchState {
  /// A fetch is in flight, or nothing has settled yet.
  loading,

  /// The last attempt failed. An older directory may still be in hand.
  failed,

  /// A directory is in hand and the last attempt for it succeeded.
  ready,
}

class FirmwareRepository extends ChangeNotifier {
  FirmwareRepository._();
  static final FirmwareRepository instance = FirmwareRepository._();

  /// How long a fetch may run before it counts as failed.
  ///
  /// `directory.json` is a few kilobytes, so thirty seconds is the whole
  /// budget rather than an idle allowance. Without it a server that accepts
  /// the connection and then never answers leaves the request pending for the
  /// life of the process - #118's own bug by a second route, and the one a
  /// catch cannot see: nothing throws, so nothing is recorded, [_loading] is
  /// never released, and the card reads Checking… until the app restarts.
  ///
  /// A deadline here rather than in `AppHttp`, which has no response or idle
  /// timeout of its own and needs one that large downloads can survive - #130.
  static const Duration _deadline = Duration(seconds: 30);

  /// How long a firmware that failed is left alone before [ensure] retries.
  ///
  /// [ensure] is not only reached when someone asks for something. FirmwareCard
  /// calls it from `didUpdateWidget`, and a connected Flipper rebuilds that
  /// subtree every five seconds, because `device_info_watch` polls the battery
  /// on that interval and its notify reaches `DeviceScope`. A failed fetch
  /// never leaves a fresh cache, so `isFresh` alone lets every one of those
  /// rebuilds through: twelve requests a minute at a server that is already
  /// not answering, for as long as the app is open.
  ///
  /// Pull-to-refresh goes through [refresh] and is not subject to this - asking
  /// again is exactly what the gesture means.
  static const Duration _retryAfter = Duration(minutes: 1);

  final Set<String> _loading = {};

  /// When the last attempt for a firmware failed. Absent once one succeeds.
  ///
  /// The time, not just the fact, because [ensure] needs both: whether to say
  /// anything, and whether enough has passed to try again.
  final Map<String, DateTime> _failedAt = {};

  FirmwareDirectory? directoryFor(FirmwareEntry entry) =>
      parserForEntry(entry).cached;

  bool isLoading(FirmwareEntry entry) => _loading.contains(entry.shortName);

  /// Whether the most recent attempt at [entry]'s directory failed.
  ///
  /// Not the same as [directoryFor] returning null, which is equally what a
  /// fetch that has not run yet looks like; and not the same as having no
  /// directory at all, because a refresh that fails leaves the previous one
  /// standing. Anything showing a spinner needs the first distinction, and
  /// anything about to report "no update" needs the second. #118.
  bool failedFor(FirmwareEntry entry) => _failedAt.containsKey(entry.shortName);

  /// What [entry]'s directory is doing, as one value.
  ///
  /// A fetch in flight wins over everything: a retry after a failure should
  /// read as checking, not as the failure it is retrying. Past that, a failure
  /// is worth saying even when an older directory is still on screen, and only
  /// a directory that arrived without a failure after it is [ready].
  FirmwareFetchState stateFor(FirmwareEntry entry) {
    if (isLoading(entry)) return FirmwareFetchState.loading;
    if (failedFor(entry)) return FirmwareFetchState.failed;
    return directoryFor(entry) == null
        ? FirmwareFetchState.loading
        : FirmwareFetchState.ready;
  }

  Future<void> ensure(FirmwareEntry entry) async {
    if (parserForEntry(entry).isFresh) return;
    final failedAt = _failedAt[entry.shortName];
    if (failedAt != null && DateTime.now().difference(failedAt) < _retryAfter) {
      return;
    }
    await _fetch(entry);
  }

  Future<void> prefetchAll() =>
      Future.wait(QAppConfig.firmware.firmwares.map(ensure));

  /// Announces a directory change without fetching one.
  ///
  /// For tests. The alternative is [refresh], which goes to the network - and
  /// on a machine with egress it succeeds and replaces whatever a test had
  /// seeded, making the assertion depend on what the upstream feed happens to
  /// serve that day.
  @visibleForTesting
  void directoryChanged() => notifyListeners();

  /// Drops everything one test could leave behind for the next.
  ///
  /// Both sets, not just the failures: a test that asserts against a fetch
  /// still in flight holds a key in [_loading] until it lets the fetch finish,
  /// and an assertion that fails before that point strands the key for the
  /// rest of the process - where it reads as a fetch in flight and makes
  /// [_fetch] return without doing anything. The next test then fails pointing
  /// at the logging rather than at the strand.
  @visibleForTesting
  void reset() {
    _loading.clear();
    _failedAt.clear();
  }

  Future<void> refresh() =>
      Future.wait(QAppConfig.firmware.firmwares.map(_fetch));

  Future<void> _fetch(FirmwareEntry entry) async {
    final key = entry.shortName;
    if (_loading.contains(key)) return;
    _loading.add(key);
    notifyListeners();
    try {
      await parserForEntry(entry).fetch().timeout(_deadline);
      // Cleared here rather than on the way in, so [failedFor] describes the
      // most recent attempt rather than the most recent one to get this far.
      // A refresh that fails over a directory already in hand has to stay
      // marked: the directory it leaves standing is the old one.
      _failedAt.remove(key);
    } catch (e, st) {
      _recordFailure(key, e, st);
    } finally {
      _loading.remove(key);
      notifyListeners();
    }
  }

  /// Marks [key] as failed, and says so the first time.
  ///
  /// Only the first. [ensure] retries on a cooldown for as long as the
  /// condition lasts, and a hundred copies of one sentence would push
  /// everything else out of a 500-entry history without telling a reader
  /// anything the first copy did not. `LogService` coalesces only consecutive
  /// identical bodies, and two firmwares failing in turn are not consecutive,
  /// so it cannot do this job here. A success clears the record, so a failure
  /// that comes back is said again.
  ///
  /// The level splits the two unrelated things that arrive here. A socket
  /// error, a deadline or an HTTP status is the user's network, and an offline
  /// launch is an expected way to run this app. Anything else is a feed whose
  /// shape changed under a parser that casts every field unguarded (#133),
  /// which disables the firmware page for every user at once and must not be
  /// filed at the same level as airplane mode.
  void _recordFailure(String key, Object e, StackTrace st) {
    final first = !_failedAt.containsKey(key);
    _failedAt[key] = DateTime.now();
    if (!first) return;
    final message =
        '[Firmware] $key directory fetch failed: ${LogService.describe(e, st)}';
    if (_isNetwork(e)) {
      LogService.warn(message);
    } else {
      LogService.error(message);
    }
  }

  /// Whether [e] is the user's network rather than the app's own doing.
  static bool _isNetwork(Object e) =>
      e is SocketException || e is TimeoutException || e is AppHttpException;
}
