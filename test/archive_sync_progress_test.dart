import 'package:flutter_test/flutter_test.dart';
import 'package:qunleashed/pages/archive/overview/controller.dart';

void main() {
  group('SyncProgress.ratio', () {
    test('null total yields no ratio', () {
      final p = SyncProgress(current: 0, total: 0, fileName: 'a');
      expect(p.ratio, isNull);
    });

    test('file-count only when no per-file progress', () {
      final p = SyncProgress(current: 2, total: 4, fileName: 'a');
      expect(p.ratio, closeTo(0.5, 1e-9));
    });

    test('combines completed files with the in-flight file fraction', () {
      final p = SyncProgress(
        current: 1,
        total: 4,
        fileName: 'a',
        fileProgress: 0.5,
      );
      expect(p.ratio, closeTo(0.375, 1e-9));
    });

    test('a large first file moves the bar off zero', () {
      final p = SyncProgress(
        current: 0,
        total: 5,
        fileName: 'big',
        fileProgress: 0.4,
      );
      expect(p.ratio, closeTo(0.08, 1e-9));
      expect(p.ratio, greaterThan(0));
    });

    test('ratio never exceeds 1', () {
      final p = SyncProgress(
        current: 5,
        total: 5,
        fileName: '',
        fileProgress: 1,
      );
      expect(p.ratio, 1.0);
    });
  });
}
