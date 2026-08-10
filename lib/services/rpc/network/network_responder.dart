import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flipperlib/flipperlib.dart';

import '../../logging.dart';
import 'http_util.dart';
import 'network_traffic.dart';

class _NetworkConnection {
  _NetworkConnection.tcp(this.id)
    : protocol = Protocol.TCP,
      isWebSocket = false;
  _NetworkConnection.udp(this.id)
    : protocol = Protocol.UDP,
      isWebSocket = false;
  _NetworkConnection.webSocket(this.id)
    : protocol = Protocol.TCP,
      isWebSocket = true;

  final int id;
  final Protocol protocol;
  final bool isWebSocket;

  Socket? tcp;
  RawDatagramSocket? udp;
  WebSocket? ws;
  InternetAddress? udpRemote;
  int udpPort = 0;
  StreamSubscription<dynamic>? subscription;
  bool closed = false;
}

class FlipperNetworkResponder {
  FlipperNetworkResponder(this._client);

  static const int maxConnections = 8;
  static const int maxChunkSize = 512;
  static const int _tlsPort = 443;
  static const Duration _defaultTimeout = Duration(seconds: 30);

  final FlipperClient _client;
  final Map<int, _NetworkConnection> _connections = {};
  final Map<int, Future<void>> _handlerChains = {};

  HttpClient? _httpClient;
  StreamSubscription<Main>? _notifications;
  StreamSubscription<FlipperConnectionState>? _connection;

  void attach() {
    _notifications ??= _client.notificationStream.listen(_onNotification);
    _connection ??= _client.connectionStream.listen(_onConnection);
  }

  Future<void> detach() async {
    final notifications = _notifications;
    final connection = _connection;
    _notifications = null;
    _connection = null;
    await notifications?.cancel();
    await connection?.cancel();
    await _closeAll();
    _httpClient?.close(force: true);
    _httpClient = null;
  }

  void _onConnection(FlipperConnectionState state) {
    if (!state.connected || state.mode != FlipperMode.rpc) {
      unawaited(_closeAll());
    }
  }

  void _onNotification(Main frame) {
    if (frame.hasNetworkConnectRequest()) {
      final request = frame.networkConnectRequest;
      _enqueueHandler(request.connectionId, () => _onConnect(request));
    } else if (frame.hasNetworkSendRequest()) {
      final request = frame.networkSendRequest;
      _enqueueHandler(request.connectionId, () => _onSend(request));
    } else if (frame.hasNetworkCloseRequest()) {
      final request = frame.networkCloseRequest;
      _enqueueHandler(request.connectionId, () => _onClose(request));
    } else if (frame.hasNetworkHttpRequest()) {
      final request = frame.networkHttpRequest;
      _enqueueHandler(request.requestId, () => _onHttp(request));
    } else if (frame.hasNetworkWebsocketOpenRequest()) {
      final request = frame.networkWebsocketOpenRequest;
      _enqueueHandler(request.connectionId, () => _onWebSocketOpen(request));
    }
  }

  void _enqueueHandler(int id, Future<void> Function() handler) {
    final previous = _handlerChains[id] ?? Future<void>.value();
    late final Future<void> next;
    next = previous
        .then((_) => handler())
        .catchError((Object error) {
          LogService.log('[Network] handler failed on $id: $error');
        })
        .whenComplete(() {
          if (identical(_handlerChains[id], next)) {
            _handlerChains.remove(id);
          }
        });
    _handlerChains[id] = next;
  }

  Future<bool> _reserveSlot(int id) async {
    if (_connections.containsKey(id)) {
      await _sendConnectError(id, ErrorCode.INVALID_CONNECTION);
      return false;
    }
    if (_connections.length >= maxConnections) {
      await _sendConnectError(id, ErrorCode.MAX_CONNECTIONS);
      return false;
    }
    return true;
  }

