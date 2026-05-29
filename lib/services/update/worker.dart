import 'dart:async';

import 'update_service.dart';

class UpdateCheckEvent {
  const UpdateCheckEvent({
    required this.source,
    required this.sourceName,
    required this.previousVersion,
    required this.newVersion,
  });

  final String source;
  final String sourceName;
  final String previousVersion;
  final String newVersion;
}

class UpdateWorker {
  static final UpdateWorker instance = UpdateWorker._();
  UpdateWorker._();

  static const Duration interval = Duration(hours: 2);

  final _eventController = StreamController<UpdateCheckEvent>.broadcast();
  Stream<UpdateCheckEvent> get events => _eventController.stream;

  Timer? _timer;

  void start() {
    _timer?.cancel();
    _timer = Timer.periodic(interval, (_) => _wake());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _wake() async {
    final updates = await UpdateService.instance.checkForUpdates();
    for (final update in updates) {
      _eventController.add(
        UpdateCheckEvent(
          source: update.source,
          sourceName: update.sourceName,
          previousVersion: update.previousVersion,
          newVersion: update.newVersion,
        ),
      );
    }
  }
}
