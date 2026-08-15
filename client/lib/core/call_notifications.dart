import 'dart:convert';
import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'logger.dart';

const _tag = 'notify';

/// What the user did on an incoming-call notification.
enum CallNotificationAction { accept, decline, open }

class CallNotificationEvent {
  final CallNotificationAction action;
  final String conversationId;
  final String peerUsername;

  const CallNotificationEvent({
    required this.action,
    required this.conversationId,
    required this.peerUsername,
  });
}

/// Android notifications for calls and messages.
///
/// The incoming-call channel owns its own ringtone rather than leaving it to
/// the in-app player: when the app is backgrounded the Dart audio player may
/// never get audio focus, so the notification is the only thing that reliably
/// rings.
class CallNotifications {
  static final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  static const int _incomingCallId = 1001;

  static const String _acceptAction = 'call_accept';
  static const String _declineAction = 'call_decline';

  /// Set by the app so notification taps can drive navigation and call
  /// control from outside the widget tree.
  static void Function(CallNotificationEvent event)? onCallAction;

  static const AndroidNotificationDetails _incomingCallDetails = AndroidNotificationDetails(
    // Channel settings (sound in particular) are frozen when the channel is
    // first created, so adding the ringtone required a new channel id.
    'incoming_calls_v2',
    'Входящие звонки',
    channelDescription: 'Уведомления о входящих звонках',
    importance: Importance.max,
    priority: Priority.max,
    category: AndroidNotificationCategory.call,
    playSound: true,
    sound: RawResourceAndroidNotificationSound('ring_incoming'),
    audioAttributesUsage: AudioAttributesUsage.notificationRingtone,
    enableVibration: true,
    vibrationPattern: null,
    ongoing: true,
    autoCancel: false,
    fullScreenIntent: true,
    visibility: NotificationVisibility.public,
    actions: <AndroidNotificationAction>[
      AndroidNotificationAction(
        _declineAction,
        'Отклонить',
        showsUserInterface: false,
        cancelNotification: true,
      ),
      AndroidNotificationAction(
        _acceptAction,
        'Ответить',
        showsUserInterface: true,
        cancelNotification: true,
      ),
    ],
  );

  static const AndroidNotificationDetails _messageDetails = AndroidNotificationDetails(
    'messages',
    'Сообщения',
    channelDescription: 'Уведомления о новых сообщениях',
    importance: Importance.high,
    priority: Priority.high,
    category: AndroidNotificationCategory.message,
    playSound: true,
    enableVibration: true,
  );

  static Future<void> init() async {
    if (!Platform.isAndroid) return;
    try {
      const settings = InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      );
      await _plugin.initialize(
        settings,
        onDidReceiveNotificationResponse: _handleResponse,
      );

      final android =
          _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      await android?.requestNotificationsPermission();
    } catch (e, st) {
      AppLogger.error(_tag, 'init failed', e, st);
    }
  }

  static void _handleResponse(NotificationResponse response) {
    final payload = response.payload;
    if (payload == null || payload.isEmpty) return;

    Map<String, dynamic> data;
    try {
      data = jsonDecode(payload) as Map<String, dynamic>;
    } catch (e) {
      AppLogger.warn(_tag, 'unreadable notification payload: $payload');
      return;
    }
    if (data['kind'] != 'call') return;

    final action = switch (response.actionId) {
      _acceptAction => CallNotificationAction.accept,
      _declineAction => CallNotificationAction.decline,
      _ => CallNotificationAction.open,
    };

    AppLogger.info(_tag, 'call notification action: $action');
    onCallAction?.call(CallNotificationEvent(
      action: action,
      conversationId: (data['conversationId'] as String?) ?? '',
      peerUsername: (data['peerUsername'] as String?) ?? '',
    ));
  }

  static Future<void> showIncomingCall({
    required String conversationId,
    required String peerUsername,
  }) async {
    if (!Platform.isAndroid) return;
    try {
      await _plugin.show(
        _incomingCallId,
        'Входящий звонок',
        peerUsername.isNotEmpty ? '@$peerUsername звонит вам' : 'Вам звонят',
        const NotificationDetails(android: _incomingCallDetails),
        payload: jsonEncode({
          'kind': 'call',
          'conversationId': conversationId,
          'peerUsername': peerUsername,
        }),
      );
    } catch (e, st) {
      AppLogger.error(_tag, 'showIncomingCall failed', e, st);
    }
  }

  static Future<void> cancelIncomingCall() async {
    if (!Platform.isAndroid) return;
    try {
      await _plugin.cancel(_incomingCallId);
    } catch (e, st) {
      AppLogger.error(_tag, 'cancelIncomingCall failed', e, st);
    }
  }

  /// One notification per conversation, so a busy chat replaces its own
  /// entry instead of stacking up a wall of them.
  static Future<void> showMessage({
    required String conversationId,
    required String senderUsername,
    required String preview,
  }) async {
    if (!Platform.isAndroid) return;
    try {
      await _plugin.show(
        conversationId.hashCode & 0x7FFFFFFF,
        '@$senderUsername',
        preview,
        const NotificationDetails(android: _messageDetails),
      );
    } catch (e, st) {
      AppLogger.error(_tag, 'showMessage failed', e, st);
    }
  }

  static Future<void> cancelMessages(String conversationId) async {
    if (!Platform.isAndroid) return;
    try {
      await _plugin.cancel(conversationId.hashCode & 0x7FFFFFFF);
    } catch (e, st) {
      AppLogger.error(_tag, 'cancelMessages failed', e, st);
    }
  }
}
