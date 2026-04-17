import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../shared/widgets/bottom_nav_shell.dart';
import '../../features/exercise/presentation/screens/exercise_screen.dart';
import '../../features/diet/presentation/screens/diet_screen.dart';
import '../../features/summary/presentation/screens/summary_screen.dart';
import '../../features/settings/presentation/screens/settings_screen.dart';
import '../../features/weight/presentation/screens/weight_screen.dart';

final rootNavigatorKey = GlobalKey<NavigatorState>();
final shellNavigatorKey = GlobalKey<NavigatorState>();

final appRouter = GoRouter(
  navigatorKey: rootNavigatorKey,
  initialLocation: '/exercise',
  routes: [
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
