// That a search which could not read everything says so.
//
// `searchAllIrFiles` walked the tree behind a `catch (_) { continue; }`. A
// folder that fails to list prunes its entire subtree from the walk, so one
// failure near the root can cost most of the library — and the short result
// was handed back as though it were complete. CLAUDE.md names that shape as
// one that has already shipped bugs here; #351 calls it out as adjacent to
// the permission work and cheap to fix alongside.
//
// The walk still returns what it found, which is the right call: ninety of a
// hundred matches beats an exception. What changed is that the caller is told
// the count is a floor rather than a total.
import 'package:flutter_test/flutter_test.dart';
import 'package:qunleashed/pages/tools/infrared/api.dart';
import 'package:qunleashed/pages/tools/infrared/models.dart';

/// An API whose directory listing fails for one named folder.
///
/// Subclasses the real [IrLibApi] and overrides only [listDir], which is the
/// network/disk boundary — so the walk under test is the real one, not a
/// reimplementation of it in the fake.
class _PartialApi extends IrLibApi {
  _PartialApi({required this.tree, required this.unreadable});

  /// path -> entries.
  final Map<String, List<IrEntry>> tree;

  /// Paths whose listing throws, as an unlistable folder does.
  final Set<String> unreadable;

  final List<String> listed = [];

  @override
  Future<List<IrEntry>> listDir(String path) async {
    listed.add(path);
    if (unreadable.contains(path)) {
      throw StateError('cannot list "$path"');
    }
    return tree[path] ?? const <IrEntry>[];
  }
}

IrEntry _dir(String path, String name) =>
    IrEntry(name: name, path: path, type: IrEntryType.dir);

IrEntry _file(String path, String name) =>
    IrEntry(name: name, path: path, type: IrEntryType.file);

void main() {
  test('a readable tree reports nothing unreadable', () async {
    final api = _PartialApi(
      tree: {
        '': [_dir('TV', 'TV')],
        'TV': [_file('TV/sony.ir', 'sony.ir')],
      },
      unreadable: const {},
    );

    final result = await api.searchAllIrFiles(
      query: 'sony',
      onProgress: (_, _) {},
    );

    expect(result.entries.map((e) => e.name), ['sony.ir']);
    expect(result.complete, isTrue);
  });

  test(
    'a folder that will not list is counted, and the walk goes on',
    () async {
      // The shape that mattered: one subtree is lost, another is fine. The old
      // code returned the one match and called it the whole answer.
      final api = _PartialApi(
        tree: {
          '': [_dir('TV', 'TV'), _dir('AC', 'AC')],
          'TV': [_file('TV/sony-tv.ir', 'sony-tv.ir')],
          'AC': [_file('AC/sony-ac.ir', 'sony-ac.ir')],
        },
        unreadable: const {'AC'},
      );

      final result = await api.searchAllIrFiles(
        query: 'sony',
        onProgress: (_, _) {},
      );

      expect(result.entries.map((e) => e.name), [
        'sony-tv.ir',
      ], reason: 'what it could reach is still returned');
      expect(
        result.complete,
        isFalse,
        reason: 'and the caller learns the list is a floor, not a total',
      );
    },
  );

  test('a root that will not list is a count, not an empty library', () async {
    // The worst case, and the one a denied storage permission produces on a
    // local library: nothing at all was readable. Zero matches plus zero
    // warnings reads as "your query matched nothing", which is a different
    // and wrong answer.
    final api = _PartialApi(tree: const {}, unreadable: const {''});

    final result = await api.searchAllIrFiles(
      query: 'sony',
      onProgress: (_, _) {},
    );

    expect(result.entries, isEmpty);
    expect(result.complete, isFalse);
  });

  test('an empty query walks nothing', () async {
    final api = _PartialApi(tree: const {}, unreadable: const {''});

    final result = await api.searchAllIrFiles(
      query: '   ',
      onProgress: (_, _) {},
    );

    expect(result.entries, isEmpty);
    expect(result.complete, isTrue);
    expect(api.listed, isEmpty, reason: 'it returned before the walk');
  });
}
