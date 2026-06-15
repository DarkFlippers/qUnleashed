import 'dart:typed_data';

import 'package:flipperlib/dfu/dfu_memory_layout.dart';
import 'package:flipperlib/dfu/dfuse_file.dart';
import 'package:flipperlib/dfu/stm32wb55/option_bytes.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DfuMemoryLayout', () {
    test('parses a single-bank descriptor and computes page addresses', () {
      final layout = DfuMemoryLayout.fromStringDescriptor(
        '@Internal Flash /0x08000000/256*004Kg',
      );
      expect(layout.isValid, isTrue);
      expect(layout.name, '@Internal Flash');
      expect(layout.address, 0x08000000);
      expect(layout.pageBanks.single.pageCount, 256);
      expect(layout.pageBanks.single.pageSize, 4096);

      final pages = layout.pageAddresses(0x08000000, 0x08000000 + 8192);
      expect(pages, [0x08000000, 0x08001000]);
    });

    test('rejects malformed descriptors', () {
      expect(DfuMemoryLayout.fromStringDescriptor('garbage').isValid, isFalse);
    });
  });

  group('OptionBytes', () {
    test('field values round-trip through device-data packing', () {
      final ob = OptionBytes.fromDeviceData(Uint8List(OptionBytes.sizeBytes));
      ob.setValue('RDP', 0xAA);
      ob.setValue('SFSA', 0x1B);
      ob.setValue('nBOOT0', 1);
      ob.setValue('nSWBOOT0', 0);
      ob.setValue('SBRV', 0x3FFFF);

      final packed = ob.toData();
      expect(packed.length, OptionBytes.sizeBytes);

      final readBack = OptionBytes.fromDeviceData(packed);
      expect(readBack.value('RDP'), 0xAA);
      expect(readBack.value('SFSA'), 0x1B);
      expect(readBack.value('nBOOT0'), 1);
      expect(readBack.value('nSWBOOT0'), 0);
      expect(readBack.value('SBRV'), 0x3FFFF);
    });

    test('complement words are written correctly', () {
      final ob = OptionBytes.fromDeviceData(Uint8List(OptionBytes.sizeBytes));
      ob.setValue('RDP', 0xAA);
      ob.setValue('nBOOT0', 1);
      final data = ob.toData();
      final bd = ByteData.sublistView(data);

      final normal = bd.getUint32(0, Endian.little);
      final complement = bd.getUint32(4, Endian.little);
      expect(normal & 0xFF, 0xAA);
      expect(complement & 0xFF, (~0xAA) & 0xFF);
      expect((normal >> 27) & 1, 1);
      expect((complement >> 27) & 1, 0);
    });

    test('compare reports only differing fields', () {
      final a = OptionBytes.fromDeviceData(Uint8List(OptionBytes.sizeBytes));
      a.setValue('nBOOT0', 1);
      final b = OptionBytes.fromDeviceData(a.toData());
      expect(a.compare(b), isEmpty);

      b.setValue('nBOOT0', 0);
      final diff = a.compare(b);
      expect(diff.keys, contains('nBOOT0'));
      expect(diff['nBOOT0'], 0);
    });

    test('parses text option-bytes file', () {
      final ob = OptionBytes.fromText('RDP:0xAA:whatever\nSFSA:0x1B:x\n');
      expect(ob.isValid, isTrue);
      expect(ob.value('RDP'), 0xAA);
      expect(ob.value('SFSA'), 0x1B);
    });
  });

  group('DfuseFile', () {
    test('parses a minimal valid DfuSe container with one element', () {
      final fw = Uint8List.fromList([0xDE, 0xAD, 0xBE, 0xEF]);
      final bytes = _buildDfuse(alt: 0, address: 0x08000000, data: fw);
      final file = DfuseFile.parse(bytes);
      expect(file.isValid, isTrue);
      final elem = file.images.single.elements.single;
      expect(elem.address, 0x08000000);
      expect(elem.data, fw);
    });

    test('rejects a corrupted CRC', () {
      final bytes = _buildDfuse(
        alt: 0,
        address: 0x08000000,
        data: Uint8List.fromList([1, 2, 3, 4]),
      );
      bytes[bytes.length - 1] ^= 0xFF;
      expect(DfuseFile.parse(bytes).isValid, isFalse);
    });
  });
}

Uint8List _buildDfuse({
  required int alt,
  required int address,
  required Uint8List data,
}) {
  final b = BytesBuilder();
  final target = BytesBuilder();
  target.add('Target'.codeUnits);
  target.addByte(alt);
  target.add(_u32(0));
  target.add(Uint8List(255));
  final elementSize = 8 + data.length;
  target.add(_u32(elementSize));
  target.add(_u32(1));
  target.add(_u32(address));
  target.add(_u32(data.length));
  target.add(data);
  final targetBytes = target.toBytes();

  b.add('DfuSe'.codeUnits);
  b.addByte(0x01);
  final dfuImageSize = 11 + targetBytes.length;
  b.add(_u32(dfuImageSize));
  b.addByte(1);
  b.add(targetBytes);

  b.add(_u16(0xFFFF));
  b.add(_u16(0xDF11));
  b.add(_u16(0x0483));
  b.add(_u16(0x011A));
  b.add([0x55, 0x46, 0x44]);
  b.addByte(16);
  final withoutCrc = b.toBytes();

  final crc = _dfuseCrc(withoutCrc);
  return Uint8List.fromList([...withoutCrc, ..._u32(crc)]);
}

int _dfuseCrc(Uint8List bytesWithoutCrc) {
  final lut = List<int>.filled(256, 0);
  for (var i = 0; i < 256; i++) {
    var val = i;
    for (var j = 0; j < 8; j++) {
      val = (val & 1) != 0 ? 0xEDB88320 ^ (val >> 1) : val >> 1;
    }
    lut[i] = val;
  }
  var val = 0xFFFFFFFF;
  for (final byte in bytesWithoutCrc) {
    val = (lut[(val ^ byte) & 0xFF] ^ (val >> 8)) & 0xFFFFFFFF;
  }
  return val;
}

Uint8List _u16(int v) =>
    Uint8List(2)..buffer.asByteData().setUint16(0, v, Endian.little);
Uint8List _u32(int v) =>
    Uint8List(4)..buffer.asByteData().setUint32(0, v, Endian.little);
