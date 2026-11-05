// That the storage permission's answer actually leaves `permissions.dart`.
//
// `paths.dart` is named in #351 as the root cause rather than one of five: it
// is the single call site of `ensureAndroidStoragePermission`, every storage
// path in the app hangs off it, and the answer never left the file. The fix is
// a sink installed by `_initCore` and called on every outcome.
//
// A sink is a single global slot, and nothing was pinning it. Delete the
// `reportStoragePermissionTo` line from `_initCore` and the whole storage half
// of this change reverts in silence, with a green suite and no analyzer
// complaint — the same failure mode `device_scope_reach_test.dart` exists to
// stop for `PermissionScope`, and the reason it was extended there.
//
// These run on the host, which is not Android, so what they can reach is the
// `unavailable` arm and the sink wiring itself. That is deliberately the half
// worth pinning: the Android arms need a platform channel, while "nothing to
// grant is not a grant" is a plain inverted-condition risk that the file's own
// comment calls out, and the sink is a wire that can simply be unplugged.
import 'package:flutter_test/flutter_test.dart';
import 'package:qunleashed/services/permissions/center.dart';
import 'package:qunleashed/services/permissions/permission.dart';
import 'package:qunleashed/services/storage/permissions.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  // `flutter_test_config.dart` resets this file's statics before every test,
  // so the sink installed below never leaks into another one.
  setUp(() => SharedPreferences.setMockInitialValues(const {}));

  test('the answer reaches whatever the composition root installed', () async {
    final seen = <PermissionOutcome>[];
    reportStoragePermissionTo(seen.add);

    await ensureAndroidStoragePermission();

    expect(
      seen,
      isNotEmpty,
      reason: 'the sink is how the answer leaves permissions.dart at all',
    );
  });

  test('a platform with nothing to grant reports unavailable, not granted', () async {
    // The distinction this file's own comment asks for: `true` is the right
    // answer to "is the path writable" on a desktop build, but reporting it as
    // a *grant* would make a desktop build draw a storage notice the day
    // somebody inverts a condition here. `unavailable` draws nothing.
    final seen = <PermissionOutcome>[];
    reportStoragePermissionTo(seen.add);

    final writable = await ensureAndroidStoragePermission();

    expect(writable, isTrue, reason: 'the path is writable without a grant');
    expect(seen, [PermissionOutcome.unavailable]);
  });

  test(
    'the read agrees with the request on a platform with no permission',
    () async {
      // Two functions answered the same state differently once - the request
      // path said `denied` where the read said `unknown` - and the resume
      // re-read then erased a notice with no user action. They have to agree.
      expect(
        await readAndroidStoragePermission(),
        PermissionOutcome.unavailable,
      );
    },
  );

  test('a centre wired to the sink hears it', () async {
    // The shape `_initCore` builds, end to end: the sink writes into a real
    // `PermissionCenter`, and `unavailable` leaves the notice off.
    final center = PermissionCenter();
    reportStoragePermissionTo(
      (outcome) => center.record(AppPermission.storage, outcome),
    );

    await ensureAndroidStoragePermission();

    expect(
      center.outcomeOf(AppPermission.storage),
      PermissionOutcome.unavailable,
    );
    expect(
      center.isDenied(AppPermission.storage),
      isFalse,
      reason: 'nothing to grant must never read as a refusal',
    );
  });

  test('with no sink installed nothing throws', () async {
    // `paths.dart` is reached from the home-screen widget's isolate and from
    // a dozen unit tests, none of which has a centre. A callback nobody set
    // is a no-op, which is what lets those paths stay unchanged.
    await ensureAndroidStoragePermission();
    expect(await readAndroidStoragePermission(), isNotNull);
  });
}
