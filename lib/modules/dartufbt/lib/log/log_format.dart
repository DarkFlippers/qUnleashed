import 'log_level.dart';
import 'progress.dart';

abstract final class UfbtLogFormat {
  static const int defaultBarWidth = 72;
  static const String barChar = '#';

  static String timestamp(DateTime time) {
    final hh = time.hour.toString().padLeft(2, '0');
    final mm = time.minute.toString().padLeft(2, '0');
    final ss = time.second.toString().padLeft(2, '0');
    final ms = time.millisecond.toString().padLeft(3, '0');
    return '$hh:$mm:$ss.$ms';
  }

  static String message(DateTime time, UfbtLogLevel level, String message) {
    return '${timestamp(time)} [${level.letter}] $message';
  }

  static String build(String tag, String value, List<String> details) {
    final head = '\t$tag\t$value';
    if (details.isEmpty) return head;
    return '$head\n${details.map((line) => '\t\t$line').join('\n')}';
  }

  static String percent(double value) {
    return '${value.toStringAsFixed(1).padLeft(5)}%';
  }

  static String progressBar(
    UfbtProgress progress, {
    int width = defaultBarWidth,
  }) {
    final fraction = progress.isDone ? 1.0 : (progress.fraction ?? 0.0);
    final filled = (fraction * width).round();
    return '${barChar * filled}${' ' * (width - filled)} '
        '${percent(fraction * 100)}';
  }
}
