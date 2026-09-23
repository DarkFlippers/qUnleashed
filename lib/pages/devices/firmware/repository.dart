import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../../components/config.dart';
import '../../../services/http/app_http.dart';
import '../../../services/logging.dart';
import 'directory.dart';

class FirmwareRepository extends ChangeNotifier {
  FirmwareRepository._();
  static final FirmwareRepository instance = FirmwareRepository._();

  /// How long a fetch may run before it counts as failed.
  ///
  /// The two directory documents are tens of kilobytes, so this is a whole-
  /// operation budget rather than an idle allowance. Without it a server that accepts
  /// the connection and then never answers leaves the request pending for the
  /// life of the process - #118's own bug by a second route, and the one a
  /// catch cannot see: nothing throws, so nothing is recorded, [_loading] is
  /// never released, and the card reads Checking… until the app restarts.
  ///
  /// A deadline here rather than in `AppHttp`, which has no response or idle
  /// timeout of its own and needs one that large downloads can survive - #130.
  static const Duration _deadline = Duration(seconds: 30);

  final Set<String> _loading = {};

  /// What the last failed attempt for a firmware was, absent once one succeeds.
  ///
  /// The reason and its classification, not just the fact, because
  /// [_recordFailure] says a failure again once it is no longer the same one.
  final Map<String, ({String reason, bool network})> _failed = {};

  FirmwareDirectory? directoryFor(FirmwareEntry entry) =>
      parserForEntry(entry).cached;

  /// Whether a fetch for [entry] is in flight.
  ///
  /// Read [stateFor] instead. This and [failedFor] are the two facts it
  /// combines, and asking them separately is what left the precedence between
  /// them for every caller to get right on its own.
  @visibleForTesting
  bool isLoading(FirmwareEntry entry) => _loading.contains(entry.shortName);

  /// Whether the most recent attempt at [entry]'s directory failed.
  ///
  /// Read [stateFor] instead - see [isLoading]. Not the same as having no
  /// directory: a refresh that fails leaves the previous one standing.
  @visibleForTesting
  bool failedFor(FirmwareEntry entry) => _failed.containsKey(entry.shortName);

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

  /// Drops what this object would otherwise carry from one test to the next.
  ///
  /// Both containers, not only the failures: a test that asserts against a
  /// fetch still in flight holds a key in [_loading] until it lets that fetch
  /// finish, and an assertion that fails before then strands the key for the
  /// rest of the process - where it reads as a fetch in flight and makes
  /// [_fetch] return without doing anything, so the next test fails pointing
  /// at the logging rather than at the strand.
  ///
  /// The directory itself lives in [FirmwareParser], so a test that wants a
  /// clean [stateFor] needs `clearCache()` as well.
  @visibleForTesting
  void reset() {
    _loading.clear();
    _failed.clear();
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
      _failed.remove(key);
    } catch (e, st) {
      // Not ours to absorb - carrying on past either is undefined.
      if (e is OutOfMemoryError || e is StackOverflowError) rethrow;
      _recordFailure(key, e, st);
    } finally {
      _loading.remove(key);
      notifyListeners();
    }
  }

  /// Records a failed attempt, and says so unless it is the same one again.
  ///
  /// The record is cleared only by a success, so suppressing on presence alone
  /// hid the case this level split exists for: a launch that failed offline
  /// and then met a feed whose shape had changed recorded the socket error and
  /// nothing after it, because a broken feed never produces the success that
  /// would clear the record. Comparing the reason keeps a genuinely repeating
  /// condition to one line and lets a changed one through.
  ///
  /// Suppressing at all is needed because [ensure] has many callers and no
  /// memory of its own: every `FirmwareController` construction prefetches,
  /// every carousel swipe and push tap asks again, and a failed fetch never
  /// leaves a fresh cache to short-circuit them. `LogService` coalesces only
  /// consecutive identical bodies, and two firmwares failing in turn are not
  /// consecutive, so it cannot do this job here.
  ///
  /// The level splits the two unrelated things that arrive. The user's network
  /// is an expected way to run this app and belongs at warn. Anything else is
  /// a feed whose shape changed under a parser of unchecked casts (#133),
  /// which disables the firmware page for every user at once and must not be
  /// filed alongside airplane mode.
  void _recordFailure(String key, Object e, StackTrace st) {
    final network = _isNetwork(e);
    final reason = '$e';
    final previous = _failed[key];
    _failed[key] = (reason: reason, network: network);
    if (previous != null &&
        previous.reason == reason &&
        previous.network == network) {
      return;
    }
    final message =
        '[Firmware] $key directory fetch failed: ${LogService.describe(e, st)}';
    if (network) {
      LogService.warn(message);
    } else {
      LogService.error(message);
    }
  }

  /// Whether [e] is the user's network rather than the app's own doing.
  ///
  /// [IOException] rather than `SocketException`, so a TLS handshake, a
  /// truncated response and a redirect loop are covered too: a stale root
  /// certificate or a skewed clock is somebody's network, not a broken feed.
  ///
  /// [FormatException] counts, which is the one judgement call here. A body
  /// that will not parse as JSON at all is a captive portal or a proxy far
  /// more often than a feed regression, because the feed is machine-generated.
  /// A feed that really did change shape parses and then fails a cast, which
  /// arrives as a `TypeError` and is filed as the app's own problem.
  static bool _isNetwork(Object e) =>
      e is IOException ||
      e is TimeoutException ||
      e is AppHttpException ||
      e is FormatException;
}
