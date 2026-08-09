import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'node_http_client.dart';

/// Thin wrapper around a single WebSocket connection to the node. One
/// connection per authenticated session; events are broadcast to whichever
/// feature (chat, calls) cares about them. Uses dart:io's WebSocket
/// directly (rather than the platform-agnostic WebSocketChannel.connect)
/// because only that API accepts a custom HttpClient — needed to pin the
/// node's TLS certificate the same way core/node_client.dart does for REST.
class WsClient {
  WebSocketChannel? _channel;
  StreamSubscription? _rawSub;
  final _eventsController = StreamController<Map<String, dynamic>>.broadcast();

  Stream<Map<String, dynamic>> get events => _eventsController.stream;
  bool get isConnected => _channel != null;

  Future<void> connect({
    required String host,
    required String nodeToken,
    required String userToken,
    required String? pinnedFingerprint,
    required void Function(String fingerprint) onFirstPin,
  }) async {
    disconnect();

    final uri = Uri.parse('wss://$host/ws?nodeToken=$nodeToken&token=$userToken');
    final httpClient = HttpClient()
      ..badCertificateCallback = buildPinningCallback(
        pinnedFingerprint: pinnedFingerprint,
        onFirstPin: onFirstPin,
      );

    try {
      final rawSocket = await WebSocket.connect(uri.toString(), customClient: httpClient);
      final channel = IOWebSocketChannel(rawSocket);
      _channel = channel;
      _rawSub = channel.stream.listen(
        (raw) {
          try {
            final decoded = jsonDecode(raw as String) as Map<String, dynamic>;
            _eventsController.add(decoded);
          } catch (_) {
            // Ignore malformed frames.
          }
        },
        onDone: () {
          _channel = null;
        },
        onError: (_) {
          _channel = null;
        },
      );
    } catch (_) {
      _channel = null;
    }
  }

  void send(Map<String, dynamic> event) {
    _channel?.sink.add(jsonEncode(event));
  }

  void disconnect() {
    _rawSub?.cancel();
    _rawSub = null;
    _channel?.sink.close();
    _channel = null;
  }

  void dispose() {
    disconnect();
    _eventsController.close();
  }
}
