/// The signed-in user and their token pair.
library;

import '../../models/user.dart';

class AuthState {
  final AppUser? user;
  final String? accessToken;
  final String? refreshToken;

  const AuthState({this.user, this.accessToken, this.refreshToken});

  bool get isAuthenticated => user != null && accessToken != null;

  AuthState copyWith({AppUser? user, String? accessToken, String? refreshToken}) {
    return AuthState(
      user: user ?? this.user,
      accessToken: accessToken ?? this.accessToken,
      refreshToken: refreshToken ?? this.refreshToken,
    );
  }
}
