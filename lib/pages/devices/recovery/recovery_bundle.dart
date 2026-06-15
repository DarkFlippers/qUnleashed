import 'dart:convert';
import 'dart:io' as io;
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flipperlib/flipperlib.dart';
import 'package:flutter/foundation.dart';

import '../firmware/directory.dart';

class RecoveryBundle {
  const RecoveryBundle._();

  static const double _firmwareShare = 0.8;
  static const double _radioShare = 0.15;
  static const double _scriptsShare = 0.05;

  static Future<RecoveryRequest> fetch({
    required FirmwareParser parser,
    required String channelId,
    String target = 'f7',
    void Function(double progress)? onProgress,
  }) async {
    await parser.get();
    final version = parser.getLatestVersionById(channelId);
    if (version == null) {
      throw const RecoveryBundleException('No firmware version for channel');
    }

    final dfu = _fileFor(version, type: 'full_dfu', target: target);
    if (dfu == null) {
      throw RecoveryBundleException('No full_dfu firmware for target $target');
    }

    final firmware = await _downloadBytes(
      dfu.url,
      (p) => onProgress?.call(p * _firmwareShare),
    );

    Uint8List? radioBin;
    final core2 = _fileFor(version, type: 'core2_firmware_tgz', target: 'any');
    if (core2 != null) {
      try {
        final tgz = await _downloadBytes(
          core2.url,
          (p) => onProgress?.call(_firmwareShare + p * _radioShare),
        );
        radioBin = await compute(_extractRadioBin, tgz);
      } catch (e) {
        LogService.log('[Recovery] radio fetch failed (skipping): $e');
      }
    }

    String? optionBytesText;
    final scripts = _fileFor(version, type: 'scripts_tgz', target: 'any');
    if (scripts != null) {
      try {
        final tgz = await _downloadBytes(
          scripts.url,
          (p) => onProgress?.call(
            _firmwareShare + _radioShare + p * _scriptsShare,
          ),
        );
        optionBytesText = await compute(_extractObData, tgz);
      } catch (e) {
        LogService.log('[Recovery] option-bytes fetch failed (skipping): $e');
      }
    }

    onProgress?.call(1.0);
    return RecoveryRequest(
      firmwareDfu: firmware,
      radioBin: radioBin,
      optionBytesText: optionBytesText,
    );
  }

  static FirmwareFile? _fileFor(
    FirmwareVersion version, {
    required String type,
    required String target,
  }) {
    for (final f in version.files) {
      if (f.type == type && f.target == target) return f;
    }
    return null;
  }

  static Future<Uint8List> _downloadBytes(
    String url,
    void Function(double progress)? onProgress,
  ) async {
    final client = io.HttpClient();
    try {
      final req = await client.getUrl(Uri.parse(url));
      req.headers.set(io.HttpHeaders.userAgentHeader, 'qunleashed-app');
      final res = await req.close();
      if (res.statusCode != 200) {
        throw RecoveryBundleException('Download failed: ${res.statusCode}');
      }
      final total = res.contentLength;
      final builder = BytesBuilder(copy: false);
      var received = 0;
      await for (final chunk in res) {
        builder.add(chunk);
        received += chunk.length;
        if (total > 0) onProgress?.call(received / total);
      }
      if (total <= 0) onProgress?.call(1.0);
      return builder.toBytes();
    } finally {
      client.close();
    }
  }
}

Uint8List? _extractRadioBin(Uint8List tgz) {
  final entries = _untar(tgz);

  final manifestBytes = _findBySuffix(entries, 'manifest.json');
  if (manifestBytes == null) return null;

  final manifest =
      jsonDecode(utf8.decode(manifestBytes)) as Map<String, dynamic>;
  final copro = manifest['copro'] as Map<String, dynamic>?;
  final radio = copro?['radio'] as Map<String, dynamic>?;
  final files = radio?['files'] as List<dynamic>?;
  if (files == null || files.isEmpty) return null;
  final name = (files.first as Map<String, dynamic>)['name'] as String?;
  if (name == null || name.isEmpty) return null;

  return _findBySuffix(entries, 'core2_firmware/$name') ??
      _findBySuffix(entries, name);
}

String? _extractObData(Uint8List tgz) {
  final entries = _untar(tgz);
  final data =
      _findBySuffix(entries, 'scripts/ob.data') ??
      _findBySuffix(entries, 'ob.data');
  return data == null ? null : utf8.decode(data);
}

Map<String, Uint8List> _untar(Uint8List tgz) {
  final gz = GZipDecoder().decodeBytes(tgz);
  final archive = TarDecoder().decodeBytes(gz);
  final out = <String, Uint8List>{};
  for (final f in archive.files) {
    if (f.isFile) out[f.name] = Uint8List.fromList(f.content as List<int>);
  }
  return out;
}

Uint8List? _findBySuffix(Map<String, Uint8List> entries, String suffix) {
  for (final entry in entries.entries) {
    if (entry.key == suffix || entry.key.endsWith('/$suffix')) {
      return entry.value;
    }
  }
  return null;
}

class RecoveryBundleException implements Exception {
  const RecoveryBundleException(this.message);
  final String message;
  @override
  String toString() => message;
}
