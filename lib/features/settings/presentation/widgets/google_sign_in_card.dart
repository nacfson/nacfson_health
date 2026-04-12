import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/router/app_router.dart';
import '../../../../core/sync/sync_state.dart';
import '../../../../shared/widgets/error_overlay.dart';

class GoogleSignInCard extends ConsumerWidget {
  const GoogleSignInCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isSignedIn = ref.watch(isSignedInProvider);
    final authService = ref.read(googleAuthServiceProvider);
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
                  color: isSignedIn ? Colors.green : Colors.grey,
                ),
                const SizedBox(width: 8),
                Text(
                  'Google 연동',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (isSignedIn && currentAccount != null) ...[
              Text(
                currentAccount.email ?? '알 수 없는 계정',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () async {
                    await authService.signOut();
                    ref.invalidate(isSignedInProvider);
                  },
                  child: const Text('로그아웃'),
                ),
              ),
            ] else ...[
              Text(
                'Google 계정에 연결하면 데이터를 백업할 수 있습니다.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () async {
                    try {
                      await authService.signIn();
                      ref.invalidate(isSignedInProvider);
                    } catch (e) {
                      if (rootNavigatorKey.currentState?.overlay != null) {
                        ErrorOverlay.show(
                          title: '로그인 실패',
                          message: '로그인에 실패했습니다: $e',
                        );
                      }
                    }
                  },
                  child: const Text('Google로 로그인'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
