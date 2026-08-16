import 'dart:convert';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'call_notifications.dart';
import 'logger.dart';

const _tag = 'push';
const _configKey = 'firebase_client_config';

/// Firebase client configuration, supplied by whichever node the user paired
/// with. None of it is secret — the same values sit inside every published
/// Firebase app — which is why the node can hand them over. The credential
/// that authorises *sending* stays on the server.
class PushConfig {
  final String apiKey;
  final String appId;
  final String messagingSenderId;
  final String projectId;

  const PushConfig({
    required this.apiKey,
    required this.appId,
    required this.messagingSenderId,
    required this.projectId,
  });

  factory PushConfig.fromJson(Map<String, dynamic> json) => PushConfig(
        apiKey: json['apiKey'] as String,
        appId: json['appId'] as String,
        messagingSenderId: json['messagingSenderId'] as String,
        projectId: json['projectId'] as String,
      );

  Map<String, dynamic> toJson() => {
        'apiKey': apiKey,
        'appId': appId,
        'messagingSenderId': messagingSenderId,
        'projectId': projectId,
      };

  FirebaseOptions toOptions() => FirebaseOptions(
        apiKey: apiKey,
        appId: appId,
        messagingSenderId: messagingSenderId,
        projectId: projectId,
      );
}

/// Loads the stored config. Also used from the background isolate, which
/// starts with no app state and has to read it back from disk.
Future<PushConfig?> loadStoredPushConfig() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_configKey);
    if (raw == null) return null;
    return PushConfig.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  } catch (e) {
    AppLogger.warn(_tag, 'failed to read stored push config: $e');
    return null;
  }
}

/// Handles pushes that arrive while the app is terminated or backgrounded.
///
/// Must be a top-level function: Android runs these in a fresh isolate, so
/// nothing from the app's state is available and Firebase has to be brought
/// up again from the persisted config. All it does is surface a
/// notification — acting on it brings the app up, which opens the socket and
/// collects whatever the server parked.
@pragma('vm:entry-point')
Future<void> firebaseBackgroundHandler(RemoteMessage message) async {
  final config = await loadStoredPushConfig();
  if (config == null) return;
  if (Firebase.apps.isEmpty) {
    await Firebase.initializeApp(options: config.toOptions());
  }

  final data = message.data;
  AppLogger.info(_tag, 'background push: ${data['kind']}');
  await CallNotifications.init();

  if (data['kind'] == 'call') {
    await CallNotifications.showIncomingCall(
      conversationId: data['conversationId'] ?? '',
      peerUsername: data['callerUsername'] ?? '',
    );
  } else if (data['kind'] == 'message') {
    await CallNotifications.showMessage(
      conversationId: data['conversationId'] ?? '',
      senderUsername: data['senderUsername'] ?? '',
      preview: data['preview'] ?? '',
    );
  }
}

/// Firebase Cloud Messaging wiring. Android only — a desktop build keeps its
/// socket open for as long as it runs, so it never needs waking.
class PushService {
  static bool _started = false;
  static String? _token;

  static String? get token => _token;
  static bool get isAvailable => _token != null;

  /// Called when a token is issued or rotated, so the session layer can pass
  /// it to the node without this service knowing about auth.
  static Future<void> Function(String token)? onTokenReady;

  /// Brings Firebase up using config the node supplied. Safe to call
  /// repeatedly; re-running with a different project (the user switched
  /// nodes) is not supported in one session and simply keeps the first.
  static Future<void> configure(PushConfig config) async {
    if (!Platform.isAndroid) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_configKey, jsonEncode(config.toJson()));

      if (_started) return;
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp(options: config.toOptions());
      }
      _started = true;

      FirebaseMessaging.onBackgroundMessage(firebaseBackgroundHandler);

      final messaging = FirebaseMessaging.instance;
      await messaging.requestPermission(alert: true, badge: true, sound: true);

      _token = await messaging.getToken();
      AppLogger.info(
        _tag,
        _token != null
            ? 'token acquired for project ${config.projectId}'
            : 'no token issued for project ${config.projectId}',
      );
      if (_token != null) await onTokenReady?.call(_token!);

      // Tokens rotate (app data cleared, restored to a new device); the node
      // needs to hear about it or pushes silently stop arriving.
      messaging.onTokenRefresh.listen((fresh) async {
        AppLogger.info(_tag, 'token refreshed');
        _token = fresh;
        await onTokenReady?.call(fresh);
      });
    } catch (e, st) {
      // A device without Play Services, or a node whose Firebase project is
      // misconfigured: the app keeps working, just without background
      // delivery.
      AppLogger.error(_tag, 'firebase init failed; push disabled', e, st);
    }
  }

  /// Forgets the node's project. Called when the user disconnects from a
  /// node so the next one doesn't inherit the previous project's config.
  static Future<void> forget() async {
    _token = null;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_configKey);
    } catch (e) {
      AppLogger.warn(_tag, 'failed to clear push config: $e');
    }
  }

  /// Pushes received while the app is in the foreground. The socket normally
  /// beats them to it, so this is only a fallback for the window right after
  /// resuming.
  static void listenForeground(void Function(RemoteMessage message) handler) {
    if (!Platform.isAndroid || !_started) return;
    FirebaseMessaging.onMessage.listen(handler);
    FirebaseMessaging.onMessageOpenedApp.listen(handler);
  }
}
