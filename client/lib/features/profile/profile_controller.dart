import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image/image.dart' as img;

import '../../core/api_client.dart';
import '../../core/logger.dart';
import '../auth/auth_controller.dart';
import '../conversations/conversations_controller.dart';

const _tag = 'profile';

/// Longest edge of a stored avatar. Large enough to look sharp on a phone,
/// small enough that the encoded image comfortably fits the server's limit.
const _maxAvatarEdge = 512;

class ProfileException implements Exception {
  final String message;
  ProfileException(this.message);
  @override
  String toString() => message;
}

class ProfileController {
  ProfileController(this._ref);

  final Ref _ref;

  /// Downscales and re-encodes before upload. Phone cameras produce files far
  /// beyond what an avatar needs, and the server rejects anything over half a
  /// megabyte — resizing here is what makes the picker's output usable.
  Future<void> uploadAvatar(Uint8List bytes) async {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) {
      throw ProfileException('Не удалось прочитать изображение.');
    }

    final resized = decoded.width > _maxAvatarEdge || decoded.height > _maxAvatarEdge
        ? img.copyResize(
            decoded,
            width: decoded.width >= decoded.height ? _maxAvatarEdge : null,
            height: decoded.height > decoded.width ? _maxAvatarEdge : null,
            interpolation: img.Interpolation.average,
          )
        : decoded;

    final jpeg = img.encodeJpg(resized, quality: 85);
    AppLogger.info(_tag, 'avatar ${bytes.length} -> ${jpeg.length} bytes');

    try {
      final dio = _ref.read(apiClientProvider);
      await dio.post('/users/me/avatar', data: {
        'data': base64Encode(jpeg),
        'mime': 'image/jpeg',
      });
      await _ref.read(authControllerProvider.notifier).refreshProfile();
    } on DioException catch (e) {
      throw ProfileException(_messageFor(e));
    }
  }

  Future<void> removeAvatar() async {
    try {
      final dio = _ref.read(apiClientProvider);
      await dio.delete('/users/me/avatar');
      await _ref.read(authControllerProvider.notifier).refreshProfile();
    } on DioException catch (e) {
      throw ProfileException(_messageFor(e));
    }
  }

  Future<void> changeUsername(String username) async {
    try {
      final dio = _ref.read(apiClientProvider);
      final res = await dio.post('/users/me/username', data: {'username': username});
      final data = res.data as Map<String, dynamic>;
      // The tag lives inside the access token, so the server issues a new
      // pair and the session has to adopt it.
      await _ref.read(authControllerProvider.notifier).adoptRenamedSession(
            username: (data['user'] as Map<String, dynamic>)['username'] as String,
            accessToken: data['accessToken'] as String,
            refreshToken: data['refreshToken'] as String,
          );
      // Peers are told through peer:updated; our own list still holds the
      // old data until it's refetched.
      await _ref.read(conversationsProvider.notifier).refresh();
    } on DioException catch (e) {
      throw ProfileException(_messageFor(e));
    }
  }

  Future<void> changePassword(String current, String next) async {
    try {
      final dio = _ref.read(apiClientProvider);
      await dio.post('/users/me/password', data: {
        'currentPassword': current,
        'newPassword': next,
      });
    } on DioException catch (e) {
      throw ProfileException(_messageFor(e));
    }
  }

  String _messageFor(DioException e) {
    final code = (e.response?.data is Map) ? (e.response!.data as Map)['error'] as String? : null;
    switch (code) {
      case 'username_taken':
        return 'Этот тег уже занят.';
      case 'invalid_username':
        return 'Тег: 3–20 символов, латиница, цифры, _';
      case 'wrong_password':
        return 'Текущий пароль неверный.';
      case 'image_too_large':
        return 'Изображение слишком большое.';
      case 'unsupported_type':
        return 'Поддерживаются JPEG, PNG и WebP.';
      case 'invalid_body':
        return 'Пароль должен быть не короче 8 символов.';
      default:
        AppLogger.warn(_tag, 'unmapped profile error: $code');
        return 'Не удалось сохранить. Попробуйте ещё раз.';
    }
  }
}

final profileControllerProvider = Provider<ProfileController>((ref) => ProfileController(ref));
