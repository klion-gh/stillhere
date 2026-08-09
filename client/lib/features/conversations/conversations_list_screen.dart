import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../auth/auth_controller.dart';
import '../connect/node_controller.dart';
import 'conversations_controller.dart';

class ConversationsListScreen extends ConsumerWidget {
  const ConversationsListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final conversationsAsync = ref.watch(conversationsProvider);
    final username = ref.watch(authControllerProvider).valueOrNull?.user?.username;

    return Scaffold(
      appBar: AppBar(
        title: Text(username != null ? '@$username' : 'StillHere'),
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'logout') {
                ref.read(authControllerProvider.notifier).logout();
              } else if (value == 'switch_server') {
                ref.read(nodeControllerProvider.notifier).disconnect();
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'logout', child: Text('Выйти')),
              PopupMenuItem(value: 'switch_server', child: Text('Сменить сервер')),
            ],
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.read(conversationsProvider.notifier).refresh(),
        child: conversationsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (err, _) => ListView(
            children: [
              const SizedBox(height: 64),
              Center(child: Text('Не удалось загрузить чаты: $err')),
            ],
          ),
          data: (conversations) {
            if (conversations.isEmpty) {
              return ListView(
                children: const [
                  SizedBox(height: 96),
                  Center(child: Text('Пока нет чатов.\nНайдите друга по @тегу.', textAlign: TextAlign.center)),
                ],
              );
            }
            return ListView.separated(
              itemCount: conversations.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final c = conversations[index];
                return ListTile(
                  leading: CircleAvatar(child: Text(c.peer.username.isNotEmpty ? c.peer.username[0].toUpperCase() : '?')),
                  title: Text('@${c.peer.username}'),
                  subtitle: Text(DateFormat.yMMMd().add_Hm().format(c.createdAt.toLocal())),
                  onTap: () => context.push('/chat/${c.id}', extra: c.peer.username),
                  trailing: IconButton(
                    icon: const Icon(Icons.call),
                    tooltip: 'Позвонить',
                    onPressed: () => context.push('/call/${c.id}?peer=${c.peer.username}&outgoing=true'),
                  ),
                );
              },
            );
          },
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.push('/search'),
        child: const Icon(Icons.person_add),
      ),
    );
  }
}
