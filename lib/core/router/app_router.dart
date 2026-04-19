import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../features/auth/presentation/screens/auth_callback_screen.dart';
import '../../features/diet/presentation/screens/diet_screen.dart';
import '../../features/exercise/presentation/screens/exercise_screen.dart';
import '../../features/onboarding/presentation/screens/onboarding_screen.dart';
import '../../features/settings/presentation/screens/settings_screen.dart';
import '../../features/summary/presentation/screens/summary_screen.dart';
import '../../features/weight/presentation/screens/weight_screen.dart';
import '../../shared/providers/user_profile_provider.dart';
import '../../shared/widgets/bottom_nav_shell.dart';
import '../sync/sync_state.dart';

final rootNavigatorKey = GlobalKey<NavigatorState>();
final shellNavigatorKey = GlobalKey<NavigatorState>();

/// GoRouter의 redirect를 Riverpod 상태와 연결하는 ChangeNotifier
class _RouterNotifier extends ChangeNotifier {
  _RouterNotifier(this._ref) {
    // 온보딩/로그인 상태 변경 시 GoRouter redirect 재평가
    _ref.listen<bool>(onboardingDoneProvider, (_, __) => notifyListeners());
    _ref.listen<bool>(isSignedInProvider, (_, __) => notifyListeners());
    // signedIn 이벤트는 stream 한 틱 뒤에 도착할 수 있어 명시적으로 구독
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

    // 온보딩 미완료 → 온보딩 화면으로
    if (!done && path != '/onboarding') return '/onboarding';
    // 온보딩 완료 후 /onboarding 접근 → 운동 화면으로
    if (done && path == '/onboarding') return '/exercise';
    // 로그인 성공 후 /login-callback 머무름 방지 → /settings로 이동
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
    // 매칭 실패(예: 딥링크 원시 URL `io.supabase.nacfson://...`) 시 안전 복구.
    // supabase_flutter가 app_links로 세션을 이미 수신하므로 화면만 정상화.
    onException: (context, state, router) {
      final signedIn = ref.read(isSignedInProvider);
      router.go(signedIn ? '/settings' : '/exercise');
    },
    routes: [
      // OS가 주입하는 루트 경로 silent 처리
      GoRoute(
        path: '/',
        redirect: (_, __) => '/exercise',
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
