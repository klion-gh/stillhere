import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/message.dart';

class MessageBubble extends StatelessWidget {
  final ChatMessage message;
  final bool isMine;

  const MessageBubble({super.key, required this.message, required this.isMine});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bubbleColor = isMine ? theme.colorScheme.primaryContainer : theme.colorScheme.surfaceContainerHighest;

    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 12),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: const BoxConstraints(maxWidth: 320),
        decoration: BoxDecoration(color: bubbleColor, borderRadius: BorderRadius.circular(16)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message.content),
            const SizedBox(height: 4),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  DateFormat.Hm().format(message.createdAt.toLocal()),
                  style: theme.textTheme.labelSmall,
                ),
                if (isMine) ...[
                  const SizedBox(width: 4),
                  Icon(
                    message.deliveredAt != null ? Icons.done_all : Icons.done,
                    size: 14,
                    color: theme.textTheme.labelSmall?.color,
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
