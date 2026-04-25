import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../data/sources/health_data_source.dart';
import '../providers/activity_provider.dart';

/// 활동 데이터 권한이 아직 없거나 거부된 상태에서 노출되는 카드.
///
/// [status] 에 따라 안내 문구·CTA 버튼이 달라진다:
/// - notDetermined: "연동하기" 버튼
/// - denied: 설정 앱으로 이동 안내
/// - needsHealthConnectInstall: Play Store 안내
/// - unsupported: 카드 자체 숨김 (호출 측에서 처리)
class ActivityPermissionCard extends ConsumerWidget {
  final ActivityAuthStatus status;
  const ActivityPermissionCard({super.key, required this.status});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final mintTint =
        isDark ? AppTheme.colorMintTintDark : AppTheme.colorMintTint;

    final (title, body, ctaLabel) = _copyFor(status);

    return Card(
      margin: const EdgeInsets.fromLTRB(20, 8, 20, 4),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: mintTint,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.directions_walk_rounded,
                    color: AppTheme.colorMint,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(title, style: theme.textTheme.titleMedium),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              body,
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '활동 데이터는 기기 밖으로 나가지 않습니다.',
              style: theme.textTheme.labelSmall?.copyWith(
                color: cs.outline,
              ),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.tonal(
                onPressed: () => _onTap(context, ref),
                child: Text(ctaLabel),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _onTap(BuildContext context, WidgetRef ref) async {
    if (status == ActivityPermissionCard._statusInstall) {
      // Play Store deeplink — 패키지 의존을 늘리지 않고 url_launcher 도 안 쓴다
      // (이미 사용 중인 url_launcher 가 있으면 사용 가능). 여기서는 안내만.
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Play 스토어에서 "Health Connect"를 설치한 뒤 다시 시도해주세요.'),
        ),
      );
      return;
    }

    final result = await requestActivityAuthorization(ref);
    if (!context.mounted) return;
    if (result == ActivityAuthStatus.denied) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('권한이 거부되었어요. 설정에서 직접 켜주세요.'),
        ),
      );
    }
  }

  // 비교 가독성을 위한 alias
  static const _statusInstall = ActivityAuthStatus.needsHealthConnectInstall;

  (String title, String body, String cta) _copyFor(ActivityAuthStatus s) {
    switch (s) {
      case ActivityAuthStatus.notDetermined:
        return (
          '활동 데이터 연동',
          '걸음 수, 소모 칼로리, 심박수를 가져와 맞춤형 조언을 만들어 드릴게요.',
          '연동하기',
        );
      case ActivityAuthStatus.denied:
        return (
          '활동 데이터 권한이 꺼져 있어요',
          '설정 앱에서 건강 데이터 접근을 켜면 더 정확한 조언을 받을 수 있어요.',
          '다시 시도',
        );
      case ActivityAuthStatus.needsHealthConnectInstall:
        return (
          'Health Connect 가 필요해요',
          'Android 기기에서 활동 데이터를 가져오려면 Google Health Connect 앱이 설치되어 있어야 합니다.',
          '설치 안내',
        );
      case ActivityAuthStatus.unsupported:
      case ActivityAuthStatus.authorized:
        return ('활동 데이터', '연결되어 있어요.', '확인');
    }
  }
}
