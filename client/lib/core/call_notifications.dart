import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'logger.dart';

const _tag = 'notify';

/// Android heads-up notification for an incoming call. On Windows there's
/// no equivalent (and none is needed — the window is right there), so every
/// method is a no-op off Android.
class CallNotifications {
  static final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  static const int _incomingCallId = 1001;

  static const AndroidNotificationDetails _incomingCallDetails = AndroidNotificationDetails(
    'incoming_calls',
    'Входящие звонки',
    channelDescription: 'Уведомления о входящих звонках',
    importance: Importance.max,
    priority: Priority.max,
    category: AndroidNotificationCategory.call,
    // The ringtone is played by RingtoneService so it behaves identically on
    // both platforms; silence the notification's own sound to avoid a double
    // ring.
    playSound: false,
    enableVibration: true,
    ongoing: true,
    autoCancel: false,
    fullScreenIntent: true,
    visibility: NotificationVisibility.public,
  );

  static Future<void> init() async {
    if (!Platform.isAndroid) return;
    try {
      const settings = InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      );
      await _plugin.initialize(settings);

      final android =
          _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      await android?.requestNotificationsPermission();
    } catch (e, st) {
      AppLogger.error(_tag, 'init failed', e, st);
    }
  }

  static Future<void> showIncomingCall(String peerUsername) async {
    if (!Platform.isAndroid) return;
    try {
      await _plugin.show(
        _incomingCallId,
        'Входящий звонок',
        '@$peerUsername звонит вам',
        const NotificationDetails(android: _incomingCallDetails),
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
