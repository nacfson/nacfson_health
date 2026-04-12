import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/sync/google_auth_service.dart';
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
    debugPrint('[GoogleSignInCard] ========== _handleSignIn() 시작 ==========');
    setState(() {
      _isLoading = true;
      debugPrint('[GoogleSignInCard] 로딩 상태 ON: $_isLoading');
    });

    try {
      debugPrint('[GoogleSignInCard] authService 읽기 시작');
      final authService = ref.read(googleAuthServiceProvider);
      debugPrint('[GoogleSignInCard] authService 획득: $authService');

      debugPrint('[GoogleSignInCard] authService.signIn() 호출 중...');
      final account = await authService.signIn();
      debugPrint('[GoogleSignInCard] authService.signIn() 응답: $account');

      debugPrint('[GoogleSignInCard] mounted 체크: $mounted');
      if (!mounted) {
        debugPrint('[GoogleSignInCard] 위젯이 해제됨 - 조기 반환');
        return;
      }

      if (account != null) {
        debugPrint('[GoogleSignInCard] 로그인 성공 - provider 갱신 시작');
        // 로그인 성공 — provider 갱신
        debugPrint('[GoogleSignInCard] isSignedInProvider 갱신 중...');
        ref.invalidate(isSignedInProvider);
        debugPrint('[GoogleSignInCard] currentAccountProvider 갱신 중...');
        ref.invalidate(currentAccountProvider);
        debugPrint('[GoogleSignInCard] provider 갱신 완료');
      } else {
        debugPrint('[GoogleSignInCard] 로그인 취소됨 - account == null');
      }
      // account == null 이면 사용자가 취소한 것 — 오류 없이 종료
    } on GoogleSignInException catch (e) {
      debugPrint('[GoogleSignInCard] GoogleSignInException 발생: ${e.message}');
      ErrorOverlay.show(
        title: '로그인 실패',
        message: e.message,
      );
    } catch (e) {
      debugPrint('[GoogleSignInCard] 예상 외 예외 발생: $e');
      ErrorOverlay.show(
        title: '로그인 실패',
        message: '알 수 없는 오류가 발생했습니다. 다시 시도해 주세요.',
      );
    } finally {
      debugPrint('[GoogleSignInCard] finally 블록 - mounted 체크: $mounted');
      if (mounted) {
        setState(() {
          _isLoading = false;
          debugPrint('[GoogleSignInCard] 로딩 상태 OFF: $_isLoading');
        });
      }
    }
  }

  Future<void> _handleSignOut() async {
    debugPrint('[GoogleSignInCard] ========== _handleSignOut() 시작 ==========');
    setState(() {
      _isLoading = true;
      debugPrint('[GoogleSignInCard] 로딩 상태 ON: $_isLoading');
    });

    try {
      debugPrint('[GoogleSignInCard] authService 읽기');
      final authService = ref.read(googleAuthServiceProvider);
      debugPrint('[GoogleSignInCard] authService.signOut() 호출 중...');
      await authService.signOut();
      debugPrint('[GoogleSignInCard] authService.signOut() 완료');

      debugPrint('[GoogleSignInCard] mounted 체크: $mounted');
      if (!mounted) {
        debugPrint('[GoogleSignInCard] 위젯이 해제됨 - 조기 반환');
        return;
      }

      debugPrint('[GoogleSignInCard] provider 갱신 시작');
      ref.invalidate(isSignedInProvider);
      ref.invalidate(currentAccountProvider);
      debugPrint('[GoogleSignInCard] provider 갱신 완료');
    } catch (e) {
      debugPrint('[GoogleSignInCard] 로그아웃 중 예외 발생: $e');
      ErrorOverlay.show(
        title: '로그아웃 실패',
        message: '로그아웃 중 오류가 발생했습니다. 다시 시도해 주세요.',
      );
    } finally {
      debugPrint('[GoogleSignInCard] finally 블록 - mounted 체크: $mounted');
      if (mounted) {
        setState(() {
          _isLoading = false;
          debugPrint('[GoogleSignInCard] 로딩 상태 OFF: $_isLoading');
        });
      }
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
                'Google 계정에 연결하면 데이터를 백업할 수 있습니다.',
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
                      : const Text('Google로 로그인'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
