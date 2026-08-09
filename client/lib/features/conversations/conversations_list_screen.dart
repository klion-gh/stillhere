import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme.dart';
import '../../core/update_checker.dart';
import '../../widgets/gradient_avatar.dart';
import '../auth/auth_controller.dart';
import '../connect/node_controller.dart';
import 'conversations_controller.dart';

class ConversationsListScreen extends ConsumerWidget {
  const ConversationsListScreen({super.key});

  Future<void> _showUpdateDialog(BuildContext context, UpdateInfo info) async {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.system_update_rounded, color: AppColors.primary, size: 32),
        title: const Text('Доступно обновление'),
        content: Text('Новая версия: ${info.latest.version}\nУ вас: ${info.currentVersion}'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Позже')),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(120, 44)),
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
      body: NightBackdrop(
        child: SafeArea(
          child: Column(
            children: [
              _Header(
                username: username,
                updateInfo: updateInfo,
                onUpdateTap: updateInfo == null ? null : () => _showUpdateDialog(context, updateInfo),
                onLogout: () => ref.read(authControllerProvider.notifier).logout(),
                onSwitchServer: () => ref.read(nodeControllerProvider.notifier).disconnect(),
              ),
              Expanded(
                child: RefreshIndicator(
                  color: AppColors.primary,
                  backgroundColor: AppColors.surfaceHigh,
                  onRefresh: () => ref.read(conversationsProvider.notifier).refresh(),
                  child: conversationsAsync.when(
                    loading: () => const Center(child: CircularProgressIndicator()),
                    error: (err, _) => ListView(
                      children: [
                        const SizedBox(height: 80),
                        Center(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 32),
                            child: Text(
                              'Не удалось загрузить чаты.\n$err',
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: AppColors.textSecondary, height: 1.5),
                            ),
                          ),
                        ),
                      ],
                    ),
                    data: (conversations) {
                      if (conversations.isEmpty) return const _EmptyState();
                      return ListView.builder(
                        padding: const EdgeInsets.fromLTRB(12, 8, 12, 100),
                        itemCount: conversations.length,
                        itemBuilder: (context, index) {
                          final c = conversations[index];
                          return _ConversationTile(
                            username: c.peer.username,
                            subtitle: DateFormat.yMMMd().add_Hm().format(c.createdAt.toLocal()),
                            onTap: () => context.push('/chat/${c.id}', extra: c.peer.username),
                            onCall: () =>
                                context.push('/call/${c.id}?peer=${c.peer.username}&outgoing=true'),
                          );
                        },
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/search'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.person_add_alt_1_rounded),
        label: const Text('Найти', style: TextStyle(fontWeight: FontWeight.w600)),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final String? username;
  final UpdateInfo? updateInfo;
  final VoidCallback? onUpdateTap;
  final VoidCallback onLogout;
  final VoidCallback onSwitchServer;

  const _Header({
    required this.username,
    required this.updateInfo,
    required this.onUpdateTap,
    required this.onLogout,
    required this.onSwitchServer,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 12, 16),
      child: Row(
        children: [
          if (username != null) GradientAvatar(username: username!, size: 44),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Чаты',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.5,
                    color: AppColors.textPrimary,
                  ),
                ),
                if (username != null)
                  Text(
                    '@$username',
                    style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
                  ),
              ],
            ),
          ),
          if (updateInfo != null)
            IconButton(
              onPressed: onUpdateTap,
              tooltip: 'Доступно обновление ${updateInfo!.latest.version}',
              icon: Stack(
                clipBehavior: Clip.none,
                children: [
                  const Icon(Icons.system_update_rounded, color: AppColors.primary),
                  Positioned(
                    right: -1,
                    top: -1,
                    child: Container(
                      width: 9,
                      height: 9,
                      decoration: BoxDecoration(
                        color: AppColors.danger,
                        shape: BoxShape.circle,
                        border: Border.all(color: AppColors.background, width: 1.5),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert_rounded),
            onSelected: (value) {
              if (value == 'logout') {
                onLogout();
              } else if (value == 'switch_server') {
                onSwitchServer();
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: 'logout',
                child: Row(children: [
                  Icon(Icons.logout_rounded, size: 19),
                  SizedBox(width: 12),
                  Text('Выйти'),
                ]),
              ),
              PopupMenuItem(
                value: 'switch_server',
                child: Row(children: [
                  Icon(Icons.dns_rounded, size: 19),
                  SizedBox(width: 12),
                  Text('Сменить сервер'),
                ]),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ConversationTile extends StatelessWidget {
  final String username;
  final String subtitle;
  final VoidCallback onTap;
  final VoidCallback onCall;

  const _ConversationTile({
    required this.username,
    required this.subtitle,
    required this.onTap,
    required this.onCall,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.surfaceOutline.withValues(alpha: 0.6)),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                GradientAvatar(username: username, size: 48),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '@$username',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        subtitle,
                        style: const TextStyle(color: AppColors.textMuted, fontSize: 12.5),
                      ),
                    ],
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
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        const SizedBox(height: 80),
        Center(
          child: Column(
            children: [
              Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.surfaceOutline),
                ),
                child: const Icon(Icons.forum_outlined, size: 42, color: AppColors.textMuted),
              ),
              const SizedBox(height: 24),
              const Text(
                'Пока пусто',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 48),
                child: Text(
                  'Найдите друга по @тегу и начните разговор.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 14.5, height: 1.5),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
