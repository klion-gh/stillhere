/// Android notifications for calls and messages.
///
/// Two channels for one incoming call: one that rings, used when the push
/// arrived at a process that isn't running the app, and a silent one for when
/// the app is alive and already looping the ring itself. A channel plays its
/// sound exactly once, which is why the looping ring can't come from here. A
/// third channel carries the controls for a call in progress.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'background_actions.dart';
import 'logger.dart';

const _tag = 'notify';

/// Action ids carried on the call notification. Top level because the
/// background isolate that handles a press has to recognise them too.
const kCallAcceptAction = 'call_accept';
const kCallDeclineAction = 'call_decline';
const kCallHangUpAction = 'call_hang_up';
const kCallMuteAction = 'call_mute';
const kCallSpeakerAction = 'call_speaker';

/// What the user did on a call notification.
enum CallNotificationAction { accept, decline, open, hangUp, toggleMute, toggleSpeaker }

/// Maps an Android action id onto [CallNotificationAction]. Shared with the
/// background isolate, which forwards presses by id.
CallNotificationAction callActionFromId(String? actionId) => switch (actionId) {
      kCallAcceptAction => CallNotificationAction.accept,
      kCallDeclineAction => CallNotificationAction.decline,
      kCallHangUpAction => CallNotificationAction.hangUp,
      kCallMuteAction => CallNotificationAction.toggleMute,
      kCallSpeakerAction => CallNotificationAction.toggleSpeaker,
      _ => CallNotificationAction.open,
    };

class CallNotificationEvent {
  final CallNotificationAction action;
  final String conversationId;
  final String peerUsername;

  const CallNotificationEvent({
    required this.action,
    required this.conversationId,
    required this.peerUsername,
  });
}

/// Android notifications for calls and messages.
///
/// The incoming-call channel owns its own ringtone rather than leaving it to
/// the in-app player: when the app is backgrounded the Dart audio player may
/// never get audio focus, so the notification is the only thing that reliably
/// rings.
class CallNotifications {
  static final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  static const int _incomingCallId = 1001;
  static const int _ongoingCallId = 1002;


  /// Set by the app so notification taps can drive navigation and call
  /// control from outside the widget tree.
  static void Function(CallNotificationEvent event)? onCallAction;

  static const _callActions = <AndroidNotificationAction>[
    AndroidNotificationAction(
      kCallDeclineAction,
      'Отклонить',
      showsUserInterface: false,
      cancelNotification: true,
    ),
    AndroidNotificationAction(
      kCallAcceptAction,
      'Ответить',
      showsUserInterface: true,
      cancelNotification: true,
    ),
  ];

  /// Used when the push arrived at a process that isn't running the app —
  /// nothing else can ring, so the channel does it. Android plays a channel
  /// sound exactly once; the looping ring takes over once the app is up.
  static const AndroidNotificationDetails _incomingCallDetails = AndroidNotificationDetails(
    // Channel settings (sound in particular) are frozen when the channel is
    // first created, so adding the ringtone required a new channel id.
    'incoming_calls_v2',
    'Входящие звонки',
    channelDescription: 'Уведомления о входящих звонках',
    importance: Importance.max,
    priority: Priority.max,
    category: AndroidNotificationCategory.call,
    playSound: true,
    sound: RawResourceAndroidNotificationSound('ring_incoming'),
    audioAttributesUsage: AudioAttributesUsage.notificationRingtone,
    enableVibration: true,
    vibrationPattern: null,
    ongoing: true,
    autoCancel: false,
    fullScreenIntent: true,
    visibility: NotificationVisibility.public,
    actions: _callActions,
  );

  /// Same notification, no sound: the app is alive and RingtoneService is
  /// already looping the ring, so the channel would only double it up.
  static const AndroidNotificationDetails _incomingCallSilentDetails = AndroidNotificationDetails(
    'incoming_calls_silent',
    'Входящие звонки (без звука)',
    channelDescription: 'Показывается, когда звонок уже звучит в приложении',
    importance: Importance.max,
    priority: Priority.max,
    category: AndroidNotificationCategory.call,
    playSound: false,
    enableVibration: true,
    vibrationPattern: null,
    ongoing: true,
    autoCancel: false,
    fullScreenIntent: true,
    visibility: NotificationVisibility.public,
    actions: _callActions,
  );

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

