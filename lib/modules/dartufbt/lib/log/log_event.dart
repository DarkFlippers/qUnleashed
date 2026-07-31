import 'log_level.dart';
import 'progress.dart';

sealed class UfbtLogEvent {
  const UfbtLogEvent({required this.time});

  final DateTime time;
}

class UfbtMessageEvent extends UfbtLogEvent {
  const UfbtMessageEvent({
    required super.time,
    required this.level,
    required this.message,
    required this.formatted,
  });

  final UfbtLogLevel level;
  final String message;
  final String formatted;
}

class UfbtBuildEvent extends UfbtLogEvent {
  const UfbtBuildEvent({
    required super.time,
    required this.tag,
    required this.value,
    required this.details,
    required this.formatted,
  });

  final String tag;
  final String value;
  final List<String> details;
  final String formatted;
}

class UfbtRawEvent extends UfbtLogEvent {
  const UfbtRawEvent({
    required super.time,
    required this.text,
    required this.newline,
  });

  final String text;
  final bool newline;
}

class UfbtProgressEvent extends UfbtLogEvent {
  const UfbtProgressEvent({required super.time, required this.progress});

  final UfbtProgress progress;
}
