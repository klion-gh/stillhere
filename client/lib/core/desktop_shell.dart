import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import 'logger.dart';

const _tag = 'shell';
const _notificationsEnabledKey = 'desktop_notifications_enabled';

/// Desktop-only window and tray behaviour: closing hides to the tray rather
/// than quitting, and a tray menu offers a real quit plus a notification
/// toggle. No-op off Windows/desktop.
class DesktopShell with WindowListener, TrayListener {
  DesktopShell._();

  static final DesktopShell instance = DesktopShell._();

  static bool get isSupported => !kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS);

  bool _notificationsEnabled = true;
  bool get notificationsEnabled => _notificationsEnabled;

  final ValueNotifier<bool> notificationsEnabledListenable = ValueNotifier(true);

  Future<void> init() async {
    if (!isSupported) return;

    final prefs = await SharedPreferences.getInstance();
    _notificationsEnabled = prefs.getBool(_notificationsEnabledKey) ?? true;
    notificationsEnabledListenable.value = _notificationsEnabled;

    await windowManager.ensureInitialized();
    // Intercept the close button so we can hide instead of exiting.
    await windowManager.setPreventClose(true);
    windowManager.addListener(this);

    trayManager.addListener(this);
    await _setUpTray();
  }

  Future<void> _setUpTray() async {
    try {
      await trayManager.setIcon('assets/icons/tray.ico');
      await trayManager.setToolTip('StillHere');
      await _refreshTrayMenu();
    } catch (e, st) {
      AppLogger.error(_tag, 'failed to set up tray icon', e, st);
    }
  }

  Future<void> _refreshTrayMenu() async {
    final menu = Menu(
      items: [
        MenuItem(key: 'show', label: 'Открыть StillHere'),
        MenuItem.separator(),
        MenuItem.checkbox(
          key: 'toggle_notifications',
          label: _notificationsEnabled ? 'Выключить уведомления' : 'Включить уведомления',
          checked: _notificationsEnabled,
        ),
        MenuItem.separator(),
        MenuItem(key: 'quit', label: 'Закрыть StillHere'),
      ],
    );
    await trayManager.setContextMenu(menu);
  }

  Future<void> setNotificationsEnabled(bool value) async {
    _notificationsEnabled = value;
    notificationsEnabledListenable.value = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_notificationsEnabledKey, value);
    await _refreshTrayMenu();
  }

  /// Brings the window back from the tray and focuses it — used by the tray
  /// menu and by clicking a notification.
  Future<void> showWindow() async {
    if (!isSupported) return;
    try {
      await windowManager.show();
      await windowManager.focus();
    } catch (e, st) {
      AppLogger.error(_tag, 'failed to show window', e, st);
    }
  }

  Future<void> quit() async {
    if (!isSupported) return;
    await windowManager.setPreventClose(false);
    await windowManager.destroy();
  }

  @override
  void onWindowClose() {
    // Keep running in the tray so calls and messages still arrive.
    windowManager.hide();
    AppLogger.info(_tag, 'window hidden to tray');
  }

  @override
  void onTrayIconMouseDown() {
    showWindow();
  }

  @override
  void onTrayIconRightMouseDown() {
    trayManager.popUpContextMenu();
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    switch (menuItem.key) {
      case 'show':
        showWindow();
        break;
      case 'toggle_notifications':
        setNotificationsEnabled(!_notificationsEnabled);
        break;
      case 'quit':
        quit();
        break;
    }
  }

  void dispose() {
    if (!isSupported) return;
    windowManager.removeListener(this);
    trayManager.removeListener(this);
  }
}
