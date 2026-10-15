import 'package:flutter_test/flutter_test.dart';
import 'package:qunleashed/services/assembler/remote_build_service.dart';
import 'package:qunleashed/services/logging.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'kept_lines.dart';
import 'refusing_prefs.dart';
import 'unopenable_prefs.dart';

/// The id that identifies this install to the build server.
///
/// It sits on the path that signs every remote build request and `build()`
/// has no catch, so anything thrown here reached the user as the stated
/// reason their firmware build failed. The ruling - best effort throughout,
/// and `caught` rather than the `warn` `persistSetting` would log - is
/// written beside the code in `remote_build_service.dart`.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(recordKeptLines);

  setUp(() {
    SharedPreferences.setMockInitialValues(const {});
    clearKeptLines();
  });

  RemoteBuildService newService() => RemoteBuildService.test(
    serverUrl: 'https://example.invalid',
    sharedKey: 'k',
  );

  const key = 'remote_build_client_id';
  final isAClientId = matches(RegExp(r'^[0-9a-f]{32}$'));

  test('a generated id is stored for the next launch', () async {
    final id = await newService().ensureClientId();

    expect(id, isAClientId);
    SharedPreferences.resetStatic();
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(key), id);
    expect(keptLines, isEmpty, reason: 'a write that worked says nothing');
  });

  test('a stored id is reused rather than regenerated', () async {
    SharedPreferences.setMockInitialValues(const {key: 'abc123'});

    expect(await newService().ensureClientId(), 'abc123');
  });

  test('the id is remembered for the session after the first call', () async {
    final service = newService();

    final first = await service.ensureClientId();

    // The store is emptied under it; the session must not change id.
    SharedPreferences.setMockInitialValues(const {});
    expect(await service.ensureClientId(), first);
  });

  group('a store that will not open', () {
    // The failure that used to escape. getInstance() is what an unopenable
    // store throws from, and it sat outside the guard until this.
    test('does not take the build down with it', () async {
      useUnopenablePrefs();

      final id = await newService().ensureClientId();

      expect(id, isAClientId);
    });

    test('says so, and says it is not worth alerting on', () async {
      useUnopenablePrefs();

      await newService().ensureClientId();

      expect(
        keptLines.where((l) => l.contains('was not remembered')),
        isNotEmpty,
      );
      expect(
        keptLines.where((l) => l.contains('could not be opened')),
        isNotEmpty,
        reason: 'this store cannot open; it did not merely refuse',
      );
      expect(keptLevels, everyElement(KeptLevel.caught));
    });
  });

  group('a store that refuses the write', () {
    test('still hands back an id for this session', () async {
      useRefusingPrefs();

      expect(await newService().ensureClientId(), isAClientId);
    });

    test('says the store refused it, at caught', () async {
      useRefusingPrefs();

      await newService().ensureClientId();

      expect(
        keptLines.where((l) => l.contains('the store refused the write')),
        isNotEmpty,
        reason: 'the words persistSetting and KnownDevices use',
      );
      expect(keptLevels, everyElement(KeptLevel.caught));
    });
  });
}
