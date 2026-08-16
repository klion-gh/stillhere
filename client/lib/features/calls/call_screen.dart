import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../widgets/gradient_avatar.dart';
import 'call_controller.dart';

class CallScreen extends ConsumerWidget {
  final String conversationId;
  final String peerUsername;
  final bool isOutgoing;

  const CallScreen({
    super.key,
    required this.conversationId,
    required this.peerUsername,
    required this.isOutgoing,
  });

  String _phaseLabel(CallUiState state) {
    switch (state.phase) {
      case CallPhase.incomingRinging:
        return 'Входящий звонок';
      case CallPhase.outgoingRinging:
        return 'Звоним…';
      case CallPhase.connecting:
        return 'Соединение…';
      case CallPhase.active:
        if (state.reconnecting) return 'Переподключение…';
        final d = state.elapsed;
        final m = d.inMinutes.toString().padLeft(2, '0');
        final s = (d.inSeconds % 60).toString().padLeft(2, '0');
        return '$m:$s';
      case CallPhase.ended:
        return 'Звонок завершён';
    }
  }

  Future<void> _showInputPicker(BuildContext context, CallController controller, CallUiState state) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surfaceHigh,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.surfaceOutline,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 4, 20, 12),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Устройство ввода',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
                ),
              ),
            ),
            if (state.inputDevices.isEmpty)
              Padding(
                padding: const EdgeInsets.all(20),
                child: Text('Микрофоны не найдены', style: TextStyle(color: AppColors.textSecondary)),
              ),
            ...state.inputDevices.map(
              (device) => ListTile(
                leading: Icon(
                  device.id == state.selectedInputDeviceId ? Icons.check_circle : Icons.circle_outlined,
                  color: device.id == state.selectedInputDeviceId
                      ? AppColors.primary
                      : AppColors.textMuted,
                ),
                title: Text(device.label, maxLines: 2, overflow: TextOverflow.ellipsis),
                onTap: () {
                  controller.selectInputDevice(device.id);
                  Navigator.of(context).pop();
                },
              ),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final args = CallArgs(conversationId: conversationId, peerUsername: peerUsername, isOutgoing: isOutgoing);
    final callState = ref.watch(callControllerProvider(args));
    final controller = ref.read(callControllerProvider(args).notifier);

    ref.listen(callControllerProvider(args), (previous, next) {
      if (next.phase == CallPhase.ended && (previous?.phase != CallPhase.ended)) {
        Future.delayed(const Duration(milliseconds: 1100), () {
          if (context.mounted && context.canPop()) context.pop();
        });
      }
    });

    final isRinging =
        callState.phase == CallPhase.incomingRinging || callState.phase == CallPhase.outgoingRinging;

    return Scaffold(
      body: NightBackdrop(
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(flex: 2),
              // Everything in this column is centered explicitly — an earlier
              // version relied on the Column's default alignment and the
              // avatar drifted left once the phase label changed width.
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  SizedBox(
                    height: 190,
                    width: 190,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        GlowOrb(
                          color: AppColors.avatarGradient(peerUsername).colors.first,
                          size: 190,
                          opacity: isRinging ? 0.4 : 0.22,
                        ),
                        _PulsingAvatar(username: peerUsername, animate: isRinging),
                      ],
                    ),
                  ),
                  const SizedBox(height: 28),
                  Text(
                    peerUsername.isNotEmpty ? '@$peerUsername' : 'Звонок',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 26,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.4,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (callState.reconnecting) ...[
                        const SizedBox(
                          width: 13,
                          height: 13,
                          child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.danger),
                        ),
                        const SizedBox(width: 9),
                      ],
                      Text(
                        _phaseLabel(callState),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: callState.reconnecting
                              ? AppColors.danger
                              : callState.phase == CallPhase.active
                                  ? AppColors.accent
                                  : AppColors.textSecondary,
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                  if (callState.phase == CallPhase.active) ...[
                    const SizedBox(height: 16),
                    _PingRow(
                      ownRttMs: callState.ownRttMs,
                      peerRttMs: callState.peerRttMs,
                      peerUsername: peerUsername,
                    ),
                  ],
                  if (callState.error != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      callState.error!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: AppColors.danger, fontSize: 14),
                    ),
                  ],
                ],
              ),
              const Spacer(flex: 3),
              _CallControls(
                state: callState,
                controller: controller,
                onPickInput: () => _showInputPicker(context, controller, callState),
              ),
              const SizedBox(height: 36),
            ],
          ),
        ),
      ),
    );
  }
}

/// Latency of each side to the node. Not the peer-to-peer path, but it's
/// what tells you whose connection is the weak one.
class _PingRow extends StatelessWidget {
  final int? ownRttMs;
  final int? peerRttMs;
  final String peerUsername;

