// The process-wide hooks `Telemetry` installs, put back.
//
// `Telemetry.start()` wires four sinks and raises flipperlib's level, and
// `_wireSinks` is deliberately one list in production so that adding a fifth
// means editing one place. A test that resets them by hand is the other half
// of that list, so there is one copy of it here rather than one per file: two
// files already needed it, and the second was written by copying the first.
//
// Call it from a `tearDown` or an `addTearDown`. It is unconditional on
// purpose - a case whose `Telemetry` never came up has nothing installed, and
// nulling a null costs nothing.
import 'package:flipperlib/flipperlib.dart' show FlipperLogLevel, Log;
import 'package:qunleashed/services/guarded.dart';
import 'package:qunleashed/services/http/app_http.dart';
import 'package:qunleashed/services/logging.dart';

void resetTelemetrySinks() {
  guardedFailureSink = null;
  LogService.keptSink = null;
  LogService.breadcrumbSink = null;
  AppHttp.exchangeSink = null;
  Log.sink = null;
  Log.level = FlipperLogLevel.info;
}