  /// [requestPermission] must be false in the FCM background isolate: the
  /// permission prompt needs an Activity, and without one the plugin throws
  /// an NPE that aborts the rest of setup.
  static Future<void> init({bool requestPermission = true}) async {
    if (!Platform.isAndroid) return;
    try {
      const settings = InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      );
      await _plugin.initialize(
        settings,
        onDidReceiveNotificationResponse: _handleResponse,
        // Declining doesn't bring the app forward, so when the app isn't
        // running the press is delivered to a separate isolate instead.
        onDidReceiveBackgroundNotificationResponse: notificationBackgroundHandler,
      );

      if (!requestPermission) return;
      final android =
          _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      await android?.requestNotificationsPermission();
    } catch (e, st) {
      AppLogger.error(_tag, 'init failed', e, st);
    }
  }

  static void _handleResponse(NotificationResponse response) {
    final payload = response.payload;
    if (payload == null || payload.isEmpty) return;

    Map<String, dynamic> data;
    try {
      data = jsonDecode(payload) as Map<String, dynamic>;
    } catch (e) {
      AppLogger.warn(_tag, 'unreadable notification payload: $payload');
      return;
    }
    if (data['kind'] != 'call') return;

    final action = callActionFromId(response.actionId);

    AppLogger.info(_tag, 'call notification action: $action');
    onCallAction?.call(CallNotificationEvent(
      action: action,
      conversationId: (data['conversationId'] as String?) ?? '',
      peerUsername: (data['peerUsername'] as String?) ?? '',
    ));
  }

  /// [withSound] should be false whenever the app itself is ringing, which is
  /// the case for every call that arrives over the socket.
  static Future<void> showIncomingCall({
    required String conversationId,
    required String peerUsername,
    bool withSound = true,
  }) async {
    if (!Platform.isAndroid) return;
    try {
      await _plugin.show(
        _incomingCallId,
        'Входящий звонок',
        peerUsername.isNotEmpty ? '@$peerUsername звонит вам' : 'Вам звонят',
        NotificationDetails(
          android: withSound ? _incomingCallDetails : _incomingCallSilentDetails,
        ),
        payload: jsonEncode({
          'kind': 'call',
          'conversationId': conversationId,
          'peerUsername': peerUsername,
        }),
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

  /// The shade entry for a call that's already running, so leaving the call
  /// screen doesn't mean losing the call.
  ///
  /// Media style is what gets the controls drawn as compact round icon
  /// buttons — a plain notification renders its actions as a row of text.
  /// Call it again with new flags to update the buttons in place; the id is
  /// fixed, so it replaces rather than stacks.
  static Future<void> showOngoingCall({
    required String conversationId,
    required String peerUsername,
    required bool micMuted,
    required bool speakerOn,
    required String status,
  }) async {
    if (!Platform.isAndroid) return;
    try {
      final details = AndroidNotificationDetails(
        'ongoing_call',
        'Текущий звонок',
        channelDescription: 'Управление активным звонком',
        // Default importance keeps it out of the "Silent" pile at the bottom
        // of the shade — a call in progress belongs at the top. The channel
        // itself is silent, so nothing buzzes when a button is pressed.
        importance: Importance.defaultImportance,
        priority: Priority.defaultPriority,
        category: AndroidNotificationCategory.call,
        playSound: false,
        enableVibration: false,
        ongoing: true,
        autoCancel: false,
        onlyAlertOnce: true,
        showWhen: false,
        visibility: NotificationVisibility.public,
        styleInformation: const MediaStyleInformation(),
        actions: <AndroidNotificationAction>[
          AndroidNotificationAction(
            kCallMuteAction,
            micMuted ? 'Включить микрофон' : 'Выключить микрофон',
            icon: DrawableResourceAndroidBitmap(micMuted ? 'ic_mic_off' : 'ic_mic'),
            showsUserInterface: false,
            cancelNotification: false,
          ),
          const AndroidNotificationAction(
            kCallHangUpAction,
            'Положить трубку',
            icon: DrawableResourceAndroidBitmap('ic_call_end'),
            showsUserInterface: false,
            cancelNotification: true,
          ),
          AndroidNotificationAction(
            kCallSpeakerAction,
            speakerOn ? 'Динамик' : 'Разговорный',
            icon: DrawableResourceAndroidBitmap(speakerOn ? 'ic_speaker_on' : 'ic_speaker_off'),
            showsUserInterface: false,
            cancelNotification: false,
          ),
        ],
      );

      await _plugin.show(
        _ongoingCallId,
        peerUsername.isNotEmpty ? '@$peerUsername' : 'Звонок',
        status,
        NotificationDetails(android: details),
        payload: jsonEncode({
          'kind': 'call',
          'conversationId': conversationId,
          'peerUsername': peerUsername,
        }),
      );
    } catch (e, st) {
      AppLogger.error(_tag, 'showOngoingCall failed', e, st);
    }
  }

  static Future<void> cancelOngoingCall() async {
    if (!Platform.isAndroid) return;
    try {
      await _plugin.cancel(_ongoingCallId);
    } catch (e, st) {
      AppLogger.error(_tag, 'cancelOngoingCall failed', e, st);
    }
  }

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
