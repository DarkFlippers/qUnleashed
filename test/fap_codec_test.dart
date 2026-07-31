import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qunleashed/components/codec/fap.dart';
import 'package:qunleashed/pages/apps/data/models/fap_details.dart';
import 'package:qunleashed/pages/apps/data/models/installed_app.dart';
import 'package:qunleashed/pages/apps/manager/widgets/fap_facts.dart';
import 'package:qunleashed/theme/theme.dart';

void main() {
  group('FapInfo.parse', () {
    test('reads the manifest of a well-formed fap', () {
      final info = FapInfo.parse(_buildFap());
      final manifest = info!.manifest!;

      expect(manifest.isValid, isTrue);
      expect(manifest.name, 'Test App');
      expect(manifest.api, '86.3');
      expect(manifest.target, 'f7');
      expect(manifest.stackSize, 2048);
      expect(manifest.version, '4.2');
      expect(manifest.hasIcon, isTrue);
      expect(manifest.isPlugin, isFalse);
    });

    test('lists undefined symbols as API imports', () {
      final info = FapInfo.parse(_buildFap())!;
      expect(info.imports, ['furi_delay_ms', 'furi_record_open']);
    });

    test('accounts for every section the loader allocates', () {
      final info = FapInfo.parse(_buildFap())!;

      expect(info.codeSize, 256);
      expect(info.readOnlyDataSize, 64);
      expect(info.bssSize, 128);
      expect(info.relocationSize, 32);
      expect(info.ramTotal, 256 + 64 + 128 + 32);
      expect(info.ramLargestBlock, 256);
      expect(info.hasFastRelocations, isTrue);
      expect(info.debugLink, 'test_app_d.elf');
    });

    test('skips ARM sections the firmware ignores', () {
      final info = FapInfo.parse(_buildFap())!;
      expect(
        info.loadedSections.map((s) => s.name),
        isNot(contains('.ARM.exidx')),
      );
    });

    test('unpacks the assets bundle', () {
      final assets = FapInfo.parse(_buildFap())!.assets!;

      expect(assets.dirs, ['sounds']);
      expect(assets.files.map((f) => f.path), ['plugins/extra.fal', 'tone.wav']);
      expect(assets.totalSize, 7);
      expect(assets.signature, '0102030405060708090a0b0c0d0e0f10');
      expect(assets.plugins.single.path, 'plugins/extra.fal');
    });

    test('rejects files that are not ELF', () {
      expect(FapInfo.parse(Uint8List.fromList([1, 2, 3, 4])), isNull);
    });

    test('reports a broken manifest', () {
      final bytes = _buildFap(metaMagic: 0xdeadbeef);
      expect(FapInfo.parse(bytes)!.isValid, isFalse);
    });
  });

  group('evaluateFap', () {
    FapInfo info({int apiMajor = 86, int target = 7}) =>
        FapInfo.parse(_buildFap(apiMajor: apiMajor, target: target))!;

    test('passes an app built for the same API major', () {
      final compat =
          evaluateFap(info(), deviceApi: '86.9', deviceTarget: 'f7');
      expect(compat.verdict, FapVerdict.ok);
      expect(compat.isBlocking, isFalse);
    });

    test('flags an app built for an older API', () {
      final compat =
          evaluateFap(info(apiMajor: 85), deviceApi: '86.9', deviceTarget: 'f7');
      expect(compat.verdict, FapVerdict.apiTooOld);
      expect(compat.isBlocking, isTrue);
    });

    test('flags an app built for a newer API', () {
      final compat =
          evaluateFap(info(apiMajor: 88), deviceApi: '86.9', deviceTarget: 'f7');
      expect(compat.verdict, FapVerdict.apiTooNew);
    });

    test('flags a hardware target mismatch', () {
      final compat =
          evaluateFap(info(target: 18), deviceApi: '86.9', deviceTarget: 'f7');
      expect(compat.verdict, FapVerdict.targetMismatch);
    });

    test('stays quiet when the device API is unknown', () {
      final compat = evaluateFap(info(), deviceApi: null, deviceTarget: null);
      expect(compat.verdict, FapVerdict.unknown);
      expect(compat.isBlocking, isFalse);
    });

    test('marks unreadable files', () {
      expect(evaluateFap(null).verdict, FapVerdict.unreadable);
    });
  });

  group('FapFactsPanel', () {
    Future<void> pump(WidgetTester tester, InstalledApp app) {
      return tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(Brightness.dark, Colors.orange),
          home: Scaffold(
            body: FapFactsPanel(
              app: app,
              deviceApi: '86.9',
              deviceTarget: 'f7',
            ),
          ),
        ),
      );
    }

    InstalledApp app({FapInfo? fap, bool checked = true}) => InstalledApp(
          alias: 'test_app',
          path: '/ext/apps/Tools/test_app.fap',
          folder: 'Tools',
          size: 512,
          md5: '',
          fap: fap,
          fapChecked: checked,
        );

    testWidgets('asks for a sync when the file was not read', (tester) async {
      await pump(tester, app(checked: false));
      expect(find.textContaining('Sync the manager'), findsOneWidget);
    });

    testWidgets('shows what the loader would allocate', (tester) async {
      await pump(tester, app(fap: FapInfo.parse(_buildFap())));

      expect(find.text('Runs on this firmware'), findsOneWidget);
      expect(find.text('API 86.3 · f7'), findsOneWidget);
      expect(find.textContaining('2 files'), findsOneWidget);
      expect(find.textContaining('imported symbols'), findsOneWidget);
      expect(find.text('fast (fastfap)'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('explains why an app will not start', (tester) async {
      await pump(tester, app(fap: FapInfo.parse(_buildFap(apiMajor: 84))));
      expect(find.text('Built for API 84.3, firmware is 86.9'), findsOneWidget);
    });
  });
}

Uint8List _buildFapMeta({
  int magic = kFapMetaMagic,
  int apiMajor = 86,
  int target = 7,
}) {
  final out = Uint8List(FapManifest.structSize);
  final data = ByteData.sublistView(out);
  data.setUint32(0, magic, Endian.little);
  data.setUint32(4, kFapMetaVersion, Endian.little);
  data.setUint16(8, 3, Endian.little);
  data.setUint16(10, apiMajor, Endian.little);
  data.setUint16(12, target, Endian.little);
  data.setUint16(14, 2048, Endian.little);
  data.setUint16(16, 2, Endian.little);
  data.setUint16(18, 4, Endian.little);
  out.setRange(
    FapManifest.nameOffset,
    FapManifest.nameOffset + 8,
    'Test App'.codeUnits,
  );
  out[FapManifest.hasIconOffset] = 1;
  return out;
}

Uint8List _buildAssets() {
  final out = BytesBuilder();

  void u32(int value) {
    final data = ByteData(4)..setUint32(0, value, Endian.little);
    out.add(data.buffer.asUint8List());
  }

  void cstring(String value) {
    u32(value.length + 1);
    out.add(Uint8List.fromList([...value.codeUnits, 0]));
  }

  u32(kFapAssetsMagic);
  u32(kFapAssetsVersion);
  u32(1);
  u32(2);
  u32(16);
  out.add(Uint8List.fromList(List<int>.generate(16, (i) => i + 1)));

  cstring('sounds');

  cstring('plugins/extra.fal');
  u32(3);
  out.add(Uint8List.fromList([1, 2, 3]));

  cstring('tone.wav');
  u32(4);
  out.add(Uint8List.fromList([4, 5, 6, 7]));

  return out.toBytes();
}

Uint8List _buildSymtab() {
  final out = Uint8List(16 * 4);
  final data = ByteData.sublistView(out);
  void symbol(int index, int nameOffset, int sectionIndex) {
    final base = index * 16;
    data.setUint32(base, nameOffset, Endian.little);
    data.setUint16(base + 14, sectionIndex, Endian.little);
  }

  symbol(0, 0, 0);
  symbol(1, 1, 0);
  symbol(2, 15, 0);
  symbol(3, 32, 4);
  return out;
}

/// Assembles a minimal ELF32 that carries the sections a real `.fap` has.
Uint8List _buildFap({
  int metaMagic = kFapMetaMagic,
  int apiMajor = 86,
  int target = 7,
}) {
  const shtProgbits = 1;
  const shtSymtab = 2;
  const shtStrtab = 3;
  const shtNobits = 8;
  const shfWrite = 0x1;
  const shfAlloc = 0x2;
  const shfExecInstr = 0x4;

  final strtab = Uint8List.fromList([
    0,
    ...'furi_delay_ms'.codeUnits,
    0,
    ...'furi_record_open'.codeUnits,
    0,
    ...'local_symbol'.codeUnits,
    0,
  ]);

  final payloads = <String, Uint8List>{
    '.text': Uint8List(256),
    '.rodata': Uint8List(64),
    '.bss': Uint8List(0),
    '.fast.rel.text': Uint8List(32),
    '.ARM.exidx': Uint8List(16),
    kFapMetaSection: _buildFapMeta(
      magic: metaMagic,
      apiMajor: apiMajor,
      target: target,
    ),
    kFapAssetsSection: _buildAssets(),
    '.symtab': _buildSymtab(),
    '.strtab': strtab,
    kFapDebugLinkSection: Uint8List.fromList([...'test_app_d.elf'.codeUnits, 0]),
  };

  final names = ['', ...payloads.keys, '.shstrtab'];
  final shstrtab = BytesBuilder();
  final nameOffsets = <String, int>{};
  for (final name in names) {
    nameOffsets[name] = shstrtab.length;
    shstrtab.add(Uint8List.fromList([...name.codeUnits, 0]));
  }
  final shstrtabBytes = shstrtab.toBytes();

  final ordered = [
    ('', shtProgbits, 0, Uint8List(0)),
    ('.text', shtProgbits, shfAlloc | shfExecInstr, payloads['.text']!),
    ('.rodata', shtProgbits, shfAlloc, payloads['.rodata']!),
    ('.bss', shtNobits, shfAlloc | shfWrite, payloads['.bss']!),
    ('.fast.rel.text', shtProgbits, 0, payloads['.fast.rel.text']!),
    ('.ARM.exidx', shtProgbits, shfAlloc, payloads['.ARM.exidx']!),
    (kFapMetaSection, shtProgbits, 0, payloads[kFapMetaSection]!),
    (kFapAssetsSection, shtProgbits, 0, payloads[kFapAssetsSection]!),
    ('.symtab', shtSymtab, 0, payloads['.symtab']!),
    ('.strtab', shtStrtab, 0, payloads['.strtab']!),
    (kFapDebugLinkSection, shtProgbits, 0, payloads[kFapDebugLinkSection]!),
    ('.shstrtab', shtStrtab, 0, shstrtabBytes),
  ];

  const headerSize = 52;
  const entrySize = 40;
  final sectionCount = ordered.length;
  final tableOffset = headerSize;
  var cursor = tableOffset + entrySize * sectionCount;

  final offsets = <int>[];
  for (final section in ordered) {
    offsets.add(cursor);
    cursor += section.$4.length;
  }

  final out = Uint8List(cursor);
  final data = ByteData.sublistView(out);

  out.setRange(0, 4, [0x7f, 0x45, 0x4c, 0x46]);
  out[4] = 1;
  out[5] = 1;
  out[6] = 1;
  data.setUint16(16, 1, Endian.little);
  data.setUint16(18, 40, Endian.little);
  data.setUint32(20, 1, Endian.little);
  data.setUint32(32, tableOffset, Endian.little);
  data.setUint16(40, headerSize, Endian.little);
  data.setUint16(46, entrySize, Endian.little);
  data.setUint16(48, sectionCount, Endian.little);
  data.setUint16(50, sectionCount - 1, Endian.little);

  for (var i = 0; i < sectionCount; i++) {
    final (name, type, flags, bytes) = ordered[i];
    final base = tableOffset + i * entrySize;
    data.setUint32(base, nameOffsets[name]!, Endian.little);
    data.setUint32(base + 4, type, Endian.little);
    data.setUint32(base + 8, flags, Endian.little);
    data.setUint32(base + 16, offsets[i], Endian.little);
    data.setUint32(base + 20, name == '.bss' ? 128 : bytes.length, Endian.little);
    data.setUint32(base + 24, name == '.symtab' ? 9 : 0, Endian.little);
    data.setUint32(base + 32, 4, Endian.little);
    out.setRange(offsets[i], offsets[i] + bytes.length, bytes);
  }

  return out;
}
