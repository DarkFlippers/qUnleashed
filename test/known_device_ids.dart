// The BLE ids the device-id migration is tested with, in one place.
//
// Four files wanted the same pair — the two new store-load cases, the persist
// group and the auto-connect case — which is the threshold `ble_fixtures.dart`
// in the submodule records for itself ("pulled out when the third file carried
// it"). The reason to share them is not the line count: [storedById] is the
// *premise* of those cases, and the thing most likely to move is what counts
// as canonical. `newestPerDevice`'s own comment names that hazard — a fold
// that ever became more than a case fold — and a premise in four copies is one
// that gets half-updated.
//
// A real Flipper OUI rather than a toy id, matching the submodule's own
// `ble_device_id_test.dart`, so the host and library cases read as one story.

/// A remembered id as a build on universal_ble 2.x wrote it: upper-case,
/// which is what the plugin reported on Android and Linux, and the shape
/// Apple's `uuidString` has too.
const String storedById = '80:E1:27:AA:BB:CC';

/// The same device as universal_ble 3.x reports it, and so the one form
/// everything in the app compares.
const String reportedById = '80:e1:27:aa:bb:cc';

/// A second Flipper, for the cases that have to show a fold or a collapse did
/// not merge two devices into one.
const String otherById = '80:e1:27:11:22:33';