  Future<void> _onConnect(ConnectRequest request) async {
    final id = request.connectionId;
    if (!await _reserveSlot(id)) return;
    if (request.host.isEmpty || request.port == 0 || request.port > 65535) {
      await _sendConnectError(id, ErrorCode.INTERNAL_ERROR);
      return;
    }

    final timeout = request.timeoutMs > 0
        ? Duration(milliseconds: request.timeoutMs)
        : _defaultTimeout;

    if (request.protocol == Protocol.UDP) {
      await _openUdp(id, request, timeout);
    } else {
      await _openTcp(id, request, timeout);
    }
  }

  Future<void> _openTcp(
    int id,
    ConnectRequest request,
    Duration timeout,
  ) async {
    final connection = _NetworkConnection.tcp(id);
    _connections[id] = connection;
    try {
      final socket = _usesTls(request)
          ? await SecureSocket.connect(
              request.host,
              request.port,
              timeout: timeout,
            )
          : await Socket.connect(request.host, request.port, timeout: timeout);
      if (connection.closed) {
        socket.destroy();
        return;
      }
      connection.tcp = socket;
      connection.subscription = socket.listen(
        (data) => _onReceived(id, data),
        onError: (Object error) => _onSocketError(id, error),
        onDone: () => _onSocketDone(id),
        cancelOnError: true,
      );
      NetworkTrafficMonitor.instance.connectionOpened(request.host);
      await _sendConnectSuccess(id, socket.remoteAddress.address);
    } catch (error) {
      _connections.remove(id);
      await _sendConnectError(id, _errorFor(error));
    }
  }

  Future<void> _openUdp(
    int id,
    ConnectRequest request,
    Duration timeout,
  ) async {
    final connection = _NetworkConnection.udp(id);
    _connections[id] = connection;
    try {
      final addresses = await InternetAddress.lookup(
        request.host,
      ).timeout(timeout);
      if (addresses.isEmpty) {
        _connections.remove(id);
        await _sendConnectError(id, ErrorCode.DNS_FAILED);
        return;
      }
      final remote = addresses.first;
      final socket = await RawDatagramSocket.bind(
        remote.type == InternetAddressType.IPv6
            ? InternetAddress.anyIPv6
            : InternetAddress.anyIPv4,
        0,
      );
      if (connection.closed) {
        socket.close();
        return;
      }
      connection.udp = socket;
      connection.udpRemote = remote;
      connection.udpPort = request.port;
      connection.subscription = socket.listen(
        (event) => _onUdpEvent(id, event),
        onError: (Object error) => _onSocketError(id, error),
        onDone: () => _onSocketDone(id),
      );
      NetworkTrafficMonitor.instance.connectionOpened(request.host);
      await _sendConnectSuccess(id, remote.address);
    } catch (error) {
      _connections.remove(id);
      await _sendConnectError(id, _errorFor(error));
    }
  }

  Future<void> _onWebSocketOpen(WebSocketOpenRequest request) async {
    final id = request.connectionId;
    if (!await _reserveSlot(id)) return;
    if (request.url.isEmpty) {
      await _sendConnectError(id, ErrorCode.INVALID_URL);
      return;
    }

    final timeout = request.timeoutMs > 0
        ? Duration(milliseconds: request.timeoutMs)
        : _defaultTimeout;

    final connection = _NetworkConnection.webSocket(id);
    _connections[id] = connection;
    try {
      final headers = parseHeaderBlock(request.headers);
      final socket = await WebSocket.connect(
        request.url,
        headers: headers.isEmpty ? null : headers,
      ).timeout(timeout);
      if (connection.closed) {
        await socket.close();
        return;
      }
      connection.ws = socket;
      connection.subscription = socket.listen(
        (frame) => _onWebSocketFrame(id, frame),
        onError: (Object error) => _onSocketError(id, error),
        onDone: () => _onSocketDone(id),
        cancelOnError: true,
      );
      NetworkTrafficMonitor.instance.connectionOpened(_hostOf(request.url));
      await _sendConnectSuccess(id, request.url);
    } catch (error) {
      _connections.remove(id);
      await _sendConnectError(id, _errorFor(error));
    }
  }

