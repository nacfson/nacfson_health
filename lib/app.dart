import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_mode_provider.dart';
import 'features/exercise/presentation/providers/rest_timer_provider.dart';
import 'features/exercise/presentation/widgets/rest_timer_bar.dart';

class NacfsonHealthApp extends ConsumerWidget {
  const NacfsonHealthApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);
    final themeMode = ref.watch(themeModeProvider);
    return MaterialApp.router(
      title: 'Nacfson Health',
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeMode,
      routerConfig: router,
      debugShowCheckedModeBanner: false,
      locale: const Locale('ko', 'KR'),
      supportedLocales: const [
        Locale('ko', 'KR'),
        Locale('en', 'US'),
      ],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      builder: (context, child) {
        return GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: () {
            final focus = FocusManager.instance.primaryFocus;
            if (focus != null && focus.hasPrimaryFocus) {
              focus.unfocus();
            }
          },
          child: _RootTimerOverlay(child: child ?? const SizedBox.shrink()),
        );
      },
    );
  }
}

/// 휴식 타이머를 root Navigator 위 상단 우측에 상시 오버레이.
///
/// `MaterialApp.router.builder`의 `child`는 내부 Navigator 결과이며,
/// 이를 Stack의 자식으로 두고 타이머를 같은 Stack의 형제로 배치하면
/// 모든 라우트·모달·시트 위에 타이머가 그려진다.
/// AppBar title("체중"/"식단 기록" 등) 오른쪽 빈 공간에 컴팩트하게 배치.
class _RootTimerOverlay extends ConsumerWidget {
  final Widget child;
  const _RootTimerOverlay({required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final timer = ref.watch(restTimerProvider);
    if (!timer.isActive) return child;

    final media = MediaQuery.of(context);

    return Stack(
      children: [
        child,
        Positioned(
          top: media.padding.top + 6,
          right: 12,
          child: const RepaintBoundary(child: RestTimerBar()),
        ),
      ],
    );
  }
}
