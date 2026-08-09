import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../core/providers.dart';
import '../../models/message.dart';

final chatControllerProvider =
    AsyncNotifierProvider.family<ChatController, List<ChatMessage>, String>(ChatController.new);

class ChatController extends FamilyAsyncNotifier<List<ChatMessage>, String> {
  StreamSubscription<Map<String, dynamic>>? _sub;

  @override
  Future<List<ChatMessage>> build(String conversationId) async {
    final dio = ref.read(apiClientProvider);
    final res = await dio.get('/conversations/$conversationId/messages');
    final messages =
        (res.data as List).map((e) => ChatMessage.fromJson(e as Map<String, dynamic>)).toList();

    _sub?.cancel();
    _sub = ref.read(wsClientProvider).events.listen(_onWsEvent);
    ref.onDispose(() => _sub?.cancel());

    return messages;
  }

  void _onWsEvent(Map<String, dynamic> event) {
    final type = event['type'] as String?;
    if (type != 'message:new' && type != 'message:ack') return;

    final raw = event['message'] as Map<String, dynamic>?;
    if (raw == null) return;
    final message = ChatMessage.fromJson(raw);
    if (message.conversationId != arg) return;

    final current = state.valueOrNull ?? [];
    final existingIndex = current.indexWhere((m) => m.id == message.id);
    if (existingIndex >= 0) {
      final updated = [...current];
      updated[existingIndex] = message;
      state = AsyncValue.data(updated);
    } else {
      state = AsyncValue.data([...current, message]);
    }
  }

  void sendMessage(String content) {
    if (content.trim().isEmpty) return;
    ref.read(wsClientProvider).send({
      'type': 'message:send',
      'conversationId': arg,
      'content': content.trim(),
    });
  }
}
