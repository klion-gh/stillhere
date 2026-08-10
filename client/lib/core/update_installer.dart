import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

import 'logger.dart';
import 'update_checker.dart';

const _tag = 'update';

enum UpdateStage { idle, downloading, launching, done, failed }

class UpdateProgress {
  final UpdateStage stage;
  final double fraction;
  final String? error;

  const UpdateProgress({this.stage = UpdateStage.idle, this.fraction = 0, this.error});

  bool get isBusy => stage == UpdateStage.downloading || stage == UpdateStage.launching;

  UpdateProgress copyWith({UpdateStage? stage, double? fraction, String? error}) {
    return UpdateProgress(
      stage: stage ?? this.stage,
      fraction: fraction ?? this.fraction,
      error: error,
    );
  }
}

/// Downloads the release asset for this platform and hands it to the OS to
/// install — no browser round trip.
///
/// On Android that means launching the package installer on the downloaded
/// APK; the system asks the user to allow installs from StillHere the first
/// time (REQUEST_INSTALL_PACKAGES only lets us ask). On Windows the
/// downloaded file is the Inno Setup installer, so simply starting it runs
/// the normal upgrade flow.
class UpdateInstaller extends StateNotifier<UpdateProgress> {
  UpdateInstaller() : super(const UpdateProgress());

  CancelToken? _cancelToken;

  Future<void> downloadAndInstall(UpdateInfo info) async {
    if (state.isBusy) return;

    final url = info.downloadUrl;
    // A release-page URL means we had no direct asset for this platform;
    // there's nothing to hand to the installer.
    if (!url.endsWith('.apk') && !url.endsWith('.exe')) {
      state = state.copyWith(
        stage: UpdateStage.failed,
        error: 'Для этой платформы нет готового файла обновления.',
      );
      return;
    }

    state = const UpdateProgress(stage: UpdateStage.downloading);
    _cancelToken = CancelToken();

    try {
      final dir = await getApplicationSupportDirectory();
      final fileName = Platform.isAndroid
          ? 'stillhere-${info.latest.version}.apk'
          : 'stillhere-${info.latest.version}.exe';
      final savePath = '${dir.path}${Platform.pathSeparator}$fileName';

      // A partial file from an interrupted attempt would be rejected by the
      // installer, so always start clean.
      final existing = File(savePath);
      if (await existing.exists()) await existing.delete();

      AppLogger.info(_tag, 'downloading $url -> $savePath');
      await Dio().download(
        url,
        savePath,
        cancelToken: _cancelToken,
        onReceiveProgress: (received, total) {
          if (total <= 0) return;
          state = state.copyWith(fraction: received / total);
        },
      );

      AppLogger.info(_tag, 'download complete, launching installer');
      state = state.copyWith(stage: UpdateStage.launching, fraction: 1);

      if (Platform.isWindows) {
        // Detached: the installer needs to replace this executable, so it
        // must outlive the process that started it.
        await Process.start(savePath, [], mode: ProcessStartMode.detached);
      } else {
        final result = await OpenFilex.open(savePath);
        if (result.type != ResultType.done) {
          throw Exception(result.message);
        }
      }

      state = state.copyWith(stage: UpdateStage.done);
    } on DioException catch (e, st) {
      if (CancelToken.isCancel(e)) {
        state = const UpdateProgress();
        return;
      }
      AppLogger.error(_tag, 'update download failed', e, st);
      state = state.copyWith(
        stage: UpdateStage.failed,
        error: 'Не удалось скачать обновление. Проверьте соединение.',
      );
    } catch (e, st) {
      AppLogger.error(_tag, 'update install failed', e, st);
      state = state.copyWith(
        stage: UpdateStage.failed,
        error: 'Не удалось запустить установку обновления.',
      );
    } finally {
      _cancelToken = null;
    }
  }

  void cancel() {
    _cancelToken?.cancel();
    state = const UpdateProgress();
  }

  void reset() {
    state = const UpdateProgress();
  }
}

final updateInstallerProvider =
    StateNotifierProvider<UpdateInstaller, UpdateProgress>((ref) => UpdateInstaller());
