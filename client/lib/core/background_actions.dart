/// Notification presses that arrive with no app to handle them.
///
/// Android dispatches a press on a button that doesn't open the app into a
/// separate isolate — the same process when the app is alive, but with none of
/// its state, so the running call is out of reach. Presses are forwarded back to
/// the app through a named port when there is one; when there isn't, declining a
/// call goes over HTTP instead of the socket that doesn't exist yet.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:ui';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'call_notifications.dart';
import 'logger.dart';
import 'node_http_client.dart';
import 'node_storage.dart';
import 'token_storage.dart';

const _tag = 'notify-bg';

/// Name the running app publishes a port under, so a notification press
/// handled in the background isolate can be forwarded to it.
///
/// Android hands presses on `showsUserInterface: false` actions to a separate
/// isolate even when the app's own process is alive — same process, but no
/// shared state, so the live call controller is out of reach from there.
/// Mute and speaker only mean anything to that controller, which is why they
/// have to travel back rather than being acted on where they land.
const kNotificationActionPort = 'stillhere/notification_actions';

/// Handles a notification button pressed while the app isn't running.
///
/// Android dispatches these into a fresh isolate, so there is no widget tree,
/// no providers and — the part that matters — no WebSocket. Declining a call
/// therefore goes over HTTP instead, through the same pinned client the app
/// uses, since the node's certificate is usually self-signed.
///
/// Must stay a top-level function: the entry point is looked up by name.
@pragma('vm:entry-point')
Future<void> notificationBackgroundHandler(NotificationResponse response) async {
  final payload = response.payload;
  if (payload == null || payload.isEmpty) return;

  Map<String, dynamic> data;
  try {
    data = jsonDecode(payload) as Map<String, dynamic>;
  } catch (_) {
    AppLogger.warn(_tag, 'unreadable payload: $payload');
    return;
  }

  if (data['kind'] != 'call') return;

  final conversationId = (data['conversationId'] as String?) ?? '';
  final actionId = response.actionId;
  if (conversationId.isEmpty || actionId == null) return;

  // If the app is running, it owns the call — hand the press over rather than
  // trying to act on a WebRTC session this isolate can't see.
  final port = IsolateNameServer.lookupPortByName(kNotificationActionPort);
  if (port != null) {
    port.send(<String, String>{
      'actionId': actionId,
      'conversationId': conversationId,
      'peerUsername': (data['peerUsername'] as String?) ?? '',
    });
    AppLogger.info(_tag, 'forwarded $actionId to the running app');
    return;
  }

  // Nothing running: the only thing that still makes sense is telling the
  // caller we're not picking up. Mute and speaker have no call to apply to.
  if (actionId != kCallDeclineAction && actionId != kCallHangUpAction) return;

  try {
    await declineCallOverHttp(conversationId);
    AppLogger.info(_tag, 'declined $conversationId over HTTP');
  } catch (e) {
    // The caller will time out on their end; nothing else to do from here.
    AppLogger.warn(_tag, 'could not decline $conversationId: $e');
  }
}

/// Publishes the port the background isolate forwards presses to. Called once
/// the app is running; the matching [ReceivePort] listener turns each message
/// back into a [CallNotificationEvent].
ReceivePort registerNotificationActionPort(
  void Function(CallNotificationEvent event) onAction,
) {
  IsolateNameServer.removePortNameMapping(kNotificationActionPort);
  final port = ReceivePort();
  IsolateNameServer.registerPortWithName(port.sendPort, kNotificationActionPort);

  port.listen((message) {
    if (message is! Map) return;
    final actionId = message['actionId'] as String?;
    if (actionId == null) return;
    onAction(CallNotificationEvent(
      action: callActionFromId(actionId),
      conversationId: (message['conversationId'] as String?) ?? '',
      peerUsername: (message['peerUsername'] as String?) ?? '',
    ));
  });

  return port;
}

/// Tells the node to end a call without going through the socket. Used by the
/// background isolate above, and as a fallback when the socket is down.
Future<void> declineCallOverHttp(String conversationId) async {
  final node = NodeStorage();
  final host = await node.readHost();
  final nodeToken = await node.readNodeToken();
  final fingerprint = await node.readFingerprint();
  final accessToken = await TokenStorage().readAccessToken();

  if (host == null || nodeToken == null || accessToken == null) {
    throw StateError('no stored session');
  }

  final httpClient = HttpClient()
    ..badCertificateCallback = buildPinningCallback(
      pinnedFingerprint: fingerprint,
      // Pairing is what establishes trust; this isolate never gets to pin a
      // certificate it hasn't seen before.
      onFirstPin: (_) {},
    );

  final dio = Dio(BaseOptions(
    baseUrl: 'https://$host',
    connectTimeout: const Duration(seconds: 10),
    headers: {
      'X-Node-Token': nodeToken,
      'Authorization': 'Bearer $accessToken',
    },
  ));
  dio.httpClientAdapter = IOHttpClientAdapter(createHttpClient: () => httpClient);

  await dio.post('/calls/$conversationId/decline');
}
