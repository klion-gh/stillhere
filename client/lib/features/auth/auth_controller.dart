import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../core/logger.dart';
import '../../core/providers.dart';
import '../../core/push_service.dart';
import '../../models/user.dart';
import '../connect/node_client.dart';
import 'auth_state.dart';

const _tag = 'auth';

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

      AppLogger.info(_tag, '$path succeeded for @${user.username}');
      state = AsyncValue.data(AuthState(user: user, accessToken: accessToken, refreshToken: refreshToken));
    } on DioException catch (e) {
      final code = (e.response?.data is Map) ? (e.response?.data as Map)['error'] as String? : null;
      final message = _messageForError(code);
      final authException = AuthException(message);
      AppLogger.error(_tag, '$path failed (code=$code)', e);
      state = AsyncValue.error(authException, StackTrace.current);
      throw authException;
    }
  }

  /// Re-reads the signed-in user from the node, so an avatar change shows up
  /// without a restart.
  Future<void> refreshProfile() async {
    final current = state.valueOrNull;
    if (current?.user == null) return;
    try {
      final dio = ref.read(apiClientProvider);
      final res = await dio.get('/users/me');
      final user = AppUser.fromJson(res.data as Map<String, dynamic>);
      state = AsyncValue.data(current!.copyWith(user: user));
    } catch (e) {
      AppLogger.warn(_tag, 'failed to refresh profile: $e');
    }
  }

  /// Takes on the token pair issued when the tag changes. The tag is encoded
  /// in the access token, so continuing with the old one would keep showing
  /// the previous name until it expired.
  Future<void> adoptRenamedSession({
    required String username,
    required String accessToken,
    required String refreshToken,
  }) async {
    final current = state.valueOrNull;
    if (current?.user == null) return;
    final user = current!.user!.copyWith(username: username);

    await ref.read(tokenStorageProvider).saveSession(
          accessToken: accessToken,
          refreshToken: refreshToken,
          userId: user.id,
          username: user.username,
        );
    state = AsyncValue.data(
      current.copyWith(user: user, accessToken: accessToken, refreshToken: refreshToken),
    );
    AppLogger.info(_tag, 'username changed to @$username');
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
      AppLogger.info(_tag, 'access token refreshed');
      return true;
    } catch (e) {
      AppLogger.error(_tag, 'token refresh failed, logging out', e);
      await logout();
      return false;
    }
  }

  /// Tells the node this device should receive pushes for the signed-in
  /// user. Failing here only costs background delivery, so it never blocks
  /// or fails the session.
  ///
  /// Called from two directions because the two prerequisites — a signed-in
  /// session and an issued FCM token — arrive in either order. On a cold
  /// start with a saved session the session is restored first and the token
  /// lands seconds later; on a fresh pair it's the other way round. Whichever
  /// completes second does the actual registration.
  Future<void> registerPushToken() async {
    if (!(state.valueOrNull?.isAuthenticated ?? false)) return;
    final token = PushService.token;
    if (token == null) return;
    try {
      final dio = ref.read(apiClientProvider);
      await dio.post('/devices/register', data: {'token': token, 'platform': 'android'});
      AppLogger.info(_tag, 'push token registered with node');
    } catch (e) {
      AppLogger.warn(_tag, 'failed to register push token: $e');
    }
  }

  Future<void> logout() async {
    AppLogger.info(_tag, 'logging out');

    // Unregister before dropping the tokens — afterwards the request can no
    // longer authenticate, and the node would keep pushing this user's calls
    // to a device that's signed out.
    final pushToken = PushService.token;
    if (pushToken != null) {
      try {
        final dio = ref.read(apiClientProvider);
        await dio.post('/devices/unregister', data: {'token': pushToken});
      } catch (e) {
        AppLogger.warn(_tag, 'failed to unregister push token: $e');
      }
    }

    await ref.read(tokenStorageProvider).clear();
    ref.read(wsClientProvider).disconnect();
    state = const AsyncValue.data(AuthState());
  }
}

final authControllerProvider = AsyncNotifierProvider<AuthController, AuthState>(AuthController.new);
