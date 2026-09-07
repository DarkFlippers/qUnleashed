import 'package:qunleashed/components/path.dart';
import 'package:flutter_test/flutter_test.dart';

/// A fixed separator keeps the expectations readable and makes the suite
/// behave the same on every host.
String? resolve(String name) => resolveArchivePath('/root', name, separator: '/');

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

    test('defaults to the host separator when none is given', () {
      final joined = resolveArchivePath('/root', 'a/b');
      expect(joined, isNotNull);
      expect(joined, startsWith('/root'));
      expect(joined, endsWith('b'));
    });
  });
}
