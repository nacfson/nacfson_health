import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/ai/coach_chat_models.dart';
import '../../../../core/ai/coach_chat_notifier.dart';
import '../../../../core/ai/suggested_prompts_provider.dart';
import '../../../../core/theme/app_theme.dart';
import 'chat_message_bubble.dart';
import 'suggested_prompt_chip.dart';

/// 요약 탭 인사이트 카드의 "더 물어보기" CTA에서 호출.
Future<void> showCoachChatSheet(BuildContext context) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => const _CoachChatSheet(),
  );
}

class _CoachChatSheet extends ConsumerWidget {
  const _CoachChatSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final size = MediaQuery.of(context).size;
    return SizedBox(
      height: size.height * 0.9,
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          children: const [
            _SheetHandle(),
            _SheetHeader(),
            Divider(height: 1),
            Expanded(child: _ChatBody()),
            _ChatInputBar(),
          ],
        ),
      ),
    );
  }
}

class _SheetHandle extends StatelessWidget {
  const _SheetHandle();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      width: 40,
      height: 4,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.outlineVariant,
        borderRadius: BorderRadius.circular(4),
      ),
    );
  }
}

class _SheetHeader extends ConsumerWidget {
  const _SheetHeader();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final mintTint =
        isDark ? AppTheme.colorMintTintDark : AppTheme.colorMintTint;
    final dateKey = coachChatDateKey(DateTime.now());
    final counts = ref.watch(coachChatCallCountProvider);
    final used = counts[dateKey] ?? 0;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: mintTint,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.auto_awesome_rounded,
              color: AppTheme.colorMint,
              size: 18,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'AI 건강 코치',
                  style: TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  '오늘 $used/$kCoachChatDailyLimit회 사용',
                  style: TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: 11,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close_rounded),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }
}

class _ChatBody extends ConsumerWidget {
  const _ChatBody();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chat = ref.watch(coachChatProvider);
    final prompts = ref.watch(suggestedPromptsProvider);

    if (chat.messages.isEmpty) {
      return _EmptyState(prompts: prompts);
    }

    // 어시스턴트 마지막 메시지의 follow_ups를 현재 추천 칩으로 사용
    final lastAssistant = chat.messages.lastWhere(
      (m) => m.role == ChatRole.assistant,
      orElse: () => ChatMessage(
        role: ChatRole.assistant,
        content: '',
        createdAt: DateTime.now(),
      ),
    );

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 12),
      children: [
        for (final m in chat.messages) ChatMessageBubble(message: m),
        if (chat.isLoading) const _TypingIndicator(),
        if (chat.error != null) _ErrorBanner(error: chat.error!),
        if (!chat.isLoading && lastAssistant.followUps.isNotEmpty)
          _FollowUpRow(followUps: lastAssistant.followUps)
        else if (!chat.isLoading && chat.error == null && prompts.isNotEmpty)
          _SuggestionRow(prompts: prompts),
      ],
    );
  }
}

class _EmptyState extends ConsumerWidget {
  final List<SuggestedPrompt> prompts;
  const _EmptyState({required this.prompts});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '어떤 것이 궁금한가요?',
            style: TextStyle(
              fontFamily: 'Pretendard',
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: cs.onSurface,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '아래 추천을 눌러보거나 직접 질문해보세요.',
            style: TextStyle(
              fontFamily: 'Pretendard',
              fontSize: 13,
              color: cs.onSurfaceVariant,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final p in prompts)
                SuggestedPromptChip(
                  prompt: p,
                  onTap: () => _handlePromptTap(context, ref, p),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SuggestionRow extends ConsumerWidget {
  final List<SuggestedPrompt> prompts;
  const _SuggestionRow({required this.prompts});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final p in prompts)
            SuggestedPromptChip(
              prompt: p,
              onTap: () => _handlePromptTap(context, ref, p),
            ),
        ],
      ),
    );
  }
}

