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

/// How often to measure application-level latency to the node.
const _rttProbeInterval = Duration(seconds: 5);

const _minReconnectDelay = Duration(seconds: 1);
const _maxReconnectDelay = Duration(seconds: 30);

/// Thin wrapper around a single WebSocket connection to the node. One
/// connection per authenticated session; events are broadcast to whichever
/// feature (chat, calls) cares about them. Uses dart:io's WebSocket
/// directly (rather than the platform-agnostic WebSocketChannel.connect)
/// because only that API accepts a custom HttpClient — needed to pin the
/// node's TLS certificate the same way core/node_client.dart does for REST.
///
/// The connection is self-healing: it pings to detect dead sockets,
/// reconnects with exponential backoff, and refreshes an expired access
/// token when the server rejects it.
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

  /// Asks the auth layer for a fresh access token. The access token expires
  /// long before a session does, so without this the socket would be locked
  /// out permanently the first time it outlives its token.
  Future<String?> Function()? _refreshAccessToken;

  Timer? _reconnectTimer;
  Timer? _rttTimer;
  int _reconnectAttempt = 0;
  bool _intentionallyClosed = false;
  bool _connecting = false;
  bool _connected = false;
  bool _refreshingToken = false;
  int? _lastRttMs;

  Stream<Map<String, dynamic>> get events => _eventsController.stream;

  /// Live connectivity, seeded with the current value so a widget that
  /// subscribes after the connection was established doesn't sit on a null
  /// (and render a bogus "disconnected" warning).
  Stream<bool> get connectionState async* {
    yield _connected;
    yield* _connectionStateController.stream;
  }

  bool get isConnected => _connected;

  /// Most recent round trip to the node, or null before the first probe.
  int? get lastRttMs => _lastRttMs;

  Future<void> connect({
    required String host,
    required String nodeToken,
    required String userToken,
    required String? pinnedFingerprint,
    required void Function(String fingerprint) onFirstPin,
    Future<String?> Function()? refreshAccessToken,
  }) async {
    _host = host;
    _nodeToken = nodeToken;
    _userToken = userToken;
    _pinnedFingerprint = pinnedFingerprint;
    _onFirstPin = onFirstPin;
    _refreshAccessToken = refreshAccessToken;
    _intentionallyClosed = false;
    _reconnectAttempt = 0;
    await _open();
  }

  void _setConnected(bool value) {
    if (_connected == value) return;
    _connected = value;
    _connectionStateController.add(value);
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
      _setConnected(true);
      _startRttProbe();

      _rawSub = channel.stream.listen(
        (raw) {
          try {
            final decoded = jsonDecode(raw as String) as Map<String, dynamic>;
            if (decoded['type'] == 'net:pong') {
              _handlePong(decoded);
              return;
            }
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

  void _handlePong(Map<String, dynamic> frame) {
    final sentAt = frame['sentAt'];
    if (sentAt is! int) return;
    _lastRttMs = DateTime.now().millisecondsSinceEpoch - sentAt;
    _eventsController.add({'type': 'net:rtt', 'rttMs': _lastRttMs});
  }

  void _startRttProbe() {
    _rttTimer?.cancel();
    _rttTimer = Timer.periodic(_rttProbeInterval, (_) {
      if (!_connected) return;
      send({'type': 'net:ping', 'sentAt': DateTime.now().millisecondsSinceEpoch});
    });
  }

  void _handleDrop({int? closeCode}) {
    _closeSocket();
    _connecting = false;
    _setConnected(false);

    if (_intentionallyClosed) return;

    // 4001 means the server rejected our credentials. Usually that's just an
    // expired access token (they're short-lived) — refresh once and retry,
    // rather than treating the session as dead.
    if (closeCode == 4001) {
      _reconnectWithFreshToken();
      return;
    }

    _scheduleReconnect();
  }

  Future<void> _reconnectWithFreshToken() async {
    if (_refreshingToken) return;
    final refresh = _refreshAccessToken;
    if (refresh == null) {
      AppLogger.warn(_tag, 'server rejected credentials and no refresh hook is set');
      return;
    }

    _refreshingToken = true;
    try {
      AppLogger.info(_tag, 'access token rejected, refreshing...');
      final fresh = await refresh();
      if (fresh == null) {
        // The refresh token is gone too — the auth layer has logged the user
        // out, so there's nothing left to reconnect as.
        AppLogger.warn(_tag, 'token refresh failed; giving up on reconnect');
        return;
      }
      _userToken = fresh;
      _reconnectAttempt = 0;
      _refreshingToken = false;
      await _open();
    } catch (e, st) {
      AppLogger.error(_tag, 'token refresh threw', e, st);
      _scheduleReconnect();
    } finally {
      _refreshingToken = false;
    }
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
    _rttTimer?.cancel();
    _rttTimer = null;
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
    if (event['type'] != 'net:ping') {
      AppLogger.info(_tag, 'send: ${event['type']}');
    }
    _channel?.sink.add(jsonEncode(event));
  }

  void disconnect() {
    _intentionallyClosed = true;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _reconnectAttempt = 0;
    _lastRttMs = null;
    _closeSocket();
    _setConnected(false);
  }

  void dispose() {
    disconnect();
    _eventsController.close();
    _connectionStateController.close();
  }
}
