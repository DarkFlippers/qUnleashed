import 'dart:typed_data';

import 'package:crypto/crypto.dart' as hashes;
import 'package:cryptography/cryptography.dart' as ed;

import '../../../services/http/app_http.dart';

const String _signingKeysDefine = String.fromEnvironment('QU_SIGNING_KEYS');

final Map<String, String> kCatalogSigningKeys = _parseKeys(_signingKeysDefine);

Map<String, String> _parseKeys(String raw) {
  final out = <String, String>{};
  for (final entry in raw.split(',')) {
    final colon = entry.indexOf(':');
    if (colon <= 0) continue;
    final kid = entry.substring(0, colon).trim();
    final key = entry.substring(colon + 1).trim().toLowerCase();
    if (kid.isNotEmpty && key.isNotEmpty) out[kid] = key;
  }
  return Map.unmodifiable(out);
}

class ArtifactSignatureException implements Exception {
  ArtifactSignatureException(this.url, this.reason);

  final String url;
  final String reason;

  /// Signed, but by a key this build was not given: a build made without
  /// `QU_SIGNING_KEYS`, or a server that moved to a new key.
  bool get unknownKey => reason.startsWith('unknown key');

  @override
  String toString() => 'ArtifactSignatureException($reason, $url)';
}

Future<Uint8List> verifySignedArtifact(
  Uri uri,
  HttpBytes response, {
  Map<String, String>? keys,
}) async {
  ArtifactSignatureException refuse(String reason) =>
      ArtifactSignatureException(uri.toString(), reason);

  final sha = response.headers['x-qu-sha256']?.trim().toLowerCase() ?? '';
  final signature = response.headers['x-qu-sign-ed25519']?.trim() ?? '';
  final kid = response.headers['x-qu-kid']?.trim() ?? '';
  if (sha.isEmpty || signature.isEmpty || kid.isEmpty) {
    throw refuse('not signed');
  }
  final key = (keys ?? kCatalogSigningKeys)[kid];
  if (key == null) throw refuse('unknown key "$kid"');

  final digest = hashes.sha256.convert(response.bytes).bytes;
  if (_hex(digest) != sha) throw refuse('sha256 does not match the body');

  final signatureBytes = _unhex(signature);
  final keyBytes = _unhex(key);
  if (signatureBytes == null || signatureBytes.length != 64) {
    throw refuse('malformed signature');
  }
  if (keyBytes == null || keyBytes.length != 32) {
    throw refuse('malformed key "$kid"');
  }
  final valid = await ed.Ed25519().verify(
    digest,
    signature: ed.Signature(
      signatureBytes,
      publicKey: ed.SimplePublicKey(keyBytes, type: ed.KeyPairType.ed25519),
    ),
  );
  if (!valid) throw refuse('signature does not verify');
  return response.bytes;
}

String _hex(List<int> bytes) {
  final out = StringBuffer();
  for (final b in bytes) {
    out.write(b.toRadixString(16).padLeft(2, '0'));
  }
  return out.toString();
}

Uint8List? _unhex(String text) {
  if (text.length.isOdd) return null;
  final out = Uint8List(text.length ~/ 2);
  for (var i = 0; i < out.length; i++) {
    final byte = int.tryParse(text.substring(i * 2, i * 2 + 2), radix: 16);
    if (byte == null) return null;
    out[i] = byte;
  }
  return out;
}
