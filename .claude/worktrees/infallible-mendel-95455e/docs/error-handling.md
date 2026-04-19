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
