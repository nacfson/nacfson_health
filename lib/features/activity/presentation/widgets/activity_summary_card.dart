import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/nutrition/nutrition_calculator.dart';
import '../../../../core/sync/sync_state.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/providers/user_profile_provider.dart';
import '../../../weight/presentation/providers/weight_provider.dart';
import '../../data/sources/health_data_source.dart';
import '../../domain/entities/daily_activity.dart';
import '../providers/activity_provider.dart';
import 'activity_permission_card.dart';

/// 요약 탭에 표시되는 일일 활동 카드.
///
/// 권한 상태에 따라 다음 4가지 형태로 렌더링:
/// - unsupported: SizedBox.shrink() (다른 OS / 플랫폼)
/// - notDetermined / denied / needsHealthConnectInstall: [ActivityPermissionCard]
/// - authorized + 데이터 있음: 활동 카드 (걸음, 소모 칼로리, 심박)
/// - authorized + 데이터 비어 있음(iOS read 권한 불투명성 케이스): 양가적 안내
class ActivitySummaryCard extends ConsumerWidget {
  const ActivitySummaryCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (kIsWeb) return const SizedBox.shrink();
    try {
      if (!Platform.isIOS && !Platform.isAndroid) {
        return const SizedBox.shrink();
      }
    } catch (_) {
      return const SizedBox.shrink();
    }

    final authAsync = ref.watch(activityAuthStatusProvider);
    return authAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (status) {
        if (status == ActivityAuthStatus.unsupported) {
          return const SizedBox.shrink();
        }
        if (status != ActivityAuthStatus.authorized) {
          return ActivityPermissionCard(status: status);
        }
        return const _AuthorizedActivityCard();
      },
    );
  }
}

class _AuthorizedActivityCard extends ConsumerWidget {
  const _AuthorizedActivityCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activityAsync = ref.watch(dailyActivityProvider);

    return activityAsync.when(
      loading: () => const _ActivityCardShell(child: _LoadingBody()),
      error: (e, _) => _ActivityCardShell(child: _ErrorBody(message: e.toString())),
      data: (activity) {
        if (activity == null || activity.isEmpty) {
          return const _ActivityCardShell(child: _AmbiguousEmptyBody());
        }
        return _ActivityCardShell(child: _ActivityBody(activity: activity));
      },
    );
  }
}

class _ActivityCardShell extends StatelessWidget {
  final Widget child;
  const _ActivityCardShell({required this.child});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.fromLTRB(20, 8, 20, 4),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.directions_walk_rounded,
                    color: AppTheme.colorMint, size: 20),
                const SizedBox(width: 8),
                Text('활동', style: theme.textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

class _LoadingBody extends StatelessWidget {
  const _LoadingBody();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      height: 60,
      child: Center(
        child: SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: AppTheme.colorMint,
          ),
        ),
      ),
    );
  }
}

class _ErrorBody extends StatelessWidget {
  final String message;
  const _ErrorBody({required this.message});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      '활동 데이터를 불러오지 못했습니다.',
      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error),
    );
  }
}

/// 권한은 OK 인데 모든 수치가 0/null 인 케이스.
/// iOS 의 read 권한 불투명성 + Android 의 빈 Health Connect 둘 다 커버하는 문구.
class _AmbiguousEmptyBody extends StatelessWidget {
  const _AmbiguousEmptyBody();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    String settingsHint;
    try {
      if (Platform.isIOS) {
        settingsHint = '설정 → 개인정보 보호 → 건강 → Nacfson Health 에서 권한이 켜져 있는지 확인하거나, '
            '오늘 걸음이 기록되었는지 Health 앱에서 확인해보세요.';
      } else {
        settingsHint = 'Health Connect 앱에서 권한이 켜져 있는지 확인하거나, '
            '다른 피트니스 앱(삼성 헬스, Google Fit 등)이 활동 데이터를 기록하고 있는지 확인해보세요.';
      }
    } catch (_) {
      settingsHint = '권한 또는 데이터 기록 상태를 확인해보세요.';
    }

    return Text(
      '오늘 활동 데이터가 비어 있어요. $settingsHint',
      style: theme.textTheme.bodySmall?.copyWith(
        color: cs.onSurfaceVariant,
        height: 1.5,
      ),
    );
  }
}

class _ActivityBody extends ConsumerWidget {
  final DailyActivity activity;
  const _ActivityBody({required this.activity});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final stepsText = _formatInt(activity.steps);
    final activeKcal = activity.activeCaloriesKcal.round();
    final totalKcal = activity.totalCaloriesKcal.round();

    final bmrKcal = _resolveBmrKcal(ref);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: _Stat(
                icon: Icons.directions_walk_rounded,
                label: '걸음',
                value: stepsText,
                unit: '보',
                color: AppTheme.colorMint,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _Stat(
                icon: Icons.local_fire_department,
                label: '소모',
                value: '$totalKcal',
                unit: 'kcal',
                color: AppTheme.colorCatDiet,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          '오늘 활동 ${activeKcal}kcal',
          style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
        ),
        if (bmrKcal != null) ...[
          const SizedBox(height: 4),
          Text(
            '기초대사량 ${bmrKcal}kcal/일',
            style: theme.textTheme.labelSmall?.copyWith(color: cs.outline),
          ),
        ],
        if (activity.averageHeartRateBpm != null ||
            activity.restingHeartRateBpm != null) ...[
          const SizedBox(height: 12),
          Row(
            children: [
              if (activity.averageHeartRateBpm != null)
                Expanded(
                  child: _Stat(
                    icon: Icons.favorite_border_rounded,
                    label: '평균 심박',
                    value: '${activity.averageHeartRateBpm}',
                    unit: 'bpm',
                    color: AppTheme.colorCoral,
                  ),
                ),
              if (activity.averageHeartRateBpm != null &&
                  activity.restingHeartRateBpm != null)
                const SizedBox(width: 8),
              if (activity.restingHeartRateBpm != null)
                Expanded(
                  child: _Stat(
                    icon: Icons.self_improvement_rounded,
                    label: '안정 시',
                    value: '${activity.restingHeartRateBpm}',
                    unit: 'bpm',
                    color: AppTheme.colorMintDeep,
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }

  static String _formatInt(int v) {
    final s = v.toString();
    final buf = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
      buf.write(s[i]);
    }
    return buf.toString();
  }

  /// 프로필이 충분히 갖춰졌을 때만 BMR(kcal/일) 반환. 하나라도 비면 null.
  /// - heightMProvider: 0 이거나 비현실적이면 null
  /// - latestWeightProvider: 체중 기록 0건이면 null
  /// - userAge: 0 이하면 null
  static int? _resolveBmrKcal(WidgetRef ref) {
    final heightM = ref.watch(heightMProvider);
    final latestWeight = ref.watch(latestWeightProvider);
    final prefs = ref.read(syncPreferencesProvider);

    if (heightM <= 0) return null;
    final weightKg = latestWeight?.weight;
    if (weightKg == null || weightKg <= 0) return null;
    final age = prefs.userAge;
    if (age <= 0) return null;

    final gender = UserGenderX.fromPrefsKey(prefs.userGenderRaw);
    final bmr = computeBmr(
      weightKg: weightKg,
      heightCm: heightM * 100,
      age: age,
      gender: gender,
    );
    return bmr.round();
  }
}

class _Stat extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final String unit;
  final Color color;

  const _Stat({
    required this.icon,
    required this.label,
    required this.value,
    required this.unit,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(height: 4),
          RichText(
            text: TextSpan(
              children: [
                TextSpan(
                  text: value,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: color,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                TextSpan(
                  text: ' $unit',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
