import 'dart:developer' as developer;

/// Minimal tagged logger. Writes to both the VM/DevTools log (dart:developer,
/// visible in `flutter run`'s "Dart VM Service" output and DevTools) and
/// stdout via print (visible directly in the `flutter run` terminal), since
/// that's the fastest way to see what's happening while iterating locally.
class AppLogger {
  static void info(String tag, String message) {
    developer.log(message, name: 'stillhere.$tag', level: 800);
    // ignore: avoid_print
    print('[$tag] $message');
  }

  static void warn(String tag, String message) {
    developer.log(message, name: 'stillhere.$tag', level: 900);
    // ignore: avoid_print
    print('[$tag][WARN] $message');
  }

  static void error(String tag, String message, [Object? error, StackTrace? stackTrace]) {
    developer.log(message, name: 'stillhere.$tag', level: 1000, error: error, stackTrace: stackTrace);
    // ignore: avoid_print
    print('[$tag][ERROR] $message${error != null ? ' — $error' : ''}');
  }
}
