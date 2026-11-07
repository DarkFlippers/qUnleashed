import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flipperlib/flipperlib.dart';

import '../../components/codec/dolphin/manifest.dart';
import 'library.dart';

class DolphinManifestEditor {
  DolphinManifestEditor({required this.client});

  final FlipperClient client;

  static const Duration _timeout = Duration(seconds: 30);

  Future<String> edit(ManifestEntry entry) async {
    final device = await _deviceMd5();
    if (device == null) return _apply('', entry);
    final local = await _readLocal();
    if (local != null && md5.convert(local).toString() == device) {
      return _apply(utf8.decode(local, allowMalformed: true), entry);
    }
    final remote = await client.storageReadChunked(
      kDolphinManifestPath,
      timeout: _timeout,
    );
    return _apply(utf8.decode(remote, allowMalformed: true), entry);
  }

  Future<void> write(String text) async {
    final bytes = utf8.encode(text);
    await client.storageWriteChunked(kDolphinManifestPath, bytes);
    final expected = md5.convert(bytes).toString();
    final actual = await _deviceMd5();
    if (actual != expected) {
      throw StateError(
        'Uploaded "$kDolphinManifestPath" is corrupted: md5 $actual, '
        'expected $expected',
      );
    }
    await saveToDolphinLibrary(kDolphinManifestPath, bytes);
  }

  Future<String?> _deviceMd5() async {
    try {
      final batch = await client.storageMd5sum(
        Md5sumRequest(path: kDolphinManifestPath),
        timeout: _timeout,
      );
      final sum = batch.items.isNotEmpty ? batch.items.first.md5sum : '';
      return sum.trim().toLowerCase();
    } on FlipperRpcStorageNotExistException {
      return null;
    }
  }

  Future<List<int>?> _readLocal() async {
    final file = await dolphinLibraryFile(kDolphinManifestPath);
    if (file == null || !await file.exists()) return null;
    return file.readAsBytes();
  }

  static String _apply(String text, ManifestEntry entry) {
    if (text.trim().isEmpty) return DolphinManifest.build([entry]);
    final eol = text.contains('\r\n') ? '\r\n' : '\n';
    final block = DolphinManifest.block(entry).replaceAll('\n', eol);
    final lines = _lines(text);
    final out = StringBuffer();
    var copied = 0;
    var placed = false;
    for (var i = 0; i < lines.length; i++) {
      if (!_namesEntry(lines[i].content, entry.name)) continue;
      var end = i + 1;
      while (end < lines.length && !_endsBlock(lines[end].content)) {
        end++;
      }
      out.write(text.substring(copied, lines[i].start));
      if (!placed) out.write(block);
      placed = true;
      copied = end < lines.length ? lines[end].start : text.length;
      i = end - 1;
    }
    if (placed) {
      out.write(text.substring(copied));
      return out.toString();
    }
    return [
      text,
      if (!text.endsWith('\n')) eol,
      if (lines.last.content.trimRight().isNotEmpty) eol,
      block,
    ].join();
  }

  static List<({int start, String content})> _lines(String text) {
    final out = <({int start, String content})>[];
    var start = 0;
    while (start < text.length) {
      final newline = text.indexOf('\n', start);
      final end = newline < 0 ? text.length : newline;
      out.add((start: start, content: text.substring(start, end)));
      start = end + 1;
    }
    return out;
  }

  static bool _namesEntry(String line, String name) {
    final trimmed = line.trimRight();
    return trimmed.startsWith('Name: ') && trimmed.substring(6).trim() == name;
  }

  static bool _endsBlock(String line) {
    final trimmed = line.trimRight();
    return trimmed.isEmpty || trimmed.startsWith('Name: ');
  }
}
