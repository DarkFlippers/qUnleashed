import 'dart:convert';
import 'dart:io';

import '../log/logger.dart';

class UfbtHttpException implements Exception {
  const UfbtHttpException(this.statusCode, this.reasonPhrase);

  final int statusCode;
  final String reasonPhrase;

  @override
  String toString() => 'HTTP Error $statusCode: $reasonPhrase';
}

class UfbtFileFetcher {
  UfbtFileFetcher({required this.logger, HttpClient? client})
    : _client = client ?? HttpClient();

  static const String userAgent = 'uFBT SDKLoader/0.2';

  final UfbtLogger logger;
  final HttpClient _client;

  void close() => _client.close(force: true);

  Future<String> readAsString(String url) async {
    final response = await _open(url);
    return response.transform(utf8.decoder).join();
  }

  Future<File> fetchFile(
    String url,
    Directory downloadDir, {
    String progressTitle = '',
    bool usePartFile = false,
  }) async {
    logger.debug('Fetching $url');

    final fileName = _fileNameFromUrl(url);
    downloadDir.createSync(recursive: true);

    final target = File(
      '${downloadDir.path}${Platform.pathSeparator}$fileName',
    );
    final sink = usePartFile ? File('${target.path}.part') : target;

    final response = await _open(url);
    final total = response.contentLength;
    final task = logger.progress(
      progressTitle,
      total: total > 0 ? total : null,
    );

    final output = sink.openWrite();
    var received = 0;
    try {
      await for (final chunk in response) {
        output.add(chunk);
        received += chunk.length;
        task.update(current: received);
      }
      await output.flush();
      await output.close();
    } catch (e) {
      await output.close();
      task.fail(message: '$e');
      rethrow;
    }
    task.finish();

    if (usePartFile) {
      if (target.existsSync()) target.deleteSync();
      sink.renameSync(target.path);
    }
    return target;
  }

  Future<HttpClientResponse> _open(String url) async {
    final request = await _client.getUrl(Uri.parse(url));
    request.headers.set(HttpHeaders.userAgentHeader, userAgent);
    final response = await request.close();
    if (response.statusCode != HttpStatus.ok) {
      await response.drain<void>();
      throw UfbtHttpException(response.statusCode, response.reasonPhrase);
    }
    return response;
  }

  static String _fileNameFromUrl(String url) {
    final segments = Uri.parse(url).pathSegments;
    return segments.isEmpty ? '' : Uri.decodeComponent(segments.last);
  }
}
