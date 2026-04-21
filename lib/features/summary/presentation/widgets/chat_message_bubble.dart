import 'package:flutter/material.dart';

import '../../../../core/ai/coach_chat_models.dart';

class ChatMessageBubble extends StatelessWidget {
  final ChatMessage message;
  const ChatMessageBubble({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == ChatRole.user;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final bgColor = isUser ? cs.primary : cs.surfaceContainerHighest;
    final fgColor = isUser ? cs.onPrimary : cs.onSurface;

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.78,
        ),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 12),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(16),
              topRight: const Radius.circular(16),
              bottomLeft: Radius.circular(isUser ? 16 : 4),
              bottomRight: Radius.circular(isUser ? 4 : 16),
            ),
          ),
          child: SelectableText(
            message.content,
            style: TextStyle(
              fontFamily: 'Pretendard',
              fontSize: 14,
              height: 1.5,
              color: fgColor,
            ),
          ),
        ),
      ),
    );
  }
}
