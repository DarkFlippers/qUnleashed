// The parts every ratchet shares, tested once instead of three times.
//
// `budgetDrift` only ever runs its passing path over the real tree, because
// the tree sits at budget - so without a test of its own, the branch that
// fails the build never executes until the day it has to.
import 'package:flutter_test/flutter_test.dart';

import 'ratchet.dart';

void main() {
  group('the budget comparison', () {
    test('says nothing when every area is exactly at budget', () {
      final drift = budgetDrift({'a': 2}, {'a': 2});
      expect(drift.over, isEmpty);
      expect(drift.under, isEmpty);
    });

    test('reports an area that has grown, and one that has shrunk', () {
      final drift = budgetDrift({'a': 3, 'b': 1}, {'a': 2, 'b': 2});
      expect(drift.over, ['a: 3, up from 2']);
      expect(drift.under, ['b: 1, down from 2']);
    });

    test('an area nobody declared starts at zero, so its first site fails', () {
      final drift = budgetDrift({'brand/new': 1}, const {});
      expect(drift.over, ['brand/new: 1, up from 0']);
    });

    test('an area that has emptied out is reported, not forgotten', () {
      final drift = budgetDrift(const {}, {'gone': 4});
      expect(drift.under, ['gone: 0, down from 4']);
    });
  });

  group('the area a file belongs to', () {
    test('is the first directory under lib', () {
      expect(areaOf('lib/services/http/app_http.dart'), 'services');
      expect(areaOf('lib/components/icon.dart'), 'components');
    });

    test('is one level deeper under pages, which is where the sites are', () {
      expect(areaOf('lib/pages/devices/widgets/firmware_card.dart'), 'pages/devices');
      expect(areaOf('lib/pages/tools/mifare/recover_controller.dart'), 'pages/tools');
    });

    test('is the file itself when it sits directly in lib', () {
      // `lib/main.dart` is not part of any area, and absorbing it into a
      // neighbour would hide it. Declaring it is the honest answer.
      expect(areaOf('lib/main.dart'), 'main.dart');
    });
  });

  group('the file list', () {
    test('is the whole of lib, and nothing outside it', () {
      final files = dartFilesUnderLib();

      expect(files, hasLength(greaterThan(100)));
      expect(files.every((path) => path.startsWith('lib/')), isTrue);
      expect(files.every((path) => path.endsWith('.dart')), isTrue);
    });

    test('leaves the submodules out, since git sees them as gitlinks', () {
      // flipperlib and dartufbt live under lib/modules and have their own
      // suites. A ratchet that walked into them would count a budget nobody
      // here can lower.
      expect(
        dartFilesUnderLib().where((path) => path.startsWith('lib/modules/')),
        isEmpty,
      );
    });
  });
}
