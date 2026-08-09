import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

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

  String _phaseLabel(CallPhase phase) {
    switch (phase) {
      case CallPhase.incomingRinging:
        return 'Входящий звонок';
      case CallPhase.outgoingRinging:
        return 'Звоним...';
      case CallPhase.connecting:
        return 'Соединение...';
      case CallPhase.active:
        return 'В разговоре';
      case CallPhase.ended:
        return 'Завершено';
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final args = CallArgs(conversationId: conversationId, peerUsername: peerUsername, isOutgoing: isOutgoing);
    final callState = ref.watch(callControllerProvider(args));
    final controller = ref.read(callControllerProvider(args).notifier);

    ref.listen(callControllerProvider(args), (previous, next) {
      if (next.phase == CallPhase.ended && (previous?.phase != CallPhase.ended)) {
        Future.delayed(const Duration(milliseconds: 900), () {
          if (context.mounted && context.canPop()) context.pop();
        });
      }
    });

    return Scaffold(
      backgroundColor: Colors.black87,
      body: SafeArea(
        child: Column(
          children: [
            const Spacer(),
            CircleAvatar(
              radius: 56,
              child: Text(
                peerUsername.isNotEmpty ? peerUsername[0].toUpperCase() : '?',
                style: const TextStyle(fontSize: 40),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              peerUsername.isNotEmpty ? '@$peerUsername' : 'Звонок',
              style: const TextStyle(color: Colors.white, fontSize: 22),
            ),
            const SizedBox(height: 8),
            Text(_phaseLabel(callState.phase), style: const TextStyle(color: Colors.white70, fontSize: 16)),
            if (callState.error != null) ...[
              const SizedBox(height: 8),
              Text(callState.error!, style: const TextStyle(color: Colors.redAccent)),
            ],
            const Spacer(),
            Padding(
              padding: const EdgeInsets.only(bottom: 48),
              child: _buildControls(context, callState.phase, controller),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildControls(BuildContext context, CallPhase phase, CallController controller) {
    if (phase == CallPhase.incomingRinging) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _CircleButton(
            icon: Icons.call_end,
            color: Colors.red,
            onPressed: controller.declineIncomingCall,
          ),
          const SizedBox(width: 48),
          _CircleButton(
            icon: Icons.call,
            color: Colors.green,
            onPressed: controller.acceptIncomingCall,
          ),
        ],
      );
    }

    if (phase == CallPhase.ended) {
      return const SizedBox.shrink();
    }

    return _CircleButton(icon: Icons.call_end, color: Colors.red, onPressed: controller.hangUp);
  }
}

class _CircleButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback onPressed;

  const _CircleButton({required this.icon, required this.color, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Icon(icon, color: Colors.white, size: 32),
        ),
      ),
    );
  }
}