class _FollowUpRow extends ConsumerWidget {
  final List<String> followUps;
  const _FollowUpRow({required this.followUps});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 6),
            child: Text(
              '이어서 물어보기',
              style: TextStyle(
                fontFamily: 'Pretendard',
                fontSize: 11,
                color: cs.outline,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              for (final q in followUps)
                FollowUpChip(
                  text: q,
                  onTap: () =>
                      ref.read(coachChatProvider.notifier).send(q),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

void _handlePromptTap(
    BuildContext context, WidgetRef ref, SuggestedPrompt p) {
  if (p.kind == SuggestedPromptKind.navigation) {
    // pop 직후 같은 context 는 deactivated 될 수 있어 라우팅 전에 router 캡처.
    final router = GoRouter.of(context);
    Navigator.of(context).pop();
    if (p.id == 'diet.missing_today') {
      router.go('/diet');
    }
    return;
  }
  ref.read(coachChatProvider.notifier).send(p.fullPrompt);
}

class _TypingIndicator extends StatelessWidget {
  const _TypingIndicator();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Row(
        children: [
          SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: cs.primary,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '코치가 답변을 작성 중이에요…',
            style: TextStyle(
              fontFamily: 'Pretendard',
              fontSize: 12,
              color: cs.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorBanner extends ConsumerWidget {
  final String error;
  const _ErrorBanner({required this.error});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final String text;
    if (error.contains('CHAT_DAILY_LIMIT_REACHED')) {
      text =
          '오늘 코치 대화는 $kCoachChatDailyLimit회까지 이용할 수 있어요. 내일 다시 이용해주세요.';
    } else if (error.contains('GEMINI_API_KEY_MISSING') ||
        error.contains('API')) {
      text = 'Gemini API 키가 설정되지 않았어요. .env 파일을 확인해주세요.';
    } else {
      text = '응답을 받지 못했어요. 네트워크 상태를 확인하고 다시 시도해주세요.';
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, size: 18, color: cs.error),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontFamily: 'Pretendard',
                fontSize: 13,
                color: cs.onErrorContainer,
                height: 1.4,
              ),
            ),
          ),
          TextButton(
            onPressed: () =>
                ref.read(coachChatProvider.notifier).clearError(),
            child: const Text('닫기'),
          ),
        ],
      ),
    );
  }
}

class _ChatInputBar extends ConsumerStatefulWidget {
  const _ChatInputBar();

  @override
  ConsumerState<_ChatInputBar> createState() => _ChatInputBarState();
}

class _ChatInputBarState extends ConsumerState<_ChatInputBar> {
  final _controller = TextEditingController();
  final _focus = FocusNode();

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _handleSend() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    ref.read(coachChatProvider.notifier).send(text);
    _controller.clear();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final chat = ref.watch(coachChatProvider);
    final dateKey = coachChatDateKey(DateTime.now());
    final counts = ref.watch(coachChatCallCountProvider);
    final remaining = (kCoachChatDailyLimit - (counts[dateKey] ?? 0))
        .clamp(0, kCoachChatDailyLimit);
    final canSend = remaining > 0 && !chat.isLoading;

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      decoration: BoxDecoration(
        color: cs.surface,
        border: Border(top: BorderSide(color: cs.outlineVariant)),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _controller,
              focusNode: _focus,
              enabled: canSend,
              minLines: 1,
              maxLines: 4,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _handleSend(),
              decoration: InputDecoration(
                hintText: remaining == 0
                    ? '내일 다시 이용해주세요'
                    : '어떤 것이 궁금한가요?',
                filled: true,
                fillColor: cs.surfaceContainerHighest,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 10),
              ),
            ),
          ),
          const SizedBox(width: 8),
          FilledButton(
            onPressed: canSend ? _handleSend : null,
            style: FilledButton.styleFrom(
              shape: const CircleBorder(),
              padding: const EdgeInsets.all(12),
            ),
            child: const Icon(Icons.send_rounded, size: 18),
          ),
        ],
      ),
    );
  }
}
