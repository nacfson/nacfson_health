import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/sync/sync_state.dart';
import '../../../../shared/widgets/error_overlay.dart';

class AuthCallbackScreen extends ConsumerStatefulWidget {
  const AuthCallbackScreen({super.key});

  @override
  ConsumerState<AuthCallbackScreen> createState() => _AuthCallbackScreenState();
}

class _AuthCallbackScreenState extends ConsumerState<AuthCallbackScreen> {
  ProviderSubscription<AsyncValue<AuthState>>? _subscription;
  bool _handled = false;

  @override
  void initState() {
    super.initState();
    // build 밖에서 한 번만 리스너 등록. signedIn 이벤트가 오면 라우팅 처리.
    _subscription = ref.listenManual<AsyncValue<AuthState>>(
      supabaseAuthStreamProvider,
      (_, next) {
        next.whenData((authState) {
          if (_handled) return;
          if (authState.event == AuthChangeEvent.signedIn) {
            _handled = true;
            _onSignedIn();
          }
        });
      },
    );
  }

  @override
  void dispose() {
    _subscription?.close();
    super.dispose();
  }

  void _onSignedIn() {
    if (!mounted) return;
    // 로그인 시작 화면(설정)으로 복귀. /exercise 강제 이동으로 인한 혼란 방지.
    context.go('/settings');
    // 동기화는 라우팅 이후 백그라운드에서 실행. 실패해도 화면은 유지.
    unawaited(_syncInBackground());
  }

  Future<void> _syncInBackground() async {
    try {
      await ref.read(syncStateProvider.notifier).performSync();
    } catch (e) {
      ErrorOverlay.show(
        title: '동기화 실패',
        message: '로그인 후 동기화에 실패했습니다. 설정에서 다시 시도해 주세요.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: CircularProgressIndicator()),
    );
  }
}