  Future<void> _onSend(SendRequest request) async {
    final id = request.connectionId;
    final connection = _connections[id];
    if (connection == null || connection.closed) {
      await _sendSendResponse(id, 0, ErrorCode.NOT_CONNECTED);
      return;
    }
    final data = request.data;
    try {
      if (connection.isWebSocket) {
        final socket = connection.ws;
        if (socket == null) {
          await _sendSendResponse(id, 0, ErrorCode.NOT_CONNECTED);
          return;
        }
        if (request.binary) {
          socket.add(data);
        } else {
          socket.add(utf8.decode(data));
        }
        NetworkTrafficMonitor.instance.recordTx(data.length);
        await _sendSendResponse(id, data.length, ErrorCode.NONE);
      } else if (connection.protocol == Protocol.UDP) {
        final socket = connection.udp;
        if (socket == null) {
          await _sendSendResponse(id, 0, ErrorCode.NOT_CONNECTED);
          return;
        }
        final sent = socket.send(
          data,
          connection.udpRemote!,
          connection.udpPort,
        );
        NetworkTrafficMonitor.instance.recordTx(sent);
        await _sendSendResponse(id, sent, ErrorCode.NONE);
      } else {
        final socket = connection.tcp;
        if (socket == null) {
          await _sendSendResponse(id, 0, ErrorCode.NOT_CONNECTED);
          return;
        }
        socket.add(data);
        await socket.flush();
        NetworkTrafficMonitor.instance.recordTx(data.length);
        await _sendSendResponse(id, data.length, ErrorCode.NONE);
      }
    } catch (error) {
      LogService.log('[Network] send failed on $id: $error');
      await _sendSendResponse(id, 0, ErrorCode.SEND_FAILED);
    }
  }

  Future<void> _onClose(CloseRequest request) async {
    final id = request.connectionId;
    final connection = _connections.remove(id);
    if (connection == null) {
      await _sendCloseResponse(id, ErrorCode.INVALID_CONNECTION);
      return;
    }
    await _teardown(connection);
    NetworkTrafficMonitor.instance.connectionClosed();
    await _sendCloseResponse(id, ErrorCode.NONE);
  }

  Future<void> _onHttp(HttpRequest request) async {
    final id = request.requestId;
    final timeout = request.timeoutMs > 0
        ? Duration(milliseconds: request.timeoutMs)
        : _defaultTimeout;

    final Uri uri;
    try {
      uri = Uri.parse(request.url);
      if (!uri.hasScheme || uri.host.isEmpty) {
        await _sendHttpError(id, ErrorCode.INVALID_URL);
        return;
      }
    } catch (_) {
      await _sendHttpError(id, ErrorCode.INVALID_URL);
      return;
    }

    NetworkTrafficMonitor.instance.hostUpdated(uri.host);

    final client = _httpClient ??= HttpClient()..connectionTimeout = timeout;

    try {
      List<int>? body;
      if (request.sendPath.isNotEmpty) {
        body = await _client.storageReadChunked(request.sendPath);
      } else if (request.body.isNotEmpty) {
        body = request.body;
      }

      final clientRequest = await client
          .openUrl(_methodName(request.method), uri)
          .timeout(timeout);

      parseHeaderBlock(request.headers).forEach((name, value) {
        clientRequest.headers.set(name, value);
      });
      if (body != null) {
        clientRequest.add(body);
        NetworkTrafficMonitor.instance.recordTx(body.length, host: uri.host);
      }

      final response = await clientRequest.close().timeout(timeout);
      final status = response.statusCode;
      final headers = request.includeHeaders
          ? _serializeHeaders(response.headers)
          : '';

      if (request.savePath.isNotEmpty) {
        final bytes = BytesBuilder(copy: false);
        await for (final chunk in response.timeout(timeout)) {
          bytes.add(chunk);
        }
        final size = bytes.length;
        NetworkTrafficMonitor.instance.recordRx(size);
        await _client.storageWriteChunked(
          request.savePath,
          bytes.takeBytes(),
          priority: FlipperRequestPriority.background,
        );
        await _sendHttpResponse(
          id,
          status: status,
          bodySize: size,
          savedToFile: true,
          headers: headers,
        );
      } else {
        var size = 0;
        await for (final chunk in response.timeout(timeout)) {
          size += chunk.length;
          for (final piece in chunkByteViews(asBytes(chunk), maxChunkSize)) {
            await _sendReceiveData(id, piece, false);
          }
        }
        await _sendHttpResponse(
          id,
          status: status,
          bodySize: size,
          savedToFile: false,
          headers: headers,
        );
      }
    } on FlipperWriteCancelledException {
      await _sendHttpError(id, ErrorCode.FILE_ERROR);
    } catch (error) {
      LogService.log('[Network] http failed on $id: $error');
      await _sendHttpError(id, _errorFor(error));
    }
  }

