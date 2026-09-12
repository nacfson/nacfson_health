import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/sync/health_auth_service.dart';
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
    // Already signed in when landing here (token accepted before route).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_handled) return;
      if (sharedHealthAuth().isSignedIn) {
        _handled = true;
        _onSignedIn();
      }
    });
  }

  @override
  void dispose() {
    _subscription?.close();
    super.dispose();
  }

  void _onSignedIn() {
    if (!mounted) return;
    context.go('/settings');
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
