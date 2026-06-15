sealed class UpdateState {
  const UpdateState();
}

class UpdateIdle extends UpdateState {
  const UpdateIdle();
}

class UpdateFetching extends UpdateState {
  const UpdateFetching();
}

class UpdateDownloading extends UpdateState {
  const UpdateDownloading(this.progress);
  final double progress;
}

class UpdateUploading extends UpdateState {
  const UpdateUploading(this.progress);
  final double progress;
}

class UpdateStarting extends UpdateState {
  const UpdateStarting();
}

class UpdateDone extends UpdateState {
  const UpdateDone();
}

class UpdateError extends UpdateState {
  const UpdateError(this.message);
  final String message;
}
