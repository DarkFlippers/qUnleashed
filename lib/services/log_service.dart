import 'dart:async';

class LogService {
  static final _ctrl = StreamController<String>.broadcast();
  static Stream<String> get stream => _ctrl.stream;

  static void log(String msg) {
    final ts = DateTime.now().toIso8601String().substring(11, 19);
    final line = '[$ts] $msg';
    // ignore: avoid_print
    print(line);
    if (!_ctrl.isClosed) _ctrl.add(line);
  }
}
