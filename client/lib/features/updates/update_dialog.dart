import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../core/update_checker.dart';
import '../../core/update_installer.dart';

/// Download-and-install flow for a new release, run entirely inside the app.
class UpdateDialog extends ConsumerWidget {
  final UpdateInfo info;

  const UpdateDialog({super.key, required this.info});

  static Future<void> show(BuildContext context, UpdateInfo info) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => UpdateDialog(info: info),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final progress = ref.watch(updateInstallerProvider);
    final installer = ref.read(updateInstallerProvider.notifier);

    return PopScope(
      canPop: !progress.isBusy,
      child: AlertDialog(
        icon: Icon(
          progress.stage == UpdateStage.failed
              ? Icons.error_outline_rounded
              : Icons.system_update_rounded,
          color: progress.stage == UpdateStage.failed ? AppColors.danger : AppColors.primary,
          size: 32,
        ),
        title: Text(_title(progress.stage)),
        content: _Content(info: info, progress: progress),
        actions: _actions(context, ref, progress, installer),
      ),
    );
  }

  String _title(UpdateStage stage) {
    switch (stage) {
      case UpdateStage.downloading:
        return 'Загрузка обновления';
      case UpdateStage.launching:
        return 'Запуск установки';
      case UpdateStage.done:
        return 'Готово к установке';
      case UpdateStage.failed:
        return 'Не получилось';
      case UpdateStage.idle:
        return 'Доступно обновление';
    }
  }

  List<Widget> _actions(
    BuildContext context,
    WidgetRef ref,
    UpdateProgress progress,
    UpdateInstaller installer,
  ) {
    switch (progress.stage) {
      case UpdateStage.downloading:
        return [
          TextButton(
            onPressed: installer.cancel,
            child: const Text('Отмена'),
          ),
        ];
      case UpdateStage.launching:
        return const [];
      case UpdateStage.done:
        return [
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(120, 44)),
            onPressed: () {
              installer.reset();
              Navigator.of(context).pop();
            },
            child: const Text('Закрыть'),
          ),
        ];
      case UpdateStage.failed:
        return [
          TextButton(
            onPressed: () {
              installer.reset();
              Navigator.of(context).pop();
            },
            child: const Text('Закрыть'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(120, 44)),
            onPressed: () => installer.downloadAndInstall(info),
            child: const Text('Ещё раз'),
          ),
        ];
      case UpdateStage.idle:
        return [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Позже'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(120, 44)),
            onPressed: () => installer.downloadAndInstall(info),
            child: const Text('Обновить'),
          ),
        ];
    }
  }
}

class _Content extends StatelessWidget {
  final UpdateInfo info;
  final UpdateProgress progress;

  const _Content({required this.info, required this.progress});

  @override
  Widget build(BuildContext context) {
    switch (progress.stage) {
      case UpdateStage.downloading:
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(100),
              child: LinearProgressIndicator(
                value: progress.fraction > 0 ? progress.fraction : null,
                minHeight: 8,
                backgroundColor: AppColors.surfaceOutline,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '${(progress.fraction * 100).toStringAsFixed(0)}%',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
            ),
          ],
        );

      case UpdateStage.launching:
        return const Row(
          children: [
            SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.2)),
            SizedBox(width: 14),
            Expanded(child: Text('Открываем установщик…')),
          ],
        );

      case UpdateStage.done:
        return Text(
          Platform.isAndroid
              ? 'Установщик открыт. Если система спросит разрешение на установку из этого источника — разрешите его для StillHere.'
              : 'Установщик запущен. Следуйте его подсказкам, чтобы завершить обновление.',
        );

      case UpdateStage.failed:
        return Text(progress.error ?? 'Неизвестная ошибка.');

      case UpdateStage.idle:
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Новая версия: ${info.latest.version}\nУ вас: ${info.currentVersion}'),
            if (Platform.isAndroid) ...[
              const SizedBox(height: 12),
              Text(
                'Android попросит разрешить установку из этого источника — это нужно один раз.',
                style: TextStyle(color: AppColors.textMuted, fontSize: 13, height: 1.4),
              ),
            ],
          ],
        );
    }
  }
}
