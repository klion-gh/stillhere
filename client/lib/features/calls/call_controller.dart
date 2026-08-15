import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../../core/api_client.dart';
import '../../core/call_notifications.dart';
import '../../core/incoming_call.dart';
import '../../core/logger.dart';
import '../../core/providers.dart';

const _tag = 'call';

enum CallPhase { incomingRinging, outgoingRinging, connecting, active, ended }

class AudioInputDevice {
  final String id;
  final String label;

  const AudioInputDevice({required this.id, required this.label});
}

class CallUiState {
  final CallPhase phase;
  final String? error;
  final bool micMuted;
  final bool speakerOn;
  final List<AudioInputDevice> inputDevices;
  final String? selectedInputDeviceId;
  final Duration elapsed;

  /// True while ICE has dropped mid-call and is trying to re-establish.
  final bool reconnecting;

  /// Latency to the node, ours and (as reported by them) the peer's.
  final int? ownRttMs;
  final int? peerRttMs;

  const CallUiState({
    required this.phase,
    this.error,
    this.micMuted = false,
    this.speakerOn = false,
    this.inputDevices = const [],
    this.selectedInputDeviceId,
    this.elapsed = Duration.zero,
    this.reconnecting = false,
    this.ownRttMs,
    this.peerRttMs,
  });

  CallUiState copyWith({
    CallPhase? phase,
    String? error,
    bool? micMuted,
    bool? speakerOn,
    List<AudioInputDevice>? inputDevices,
    String? selectedInputDeviceId,
    Duration? elapsed,
    bool? reconnecting,
    int? ownRttMs,
    int? peerRttMs,
  }) {
    return CallUiState(
      phase: phase ?? this.phase,
      error: error ?? this.error,
      micMuted: micMuted ?? this.micMuted,
      speakerOn: speakerOn ?? this.speakerOn,
      inputDevices: inputDevices ?? this.inputDevices,
      selectedInputDeviceId: selectedInputDeviceId ?? this.selectedInputDeviceId,
      elapsed: elapsed ?? this.elapsed,
      reconnecting: reconnecting ?? this.reconnecting,
      ownRttMs: ownRttMs ?? this.ownRttMs,
      peerRttMs: peerRttMs ?? this.peerRttMs,
    );
  }
}

class CallArgs {
  final String conversationId;
  final String peerUsername;
  final bool isOutgoing;

  const CallArgs({required this.conversationId, required this.peerUsername, required this.isOutgoing});

  @override
  bool operator ==(Object other) =>
      other is CallArgs &&
      other.conversationId == conversationId &&
      other.peerUsername == peerUsername &&
      other.isOutgoing == isOutgoing;

  @override
  int get hashCode => Object.hash(conversationId, peerUsername, isOutgoing);
}

final callControllerProvider =
    StateNotifierProvider.autoDispose.family<CallController, CallUiState, CallArgs>((ref, args) {
  final controller = CallController(ref, args);
  ref.onDispose(controller.disposeCall);
  return controller;
});

class CallController extends StateNotifier<CallUiState> {
  CallController(this._ref, this.args)
      : super(CallUiState(phase: args.isOutgoing ? CallPhase.connecting : CallPhase.incomingRinging)) {
    AppLogger.info(_tag, 'created for ${args.conversationId} (outgoing=${args.isOutgoing})');

    // Riverpod forbids a provider from writing another provider's state
    // synchronously while it's still being built (this constructor runs
    // inside callControllerProvider's own `create` callback) — defer to a
    // microtask so it runs right after this provider finishes building.
    Future.microtask(() {
      if (mounted) {
        _ref.read(activeCallConversationIdProvider.notifier).state = args.conversationId;
      }
    });

    _wsSub = _ref.read(wsClientProvider).events.listen(_onWsEvent);
    if (args.isOutgoing) {
      unawaited(_startOutgoingCall());
    } else {
      final pending = _ref.read(pendingIncomingCallProvider);
      if (pending != null && pending.conversationId == args.conversationId) {
        _pendingOfferSdp = pending.sdp;
      }
      unawaited(_ref.read(ringtoneServiceProvider).playIncoming());
      Future.microtask(() {
        if (mounted) {
          _ref.read(pendingIncomingCallProvider.notifier).state = null;
        }
      });
    }
  }

  final Ref _ref;
  final CallArgs args;

