import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

class AppHttpException implements Exception {
  AppHttpException(this.statusCode, this.url, [this.body]);

  final int statusCode;
  final String url;
  final String? body;

  @override
  String toString() =>
      'AppHttpException($statusCode, $url${body == null ? '' : ', $body'})';
}

/// Single shared HTTP client for the whole app: connections are kept alive
/// between requests instead of paying TCP+TLS setup per call. Never close it
/// from feature code — page-level `close()` methods must only stop issuing
/// new requests.
class AppHttp {
  AppHttp._();

  static const String userAgent = 'qunleashed-app';

  static final io.HttpClient client = io.HttpClient()
    ..connectionTimeout = const Duration(seconds: 25)
    ..userAgent = userAgent;

  static Future<io.HttpClientResponse> get(
    Uri uri, {
    Map<String, String> headers = const {},
  }) async {
    final req = await client.getUrl(uri);
    for (final entry in headers.entries) {
      req.headers.set(entry.key, entry.value);
    }
    return req.close();
  }

  static Future<dynamic> getJson(
    Uri uri, {
    Map<String, String> headers = const {},
  }) async {
    final res = await get(uri, headers: {
      io.HttpHeaders.acceptHeader: 'application/json',
      ...headers,
    });
    final text = await res.transform(utf8.decoder).join();
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw AppHttpException(res.statusCode, uri.toString(), text);
    }
    if (text.isEmpty) return null;
    return compute(jsonDecode, text);
  }

  static Future<Uint8List> getBytes(
    Uri uri, {
    Map<String, String> headers = const {},
    void Function(int received, int? total)? onProgress,
  }) async {
    final res = await get(uri, headers: headers);
    if (res.statusCode < 200 || res.statusCode >= 300) {
      final text = await res.transform(utf8.decoder).join();
      throw AppHttpException(res.statusCode, uri.toString(), text);
    }
    final total = res.contentLength > 0 ? res.contentLength : null;
    final out = BytesBuilder(copy: false);
    onProgress?.call(0, total);
    await for (final chunk in res) {
      out.add(chunk);
      onProgress?.call(out.length, total);
    }
    return out.takeBytes();
  }

  static Future<void> downloadToFile(
    Uri uri,
    String savePath, {
    Map<String, String> headers = const {},
    void Function(int received, int? total)? onProgress,
  }) async {
    final res = await get(uri, headers: headers);
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw AppHttpException(res.statusCode, uri.toString());
    }
    final total = res.contentLength > 0 ? res.contentLength : null;
    final sink = io.File(savePath).openWrite();
    var received = 0;
    try {
      onProgress?.call(0, total);
      await for (final chunk in res) {
        sink.add(chunk);
        received += chunk.length;
        onProgress?.call(received, total);
      }
      await sink.flush();
    } finally {
      await sink.close();
    }
  }
}
