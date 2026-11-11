import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart';

import 'package:qunleashed/pages/archive/map/tile_http_client.dart';

/// Fails the request itself, before any response exists.
class _FailsToConnect extends BaseClient {
  _FailsToConnect(this.error);

  final Object error;

  @override
  Future<StreamedResponse> send(BaseRequest request) async => throw error;
}

/// Answers, then fails while the body is being read - which is where dart:io
/// reports a server that hung up mid-response.
class _FailsMidBody extends BaseClient {
  _FailsMidBody(this.error);

  final Object error;

  @override
  Future<StreamedResponse> send(BaseRequest request) async =>
      StreamedResponse(Stream<List<int>>.error(error), 200);
}

/// The two sentences dart:io actually produces for a hang-up, which `IOClient`
/// passes through as the `ClientException` message verbatim.
const headerDrop = 'Connection closed before full header was received';
const bodyDrop = 'Connection closed while receiving data';

Future<Object> _errorFrom(Client client) async {
  try {
    final response = await client.send(Request('GET', Uri.parse('http://t/1')));
    await response.stream.toBytes();
  } catch (e) {
    return e;
  }
  fail('expected the request to fail');
}

void main() {
  group('a tile source that hangs up stays visible to flutter_map', () {
    // The point of the whole file: flutter_map 8 answers a `ClientException`
    // whose message contains `closed` or `cancel` with a transparent tile and
    // no callback, so a renamed message is the difference between the
    // "source is not answering" notice appearing and blank squares.
    test('the renamed error no longer matches the heuristic', () {
      for (final message in [headerDrop, bodyDrop, 'Request was cancelled']) {
        final renamed = TileHttpClient.renamed(ClientException(message));
        expect(
          TileHttpClient.readsAsAborted(renamed),
          isFalse,
          reason: 'flutter_map would swallow "${renamed.message}"',
        );
      }
    });

    test('the original messages do match it, or there is nothing to fix', () {
      for (final message in [headerDrop, bodyDrop, 'Request was cancelled']) {
        expect(
          TileHttpClient.readsAsAborted(ClientException(message)),
          isTrue,
          reason: 'flutter_map keys off "closed" and "cancel"',
        );
      }
    });

    test('a hang-up before the headers is renamed', () async {
      final error = await _errorFrom(
        TileHttpClient(_FailsToConnect(ClientException(headerDrop))),
      );
      expect(error, isA<ClientException>());
      expect(TileHttpClient.readsAsAborted(error), isFalse);
    });

    test('a hang-up during the body is renamed too', () async {
      // This one arrives on the response stream rather than from `send`,
      // because flutter_map reads the body itself.
      final error = await _errorFrom(
        TileHttpClient(_FailsMidBody(ClientException(bodyDrop))),
      );
      expect(error, isA<ClientException>());
      expect(TileHttpClient.readsAsAborted(error), isFalse);
    });

    test('the request uri survives the rename', () async {
      final renamed = TileHttpClient.renamed(
        ClientException(headerDrop, Uri.parse('http://tiles/9/1/2.png')),
      );
      expect(renamed.uri, Uri.parse('http://tiles/9/1/2.png'));
    });
  });

  group('everything else is passed through untouched', () {
    // A timeout or a refusal never needed renaming: flutter_map reports those
    // already, and swallowing them here would be the same bug in reverse.
    test('a timeout keeps its own exception', () async {
      final original = ClientException('Connection timed out');
      final error = await _errorFrom(TileHttpClient(_FailsToConnect(original)));
      expect(error, same(original));
    });

    test('a refusal keeps its own exception', () async {
      final original = ClientException('Connection refused');
      final error = await _errorFrom(TileHttpClient(_FailsMidBody(original)));
      expect(error, same(original));
    });

    test('a non-http error is not touched', () async {
      final original = StateError('decoder blew up');
      final error = await _errorFrom(TileHttpClient(_FailsMidBody(original)));
      expect(error, same(original));
    });

    test('a successful response is relayed whole', () async {
      final client = TileHttpClient(_Ok());
      final response = await client.send(
        Request('GET', Uri.parse('http://t/1')),
      );
      expect(response.statusCode, 200);
      expect(response.contentLength, 3);
      expect(response.headers['content-type'], 'image/png');
      expect(response.reasonPhrase, 'OK');
      expect(await response.stream.toBytes(), [1, 2, 3]);
    });
  });
}

class _Ok extends BaseClient {
  @override
  Future<StreamedResponse> send(BaseRequest request) async => StreamedResponse(
    Stream<List<int>>.value(const [1, 2, 3]),
    200,
    contentLength: 3,
    request: request,
    headers: const {'content-type': 'image/png'},
    reasonPhrase: 'OK',
  );
}
