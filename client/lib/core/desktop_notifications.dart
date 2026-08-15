import 'package:local_notifier/local_notifier.dart';

import 'desktop_shell.dart';
import 'logger.dart';

const _tag = 'toast';

/// Native Windows toasts for calls and messages, with actions. Mirrors what
/// CallNotifications does on Android.
class DesktopNotifications {
  static bool _ready = false;

  /// Wired up by the app so toast actions can drive navigation and calls.
  static void Function(String conversationId, String peerUsername, bool accept)? onCallAction;
  static void Function(String conversationId, String peerUsername)? onMessageTap;

  // Held so the call toast can be dismissed when the call ends. Message
  // toasts aren't retained — local_notifier keeps its own reference for
  // callback dispatch, and they're never cancelled programmatically.
  static LocalNotification? _callToast;

  static Future<void> init() async {
    if (!DesktopShell.isSupported) return;
    try {
      await localNotifier.setup(appName: 'StillHere');
      _ready = true;
    } catch (e, st) {
      AppLogger.error(_tag, 'setup failed', e, st);
    }
  }

  static bool get _suppressed => !_ready || !DesktopShell.instance.notificationsEnabled;

  static Future<void> showIncomingCall({
    required String conversationId,
    required String peerUsername,
  }) async {
    if (!DesktopShell.isSupported || _suppressed) return;
    try {
      await _callToast?.close();
      final toast = LocalNotification(
        title: 'Входящий звонок',
        body: peerUsername.isNotEmpty ? '@$peerUsername звонит вам' : 'Вам звонят',
        actions: [
          LocalNotificationAction(text: 'Ответить'),
          LocalNotificationAction(text: 'Отклонить'),
        ],
      );
      toast.onClick = () {
        DesktopShell.instance.showWindow();
        onCallAction?.call(conversationId, peerUsername, false);
      };
      toast.onClickAction = (index) {
        final accept = index == 0;
        if (accept) DesktopShell.instance.showWindow();
        onCallAction?.call(conversationId, peerUsername, accept);
      };
      _callToast = toast;
      await toast.show();
    } catch (e, st) {
      AppLogger.error(_tag, 'showIncomingCall failed', e, st);
    }
  }

  static Future<void> cancelIncomingCall() async {
    if (!DesktopShell.isSupported) return;
    try {
      await _callToast?.close();
      _callToast = null;
    } catch (e) {
      AppLogger.warn(_tag, 'failed to close call toast: $e');
    }
  }

  static Future<void> showMessage({
    required String conversationId,
    required String senderUsername,
    required String preview,
  }) async {
    if (!DesktopShell.isSupported || _suppressed) return;
    try {
      final toast = LocalNotification(title: '@$senderUsername', body: preview);
      toast.onClick = () {
        DesktopShell.instance.showWindow();
        onMessageTap?.call(conversationId, senderUsername);
      };
      await toast.show();
    } catch (e, st) {
      AppLogger.error(_tag, 'showMessage failed', e, st);
    }
  }
}
