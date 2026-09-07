import 'package:flutter_test/flutter_test.dart';
import 'package:qunleashed/components/path.dart';

/// A fixed separator keeps the expectations readable and makes the suite
/// behave the same on every host.
String? resolve(String name) =>
    resolveArchivePath('/root', name, separator: '/');

String? resolveWrapped(String name) =>
    resolveWrappedArchivePath('/root', name, separator: '/');

/// Entry names an archive has no business carrying, each with the exact result
/// it must produce. Spelling out the `null`s is the point: an implementation
/// that "repaired" a traversal by popping a segment instead of refusing it
/// would still keep every result inside the root, so only pinning the refusal
/// catches it.
const Map<String, String?> hostileNames = {
  '../evil': null,
  '../../evil': null,
  'a/../../evil': null,
  'a/b/../../../../../evil': null,
  './../evil': null,
  'a/./../../evil': null,
  r'..\evil': null,
  r'a\..\..\evil': null,
  'a/..\\../evil': null,
  ' .. /evil': null,
  'a/ ..  /evil': null,
  '/../evil': null,
  '//../../evil': null,
  '..': null,
  '../': null,
  'a/b/..': null,
  '': null,
  '/': null,
  './.': null,
  // Not traversals: they stay inside the root as literal names.
  r'C:\Windows\evil': '/root/C_/Windows/evil',
  r'\\server\share\evil': '/root/server/share/evil',
  '....//....//evil': '/root/..../..../evil',
  'a/...../../../evil': null,
};

void main() {
  group('resolveArchivePath', () {
    test('joins a plain relative entry under the root', () {
      expect(resolve('Samsung/TV.ir'), '/root/Samsung/TV.ir');
    });

    test('accepts backslash separated entries', () {
      expect(resolve(r'Samsung\TV.ir'), '/root/Samsung/TV.ir');
    });

    test('drops empty and current-directory segments', () {
      expect(resolve('.//Samsung/./TV.ir'), '/root/Samsung/TV.ir');
    });

    test('reads an absolute entry as relative to the root', () {
      expect(resolve('/etc/passwd'), '/root/etc/passwd');
    });

    test('refuses a parent-directory segment', () {
      expect(resolve('../evil'), isNull);
      expect(resolve('Samsung/../../evil'), isNull);
      expect(resolve('a/b/../../../../evil'), isNull);
    });

    test('refuses a parent-directory segment written with backslashes', () {
      expect(resolve(r'..\..\evil'), isNull);
      expect(resolve(r'Samsung\..\..\evil'), isNull);
    });

    test('refuses a parent-directory segment padded with whitespace', () {
      expect(resolve('Samsung/ .. /evil'), isNull);
    });

    test('refuses an entry with nothing left to write', () {
      expect(resolve(''), isNull);
      expect(resolve('/'), isNull);
      expect(resolve('./.'), isNull);
    });

    test('sanitizes characters no filesystem accepts', () {
      expect(resolve('So?ny/T*V.ir'), '/root/So_ny/T_V.ir');
    });

    test('neutralizes a Windows drive prefix into a plain segment', () {
      // The colon cannot survive as a drive letter, so the entry stays inside
      // the root instead of being redirected to another volume.
      expect(resolve(r'C:\Windows\evil'), '/root/C_/Windows/evil');
    });

    test('builds the path with the separator it is given', () {
      // The IRDB unpacker runs in an isolate and passes the host separator
      // through its spawn arguments, so this parameter is load-bearing on
      // Windows rather than a testing convenience.
      expect(
        resolveArchivePath(r'C:\root', 'Samsung/TV.ir', separator: r'\'),
        r'C:\root\Samsung\TV.ir',
      );
    });

    test('resolves every hostile name to exactly the documented result', () {
      hostileNames.forEach((name, expected) {
        expect(resolve(name), expected, reason: 'entry: "$name"');
      });
    });
  });

  group('resolveWrappedArchivePath', () {
    test('strips the wrapper folder the source archive adds', () {
      expect(
        resolveWrapped('Flipper-IRDB-main/Samsung/TV.ir'),
        '/root/Samsung/TV.ir',
      );
    });

    test('skips an entry sitting beside the wrapper folder', () {
      expect(resolveWrapped('README.md'), isNull);
    });

    test('skips the wrapper folder itself', () {
      expect(resolveWrapped('Flipper-IRDB-main/'), isNull);
    });

    // The regression this guards: before the containment check, the unpacker
    // joined the stripped name straight onto the root, so these wrote outside
    // the IR library entirely.
    test('refuses an entry escaping the library root', () {
      expect(resolveWrapped('Flipper-IRDB-main/../../evil'), isNull);
      expect(resolveWrapped(r'Flipper-IRDB-main\..\..\evil'), isNull);
    });

    test('applies the same refusals once the wrapper is stripped', () {
      hostileNames.forEach((name, expected) {
        expect(
          resolveWrapped('Flipper-IRDB-main/$name'),
          expected,
          reason: 'entry: "$name"',
        );
      });
    });
  });
}
