/// Process entry point.
///
/// Everything here has to happen before the first frame, and the order is not
/// arbitrary: locale data first (a missing locale turns a formatted date into a
/// thrown exception and a grey box where the widget should be), push next (its
/// background handler must be registered on every launch, because Android's
/// stored pointer to it goes stale when the app is updated), then the desktop
/// window and tray.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

import 'app.dart';
import 'core/call_notifications.dart';
import 'core/desktop_notifications.dart';
import 'core/desktop_shell.dart';
import 'core/logger.dart';
import 'core/push_service.dart';

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

    // The whole UI is Russian, and intl throws rather than falling back when
    // asked for a locale it has no data for. An uncaught throw inside build()
    // is replaced by a grey ErrorWidget that expands to fill the viewport —
    // which is what a weekday-formatted chat timestamp used to do to the
    // conversation list.
    await initializeDateFormatting('ru');
    Intl.defaultLocale = 'ru';

    await CallNotifications.init();

    // Push has to come up before the first frame, not once the node state
    // resolves: the node's config is already on disk from pairing, and
    // waiting on state meant a cold start silently skipped setup entirely —
    // no FCM token, no background handler, no calls unless the app was open.
    await PushService.restoreFromStorage();

    // Desktop: tray icon, close-to-tray, and native toasts. Must run before
    // the first frame so the close handler is in place from the start.
    await DesktopShell.instance.init();
    await DesktopNotifications.init();

    runApp(const ProviderScope(child: StillHereApp()));
  }, (error, stack) {
    AppLogger.error('uncaught', error.toString(), error, stack);
  });
}
