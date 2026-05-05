import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kHeightKey = 'user_height_m';
const _kOnboardingKey = 'onboarding_done';

// ── 키(신장) Provider ────────────────────────────────────────────────────────

class HeightNotifier extends StateNotifier<double> {
  /// [initial]: main.dart에서 미리 로드한 값 (없으면 1.70)
  HeightNotifier([super.initial = 1.70]);

  Future<void> setHeight(double heightM) async {
    state = heightM;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_kHeightKey, heightM);
  }
}

final heightMProvider = StateNotifierProvider<HeightNotifier, double>(
  (ref) => HeightNotifier(),
);

// ── 온보딩 완료 여부 Provider ─────────────────────────────────────────────────

class OnboardingNotifier extends StateNotifier<bool> {
  /// [initial]: main.dart에서 미리 로드한 값 (없으면 false)
  OnboardingNotifier([super.initial = false]);

  Future<void> complete() async {
    state = true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kOnboardingKey, true);
  }
}

final onboardingDoneProvider = StateNotifierProvider<OnboardingNotifier, bool>(
  (ref) => OnboardingNotifier(),
);