  void _onReceived(int id, List<int> data) => _emitInbound(id, data, false);

  void _onWebSocketFrame(int id, dynamic frame) {
    if (frame is String) {
      _emitInbound(id, utf8.encode(frame), false);
    } else if (frame is List<int>) {
      _emitInbound(id, frame, true);
    }
  }

  void _emitInbound(int id, List<int> data, bool binary) {
    for (final piece in chunkByteViews(asBytes(data), maxChunkSize)) {
      unawaited(_sendReceiveData(id, piece, binary));
    }
  }

  void _onUdpEvent(int id, RawSocketEvent event) {
    if (event != RawSocketEvent.read) return;
    final connection = _connections[id];
    final datagram = connection?.udp?.receive();
    if (datagram == null) return;
    _onReceived(id, datagram.data);
  }

  void _onSocketError(int id, Object error) {
    LogService.log('[Network] socket error on $id: $error');
    final connection = _connections.remove(id);
    if (connection == null) return;
    unawaited(_teardown(connection));
    NetworkTrafficMonitor.instance.connectionClosed();
    unawaited(_sendStateChanged(id, ConnectionState.ERROR, _errorFor(error)));
  }

  void _onSocketDone(int id) {
    final connection = _connections.remove(id);
    if (connection == null) return;
    unawaited(_teardown(connection));
    NetworkTrafficMonitor.instance.connectionClosed();
    unawaited(
      _sendStateChanged(id, ConnectionState.DISCONNECTED, ErrorCode.NONE),
    );
  }

  Future<void> _teardown(_NetworkConnection connection) async {
    connection.closed = true;
    await connection.subscription?.cancel();
    connection.subscription = null;
    try {
      connection.tcp?.destroy();
      connection.udp?.close();
      await connection.ws?.close();
    } catch (error) {
      LogService.log('[Network] teardown error on ${connection.id}: $error');
    }
  }

  Future<void> _closeAll() async {
    final connections = _connections.values.toList();
    _connections.clear();
    for (final connection in connections) {
      await _teardown(connection);
    }
    NetworkTrafficMonitor.instance.reset();
  }

  static bool _usesTls(ConnectRequest request) => request.port == _tlsPort;

  static String _hostOf(String url) {
    try {
      final host = Uri.parse(url).host;
      return host.isNotEmpty ? host : url;
    } catch (_) {
      return url;
    }
  }

  static String _methodName(HttpMethod method) {
    switch (method) {
      case HttpMethod.HTTP_POST:
        return 'POST';
      case HttpMethod.HTTP_PUT:
        return 'PUT';
      case HttpMethod.HTTP_PATCH:
        return 'PATCH';
      case HttpMethod.HTTP_DELETE:
        return 'DELETE';
      case HttpMethod.HTTP_HEAD:
        return 'HEAD';
      case HttpMethod.HTTP_GET:
      default:
        return 'GET';
    }
  }

  static String _serializeHeaders(HttpHeaders headers) {
    final map = <String, String>{};
    headers.forEach((name, values) {
      map[name] = values.join(', ');
    });
    return formatHeaderBlock(map);
  }

