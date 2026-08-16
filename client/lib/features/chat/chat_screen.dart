import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/call_notifications.dart';
import '../../core/incoming_call.dart';
import '../../core/theme.dart';
import '../../widgets/gradient_avatar.dart';
import '../auth/auth_controller.dart';
import 'chat_controller.dart';
import 'message_bubble.dart';

class ChatScreen extends ConsumerStatefulWidget {
  final String conversationId;
  final String? peerUsername;

  const ChatScreen({super.key, required this.conversationId, this.peerUsername});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _textController = TextEditingController();
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    // Enables/disables the send button as the field fills and empties.
    _textController.addListener(() => setState(() {}));

    // Mark this chat as open so its incoming messages don't fire a
    // notification while the user is reading them, and clear any that
    // arrived before they opened it.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(activeChatConversationIdProvider.notifier).state = widget.conversationId;
      CallNotifications.cancelMessages(widget.conversationId);
    });
  }

  @override
  void dispose() {
    final container = ProviderScope.containerOf(context, listen: false);
    final active = container.read(activeChatConversationIdProvider);
    if (active == widget.conversationId) {
      container.read(activeChatConversationIdProvider.notifier).state = null;
    }
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom({bool animate = true}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      final target = _scrollController.position.maxScrollExtent;
      if (animate) {
        _scrollController.animateTo(
          target,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
        );
      } else {
        _scrollController.jumpTo(target);
      }
    });
  }

  void _send() {
    final text = _textController.text;
    if (text.trim().isEmpty) return;
    ref.read(chatControllerProvider(widget.conversationId).notifier).sendMessage(text);
    _textController.clear();
    _scrollToBottom();
  }

  @override
  Widget build(BuildContext context) {
    final myId = ref.watch(authControllerProvider).valueOrNull?.user?.id;
    final messagesAsync = ref.watch(chatControllerProvider(widget.conversationId));
    final peer = widget.peerUsername ?? '';
    final canSend = _textController.text.trim().isNotEmpty;

    return Scaffold(
      body: NightBackdrop(
        child: SafeArea(
          child: Column(
            children: [
              _ChatHeader(
                peerUsername: peer,
                onBack: () => context.pop(),
                onCall: () => context.push('/call/${widget.conversationId}?peer=$peer&outgoing=true'),
              ),
              const Divider(height: 1),
              Expanded(
                child: messagesAsync.when(
                  loading: () => const Center(child: CircularProgressIndicator()),
                  error: (err, _) => Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Text(
                        'Ошибка загрузки:\n$err',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: AppColors.textSecondary, height: 1.5),
                      ),
                    ),
                  ),
                  data: (messages) {
                    _scrollToBottom(animate: false);
                    if (messages.isEmpty) {
                      return _EmptyChat(peerUsername: peer);
                    }
                    return ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.only(top: 8, bottom: 16),
                      itemCount: messages.length,
                      itemBuilder: (context, index) {
                        final m = messages[index];
                        final prev = index > 0 ? messages[index - 1] : null;
                        return MessageBubble(
                          message: m,
                          isMine: m.senderId == myId,
                          isGroupStart: prev == null || prev.senderId != m.senderId,
                        );
                      },
                    );
                  },
                ),
              ),
              _Composer(
                controller: _textController,
                canSend: canSend,
                onSend: _send,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChatHeader extends StatelessWidget {
  final String peerUsername;
  final VoidCallback onBack;
  final VoidCallback onCall;

  const _ChatHeader({required this.peerUsername, required this.onBack, required this.onCall});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 8, 12, 10),
      child: Row(
        children: [
          IconButton(onPressed: onBack, icon: const Icon(Icons.arrow_back_rounded)),
          if (peerUsername.isNotEmpty) GradientAvatar(username: peerUsername, size: 40),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              peerUsername.isNotEmpty ? '@$peerUsername' : 'Чат',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          IconButton(
            onPressed: onCall,
            tooltip: 'Позвонить',
            style: IconButton.styleFrom(
              backgroundColor: AppColors.surfaceHigh,
              foregroundColor: AppColors.accent,
            ),
            icon: const Icon(Icons.call_rounded, size: 20),
          ),
        ],
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  final TextEditingController controller;
  final bool canSend;
  final VoidCallback onSend;

  const _Composer({required this.controller, required this.canSend, required this.onSend});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(
        color: AppColors.background,
        border: Border(top: BorderSide(color: AppColors.surfaceOutline)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              decoration: const InputDecoration(
                hintText: 'Сообщение…',
                contentPadding: EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              ),
              minLines: 1,
              maxLines: 5,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => onSend(),
            ),
          ),
          const SizedBox(width: 10),
          AnimatedScale(
            scale: canSend ? 1 : 0.9,
            duration: const Duration(milliseconds: 150),
            child: Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: canSend ? AppColors.brandGradient : null,
                color: canSend ? null : AppColors.surfaceHigh,
              ),
              child: Material(
                color: Colors.transparent,
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: canSend ? onSend : null,
                  child: SizedBox(
                    width: 50,
                    height: 50,
                    child: Icon(
                      Icons.arrow_upward_rounded,
                      color: canSend ? Colors.white : AppColors.textMuted,
                      size: 22,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyChat extends StatelessWidget {
  final String peerUsername;

  const _EmptyChat({required this.peerUsername});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (peerUsername.isNotEmpty) GradientAvatar(username: peerUsername, size: 72, showPulse: true),
          const SizedBox(height: 20),
          Text(
            peerUsername.isNotEmpty ? 'Это начало вашего чата с @$peerUsername' : 'Пока нет сообщений',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textSecondary, fontSize: 14.5, height: 1.5),
          ),
        ],
      ),
    );
  }
}
