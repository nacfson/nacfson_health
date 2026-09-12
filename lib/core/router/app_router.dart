import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/presentation/screens/auth_callback_screen.dart';
import '../../features/diet/presentation/screens/diet_screen.dart';
import '../../features/exercise/presentation/screens/exercise_screen.dart';
import '../../features/exercise/presentation/screens/one_rm_coach_screen.dart';
import '../../features/onboarding/presentation/screens/onboarding_screen.dart';
import '../../features/settings/presentation/screens/settings_screen.dart';
import '../../features/summary/presentation/screens/summary_screen.dart';
import '../../features/weight/presentation/screens/weight_screen.dart';
import '../../shared/providers/user_profile_provider.dart';
import '../../shared/widgets/bottom_nav_shell.dart';
import '../sync/health_auth_service.dart';
import '../sync/sync_state.dart';

final rootNavigatorKey = GlobalKey<NavigatorState>();
final shellNavigatorKey = GlobalKey<NavigatorState>();

/// GoRouter의 redirect를 Riverpod 상태와 연결하는 ChangeNotifier
class _RouterNotifier extends ChangeNotifier {
  _RouterNotifier(this._ref) {
    _ref.listen<bool>(onboardingDoneProvider, (_, _) => notifyListeners());
    _ref.listen<bool>(isSignedInProvider, (_, _) => notifyListeners());
    _ref.listen<AsyncValue<AuthState>>(supabaseAuthStreamProvider, (_, next) {
      next.whenData((authState) {
        if (authState.event == AuthChangeEvent.signedIn) {
          notifyListeners();
        }
      });
    });
  }

  final Ref _ref;

  String? redirect(BuildContext context, GoRouterState state) {
    final done = _ref.read(onboardingDoneProvider);
    final signedIn = _ref.read(isSignedInProvider);
    final path = state.uri.path;

    if (!done && path != '/onboarding') return '/onboarding';
    if (done && path == '/onboarding') return '/exercise';
    if (signedIn && path == '/login-callback') return '/settings';
    return null;
  }
}

final _routerNotifierProvider = ChangeNotifierProvider<_RouterNotifier>(
  (ref) => _RouterNotifier(ref),
);

final appRouterProvider = Provider<GoRouter>((ref) {
  // ref.read: GoRouter는 한 번만 생성. redirect 재평가는 refreshListenable이 담당
  final notifier = ref.read(_routerNotifierProvider);

  return GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: '/exercise',
    refreshListenable: notifier,
    redirect: notifier.redirect,
    // 매칭 실패(예: 딥링크 원시 URL) 시 안전 복구.
    onException: (context, state, router) {
      final signedIn = ref.read(isSignedInProvider);
      router.go(signedIn ? '/settings' : '/exercise');
    },
    routes: [
      // OS가 주입하는 루트 경로 silent 처리
      GoRoute(
        path: '/',
        redirect: (_, _) => '/exercise',
      ),
      GoRoute(
        path: '/onboarding',
        pageBuilder: (context, state) => const NoTransitionPage(
          child: OnboardingScreen(),
        ),
      ),
      GoRoute(
        path: '/login-callback',
        pageBuilder: (context, state) => const NoTransitionPage(
          child: AuthCallbackScreen(),
        ),
      ),
      ShellRoute(
        navigatorKey: shellNavigatorKey,
        builder: (context, state, child) => BottomNavShell(child: child),
        routes: [
          GoRoute(
            path: '/exercise',
            pageBuilder: (context, state) => const NoTransitionPage(
              child: ExerciseScreen(),
            ),
            routes: [
              GoRoute(
                path: 'coach/one-rm',
                // BottomNav 숨긴 몰입형 풀스크린: ShellRoute 밖의 root navigator 에 push.
                parentNavigatorKey: rootNavigatorKey,
                pageBuilder: (context, state) => MaterialPage(
                  fullscreenDialog: true,
                  child: OneRMCoachScreen(
                    initialExerciseName:
                        state.uri.queryParameters['exercise'],
                  ),
                ),
              ),
            ],
          ),
          GoRoute(
            path: '/diet',
            pageBuilder: (context, state) => const NoTransitionPage(
              child: DietScreen(),
            ),
          ),
          GoRoute(
            path: '/summary',
            pageBuilder: (context, state) => const NoTransitionPage(
              child: SummaryScreen(),
            ),
          ),
          GoRoute(
            path: '/weight',
            pageBuilder: (context, state) => const NoTransitionPage(
              child: WeightScreen(),
            ),
          ),
          GoRoute(
            path: '/settings',
            pageBuilder: (context, state) => const NoTransitionPage(
              child: SettingsScreen(),
            ),
          ),
        ],
      ),
    ],
  );
});
