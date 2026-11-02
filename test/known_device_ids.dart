// The BLE ids the device-id migration is tested with, in one place.
//
// Three files want the same pair — the store-load cases, the persist group and
// the auto-connect case — which is the threshold `ble_fixtures.dart` in the
// submodule records for itself ("pulled out when the third file carried it").
// The reason to share them is not the line count: [storedById] is the
// *premise* of those cases, and the thing most likely to move is what counts
// as canonical. [KnownDevice]'s constructor doc is where the scope of the fold
// is argued, and a premise in three copies is one that gets half-updated.
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

/// One entry as `known_devices_v1` holds it.
///
/// Hand-built rather than `KnownDevice(...).toJson()`, which could not serve
/// these cases at all: the canonicalising constructor lower-cases [id], and
/// an upper-case id surviving to disk is the premise of every migration case.
///
/// A map and not a [KnownDevice], because what a fixture here is for is a
/// shape on disk - including shapes `toJson` cannot write, which the load
/// cases seed inline rather than through this.
Map<String, Object> storedEntry(String id, String name, String when) => {
  'id': id,
  'name': name,
  'lastConnectedAt': when,
};
