import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/appearance.dart';
import '../../core/theme.dart';
import '../../models/user.dart';
import '../../widgets/gradient_avatar.dart';
import 'conversations_controller.dart';

class UserSearchScreen extends ConsumerStatefulWidget {
  const UserSearchScreen({super.key});

  @override
  ConsumerState<UserSearchScreen> createState() => _UserSearchScreenState();
}

class _UserSearchScreenState extends ConsumerState<UserSearchScreen> {
  final _tagController = TextEditingController();
  bool _searching = false;
  bool _searched = false;
  AppUser? _found;

  @override
  void dispose() {
    _tagController.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final tag = _tagController.text.trim();
    if (tag.isEmpty) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _searching = true;
      _searched = false;
      _found = null;
    });
    final result = await ref.read(conversationsProvider.notifier).lookupUser(tag);
    if (!mounted) return;
    setState(() {
      _searching = false;
      _searched = true;
      _found = result;
    });
  }

  Future<void> _startChat() async {
    if (_found == null) return;
    final conversation = await ref.read(conversationsProvider.notifier).startConversation(_found!.username);
    if (mounted) context.pushReplacement('/chat/${conversation.id}', extra: conversation.peer.username);
  }

  @override
  Widget build(BuildContext context) {
    // Colours come from AppColors statics, which Flutter can't track;
    // this makes the screen rebuild when the palette changes.
    watchPalette(ref);
    return Scaffold(
      appBar: AppBar(title: const Text('Найти по тегу')),
      extendBodyBehindAppBar: true,
      body: NightBackdrop(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _tagController,
                  autofocus: true,
                  autocorrect: false,
                  decoration: InputDecoration(
                    hintText: 'username',
                    prefixText: '@',
                    prefixIcon: const Icon(Icons.search_rounded, size: 20),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.arrow_forward_rounded, size: 20),
                      onPressed: _searching ? null : _search,
                    ),
                  ),
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) => _search(),
                ),
                const SizedBox(height: 28),
                if (_searching)
                  const Center(child: CircularProgressIndicator())
                else if (_searched && _found == null)
                  const _NotFound()
                else if (_found != null)
                  _FoundCard(user: _found!, onStart: _startChat),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FoundCard extends StatelessWidget {
  final AppUser user;
  final VoidCallback onStart;

  const _FoundCard({required this.user, required this.onStart});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.surfaceOutline),
      ),
      child: Column(
        children: [
          GradientAvatar.of(user, fallbackUsername: user.username, size: 76, showPulse: true),
          const SizedBox(height: 18),
          Text(
            '@${user.username}',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 22),
          FilledButton.icon(
            onPressed: onStart,
            icon: const Icon(Icons.chat_bubble_rounded, size: 19),
            label: const Text('Написать'),
          ),
        ],
      ),
    );
  }
}

class _NotFound extends StatelessWidget {
  const _NotFound();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const SizedBox(height: 24),
        Container(
          width: 76,
          height: 76,
          decoration: BoxDecoration(
            color: AppColors.surface,
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.surfaceOutline),
          ),
          child: Icon(Icons.person_off_outlined, size: 34, color: AppColors.textMuted),
        ),
        const SizedBox(height: 18),
        Text(
          'Пользователь не найден',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
        ),
        const SizedBox(height: 6),
        Text(
          'Проверьте тег — он должен быть точным.',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
        ),
      ],
    );
  }
}
