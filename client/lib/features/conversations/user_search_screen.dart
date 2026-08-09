import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../models/user.dart';
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
    setState(() {
      _searching = true;
      _searched = false;
      _found = null;
    });
    final result = await ref.read(conversationsProvider.notifier).lookupUser(tag);
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
    return Scaffold(
      appBar: AppBar(title: const Text('Найти по тегу')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _tagController,
                    decoration: const InputDecoration(labelText: '@username', prefixText: '@'),
                    onSubmitted: (_) => _search(),
                  ),
                ),
                const SizedBox(width: 12),
                FilledButton(onPressed: _searching ? null : _search, child: const Text('Найти')),
              ],
            ),
            const SizedBox(height: 24),
            if (_searching) const Center(child: CircularProgressIndicator()),
            if (!_searching && _searched && _found == null) const Text('Пользователь не найден.'),
            if (!_searching && _found != null)
              Card(
                child: ListTile(
                  leading: CircleAvatar(child: Text(_found!.username[0].toUpperCase())),
                  title: Text('@${_found!.username}'),
                  trailing: FilledButton(onPressed: _startChat, child: const Text('Написать')),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
