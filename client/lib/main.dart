import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/call_notifications.dart';
import 'core/connection_service.dart';
import 'core/logger.dart';

void main() {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();

    FlutterError.onError = (details) {
      AppLogger.error('flutter', details.exceptionAsString(), details.exception, details.stack);
      FlutterError.presentError(details);
    };
    PlatformDispatcher.instance.onError = (error, stack) {
      AppLogger.error('platform', error.toString(), error, stack);
      return true;
    };

    await CallNotifications.init();
    ConnectionService.init();
    runApp(const ProviderScope(child: StillHereApp()));
  }, (error, stack) {
    AppLogger.error('uncaught', error.toString(), error, stack);
  });
}
