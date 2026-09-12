import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/sync/health_auth_service.dart';
import '../../../../core/sync/sync_state.dart';
import '../../../../shared/widgets/error_overlay.dart';

class GoogleSignInCard extends ConsumerStatefulWidget {
  const GoogleSignInCard({super.key});

  @override
  ConsumerState<GoogleSignInCard> createState() => _GoogleSignInCardState();
}

class _GoogleSignInCardState extends ConsumerState<GoogleSignInCard> {
  bool _isLoading = false;

  Future<void> _handleSignIn() async {
    setState(() => _isLoading = true);

    try {
      final authService = ref.read(googleAuthServiceProvider);
      await authService.signIn();
      // 세션 도착은 Supabase auth stream이 자동으로 처리
    } on HealthAuthException catch (e) {
      ErrorOverlay.show(
        title: '로그인 실패',
        message: e.message,
      );
    } catch (e) {
      ErrorOverlay.show(
        title: '로그인 실패',
        message: '알 수 없는 오류가 발생했습니다. 다시 시도해 주세요.',
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleSignOut() async {
    setState(() => _isLoading = true);

    try {
      final authService = ref.read(googleAuthServiceProvider);
      await authService.signOut();
    } catch (e) {
      ErrorOverlay.show(
        title: '로그아웃 실패',
        message: '로그아웃 중 오류가 발생했습니다. 다시 시도해 주세요.',
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isSignedIn = ref.watch(isSignedInProvider);
    final currentAccount = ref.watch(currentAccountProvider);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  isSignedIn ? Icons.check_circle : Icons.cloud_off,
                  color: isSignedIn
                      ? Colors.green
                      : Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Text(
                  '클라우드 연동',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (isSignedIn && currentAccount != null) ...[
              Text(
                currentAccount.email,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: _isLoading ? null : _handleSignOut,
                  child: _isLoading
                      ? const SizedBox(
                          height: 16,
                          width: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('로그아웃'),
                ),
              ),
            ] else ...[
              Text(
                'nacfson.cloud 계정에 연결하면 데이터를 백업하고 기기 간 동기화할 수 있습니다.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _handleSignIn,
                  child: _isLoading
                      ? const SizedBox(
                          height: 16,
                          width: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('로그인'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
