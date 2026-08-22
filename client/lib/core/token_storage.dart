/// Persistence for the user session: the signed-in one, and every account signed
/// into before. See features/auth/saved_account.dart for the record itself.
library;

import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../features/auth/saved_account.dart';
import 'logger.dart';

const _tag = 'token-storage';

/// The signed-in session, plus every account signed into before.
///
/// Separate from NodeStorage, which holds the connection to the node itself.
/// Signing out clears the active session and leaves the saved list — that's
/// what lets someone come back by tapping their name instead of typing a
/// password.
class TokenStorage {
  final _storage = const FlutterSecureStorage();

  static const _kAccessToken = 'access_token';
  static const _kRefreshToken = 'refresh_token';
  static const _kUserId = 'user_id';
  static const _kUsername = 'username';
  static const _kSavedAccounts = 'saved_accounts';

  Future<void> saveSession({
    required String accessToken,
    required String refreshToken,
    required String userId,
    required String username,
  }) async {
    await Future.wait([
      _storage.write(key: _kAccessToken, value: accessToken),
      _storage.write(key: _kRefreshToken, value: refreshToken),
      _storage.write(key: _kUserId, value: userId),
      _storage.write(key: _kUsername, value: username),
    ]);
  }

  Future<void> saveTokens({required String accessToken, required String refreshToken}) async {
    await Future.wait([
      _storage.write(key: _kAccessToken, value: accessToken),
      _storage.write(key: _kRefreshToken, value: refreshToken),
    ]);
  }

  Future<String?> readAccessToken() => _storage.read(key: _kAccessToken);
  Future<String?> readRefreshToken() => _storage.read(key: _kRefreshToken);
  Future<String?> readUserId() => _storage.read(key: _kUserId);
  Future<String?> readUsername() => _storage.read(key: _kUsername);

  /// Ends the session. Leaves the saved accounts alone — signing out is not
  /// the same as saying "forget me".
  Future<void> clear() async {
    await Future.wait([
      _storage.delete(key: _kAccessToken),
      _storage.delete(key: _kRefreshToken),
      _storage.delete(key: _kUserId),
      _storage.delete(key: _kUsername),
    ]);
  }

  Future<List<SavedAccount>> readSavedAccounts() async {
    try {
      final raw = await _storage.read(key: _kSavedAccounts);
      if (raw == null || raw.isEmpty) return const [];
      final list = (jsonDecode(raw) as List)
          .whereType<Map<String, dynamic>>()
          .map(SavedAccount.fromJson)
          .whereType<SavedAccount>()
          .toList();
      list.sort((a, b) => b.lastUsedAt.compareTo(a.lastUsedAt));
      return list;
    } catch (e, st) {
      // A corrupt list must not lock anyone out; the password form still works.
      AppLogger.error(_tag, 'could not read saved accounts', e, st);
      return const [];
    }
  }

  /// Accounts saved for one node, most recently used first.
  Future<List<SavedAccount>> readSavedAccountsFor(String host) async {
    final all = await readSavedAccounts();
    return all.where((a) => a.host == host).toList();
  }

  Future<void> _writeSavedAccounts(List<SavedAccount> accounts) async {
    await _storage.write(
      key: _kSavedAccounts,
      value: jsonEncode(accounts.map((a) => a.toJson()).toList()),
    );
  }

  /// Adds or refreshes an account, keyed by host and user id. Signing in
  /// again replaces the stored token rather than listing the person twice,
  /// and a renamed tag updates in place because the id is what identifies
  /// them.
  Future<void> rememberAccount(SavedAccount account) async {
    final accounts = await readSavedAccounts();
    final updated = [
      account,
      ...accounts.where((a) => !(a.host == account.host && a.userId == account.userId)),
    ];
    await _writeSavedAccounts(updated);
    AppLogger.info(_tag, 'remembered @${account.username} on ${account.host}');
  }

  Future<void> forgetAccount({required String host, required String userId}) async {
    final accounts = await readSavedAccounts();
    await _writeSavedAccounts(
      accounts.where((a) => !(a.host == host && a.userId == userId)).toList(),
    );
    AppLogger.info(_tag, 'forgot an account on $host');
  }

  /// Drops every account belonging to a node the user removed, so forgetting
  /// a server doesn't leave its credentials behind on the device.
  Future<void> forgetAccountsFor(String host) async {
    final accounts = await readSavedAccounts();
    await _writeSavedAccounts(accounts.where((a) => a.host != host).toList());
  }
}
