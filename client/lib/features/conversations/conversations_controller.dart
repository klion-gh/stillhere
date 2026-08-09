import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../models/conversation.dart';
import '../../models/user.dart';

final conversationsProvider = AsyncNotifierProvider<ConversationsController, List<Conversation>>(
  ConversationsController.new,
);

class ConversationsController extends AsyncNotifier<List<Conversation>> {
  @override
  Future<List<Conversation>> build() async {
    final dio = ref.read(apiClientProvider);
    final res = await dio.get('/conversations');
    return (res.data as List).map((e) => Conversation.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<void> refresh() async {
    ref.invalidateSelf();
    await future;
  }

  /// Looks up a user by @tag. Returns null if not found.
  Future<AppUser?> lookupUser(String tag) async {
    final dio = ref.read(apiClientProvider);
    try {
      final res = await dio.get('/users/lookup', queryParameters: {'tag': tag});
      return AppUser.fromJson(res.data as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  /// Creates (or fetches the existing) 1:1 conversation with the given tag.
  Future<Conversation> startConversation(String tag) async {
    final dio = ref.read(apiClientProvider);
    final res = await dio.post('/conversations', data: {'tag': tag});
    final conversation = Conversation.fromJson(res.data as Map<String, dynamic>);
    await refresh();
    return conversation;
  }
}
