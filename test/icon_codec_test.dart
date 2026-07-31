import 'dart:io';

import 'package:dartufbt/dartufbt.dart';
import 'package:flutter_test/flutter_test.dart';

/// A Netpbm bitmap icon, the form the catalog ships for some apps.
const String _pbmIcon = '''
P1
10 10
0 0 0 0 1 1 0 0 0 0
0 0 0 1 1 1 1 0 0 0
0 0 1 1 1 1 1 1 0 0
0 1 1 1 0 0 1 1 1 0
0 1 1 0 0 0 0 1 1 0
0 1 0 0 0 0 0 0 1 0
0 1 1 0 0 0 0 1 1 0
0 0 1 1 0 0 1 1 0 0
0 0 0 1 1 1 1 0 0 0
0 0 0 0 1 1 0 0 0 0
''';

/// Bytes ufbt puts into .fapmeta for the icon above.
const List<int> _referenceXbm = [
  0x30, 0x00, //
  0x78, 0x00,
  0xFC, 0x00,
  0xCE, 0x01,
  0x86, 0x01,
  0x02, 0x01,
  0x86, 0x01,
  0xCC, 0x00,
  0x78, 0x00,
  0x30, 0x00,
];

void main() {
  test('decodes a netpbm icon the way fbt does', () async {
    final dir = await Directory.systemTemp.createTemp('dartufbt_icon');
    addTearDown(() => dir.deleteSync(recursive: true));
    final file = File('${dir.path}/icon.icon')..writeAsStringSync(_pbmIcon);

    final image = const IconCodec().fileToImage(file);

    expect(image.width, 10);
    expect(image.height, 10);
    expect(image.xbm, _referenceXbm);
    expect(image.isCompressed, isFalse);
  });
}