  static ErrorCode _errorFor(Object error) {
    if (error is TimeoutException) return ErrorCode.TIMEOUT;
    if (error is HandshakeException) return ErrorCode.TLS_FAILED;
    if (error is TlsException) return ErrorCode.TLS_FAILED;
    if (error is WebSocketException) return ErrorCode.INTERNAL_ERROR;
    if (error is SocketException) {
      final osError = error.osError;
      if (osError == null) {
        return error.message.contains('Failed host lookup')
            ? ErrorCode.DNS_FAILED
            : ErrorCode.INTERNAL_ERROR;
      }
      switch (osError.errorCode) {
        case 61:
        case 111:
          return ErrorCode.CONNECTION_REFUSED;
        case 60:
        case 110:
          return ErrorCode.TIMEOUT;
        case 65:
        case 113:
          return ErrorCode.HOST_UNREACHABLE;
        case 51:
        case 101:
          return ErrorCode.NETWORK_UNREACHABLE;
        case 8:
        case -2:
          return ErrorCode.DNS_FAILED;
        default:
          return ErrorCode.INTERNAL_ERROR;
      }
    }
    return ErrorCode.INTERNAL_ERROR;
  }

  Future<void> _sendConnectSuccess(int id, String resolvedIp) {
    return _send(
      Main(
        networkConnectResponse: ConnectResponse(
          connectionId: id,
          state: ConnectionState.CONNECTED,
          error: ErrorCode.NONE,
          resolvedIp: resolvedIp,
        ),
      ),
    );
  }

  Future<void> _sendConnectError(int id, ErrorCode error) {
    return _send(
      Main(
        networkConnectResponse: ConnectResponse(
          connectionId: id,
          state: ConnectionState.ERROR,
          error: error,
        ),
      ),
    );
  }

  Future<void> _sendSendResponse(int id, int bytesSent, ErrorCode error) {
    return _send(
      Main(
        networkSendResponse: SendResponse(
          connectionId: id,
          bytesSent: bytesSent,
          error: error,
        ),
      ),
    );
  }

  Future<void> _sendReceiveData(int id, Uint8List data, bool binary) {
    NetworkTrafficMonitor.instance.recordRx(data.length);
    return _send(
      Main(
        networkReceiveData: ReceiveData(
          connectionId: id,
          data: data,
          binary: binary,
        ),
      ),
    );
  }

  Future<void> _sendHttpResponse(
    int id, {
    required int status,
    required int bodySize,
    required bool savedToFile,
    required String headers,
  }) {
    return _send(
      Main(
        networkHttpResponse: HttpResponse(
          requestId: id,
          status: status,
          error: ErrorCode.NONE,
          bodySize: bodySize,
          savedToFile: savedToFile,
          headers: headers,
        ),
      ),
    );
  }

  Future<void> _sendHttpError(int id, ErrorCode error) {
    return _send(
      Main(
        networkHttpResponse: HttpResponse(requestId: id, error: error),
      ),
    );
  }

  Future<void> _sendCloseResponse(int id, ErrorCode error) {
    return _send(
      Main(
        networkCloseResponse: CloseResponse(connectionId: id, error: error),
      ),
    );
  }

  Future<void> _sendStateChanged(
    int id,
    ConnectionState state,
    ErrorCode error,
  ) {
    return _send(
      Main(
        networkStateChanged: StateChanged(
          connectionId: id,
          state: state,
          error: error,
        ),
      ),
    );
  }

  Future<void> _send(
    Main message, {
    FlipperRequestPriority priority = FlipperRequestPriority.defaultPriority,
  }) async {
    try {
      await _client.sendRpc(message, priority: priority);
    } catch (error) {
      LogService.log('[Network] failed to send response: $error');
    }
  }
}

extension FlipperNetworkApi on FlipperClient {
  FlipperNetworkResponder attachNetworkResponder() {
    final responder = FlipperNetworkResponder(this);
    responder.attach();
    return responder;
  }
}
