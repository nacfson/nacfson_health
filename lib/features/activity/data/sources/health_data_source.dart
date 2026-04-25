import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:health/health.dart';

import '../../domain/entities/daily_activity.dart';

/// 활동 데이터 인증 상태.
enum ActivityAuthStatus {
  /// Health Connect 또는 HealthKit 자체를 디바이스가 지원하지 않음.
  unsupported,

  /// (Android only) Health Connect 앱이 설치되어 있지 않음.
  needsHealthConnectInstall,

  /// 권한이 한 번도 요청된 적 없음 — 시트를 띄울 수 있는 상태.
  notDetermined,

  /// 사용자가 명시적으로 거부 (Android 만 명확히 알 수 있음).
  denied,

  /// 권한 OK (또는 iOS 의 "allowed" 응답 — 실제 read 는 별개).
  authorized,
}

/// `health` 패키지를 감싸 도메인이 모르는 외부 SDK 를 격리.
///
/// 추상화 이유:
/// 1. 테스트에서 fake 로 갈아끼울 수 있게.
/// 2. iOS HealthKit 과 Android Health Connect 의 데이터 모델 차이를
///    [DailyActivity] 로 통일.
abstract class HealthDataSource {
  Future<ActivityAuthStatus> checkAvailability();

  /// 권한 시트를 띄우고 결과를 돌려준다.
  /// iOS 는 "허용했다"만 반환하고 실제 read 거부 여부를 알 수 없으므로,
  /// 호출 측은 [getDailyActivity] 의 결과로 추가 판단해야 한다.
  Future<ActivityAuthStatus> requestAuthorization();

  /// [date] 의 자정 → 다음 자정 사이의 활동 데이터를 집계한다.
  /// 데이터가 없거나 권한이 거부되어도 throw 하지 않고 [DailyActivity.empty] 를
  /// 반환한다 (UI 가 양가적 안내를 처리).
  Future<DailyActivity> getDailyActivity(DateTime date);
}

class HealthDataSourceImpl implements HealthDataSource {
  HealthDataSourceImpl();

  static const _readTypes = <HealthDataType>[
    HealthDataType.STEPS,
    HealthDataType.ACTIVE_ENERGY_BURNED,
    HealthDataType.BASAL_ENERGY_BURNED,
    HealthDataType.HEART_RATE,
    HealthDataType.RESTING_HEART_RATE,
  ];

  static const _permissions = <HealthDataAccess>[
    HealthDataAccess.READ,
    HealthDataAccess.READ,
    HealthDataAccess.READ,
    HealthDataAccess.READ,
    HealthDataAccess.READ,
  ];

  bool _configured = false;

  Health get _health {
    final h = Health();
    if (!_configured) {
      h.configure();
      _configured = true;
    }
    return h;
  }

  @override
  Future<ActivityAuthStatus> checkAvailability() async {
    if (!_isPlatformSupported) return ActivityAuthStatus.unsupported;

    if (Platform.isAndroid) {
      try {
        final status = await _health.getHealthConnectSdkStatus();
        if (status != HealthConnectSdkStatus.sdkAvailable) {
          return ActivityAuthStatus.needsHealthConnectInstall;
        }
      } catch (e) {
        debugPrint('[HealthDataSource] HC status check failed: $e');
        return ActivityAuthStatus.needsHealthConnectInstall;
      }
    }

    final hasAll = await _hasAllPermissions();
    return hasAll ? ActivityAuthStatus.authorized : ActivityAuthStatus.notDetermined;
  }

  @override
  Future<ActivityAuthStatus> requestAuthorization() async {
    if (!_isPlatformSupported) return ActivityAuthStatus.unsupported;

    try {
      final granted = await _health.requestAuthorization(
        _readTypes,
        permissions: _permissions,
      );
      if (!granted) return ActivityAuthStatus.denied;

      // Android 는 hasPermissions 로 명확히 검증 가능.
      // iOS 는 read 권한 거부를 알려주지 않으므로 일단 authorized 로 둠.
      if (Platform.isAndroid) {
        final hasAll = await _hasAllPermissions();
        return hasAll ? ActivityAuthStatus.authorized : ActivityAuthStatus.denied;
      }
      return ActivityAuthStatus.authorized;
    } catch (e, st) {
      debugPrint('[HealthDataSource] requestAuthorization failed: $e\n$st');
      return ActivityAuthStatus.denied;
    }
  }

  @override
  Future<DailyActivity> getDailyActivity(DateTime date) async {
    if (!_isPlatformSupported) return DailyActivity.empty(date);

    final start = DateTime(date.year, date.month, date.day);
    final end = start.add(const Duration(days: 1));

    int steps = 0;
    double activeKcal = 0;
    double basalKcal = 0;
    final heartRates = <int>[];
    int? restingHr;

    try {
      // 걸음 수는 전용 헬퍼가 더 정확/효율적.
      final stepsCount = await _health.getTotalStepsInInterval(start, end);
      if (stepsCount != null && stepsCount >= 0) steps = stepsCount;
    } catch (e) {
      debugPrint('[HealthDataSource] steps fetch failed: $e');
    }

    try {
      final samples = await _health.getHealthDataFromTypes(
        startTime: start,
        endTime: end,
        types: const [
          HealthDataType.ACTIVE_ENERGY_BURNED,
          HealthDataType.BASAL_ENERGY_BURNED,
          HealthDataType.HEART_RATE,
          HealthDataType.RESTING_HEART_RATE,
        ],
      );
      final cleaned = _health.removeDuplicates(samples);

      for (final sample in cleaned) {
        final value = sample.value;
        if (value is! NumericHealthValue) continue;
        final num = value.numericValue.toDouble();

        switch (sample.type) {
          case HealthDataType.ACTIVE_ENERGY_BURNED:
            activeKcal += num;
            break;
          case HealthDataType.BASAL_ENERGY_BURNED:
            basalKcal += num;
            break;
          case HealthDataType.HEART_RATE:
            if (num > 0) heartRates.add(num.round());
            break;
          case HealthDataType.RESTING_HEART_RATE:
            // 하루치에서 가장 최근 값을 안정 시 심박수로 채택.
            if (num > 0) restingHr = num.round();
            break;
          default:
            break;
        }
      }
    } catch (e, st) {
      debugPrint('[HealthDataSource] samples fetch failed: $e\n$st');
    }

    int? avgHr;
    int? maxHr;
    if (heartRates.isNotEmpty) {
      final sum = heartRates.fold<int>(0, (a, b) => a + b);
      avgHr = (sum / heartRates.length).round();
      maxHr = heartRates.reduce((a, b) => a > b ? a : b);
    }

    return DailyActivity(
      date: start,
      steps: steps,
      activeCaloriesKcal: activeKcal,
      basalCaloriesKcal: basalKcal,
      averageHeartRateBpm: avgHr,
      restingHeartRateBpm: restingHr,
      maxHeartRateBpm: maxHr,
      fetchedAt: DateTime.now(),
    );
  }

  Future<bool> _hasAllPermissions() async {
    try {
      final result = await _health.hasPermissions(
        _readTypes,
        permissions: _permissions,
      );
      return result == true;
    } catch (e) {
      debugPrint('[HealthDataSource] hasPermissions failed: $e');
      return false;
    }
  }

  bool get _isPlatformSupported {
    try {
      return Platform.isIOS || Platform.isAndroid;
    } catch (_) {
      return false;
    }
  }
}
