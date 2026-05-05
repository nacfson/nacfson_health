# 예외 처리 및 오류 가시화

모든 DB 작업, 동기화, 폼 제출 작업은 반드시 `try/catch`로 감싸고 실패 시 사용자가 알 수 있도록 UI 피드백을 제공해야 합니다.

## 심각도별 처리 전략

| 심각도 | 상황 | UI 컴포넌트 | 특징 |
|--------|------|-----------|------|
| 낮음 | 동기화/네트워크 실패 | `ErrorOverlay` | 자동 닫힘, 방해 최소화 |
| 중간 | 저장 실패, 유효성 검사 실패 | `SnackBar` | 사용자 확인 가능, 해제 필요 |
| 높음 | DB 오픈 실패, 심각한 오류 | `AlertDialog` | 사용자 행동 강제, 명확한 선택지 |

## 금지 사항

- `try/catch` 없는 `await` 실행
- 로그(`debugPrint`)만 남기고 UI 피드백 생략
- 네트워크 오류를 무시하고 진행
- **주석/로그 모두 없는 빈 catch (`catch (_) {}`)** — 의도적 무시여도 반드시 한 줄 사유 주석을 남길 것

## 의도적 빈 catch 가 허용되는 경우

다음 두 패턴만 예외로 인정. 그 외에는 위 표의 심각도별 처리 전략을 적용한다.

### 1. SQLite 멱등 마이그레이션 (`ALTER TABLE ADD COLUMN`)

이미 컬럼이 존재하는 DB 에 동일 마이그레이션이 재진입하는 경우 SQLite 가 throw 한다. 이때는 무시가 정답. `lib/core/database/database_helper.dart` 의 v6~v12 마이그레이션 블록 패턴 참조.

```dart
try {
  await db.execute('ALTER TABLE user_profiles ADD COLUMN activity_level TEXT');
} catch (_) {
  // 이미 존재
}
```

### 2. UI dispose / finally 단계의 ref 정리 실패

`ConsumerStatefulWidget` 의 `dispose()` 또는 `finally` 블록에서 ref 가 이미 무효화된 경우, 이후 진입에서 자연 복구되는 화면에 한해 무시 가능. 사유를 한 줄로 명시.

```dart
} finally {
  try {
    ref.read(_sheetStateProvider.notifier).reset();
  } catch (_) {
    // 위젯이 이미 dispose 되어 ref 무효 — 시트 상태 정리 실패는 다음 진입 시 자연 복구됨
  }
}
```

## 예시

```dart
// ❌ 잘못된 예
Future<void> saveRecord() async {
  await repository.save(record); // try/catch 없음
}

// ✅ 올바른 예
Future<void> saveRecord() async {
  try {
    await repository.save(record);
  } catch (e) {
    showSnackBar('저장 실패: $e');
  }
}

// ✅ 동기화 실패 (ErrorOverlay 사용)
Future<void> syncData() async {
  try {
    await syncService.sync();
  } catch (e) {
    showErrorOverlay('동기화 실패. 나중에 다시 시도합니다.');
  }
}
```
