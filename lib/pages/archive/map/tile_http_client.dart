import 'package:http/http.dart';

/// Keeps a tile server's mid-response hang-up visible to `errorTileCallback`.
///
/// flutter_map 8 decides a failed tile request was *its own* doing by looking
/// for the words `closed` or `cancel` in a `ClientException`'s message, and
/// answers with a transparent tile instead of reporting the failure - the
/// `on ClientException` branch of
/// `tile_provider/network/image_provider/image_provider.dart`. dart:io spells a
/// server that hangs up mid-response in exactly those words (`Connection closed
/// before full header was received`, `Connection closed while receiving data`)
/// and `IOClient` passes them through with the message intact, as a
/// `ClientException` built from the `HttpException`. So without this wrapper
/// that failure reaches no callback at all: `_reportTileFailure` never counts
/// it, the `mapSourceNotAnswering` notice never appears, and the user is left
/// with blank squares and nothing saying the source is the reason. flutter_map
/// 7 rethrew every exception at that point, which is why the notice worked
/// before this bump.
///
/// The heuristic is there for tiles aborted when a layer is disposed early, and
/// that cannot reach us twice over: an abort arrives as
/// `RequestAbortedException`, caught one branch earlier, and
/// `NetworkTileProvider.dispose` closes only a client it created itself, which
/// this is not. So every `closed` that gets this far is the server's.
///
/// Timeouts, refusals and DNS failures never needed this: `IOClient` turns a
/// `SocketException` into a `ClientException` whose message says `timed out` or
/// `refused`, which the heuristic does not match.
///
/// Nothing here is logged on purpose. One dropped tile is ordinary and a dead
/// source drops a screenful at a time, which is how a single loop has drowned
/// real errors in `LogService` before; the notice is the report, and it counts.
class TileHttpClient extends BaseClient {
  TileHttpClient(this._inner);

  final Client _inner;

  @override
  Future<StreamedResponse> send(BaseRequest request) async {
    // A hang-up before the headers arrive throws from `send`; one during the
    // body arrives on the stream, which flutter_map consumes itself through
    // `consolidateStreamedResponseBytes`. Both have to be renamed.
    final response = await _inner
        .send(request)
        .onError<ClientException>(
          (error, stack) => Error.throwWithStackTrace(renamed(error), stack),
        );
    return StreamedResponse(
      response.stream.handleError(
        (Object error, StackTrace stack) =>
            Error.throwWithStackTrace(renamed(error as ClientException), stack),
        test: readsAsAborted,
      ),
      response.statusCode,
      contentLength: response.contentLength,
      request: response.request,
      headers: response.headers,
      isRedirect: response.isRedirect,
      persistentConnection: response.persistentConnection,
      reasonPhrase: response.reasonPhrase,
    );
  }

  @override
  void close() => _inner.close();

  /// The same test flutter_map applies, so that what it would swallow is
  /// exactly what gets renamed.
  static bool readsAsAborted(Object? error) =>
      error is ClientException &&
      (error.message.contains('closed') || error.message.contains('cancel'));

  /// Drops the original sentence rather than quoting it: the trigger words are
  /// *in* that sentence, so quoting it would keep flutter_map swallowing the
  /// error. Nothing is lost that was being reported before - the old path
  /// reported the failure as a count, not as text.
  static ClientException renamed(ClientException error) => readsAsAborted(error)
      ? ClientException('the tile source ended the response early', error.uri)
      : error;
}
