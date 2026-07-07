import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;

import '../../../../services/http/app_http.dart';
import 'infrared_backend_models.dart';

class InfraredBackendException implements Exception {
  InfraredBackendException(this.statusCode, this.url, [this.body]);
  final int statusCode;
  final String url;
  final String? body;

  @override
  String toString() =>
      'InfraredBackendException($statusCode, $url${body == null ? '' : ', $body'})';
}

class InfraredBackendApi {
  InfraredBackendApi({
    this.host = 'https://infrared.flipperzero.one',
    this.userAgent = 'qunleashed-infrared',
  });

  final String host;
  final String userAgent;
  bool _closed = false;

  void close() {
    _closed = true;
  }

  Future<List<DeviceCategory>> getCategories() async {
    final body = await _getJson(Uri.parse('$host/categories'));
    final list = (body is Map<String, dynamic>) ? body['categories'] : null;
    if (list is! List) return const [];
    return list
        .whereType<Map>()
        .map((m) => DeviceCategory.fromJson(m.cast<String, dynamic>()))
        .toList();
  }

  Future<List<BrandModel>> getBrands(int categoryId) async {
    final body = await _getJson(
      Uri.parse('$host/brands').replace(queryParameters: {
        'category_id': '$categoryId',
      }),
    );
    final list = (body is Map<String, dynamic>) ? body['brands'] : null;
    if (list is! List) return const [];
    return list
        .whereType<Map>()
        .map((m) => BrandModel.fromJson(m.cast<String, dynamic>()))
        .toList();
  }

  Future<List<IfrFileModel>> getInfrareds(int brandId) async {
    final body = await _getJson(
      Uri.parse('$host/infrareds').replace(queryParameters: {
        'brand_id': '$brandId',
      }),
    );
    final list =
        (body is Map<String, dynamic>) ? body['infrared_files'] : null;
    if (list is! List) return const [];
    return list
        .whereType<Map>()
        .map((m) => IfrFileModel.fromJson(m.cast<String, dynamic>()))
        .toList();
  }

  Future<String> getKeyContent(int ifrFileId) async {
    final body = await _getJson(
      Uri.parse('$host/key').replace(queryParameters: {
        'ifr_file_id': '$ifrFileId',
      }),
    );
    if (body is Map<String, dynamic>) {
      final c = body['content'];
      if (c is String) return c;
    }
    return '';
  }

  Future<dynamic> _getJson(Uri uri) async {
    if (_closed) throw StateError('InfraredBackendApi has been closed');
    final res = await AppHttp.get(uri, headers: {
      io.HttpHeaders.userAgentHeader: userAgent,
      io.HttpHeaders.acceptHeader: 'application/json',
    });
    final text = await res.transform(utf8.decoder).join();
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw InfraredBackendException(res.statusCode, uri.toString(), text);
    }
    if (text.isEmpty) return null;
    return jsonDecode(text);
  }
}