  RTCPeerConnection? _pc;
  MediaStream? _localStream;
  StreamSubscription<Map<String, dynamic>>? _wsSub;
  final List<RTCIceCandidate> _pendingRemoteCandidates = [];
  bool _remoteDescriptionSet = false;
  Map<String, dynamic>? _pendingOfferSdp;
  Timer? _elapsedTimer;
  Timer? _statsTimer;

  Future<List<Map<String, dynamic>>> _fetchIceServers() async {
    final dio = _ref.read(apiClientProvider);
    final res = await dio.get('/calls/ice-servers');
    return (res.data['iceServers'] as List).cast<Map<String, dynamic>>();
  }

  Future<void> _stopRingtone() async {
    await _ref.read(ringtoneServiceProvider).stop();
    await CallNotifications.cancelIncomingCall();
  }

  void _startElapsedTimer() {
    _elapsedTimer?.cancel();
    _elapsedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      state = state.copyWith(elapsed: state.elapsed + const Duration(seconds: 1));
    });
    _startStatsExchange();
  }

  /// Publishes our latency to the node so the other side can display it,
  /// and picks up whatever the WS client last measured for ourselves.
  void _startStatsExchange() {
    _statsTimer?.cancel();
    _statsTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (!mounted) return;
      final rtt = _ref.read(wsClientProvider).lastRttMs;
      if (rtt == null) return;
      state = state.copyWith(ownRttMs: rtt);
      _ref.read(wsClientProvider).send({
        'type': 'call:stats',
        'conversationId': args.conversationId,
        'rttMs': rtt,
      });
    });
  }

  Future<void> _ensurePeerConnection() async {
    if (_pc != null) return;

    final iceServers = await _fetchIceServers();
    AppLogger.info(_tag, 'fetched ${iceServers.length} ICE server(s): ${iceServers.map((s) => s['urls']).toList()}');
    final pc = await createPeerConnection({'iceServers': iceServers});
    _pc = pc;

    pc.onIceCandidate = (candidate) {
      if (candidate.candidate == null) return;
      AppLogger.info(_tag, 'local ICE candidate: ${candidate.candidate}');
      _ref.read(wsClientProvider).send({
        'type': 'call:ice-candidate',
        'conversationId': args.conversationId,
        'candidate': {
          'candidate': candidate.candidate,
          'sdpMid': candidate.sdpMid,
          'sdpMLineIndex': candidate.sdpMLineIndex,
        },
      });
    };

    pc.onConnectionState = (connState) {
      AppLogger.info(_tag, 'peer connection state: $connState');
      if (connState == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        unawaited(_stopRingtone());
        if (!mounted) return;
        if (state.phase != CallPhase.active) {
          state = state.copyWith(phase: CallPhase.active, reconnecting: false);
          _startElapsedTimer();
          // Audio routing only sticks once the session is actually running,
          // which is why setting it earlier could silently do nothing.
          unawaited(_applyAudioRouting());
        } else {
          state = state.copyWith(reconnecting: false);
        }
      } else if (connState == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
        unawaited(_stopRingtone());
        if (mounted) state = state.copyWith(phase: CallPhase.ended, error: 'Не удалось соединиться');
      }
    };

    pc.onIceConnectionState = (iceState) {
      AppLogger.info(_tag, 'ICE connection state: $iceState');
      if (!mounted) return;
      // A mid-call ICE drop usually recovers on its own; show it rather than
      // leaving the user wondering why the other side went quiet.
      final dropped = iceState == RTCIceConnectionState.RTCIceConnectionStateDisconnected ||
          iceState == RTCIceConnectionState.RTCIceConnectionStateChecking;
      if (state.phase == CallPhase.active) {
        state = state.copyWith(reconnecting: dropped);
      }
    };

    _localStream = await navigator.mediaDevices.getUserMedia({'audio': true, 'video': false});
    AppLogger.info(_tag, 'got local audio stream (${_localStream!.getAudioTracks().length} track(s))');
    for (final track in _localStream!.getAudioTracks()) {
      await pc.addTrack(track, _localStream!);
    }

    unawaited(_loadInputDevices());
  }

  /// Pushes the current speaker choice down to the platform. Android's audio
  /// manager quietly ignores routing changes made before the call's audio
  /// session is live, so this is re-applied on connect as well as on toggle
  /// — that mismatch is why the button used to need several presses.
  Future<void> _applyAudioRouting() async {
    if (!Platform.isAndroid) return;
    try {
      await Helper.setSpeakerphoneOn(state.speakerOn);
      AppLogger.info(_tag, 'audio routing applied (speaker=${state.speakerOn})');
    } catch (e, st) {
      AppLogger.error(_tag, 'failed to apply audio routing', e, st);
    }
  }

  /// Enumerates microphones so the desktop UI can offer a picker. Only
  /// meaningful once getUserMedia has granted permission — before that,
  /// labels come back empty on most platforms.
  Future<void> _loadInputDevices() async {
    try {
      final devices = await navigator.mediaDevices.enumerateDevices();
      final inputs = devices
          .where((d) => d.kind == 'audioinput')
          .map((d) => AudioInputDevice(
                id: d.deviceId,
                label: d.label.isNotEmpty ? d.label : 'Микрофон ${d.deviceId}',
              ))
          .toList();
      if (mounted && inputs.isNotEmpty) {
        state = state.copyWith(
          inputDevices: inputs,
          selectedInputDeviceId: state.selectedInputDeviceId ?? inputs.first.id,
        );
      }
    } catch (e, st) {
      AppLogger.error(_tag, 'failed to enumerate audio inputs', e, st);
    }
  }

  Future<void> _startOutgoingCall() async {
    try {
      await _ensurePeerConnection();
      final offer = await _pc!.createOffer();
      await _pc!.setLocalDescription(offer);
      AppLogger.info(_tag, 'sending offer for ${args.conversationId}');
      _ref.read(wsClientProvider).send({
        'type': 'call:offer',
        'conversationId': args.conversationId,
        'sdp': {'sdp': offer.sdp, 'type': offer.type},
      });
      if (mounted) state = state.copyWith(phase: CallPhase.outgoingRinging);
      unawaited(_ref.read(ringtoneServiceProvider).playOutgoing());
    } catch (e, st) {
      AppLogger.error(_tag, 'failed to start outgoing call', e, st);
      await _stopRingtone();
      if (mounted) state = state.copyWith(phase: CallPhase.ended, error: 'Нет доступа к микрофону');
    }
  }

  /// Called when the callee taps "Accept" on an incoming call.
  Future<void> acceptIncomingCall() async {
    final sdp = _pendingOfferSdp;
    if (sdp == null) {
      AppLogger.warn(_tag, 'acceptIncomingCall called with no pending offer');
      return;
    }
    await _stopRingtone();
    if (mounted) state = state.copyWith(phase: CallPhase.connecting);

    try {
      await _ensurePeerConnection();
      await _pc!.setRemoteDescription(RTCSessionDescription(sdp['sdp'] as String, sdp['type'] as String));
      _remoteDescriptionSet = true;
      await _drainPendingCandidates();

      final answer = await _pc!.createAnswer();
      await _pc!.setLocalDescription(answer);
      AppLogger.info(_tag, 'sending answer for ${args.conversationId}');
      _ref.read(wsClientProvider).send({
        'type': 'call:answer',
        'conversationId': args.conversationId,
        'sdp': {'sdp': answer.sdp, 'type': answer.type},
      });
    } catch (e, st) {
      AppLogger.error(_tag, 'failed to accept incoming call', e, st);
      if (mounted) state = state.copyWith(phase: CallPhase.ended, error: 'Нет доступа к микрофону');
    }
  }

  void declineIncomingCall() {
    AppLogger.info(_tag, 'declining incoming call for ${args.conversationId}');
    unawaited(_stopRingtone());
    _ref.read(wsClientProvider).send({'type': 'call:end', 'conversationId': args.conversationId});
    if (mounted) state = state.copyWith(phase: CallPhase.ended);
  }

  /// Mutes/unmutes the outgoing audio track. Disabling the track (rather
  /// than removing it) keeps the negotiated connection intact.
  Future<void> toggleMute() async {
    final tracks = _localStream?.getAudioTracks() ?? [];
    if (tracks.isEmpty) return;
    final newMuted = !state.micMuted;
    for (final track in tracks) {
      track.enabled = !newMuted;
    }
    AppLogger.info(_tag, 'mic ${newMuted ? 'muted' : 'unmuted'}');
    if (mounted) state = state.copyWith(micMuted: newMuted);
  }

  /// Android-only: routes audio between earpiece and loudspeaker.
  Future<void> toggleSpeaker() async {
    if (!Platform.isAndroid) return;
    final newSpeakerOn = !state.speakerOn;
    // Record the intent first, then apply it — so if the platform call is a
    // no-op because the audio session isn't ready yet, _applyAudioRouting
    // will replay the same intent once the call connects.
    if (mounted) state = state.copyWith(speakerOn: newSpeakerOn);
    await _applyAudioRouting();
  }

  /// Desktop-focused: switches which microphone feeds the call.
  Future<void> selectInputDevice(String deviceId) async {
    try {
      await Helper.selectAudioInput(deviceId);
      AppLogger.info(_tag, 'switched audio input to $deviceId');
      if (mounted) state = state.copyWith(selectedInputDeviceId: deviceId);
    } catch (e, st) {
      AppLogger.error(_tag, 'failed to select audio input', e, st);
    }
  }

  Future<void> _drainPendingCandidates() async {
    if (_pendingRemoteCandidates.isEmpty) return;
    AppLogger.info(_tag, 'draining ${_pendingRemoteCandidates.length} pending ICE candidate(s)');
    for (final c in _pendingRemoteCandidates) {
      await _pc?.addCandidate(c);
    }
    _pendingRemoteCandidates.clear();
  }

  void _onWsEvent(Map<String, dynamic> event) {
    if (event['conversationId'] != args.conversationId) return;

    switch (event['type']) {
      case 'call:answer':
        AppLogger.info(_tag, 'received answer for ${args.conversationId}');
        _handleAnswer(event['sdp'] as Map<String, dynamic>);
        break;
      case 'call:ice-candidate':
        _handleRemoteCandidate(event['candidate'] as Map<String, dynamic>);
        break;
      case 'call:end':
        AppLogger.info(_tag, 'peer ended call ${args.conversationId}');
        unawaited(_stopRingtone());
        if (mounted) state = state.copyWith(phase: CallPhase.ended);
        break;
      case 'call:stats':
        final peerRtt = event['rttMs'];
        if (peerRtt is int && mounted) {
          state = state.copyWith(peerRttMs: peerRtt);
        }
        break;
      case 'call:unavailable':
        AppLogger.warn(_tag, 'peer unreachable for ${args.conversationId}');
        unawaited(_stopRingtone());
        if (mounted) {
          state = state.copyWith(phase: CallPhase.ended, error: 'Пользователь не в сети');
        }
        break;
    }
  }

  Future<void> _handleAnswer(Map<String, dynamic> sdp) async {
    if (_pc == null) {
      AppLogger.warn(_tag, 'received answer with no local peer connection');
      return;
    }
    await _stopRingtone();
    await _pc!.setRemoteDescription(RTCSessionDescription(sdp['sdp'] as String, sdp['type'] as String));
    _remoteDescriptionSet = true;
    await _drainPendingCandidates();
    if (mounted && state.phase != CallPhase.active) {
      state = state.copyWith(phase: CallPhase.connecting);
    }
  }

  Future<void> _handleRemoteCandidate(Map<String, dynamic> c) async {
    AppLogger.info(_tag, 'remote ICE candidate: ${c['candidate']}');
    final candidate = RTCIceCandidate(
      c['candidate'] as String?,
      c['sdpMid'] as String?,
      c['sdpMLineIndex'] as int?,
    );
    if (_remoteDescriptionSet && _pc != null) {
      await _pc!.addCandidate(candidate);
    } else {
      _pendingRemoteCandidates.add(candidate);
    }
  }

  void hangUp() {
    if (state.phase != CallPhase.ended) {
      AppLogger.info(_tag, 'hanging up ${args.conversationId}');
      unawaited(_stopRingtone());
      _ref.read(wsClientProvider).send({'type': 'call:end', 'conversationId': args.conversationId});
      state = state.copyWith(phase: CallPhase.ended);
    }
  }

  Future<void> disposeCall() async {
    AppLogger.info(_tag, 'disposing call controller for ${args.conversationId}');
    _elapsedTimer?.cancel();
    _statsTimer?.cancel();
    await _stopRingtone();
    await _wsSub?.cancel();
    for (final track in _localStream?.getTracks() ?? <MediaStreamTrack>[]) {
      await track.stop();
    }
    await _pc?.close();
    if (_ref.read(activeCallConversationIdProvider) == args.conversationId) {
      _ref.read(activeCallConversationIdProvider.notifier).state = null;
    }
  }
}
