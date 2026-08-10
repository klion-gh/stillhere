import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'logger.dart';
import 'node_http_client.dart';

const _tag = 'ws';

/// How often to ping the server. dart:io closes the socket if a pong doesn't
/// come back within the same interval, which is what makes a silently-dead
/// connection (mobile NAT dropping an idle mapping, for instance) actually
/// surface as a disconnect instead of hanging forever in a half-open state.
const _pingInterval = Duration(seconds: 20);

const _minReconnectDelay = Duration(seconds: 1);
const _maxReconnectDelay = Duration(seconds: 30);

/// Thin wrapper around a single WebSocket connection to the node. One
/// connection per authenticated session; events are broadcast to whichever
/// feature (chat, calls) cares about them. Uses dart:io's WebSocket
/// directly (rather than the platform-agnostic WebSocketChannel.connect)
/// because only that API accepts a custom HttpClient — needed to pin the
/// node's TLS certificate the same way core/node_client.dart does for REST.
///
/// The connection is self-healing: it pings to detect dead sockets and
/// reconnects with exponential backoff. Without this an incoming call
/// simply never arrives — the server writes the offer into a socket that
/// no longer exists on the other end.
class WsClient {
  WebSocketChannel? _channel;
  StreamSubscription? _rawSub;
  final _eventsController = StreamController<Map<String, dynamic>>.broadcast();
  final _connectionStateController = StreamController<bool>.broadcast();

  // Retained so a reconnect can re-authenticate without the caller's help.
  String? _host;
  String? _nodeToken;
  String? _userToken;
  String? _pinnedFingerprint;
  void Function(String)? _onFirstPin;

  Timer? _reconnectTimer;
  int _reconnectAttempt = 0;
  bool _intentionallyClosed = false;
  bool _connecting = false;

  Stream<Map<String, dynamic>> get events => _eventsController.stream;

  /// Emits true on connect, false on disconnect — drives the UI's
  /// "connection lost" indicator.
  Stream<bool> get connectionState => _connectionStateController.stream;

  bool get isConnected => _channel != null;

  Future<void> connect({
    required String host,
    required String nodeToken,
    required String userToken,
    required String? pinnedFingerprint,
    required void Function(String fingerprint) onFirstPin,
  }) async {
    _host = host;
    _nodeToken = nodeToken;
    _userToken = userToken;
    _pinnedFingerprint = pinnedFingerprint;
    _onFirstPin = onFirstPin;
    _intentionallyClosed = false;
    _reconnectAttempt = 0;
    await _open();
  }

  Future<void> _open() async {
    if (_connecting || _intentionallyClosed) return;
    final host = _host;
    final nodeToken = _nodeToken;
    final userToken = _userToken;
    if (host == null || nodeToken == null || userToken == null) return;

    _connecting = true;
    _closeSocket();

    final uri = Uri.parse('wss://$host/ws?nodeToken=$nodeToken&token=$userToken');
    AppLogger.info(_tag, 'connecting to $host (attempt ${_reconnectAttempt + 1})...');
    final httpClient = HttpClient()
      ..badCertificateCallback = buildPinningCallback(
        pinnedFingerprint: _pinnedFingerprint,
        onFirstPin: (fp) {
          _pinnedFingerprint = fp;
          _onFirstPin?.call(fp);
        },
      );

    try {
      final rawSocket = await WebSocket.connect(uri.toString(), customClient: httpClient);
      // Makes dart:io send pings and tear the socket down if pongs stop.
      rawSocket.pingInterval = _pingInterval;

      AppLogger.info(_tag, 'connected to $host');
      final channel = IOWebSocketChannel(rawSocket);
      _channel = channel;
      _reconnectAttempt = 0;
      _connecting = false;
      _connectionStateController.add(true);

      _rawSub = channel.stream.listen(
        (raw) {
          try {
            final decoded = jsonDecode(raw as String) as Map<String, dynamic>;
            AppLogger.info(_tag, 'recv: ${decoded['type']}');
            _eventsController.add(decoded);
          } catch (e, st) {
            AppLogger.error(_tag, 'failed to decode incoming frame', e, st);
          }
        },
        onDone: () {
          AppLogger.warn(
            _tag,
            'connection closed (code=${channel.closeCode}, reason=${channel.closeReason})',
          );
          _handleDrop(closeCode: channel.closeCode);
        },
        onError: (e, st) {
          AppLogger.error(_tag, 'connection error', e, st);
          _handleDrop();
        },
      );
    } catch (e, st) {
      AppLogger.error(_tag, 'failed to connect to $host', e, st);
      _connecting = false;
      _handleDrop();
    }
  }

  void _handleDrop({int? closeCode}) {
    _closeSocket();
    _connecting = false;
    _connectionStateController.add(false);

    if (_intentionallyClosed) return;

    // 4001 is our own auth rejection (bad/expired token). Retrying with the
    // same credentials would just loop, so leave it to the auth layer to
    // refresh and reconnect.
    if (closeCode == 4001) {
      AppLogger.warn(_tag, 'server rejected credentials; not reconnecting');
      return;
    }

    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    _reconnectTimer?.cancel();
    // Exponential backoff with jitter, so a node coming back up doesn't get
    // stampeded by every client at once.
    final exponential = _minReconnectDelay * pow(2, _reconnectAttempt).toInt();
    final capped = exponential > _maxReconnectDelay ? _maxReconnectDelay : exponential;
    final jitterMs = Random().nextInt(1000);
    final delay = capped + Duration(milliseconds: jitterMs);
    _reconnectAttempt++;

    AppLogger.info(_tag, 'reconnecting in ${delay.inMilliseconds}ms');
    _reconnectTimer = Timer(delay, _open);
  }

  void _closeSocket() {
    _rawSub?.cancel();
    _rawSub = null;
    try {
      _channel?.sink.close();
    } catch (_) {
      // Already gone — nothing to do.
    }
    _channel = null;
  }

  void send(Map<String, dynamic> event) {
    if (_channel == null) {
      AppLogger.warn(_tag, 'send(${event['type']}) dropped: not connected');
      return;
    }
    AppLogger.info(_tag, 'send: ${event['type']}');
    _channel?.sink.add(jsonEncode(event));
  }

  void disconnect() {
    _intentionallyClosed = true;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _reconnectAttempt = 0;
    _closeSocket();
    _connectionStateController.add(false);
  }

  void dispose() {
    disconnect();
    _eventsController.close();
    _connectionStateController.close();
  }
}
