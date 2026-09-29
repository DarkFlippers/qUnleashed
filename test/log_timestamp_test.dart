import 'package:flutter_test/flutter_test.dart';
import 'package:qunleashed/services/logging.dart';

/// The `hh:mm:ss` every kept line carries, and what it costs to produce.
///
/// Reading an hour off a local `DateTime` forces a timezone lookup, and that
/// lookup was most of what a log line cost - 6676 ns against 260 ns for the
/// shape here, per line, and worse under AOT. #116 measured it; this pins the
/// behaviour that makes the cheaper shape safe to keep.
String _two(int v) => v < 10 ? '0$v' : '$v';

String wallClock(DateTime at) =>
    '${_two(at.hour)}:${_two(at.minute)}:${_two(at.second)}';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    LogService.clearHistory();
    LogService.debugResetZoneOffset();
    addTearDown(LogService.debugResetZoneOffset);
  });

  String? lastStamp() => LogService.history.isEmpty
      ? null
      : LogService.history.last.substring(1, 9);

  group('the stamp', () {
    // The whole point of the cache is that it cannot be seen here: a line has
    // to read as the clock on the wall, offset or no offset.
    test('is the local wall clock, not UTC', () {
      final before = DateTime.now();
      LogService.warn('something happened');
      final after = DateTime.now();

      expect(
        lastStamp(),
        anyOf(wallClock(before), wallClock(after)),
        reason: 'the second may tick between the two reads',
      );
    });

    test('is still the wall clock on a line taken from the cache', () {
      LogService.warn('first');
      final before = DateTime.now();
      LogService.warn('second');
      final after = DateTime.now();

      expect(lastStamp(), anyOf(wallClock(before), wallClock(after)));
    });
  });

  group('a single digit', () {
    // The clock only shows one for part of the day, so an assertion on
    // whatever `now` reads covers this at nine in the morning and not at two
    // in the afternoon. The offset is reset first, so it is read off the
    // instant passed in and the stamp is that instant's own wall clock.
    test('is padded, in every field', () {
      expect(LogService.debugStamp(DateTime(2026, 1, 2, 4, 5, 6)), '04:05:06');
    });

    test('is not padded when there is no room for one', () {
      expect(
        LogService.debugStamp(DateTime(2026, 1, 2, 16, 45, 59)),
        '16:45:59',
      );
    });

    test('is a zero where the field is zero', () {
      expect(LogService.debugStamp(DateTime(2026, 1, 2, 0, 0, 0)), '00:00:00');
    });
  });

  group('the zone offset', () {
    test('is read once, not once per line', () {
      LogService.warn('one');
      LogService.warn('two');
      LogService.warn('three');

      expect(LogService.debugZoneLookups, 1);
    });

    // It has to expire, or a DST change never reaches the log at all.
    test('is read again once its window has passed', () {
      LogService.debugResetZoneOffset(ttl: Duration.zero);

      LogService.warn('one');
      LogService.warn('two');

      expect(LogService.debugZoneLookups, 2);
    });
  });

  group('a line nobody is listening to', () {
    // `_write` is the sink package:logging and universal_ble hand their lines
    // to, and in a build that prints nothing it keeps neither. Every one of
    // those used to buy a timestamp first.
    test('costs no zone lookup', () {
      LogService.debugEmitUnheard('chatter');

      expect(LogService.debugZoneLookups, 0);
      expect(LogService.history, isEmpty);
    });

    test('is the only kind that is skipped', () {
      LogService.debugEmitUnheard('chatter');
      LogService.warn('a real failure');

      expect(LogService.debugZoneLookups, 1);
      expect(LogService.history, hasLength(1));
    });
  });
}
