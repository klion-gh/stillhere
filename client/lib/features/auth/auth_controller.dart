import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../models/user.dart';
import '../connect/node_client.dart';
import 'auth_state.dart';

class AuthException implements Exception {
  final String message;
  AuthException(this.message);
  @override
  String toString() => message;
}

String _messageForError(String? code) {
  switch (code) {
    case 'username_taken':
      return 'Этот тег уже занят.';
    case 'invalid_username':
      return 'Тег: 3-20 символов, латиница/цифры/подчёркивание.';
    case 'invalid_credentials':
      return 'Неверный тег или пароль.';
    case 'invalid_body':
      return 'Пароль должен быть не короче 8 символов.';
    default:
      return 'Что-то пошло не так. Попробуйте ещё раз.';
  }
}

class AuthController extends AsyncNotifier<AuthState> {
  @override
  Future<AuthState> build() async {
    final storage = ref.read(tokenStorageProvider);
    final access = await storage.readAccessToken();
    final refresh = await storage.readRefreshToken();
    final userId = await storage.readUserId();
    final username = await storage.readUsername();

    if (access == null || refresh == null || userId == null || username == null) {
      return const AuthState();
    }
    return AuthState(
      user: AppUser(id: userId, username: username),
      accessToken: access,
      refreshToken: refresh,
    );
  }

  Future<void> register(String username, String password) async {
    await _submit('/auth/register', username, password);
  }

  Future<void> login(String username, String password) async {
    await _submit('/auth/login', username, password);
  }

  Future<void> _submit(String path, String username, String password) async {
    state = const AsyncValue.loading();
    try {
      final dio = buildNodeDio(ref);
      final res = await dio.post(path, data: {'username': username, 'password': password});
      final data = res.data as Map<String, dynamic>;
      final user = AppUser.fromJson(data['user'] as Map<String, dynamic>);
      final accessToken = data['accessToken'] as String;
      final refreshToken = data['refreshToken'] as String;

      await ref.read(tokenStorageProvider).saveSession(
            accessToken: accessToken,
            refreshToken: refreshToken,
            userId: user.id,
            username: user.username,
          );

      state = AsyncValue.data(AuthState(user: user, accessToken: accessToken, refreshToken: refreshToken));
    } on DioException catch (e) {
      final code = (e.response?.data is Map) ? (e.response?.data as Map)['error'] as String? : null;
      final message = _messageForError(code);
      final authException = AuthException(message);
      state = AsyncValue.error(authException, StackTrace.current);
      throw authException;
    }
  }

  /// Attempts to refresh the access token using the stored refresh token.
  /// Returns true on success. On failure, logs the user out.
  Future<bool> tryRefresh() async {
    final current = state.valueOrNull;
    final refreshToken = current?.refreshToken;
    if (refreshToken == null) return false;

    try {
      final dio = buildNodeDio(ref);
      final res = await dio.post('/auth/refresh', data: {'refreshToken': refreshToken});
      final data = res.data as Map<String, dynamic>;
      final accessToken = data['accessToken'] as String;
      final newRefreshToken = data['refreshToken'] as String;

      await ref.read(tokenStorageProvider).saveTokens(accessToken: accessToken, refreshToken: newRefreshToken);
      state = AsyncValue.data(current!.copyWith(accessToken: accessToken, refreshToken: newRefreshToken));
      return true;
    } catch (_) {
      await logout();
      return false;
    }
  }

  Future<void> logout() async {
    await ref.read(tokenStorageProvider).clear();
    ref.read(wsClientProvider).disconnect();
    state = const AsyncValue.data(AuthState());
  }
}

final authControllerProvider = AsyncNotifierProvider<AuthController, AuthState>(AuthController.new);
