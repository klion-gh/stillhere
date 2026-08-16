import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import 'call_notifications.dart';
import 'logger.dart';

const _tag = 'push';

/// Handles pushes that arrive while the app is terminated or backgrounded.
///
/// Must be a top-level function: Android spins up a fresh isolate for these,
/// so anything captured from the app's state is unavailable here. All it does
/// is surface a notification — when the user acts on it the app comes to the
/// foreground, opens its socket, and the server hands over the parked call.
@pragma('vm:entry-point')
Future<void> firebaseBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  final data = message.data;
  AppLogger.info(_tag, 'background push: ${data['kind']}');

  if (data['kind'] == 'call') {
    await CallNotifications.init();
    await CallNotifications.showIncomingCall(
      conversationId: data['conversationId'] ?? '',
      peerUsername: data['callerUsername'] ?? '',
    );
  } else if (data['kind'] == 'message') {
    await CallNotifications.init();
    await CallNotifications.showMessage(
      conversationId: data['conversationId'] ?? '',
      senderUsername: data['senderUsername'] ?? '',
      preview: data['preview'] ?? '',
    );
  }
}

/// Firebase Cloud Messaging wiring. Android only — the desktop build keeps
/// its socket open for as long as it runs, so it has no need to be woken.
class PushService {
  static bool _available = false;
  static String? _token;

  /// The device's push token, once Firebase has issued one.
  static String? get token => _token;

  static bool get isAvailable => _available;

  /// Called by whoever owns the session, so a refreshed token reaches the
  /// server without the service needing to know about auth.
  static Future<void> Function(String token)? onTokenReady;

  static Future<void> init() async {
    if (!Platform.isAndroid) return;
    try {
      await Firebase.initializeApp();
      FirebaseMessaging.onBackgroundMessage(firebaseBackgroundHandler);

      final messaging = FirebaseMessaging.instance;
      await messaging.requestPermission(alert: true, badge: true, sound: true);

      _token = await messaging.getToken();
      _available = _token != null;
      AppLogger.info(_tag, _available ? 'token acquired' : 'no token issued');
      if (_token != null) await onTokenReady?.call(_token!);

      // Tokens rotate (app data cleared, restore to a new device); the server
      // needs to hear about it or pushes silently stop arriving.
      messaging.onTokenRefresh.listen((fresh) async {
        AppLogger.info(_tag, 'token refreshed');
        _token = fresh;
        await onTokenReady?.call(fresh);
      });
    } catch (e, st) {
      // A build without google-services.json, or a device without Play
      // Services, simply doesn't get background delivery.
      AppLogger.error(_tag, 'firebase init failed; push disabled', e, st);
      _available = false;
    }
  }

  /// Pushes received while the app is in the foreground. The socket normally
  /// beats the push to it, so this is only a fallback for the window right
  /// after resuming.
  static void listenForeground(void Function(RemoteMessage message) handler) {
    if (!Platform.isAndroid) return;
    FirebaseMessaging.onMessage.listen(handler);
    FirebaseMessaging.onMessageOpenedApp.listen(handler);
  }
}
