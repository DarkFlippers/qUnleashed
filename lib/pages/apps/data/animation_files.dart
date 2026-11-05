import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';

import '../../../services/guarded.dart';
import '../../../services/http/app_http.dart';
import 'catalog_api.dart';

class AnimationFiles {
  AnimationFiles({required this.api});

  final AppsCatalogApi api;

  static const int _maxRunning = 4;
  static const Duration _spacing = Duration(milliseconds: 125);
  static const Duration _rateLimitPause = Duration(seconds: 10);
  static const int _maxCached = 4000;

  final LinkedHashMap<String, Uint8List> _cache = LinkedHashMap();
  final Map<String, _FileJob> _pending = {};
  final Queue<_FileJob> _queue = Queue();
  int _running = 0;
  DateTime _nextStart = DateTime.fromMillisecondsSinceEpoch(0);
  Timer? _wake;

  Future<Uint8List?> read(
    String versionId,
    String name, {
    required bool Function() wanted,
  }) {
    final server = api.server;
    final key = '$server/$versionId/$name';
    final hit = _cache.remove(key);
    if (hit != null) {
      _cache[key] = hit;
      return Future.value(hit);
    }
    final pending = _pending[key];
    if (pending != null) {
      pending.wanted.add(wanted);
      return pending.done.future;
    }
    final job = _FileJob(key, server, versionId, name)..wanted.add(wanted);
    _pending[key] = job;
    _queue.add(job);
    _pump();
    return job.done.future;
  }

  void _pump() {
    _wake?.cancel();
    _wake = null;
    while (_running < _maxRunning && _queue.isNotEmpty) {
      final job = _queue.first;
      if (!job.isWanted || job.server != api.server) {
        _queue.removeFirst();
        _finish(job, null);
        continue;
      }
      final now = DateTime.now();
      if (now.isBefore(_nextStart)) {
        _wake = Timer(_nextStart.difference(now), _pump);
        return;
      }
      _queue.removeFirst();
      _running++;
      _nextStart = now.add(_spacing);
      unawaited(guarded('[Animations] fetch ${job.key}', () => _run(job)));
    }
  }

  Future<void> _run(_FileJob job) async {
    try {
      final bytes = await api.fetchAnimationFile(job.versionId, job.name);
      if (job.server != api.server) {
        _finish(job, null);
        return;
      }
      _cache[job.key] = bytes;
      while (_cache.length > _maxCached) {
        _cache.remove(_cache.keys.first);
      }
      _finish(job, bytes);
    } on AppHttpException catch (e) {
      if (e.statusCode == 429) {
        _nextStart = DateTime.now().add(_rateLimitPause);
        _queue.addFirst(job);
      } else {
        _finish(job, null);
      }
    } catch (_) {
      _finish(job, null);
    } finally {
      _running--;
      _pump();
    }
  }

  void _finish(_FileJob job, Uint8List? bytes) {
    _pending.remove(job.key);
    if (!job.done.isCompleted) job.done.complete(bytes);
  }
}

class _FileJob {
  _FileJob(this.key, this.server, this.versionId, this.name);

  final String key;
  final String server;
  final String versionId;
  final String name;
  final List<bool Function()> wanted = [];
  final Completer<Uint8List?> done = Completer<Uint8List?>();

  bool get isWanted => wanted.any((w) => w());
}
