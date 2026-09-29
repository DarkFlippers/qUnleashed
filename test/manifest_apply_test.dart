import 'dart:async';

import 'package:flipperlib/flipperlib.dart' hide DateTime, File;
import 'package:flutter_test/flutter_test.dart';
import 'package:qunleashed/pages/tools/paint/dolphin/manifest.dart';
import 'package:qunleashed/pages/tools/paint/dolphin_animation.dart';
import 'package:qunleashed/pages/tools/paint/manager/controller.dart';
import 'package:qunleashed/pages/tools/paint/project.dart';
import 'package:qunleashed/pages/tools/paint/virtual_display_session.dart';

/// Applying hand-edited manifest text to the library.
///
/// `dolphin_manifest_test.dart` covers the parser; this is the half above it —
/// which animations end up in the pack, with which settings, and what the
/// screen is told. The pack is what gets uploaded, so an animation that
/// quietly leaves it is one the Flipper stops playing.
///
/// Not covered: the device preview failing. `loadDevicePreview` cannot be
/// made to throw from here - a missing frame file falls back to a blank one
/// and `BmCodec.xbmToPixels` bounds-checks every read, so a truncated file is
/// decoded rather than refused. Only a genuine I/O fault on a file that
/// `exists()` has already answered for would reach it, which is not something
/// a test can arrange portably. The catch there reports now, and this is the
/// record that it does so untested.
class FakeManagerClient implements FlipperClient {
  final _connection = StreamController<FlipperConnectionState>.broadcast();

  Future<void> close() => _connection.close();

  @override
  bool get isConnected => false;

  @override
  Stream<FlipperConnectionState> get connectionStream => _connection.stream;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// A display that answers but reaches no device: the manager takes one at
/// construction, and the shared session would use the app's own client.
class FakeDisplayClient implements FlipperClient {
  final _connection = StreamController<FlipperConnectionState>.broadcast();

  Future<void> close() => _connection.close();

  @override
  bool get isConnected => false;

  @override
  Stream<FlipperConnectionState> get connectionStream => _connection.stream;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// One animation in the library. Only its name and manifest entry matter
/// here; [dirPath] is where a preview would read its frames, and no case
/// needs it - see the note at the top about why.
PaintItem item(
  String name, {
  bool selected = false,
  int weight = 8,
  String? dirPath,
}) => PaintItem(
  PaintProject(
    id: name,
    name: name,
    path: dirPath ?? '/local/$name',
    isDraft: false,
    modified: DateTime(2026),
    frameCount: 1,
    dolphin: DolphinAnimation(
      name: name,
      dirPath: dirPath ?? '/local/$name',
      metaPath: '${dirPath ?? '/local/$name'}/meta.txt',
      width: 128,
      height: 54,
      passiveFrames: 1,
      activeFrames: 0,
      frameRate: 2,
      duration: 3600,
      activeCycles: 1,
      activeCooldown: 5,
      framesOrder: const [0],
      frameFileCount: 1,
    ),
  ),
  ManifestEntry(name: name, selected: selected, weight: weight),
);

void main() {
  late FakeManagerClient client;
  late FakeDisplayClient displayClient;
  late ProjectManagerController manager;

  setUp(() {
    client = FakeManagerClient();
    displayClient = FakeDisplayClient();
    manager = ProjectManagerController(
      client: client,
      display: VirtualDisplaySession.forTest(displayClient),
    );
    addTearDown(() async {
      manager.dispose();
      await client.close();
      await displayClient.close();
    });
  });

  String manifestOf(Iterable<ManifestEntry> entries) =>
      DolphinManifest.build(entries);

  ManifestEntry entryOf(String name) =>
      manager.items.firstWhere((i) => i.id == name).entry;

  group('what the text names', () {
    test('joins the pack with the settings it was given', () {
      manager.seedItems([item('A'), item('B')]);

      final result = manager.applyManifest(
        manifestOf([ManifestEntry(name: 'A', weight: 3, minLevel: 5)]),
      );

      expect(result.applied, 1);
      expect(entryOf('A').selected, isTrue);
      expect(entryOf('A').weight, 3);
      expect(entryOf('A').minLevel, 5);
    });

    // The text is the whole pack, not a set of edits to it: an animation left
    // out of it is one the user removed, and leaving it selected would upload
    // a pack they did not write.
    test('and everything else leaves it', () {
      manager.seedItems([item('A', selected: true), item('B', selected: true)]);

      manager.applyManifest(manifestOf([ManifestEntry(name: 'A')]));

      expect(entryOf('A').selected, isTrue);
      expect(entryOf('B').selected, isFalse);
    });

    // A name in the text with no animation behind it is someone else's
    // library, or a folder that has been deleted. It cannot join a pack that
    // has nothing to upload for it.
    test('is counted only where the animation exists here', () {
      manager.seedItems([item('A')]);

      final result = manager.applyManifest(
        manifestOf([ManifestEntry(name: 'A'), ManifestEntry(name: 'Gone')]),
      );

      expect(result.applied, 1);
    });
  });

  group('text that names nothing', () {
    // Distinct from "nothing was selected": a manifest with no blocks at all
    // is a paste that went wrong, and clearing the pack over it would lose
    // the user's selection to a mistake.
    test('leaves the pack alone', () {
      manager.seedItems([item('A', selected: true)]);

      final result = manager.applyManifest('nonsense');

      expect(result.applied, 0);
      expect(entryOf('A').selected, isTrue);
    });

    test('still reports a paragraph that named no animation', () {
      manager.seedItems([item('A', selected: true)]);

      final result = manager.applyManifest('Weight: 9\n');

      expect(result.nameless, 1);
      expect(
        entryOf('A').selected,
        isTrue,
        reason: 'and still changes nothing',
      );
    });
  });

  test('a paragraph with no name is reported alongside what applied', () {
    manager.seedItems([item('A')]);

    final result = manager.applyManifest('Name: A\nWeight: 3\n\nWeight: 9\n');

    expect(result.applied, 1);
    expect(result.nameless, 1);
    expect(
      entryOf('A').weight,
      3,
      reason: 'the stray paragraph did not reach the block above it',
    );
  });

  group('the text it offers to edit', () {
    test('holds what is in the pack', () {
      manager.seedItems([
        item('A', selected: true, weight: 3),
        item('B', selected: true),
      ]);

      final text = manager.manifestText();

      expect(text, contains('Name: A'));
      expect(text, contains('Weight: 3'));
      expect(text, contains('Name: B'));
    });

    test('leaves out what is not', () {
      manager.seedItems([item('A', selected: true), item('B')]);

      expect(manager.manifestText(), isNot(contains('Name: B')));
    });

    // Round trip: the text the screen hands the editor has to come back as
    // the same pack, or saving without an edit would change the upload.
    test('comes back as the same pack', () {
      manager.seedItems([
        item('A', selected: true, weight: 3),
        item('B'),
        item('C', selected: true),
      ]);

      final result = manager.applyManifest(manager.manifestText());

      expect(result.applied, 2);
      expect(result.nameless, 0);
      expect(entryOf('A').selected, isTrue);
      expect(entryOf('A').weight, 3);
      expect(entryOf('B').selected, isFalse);
      expect(entryOf('C').selected, isTrue);
    });
  });

  // The preview is the whole point of selecting a row: the animation appears
  // on the Flipper's external display. It is loaded off disk, and a project
  // whose folder has gone used to fail with the row selected, the device
  // blank, and nothing said anywhere.
}
