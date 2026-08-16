import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api_client.dart';
import 'logger.dart';

const _tag = 'avatar';

/// Identifies one version of one user's picture. Including the timestamp
/// means a new upload is a different key, so the old bytes aren't reused.
class AvatarRef {
  final String userId;
  final int version;

  const AvatarRef(this.userId, this.version);

  @override
  bool operator ==(Object other) =>
      other is AvatarRef && other.userId == userId && other.version == version;

  @override
  int get hashCode => Object.hash(userId, version);
}

/// Avatar bytes, fetched through the app's own HTTP client.
///
/// Image.network can't be used here for two reasons: the endpoint sits behind
/// the node-token gate, and a self-hosted node usually presents a self-signed
/// certificate that only our pinned client trusts. Going through the shared
/// Dio instance covers both.
final avatarBytesProvider = FutureProvider.family<Uint8List?, AvatarRef>((ref, avatar) async {
  // Keep decoded avatars around; a chat list re-renders constantly and these
  // are small.
  ref.keepAlive();
  try {
    final dio = ref.read(apiClientProvider);
    final res = await dio.get<List<int>>(
      '/users/${avatar.userId}/avatar',
      options: Options(responseType: ResponseType.bytes),
    );
    final data = res.data;
    if (data == null || data.isEmpty) return null;
    return Uint8List.fromList(data);
  } on DioException catch (e) {
    // 404 just means they haven't set one — not worth logging as an error.
    if (e.response?.statusCode != 404) {
      AppLogger.warn(_tag, 'failed to load avatar for ${avatar.userId}: ${e.message}');
    }
    return null;
  }
});
