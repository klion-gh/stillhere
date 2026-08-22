/// A single message. Consecutive messages from the same person are grouped, so
/// only the first of a run carries the full spacing.
library;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/theme.dart';
import '../../models/message.dart';

class MessageBubble extends StatelessWidget {
  final ChatMessage message;
  final bool isMine;
  final bool isGroupStart;

  const MessageBubble({
    super.key,
    required this.message,
    required this.isMine,
    this.isGroupStart = true,
  });

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.only(
      topLeft: Radius.circular(isMine ? 20 : (isGroupStart ? 20 : 8)),
      topRight: Radius.circular(isMine ? (isGroupStart ? 20 : 8) : 20),
      bottomLeft: const Radius.circular(20),
      bottomRight: const Radius.circular(20),
    );

    return Padding(
      padding: EdgeInsets.only(top: isGroupStart ? 10 : 3, left: 14, right: 14),
      child: Align(
        alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.76),
          child: Container(
            padding: const EdgeInsets.fromLTRB(15, 10, 12, 9),
            decoration: BoxDecoration(
              gradient: isMine ? AppColors.brandGradient : null,
              color: isMine ? null : AppColors.surfaceHigh,
              borderRadius: radius,
              border: isMine ? null : Border.all(color: AppColors.surfaceOutline.withValues(alpha: 0.7)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  message.content,
                  style: TextStyle(
                    color: isMine ? Colors.white : AppColors.textPrimary,
                    fontSize: 15.5,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 3),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      DateFormat.Hm().format(message.createdAt.toLocal()),
                      style: TextStyle(
                        fontSize: 11,
                        color: isMine ? Colors.white.withValues(alpha: 0.75) : AppColors.textMuted,
                      ),
                    ),
                    if (isMine) ...[
                      const SizedBox(width: 5),
                      Icon(
                        message.deliveredAt != null ? Icons.done_all_rounded : Icons.done_rounded,
                        size: 14,
                        color: Colors.white.withValues(alpha: 0.85),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
