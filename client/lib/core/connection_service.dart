import 'dart:io';

import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import 'logger.dart';

const _tag = 'fgservice';

/// Keeps the app's process alive on Android while the user is signed in.
///
/// The WebSocket lives in the main Dart isolate, and Android is free to kill
/// a backgrounded process at any time — which is why calls and messages only
/// arrived while the app was open. A foreground service makes the process
/// ineligible for that, so the socket (and therefore incoming calls) keeps
/// working with the app in the background. Android requires the persistent
/// notification that comes with it.
///
/// No-op off Android; desktop processes aren't reaped this way.
class ConnectionService {
  static bool _started = false;

  static void init() {
    if (!Platform.isAndroid) return;
    FlutterForegroundTask.initCommunicationPort();
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'stillhere_connection',
        channelName: 'Соединение StillHere',
        channelDescription: 'Держит связь с сервером, чтобы доходили звонки и сообщения.',
        // Android will not let a foreground service run without a
        // notification, but MIN importance keeps it out of the status bar
        // and tucks it into the shade's silent section — as close to
        // invisible as the platform permits.
        channelImportance: NotificationChannelImportance.MIN,
        priority: NotificationPriority.MIN,
        onlyAlertOnce: true,
        showWhen: false,
      ),
      iosNotificationOptions: const IOSNotificationOptions(),
      foregroundTaskOptions: ForegroundTaskOptions(
        // The socket keeps itself alive; this service exists purely to stop
        // the process from being killed, so it needs no periodic work.
        eventAction: ForegroundTaskEventAction.nothing(),
        autoRunOnBoot: false,
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );
  }

  /// Asks Android to exempt the app from battery optimisation.
  ///
  /// A foreground service alone isn't enough on most real phones: Doze and
  /// especially OEM battery managers (Xiaomi, Samsung, Huawei…) still freeze
  /// or kill the process, which is what makes background delivery work only
  /// some of the time. The user has to grant this themselves; we can only
  /// bring up the dialog, and only once — repeatedly nagging is worse than
  /// the problem.
  static Future<void> ensureBatteryExemption() async {
    if (!Platform.isAndroid) return;
    try {
      if (await FlutterForegroundTask.isIgnoringBatteryOptimizations) return;
      await FlutterForegroundTask.requestIgnoreBatteryOptimization();
    } catch (e, st) {
      AppLogger.error(_tag, 'battery optimisation request failed', e, st);
    }
  }

  static Future<void> start() async {
    if (!Platform.isAndroid || _started) return;
    try {
      final permission = await FlutterForegroundTask.checkNotificationPermission();
      if (permission != NotificationPermission.granted) {
        await FlutterForegroundTask.requestNotificationPermission();
      }
      await ensureBatteryExemption();

      if (await FlutterForegroundTask.isRunningService) {
        _started = true;
        return;
      }

      await FlutterForegroundTask.startService(
        notificationTitle: 'StillHere',
        notificationText: 'На связи',
      );
      _started = true;
      AppLogger.info(_tag, 'foreground service started');
    } catch (e, st) {
      // Losing the service degrades background delivery but must never stop
      // the user from using the app in the foreground.
      AppLogger.error(_tag, 'failed to start foreground service', e, st);
    }
  }

  static Future<void> stop() async {
    if (!Platform.isAndroid || !_started) return;
    try {
      await FlutterForegroundTask.stopService();
      AppLogger.info(_tag, 'foreground service stopped');
    } catch (e, st) {
      AppLogger.error(_tag, 'failed to stop foreground service', e, st);
    } finally {
      _started = false;
    }
  }
}
