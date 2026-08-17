import 'dart:developer' as developer;

/// Minimal tagged logger. Writes to both the VM/DevTools log (dart:developer,
/// visible in `flutter run`'s "Dart VM Service" output and DevTools) and
/// stdout via print (visible directly in the `flutter run` terminal), since
/// that's the fastest way to see what's happening while iterating locally.
class AppLogger {
  /// Receives every line the app logs. Set by the diagnostics reporter when
  /// the node has recording switched on, so a trail of what actually happened
  /// can be collected from a user's device rather than reproduced by hand.
  /// Null the rest of the time, which is the normal case.
  static void Function(String level, String tag, String message)? sink;

  static void _emit(String level, String tag, String message) {
    final target = sink;
    if (target == null) return;
    // A logger that can throw would take down the code it's observing.
    try {
      target(level, tag, message);
    } catch (_) {}
  }

  static void info(String tag, String message) {
    developer.log(message, name: 'stillhere.$tag', level: 800);
    // ignore: avoid_print
    print('[$tag] $message');
    _emit('info', tag, message);
  }

  static void warn(String tag, String message) {
    developer.log(message, name: 'stillhere.$tag', level: 900);
    // ignore: avoid_print
    print('[$tag][WARN] $message');
    _emit('warn', tag, message);
  }

  static void error(String tag, String message, [Object? error, StackTrace? stackTrace]) {
    developer.log(message, name: 'stillhere.$tag', level: 1000, error: error, stackTrace: stackTrace);
    // ignore: avoid_print
    print('[$tag][ERROR] $message${error != null ? ' — $error' : ''}');
    _emit('error', tag, '$message${error != null ? ' — $error' : ''}');
  }
}