  const _PingRow({required this.ownRttMs, required this.peerRttMs, required this.peerUsername});

  static Color _colorFor(int? rtt) {
    if (rtt == null) return AppColors.textMuted;
    if (rtt < 100) return AppColors.success;
    if (rtt < 250) return AppColors.accent;
    return AppColors.danger;
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        _PingChip(label: 'Вы', rttMs: ownRttMs, color: _colorFor(ownRttMs)),
        const SizedBox(width: 10),
        _PingChip(
          label: peerUsername.isNotEmpty ? '@$peerUsername' : 'Собеседник',
          rttMs: peerRttMs,
          color: _colorFor(peerRttMs),
        ),
      ],
    );
  }
}

class _PingChip extends StatelessWidget {
  final String label;
  final int? rttMs;
  final Color color;

  const _PingChip({required this.label, required this.rttMs, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(100),
        border: Border.all(color: AppColors.surfaceOutline),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 7),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 92),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            rttMs != null ? '$rttMs мс' : '—',
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

class _PulsingAvatar extends StatefulWidget {
  final String username;
  final bool animate;

  const _PulsingAvatar({required this.username, required this.animate});

  @override
  State<_PulsingAvatar> createState() => _PulsingAvatarState();
}

class _PulsingAvatarState extends State<_PulsingAvatar> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );

  @override
  void initState() {
    super.initState();
    if (widget.animate) _controller.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(_PulsingAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.animate && !_controller.isAnimating) {
      _controller.repeat(reverse: true);
    } else if (!widget.animate && _controller.isAnimating) {
      _controller.stop();
      _controller.animateTo(0, duration: const Duration(milliseconds: 250));
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final scale = 1.0 + (_controller.value * 0.06);
        return Transform.scale(scale: scale, child: child);
      },
      child: GradientAvatar(username: widget.username, size: 128, showPulse: true),
    );
  }
}

class _CallControls extends StatelessWidget {
  final CallUiState state;
  final CallController controller;
  final VoidCallback onPickInput;

  const _CallControls({
    required this.state,
    required this.controller,
    required this.onPickInput,
  });

  @override
  Widget build(BuildContext context) {
    if (state.phase == CallPhase.ended) {
      return const SizedBox(height: 76);
    }

    if (state.phase == CallPhase.incomingRinging) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _CircleButton(
            icon: Icons.call_end_rounded,
            color: AppColors.danger,
            size: 68,
            label: 'Отклонить',
            onPressed: controller.declineIncomingCall,
          ),
          const SizedBox(width: 56),
          _CircleButton(
            icon: Icons.call_rounded,
            color: AppColors.success,
            size: 68,
            label: 'Ответить',
            onPressed: controller.acceptIncomingCall,
          ),
        ],
      );
    }

    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _CircleButton(
              icon: state.micMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
              color: state.micMuted ? AppColors.primary : AppColors.surfaceHigh,
              size: 56,
              label: state.micMuted ? 'Включить' : 'Микрофон',
              onPressed: controller.toggleMute,
            ),
            const SizedBox(width: 24),
            if (Platform.isAndroid)
              _CircleButton(
                icon: state.speakerOn ? Icons.volume_up_rounded : Icons.hearing_rounded,
                color: state.speakerOn ? AppColors.primary : AppColors.surfaceHigh,
                size: 56,
                label: state.speakerOn ? 'Динамик' : 'Наушник',
                onPressed: controller.toggleSpeaker,
              )
            else
              _CircleButton(
                icon: Icons.settings_voice_rounded,
                color: AppColors.surfaceHigh,
                size: 56,
                label: 'Устройство',
                onPressed: onPickInput,
              ),
          ],
        ),
        const SizedBox(height: 28),
        _CircleButton(
          icon: Icons.call_end_rounded,
          color: AppColors.danger,
          size: 68,
          label: 'Завершить',
          onPressed: controller.hangUp,
        ),
      ],
    );
  }
}

class _CircleButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final double size;
  final String label;
  final VoidCallback onPressed;

  const _CircleButton({
    required this.icon,
    required this.color,
    required this.size,
    required this.label,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final isAccent = color != AppColors.surfaceHigh;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: isAccent
                ? [BoxShadow(color: color.withValues(alpha: 0.35), blurRadius: 22, spreadRadius: 1)]
                : null,
          ),
          child: Material(
            color: color,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onPressed,
              child: SizedBox(
                width: size,
                height: size,
                child: Icon(icon, color: Colors.white, size: size * 0.42),
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          label,
          style: TextStyle(color: AppColors.textSecondary, fontSize: 12.5),
        ),
      ],
    );
  }
}
