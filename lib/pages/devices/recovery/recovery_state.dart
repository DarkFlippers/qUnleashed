import 'package:flipperlib/flipperlib.dart' show RecoveryStep;

sealed class RecoveryState {
  const RecoveryState();
}

class RecoveryIdle extends RecoveryState {
  const RecoveryIdle();
}

class RecoveryEnteringDfu extends RecoveryState {
  const RecoveryEnteringDfu();
}

class RecoveryFetching extends RecoveryState {
  const RecoveryFetching(this.progress);
  final double progress;
}

class RecoveryRunning extends RecoveryState {
  const RecoveryRunning(this.step, this.percent);
  final RecoveryStep step;
  final double percent;
}

class RecoveryDoneState extends RecoveryState {
  const RecoveryDoneState();
}

class RecoveryErrorState extends RecoveryState {
  const RecoveryErrorState(this.message);
  final String message;
}
