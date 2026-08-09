import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/update_checker.dart';
import '../auth/auth_controller.dart';
import '../connect/node_controller.dart';
import 'conversations_controller.dart';

class ConversationsListScreen extends ConsumerWidget {
  const ConversationsListScreen({super.key});

  Future<void> _showUpdateDialog(BuildContext context, UpdateInfo info) async {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Доступно обновление'),
        content: Text(
          'Новая версия: ${info.latest.version}\nУ вас: ${info.currentVersion}',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Позже')),
          FilledButton(
            onPressed: () {
              launchUrl(Uri.parse(info.downloadUrl), mode: LaunchMode.externalApplication);
              Navigator.of(context).pop();
            },
            child: const Text('Скачать'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final conversationsAsync = ref.watch(conversationsProvider);
    final username = ref.watch(authControllerProvider).valueOrNull?.user?.username;
    final updateInfo = ref.watch(updateCheckProvider).valueOrNull;

    return Scaffold(
      appBar: AppBar(
        title: Text(username != null ? '@$username' : 'StillHere'),
        actions: [
          if (updateInfo != null)
            IconButton(
              icon: const Badge(
                smallSize: 8,
                child: Icon(Icons.system_update),
              ),
              tooltip: 'Доступно обновление ${updateInfo.latest.version}',
              onPressed: () => _showUpdateDialog(context, updateInfo),
            ),
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
