/// The chat list, and the incremental updates that keep it current — a new
/// message moving a conversation to the top, a peer renaming themselves —
/// without refetching the whole list each time.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../models/conversation.dart';
import '../../models/user.dart';

final conversationsProvider = AsyncNotifierProvider<ConversationsController, List<Conversation>>(
  ConversationsController.new,
);

/// The other person in a conversation, for screens that only have the
/// conversation id. They used to build an avatar from the tag alone, which is
/// why an uploaded picture appeared in the chat list and nowhere else.
final conversationPeerProvider = Provider.family<AppUser?, String>((ref, conversationId) {
  final conversations = ref.watch(conversationsProvider).valueOrNull;
  if (conversations == null) return null;
  for (final c in conversations) {
    if (c.id == conversationId) return c.peer;
  }
  return null;
});

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

  /// Moves a conversation to the top with its new preview, without refetching
  /// the whole list on every message.
  void applyIncomingMessage({
    required String conversationId,
    required String content,
    required DateTime createdAt,
    required bool fromMe,
  }) {
    final current = state.valueOrNull;
    if (current == null) return;

    final index = current.indexWhere((c) => c.id == conversationId);
    if (index < 0) return;

    final updated = current[index].copyWith(
      lastMessage: LastMessage(content: content, createdAt: createdAt, fromMe: fromMe),
    );
    final rest = [...current]..removeAt(index);
    state = AsyncValue.data([updated, ...rest]);
  }

  /// A peer changed their tag; reflect it without a round trip.
  void applyPeerRename({required String userId, required String username}) {
    final current = state.valueOrNull;
    if (current == null) return;
    state = AsyncValue.data([
      for (final c in current)
        c.peer.id == userId ? c.copyWith(peer: c.peer.copyWith(username: username)) : c,
    ]);
  }
}
