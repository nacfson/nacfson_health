# v12-2 변경 로그 — 품질 보강 (B/C 그룹 audit)

> 작성: 2026-05
> DB 버전: v12 (변경 없음 — 코드/UX 레벨 패치)

## 배경

v12-1 보안 하드닝 직후, **A 그룹 (블로커/보안)** 후속으로 **B 그룹 (데이터 무결성/품질)** + **C 그룹 (UX 폴리싱)** audit. 3개 영역 (코드 품질·UX 일관성·데이터/성능) 을 병렬 Explore 후 실코드 재검증 — 에이전트 보고 11건 중 **실보완 7건**, **false positive 4건** 으로 정리.

검증 원칙: 보고된 문제를 그대로 수용하지 않고 매번 코드 직접 확인 → 의도적 디자인이거나 이미 패턴이 정착된 곳은 작업 없이 정정 사실만 기록. v12 본 작업에서 fine-grained Provider 라이프사이클·AsyncValue 일관 처리·brand-on-brand 흰색 의도 격리 등이 이미 잘 정착되어 있어, plan 의 일부 항목은 over-engineering 위험으로 close.

DB 스키마 변경 없으므로 v12-1 → v12-2 로 패치 릴리즈.

---

## 실보완 7건

### B1. 빈 `catch (_)` 전수 점검 — 무주석 7건 정리

`docs/error-handling.md` §"의도적 빈 catch 가 허용되는 경우" 가이드에 맞춰 무주석 catch 7건에 한 줄 사유 추가:

- `lib/main.dart:173` — Platform 접근 실패 (테스트/desktop) 시 홈 위젯 동기화 비활성
- `lib/core/ai/food_vision_provider.dart:39` — 손상된 JSON 캐시 비우고 새로 시작
- `lib/core/training/one_rm_formula.dart:44` — coefficients 파싱 실패 → spec 미적용 (Epley fallback)
- `lib/features/weight/presentation/providers/weight_provider.dart:86` — `firstWhere` 미매치 (오늘 기록 없음)
- `lib/features/activity/presentation/widgets/activity_summary_card.dart:34/161` — Platform 접근 실패 (web/desktop) / Platform 분기 실패 일반 안내
- `lib/features/activity/data/sources/health_data_source.dart:237` — Platform 접근 실패 (web 등) 미지원 처리

A 그룹 v12-1 에서 정리한 4건 + 이번 7건으로, 무주석 `catch (_)` 0건 달성.

---

### B3. Master data fetch 5분 attempt throttle

`lib/features/exercise/data/repositories/sqlite_master_data_repository.dart` 의 `ensureFresh()` — 24h TTL 만료 + 오프라인 상태에서 매 화면 진입마다 Supabase 호출 → 비용 누적.

**변경**:
- `_lastAttemptKey = 'master_data_last_fetch_attempt_at'` 추가 (성공/실패 무관 기록).
- `_attemptThrottleMs = 5분` — 직전 시도가 5분 안이면 재시도 차단.
- 첫 설치 + 오프라인 + 화면 빠른 전환 시나리오에서 무한 호출 방지.

`ExercisePickerField` 의 `bundle.isEmpty` 안내 ("아직 운동 목록이 다운로드되지 않았습니다…") 는 v12 본 릴리즈에 이미 포함 — 추가 UI 작업 없음.

---

### B4. 휴식 타이머 stale Live Activity race 가드

`lib/features/exercise/presentation/providers/rest_timer_provider.dart` 의 `start()` / `stop()` 에서 네이티브 `_notifications.end()` 호출이 try-catch 없이 실행 → 응답 지연/실패 시 예외가 상위로 전파, 상태 정리 중단.

**변경**:
- `start()` (line 130) — 직전 활성 타이머 종료 시 try-catch + `debugPrint`. 실패해도 새 `show()` 진행.
- `stop()` (line 247) — `cancelPreAlert()` / `end()` 각각 try-catch. state 비움 → 다음 start 시 자체 정리.
- 빠른 start→stop→start 반복 / Personal team 빌드의 entitlement 미보장 환경에서도 stale Live Activity 잔존 차단.

---

### C1. RecordFormSheet 미저장 경고 (PopScope) — API + WeightForm 적용

`lib/shared/widgets/record_form_sheet.dart`:
- 신규 매개변수 `Future<bool> Function()? onConfirmClose` — `true` 반환 시 닫고, `false` 면 닫지 않음. 닫기 버튼 + system back 모두 같은 가드를 거침 (`PopScope(canPop: false, onPopInvokedWithResult: ...)`).
- 매개변수 미지정 시 기존 동작 (즉시 pop) 유지 — backward compatible.

`WeightForm` (`lib/features/weight/presentation/widgets/weight_form.dart`):
- State class 를 `_WeightFormState` → `WeightFormState` 로 public 화 (외부 GlobalKey 접근).
- `bool get isDirty` getter — controller text 가 비어있지 않고 (initial 과 다르거나 날짜 변경) 시 dirty.

호출 측 `weight_input_card.dart` / `weight_screen.dart` — `GlobalKey<WeightFormState>` + `_confirmDiscardIfDirty` 헬퍼로 dirty 시 AlertDialog 표시.

다른 폼 (`DietForm` / `DirectRoutineInputDialog` / `ExerciseTemplateCard` 추가 탭 / `FoodTemplate` 폼) 은 같은 패턴으로 점진 마이그레이션 — 본 릴리즈에서는 손실 위험 가장 큰 체중 기록 폼만 적용.

---

### C4. SnackBar 중복 제어 헬퍼 + 빈번 충돌 화면 6곳 교체

`lib/shared/util/snackbar.dart` 신규:
```dart
void showAppSnackBar(BuildContext context, String message, {Duration duration, SnackBarAction? action}) {
  ScaffoldMessenger.of(context)
    ..clearSnackBars()
    ..showSnackBar(SnackBar(content: Text(message), behavior: SnackBarBehavior.floating, ...));
}
```

호출 직전 `clearSnackBars()` → 같은 화면 빠른 연속 액션 (저장 + 삭제) 시 SnackBar 스택 차단 + floating 스타일 일관.

교체 적용 (6곳):
- `diet_screen.dart` 78/100 — 식단 템플릿 추가 (이미 존재 / 등록 완료 안내)
- `photo_analysis_card.dart` `_showSnackBar` 헬퍼 → 새 헬퍼 위임
- `exercise_screen.dart` 165/222 — 루틴 제거 / 프리셋 저장 안내

나머지 호출처 (validation 단발성 — `inline_set_input`, `weight_form` 의 저장 실패 alert 등) 는 충돌 위험 작아 점진 마이그레이션.

---

### C5. exercise_chips Semantics(button) 1건

`lib/features/exercise/presentation/widgets/one_rm/exercise_chips.dart` 의 종목 칩 (`GestureDetector` 위 `AnimatedContainer`) 이 button 의도이지만 Semantics 미명시 → 스크린리더에 단순 컨테이너로 인식.

**변경**:
- `Semantics(button: true, selected: isSelected, label: name)` 로 감싸 VoiceOver/TalkBack 에서 "선택됨" / "버튼" 인식.

다른 IconButton 들은 Flutter 가 `tooltip` 을 자동으로 Semantics 라벨로 노출 — 추가 작업 불필요. `rest_timer_bar.dart` 의 IconButton 들은 이미 `Semantics(label: tooltip, ...)` 명시.

---

### B6. legacy_korean_mapping 회귀 테스트

v12 마이그레이션의 한글명 → `exercise_key` 백필 정확성 회귀 차단:

`test/features/exercise/legacy_korean_mapping_test.dart` 신규 (12 테스트):
- `legacyKoreanToExerciseKey` — null/빈 문자열/공백 trim/대표 종목/미등록 종목 5건
- `kLegacyKoreanExerciseNameToKey` 무결성 — snake_case 패턴, 키 중복, 카테고리별 필수 종목 포함 3건
- `kLegacyKoreanCategoryToKey` 무결성 — 6개 카테고리 매핑 + 유산소/기타 NULL 2건
- `buildExerciseNameCaseSql` / `buildCategoryCaseSql` — SQL CASE 문 생성 정확성 2건

12 테스트 모두 통과. `exercise_picker_field` 위젯 통합 테스트 / `base_supabase_sync` mocktail 테스트는 다음 라운드.

---

## False positive 4건 (정정 기록)

audit 보고된 항목 중 실코드 검증 결과 잘못 분류된 것:

### C2. 다크 모드 hardcoded `Colors.white`

`weight_screen.dart:113`, `diet_screen.dart:238`, `exercise_screen.dart:497`, `coach_note_card.dart:40`, `exercise_group_card.dart:395` 등 features 의 `Colors.white` 9건은 모두 brand 배경 (navy hero card / coral badge / gradient indicator) 위 의도적 라이트·다크 무관 흰색. `app_theme.dart:71` §"Liquid Glass surface helpers" 의 컨벤션은 일반 텍스트/배경 색을 헬퍼화하는 의도이며, brand-on-brand 흰색까지는 제외 대상. 가독성 회귀 없음 → 작업 없음.

### C3. AsyncValue.when 누락

비동기 Provider 들이 이미 `.when` (loading/error/data 모두 처리) 또는 의도적 `valueOrNull` (보조 칩 — 로딩 시 hidden) 로 일관 처리:
- `exercise_picker_field.dart:116` `bundleAsync.when` ✓ (loading + error + data + isEmpty 안내까지 포함)
- `summary_screen.dart:769` `insightAsync.when` ✓
- `coach_note_card.dart:57` `noteAsync.when` ✓
- `exercise_group_card.dart:99` `batchAsync.valueOrNull` ✓ (로딩 시 칩 hidden — 의도적)

`AsyncStateView` 헬퍼 신설은 over-engineering — 현재 패턴 유지.

### B2. Provider autoDispose 누락

`exerciseRecordsProvider` / `dietRecordsProvider` / `weightRecordsProvider` 가 `.autoDispose` 없는 것은 의도적:
- ShellRoute 단일 Navigator → 탭 전환 시 화면 unmount + remount.
- `.autoDispose` 추가 시 탭 전환마다 `_loadRecords()` 재실행 → 미세 로딩 회귀.
- 1RM 코치의 derived FutureProvider 들은 이미 `autoDispose` + `keepAlive` 30s + `family.autoDispose` 등 fine-grained 라이프사이클.
- `last90DaysExerciseRecordsProvider` 도입은 90일 이전 데이터 변경이 드물어 invalidation 면제 효익 < 작업 비용.

### B5. 타임존 헬퍼 (appNow/appToday)

`lib/` 의 `DateTime.now()` 84건은 디바이스 로컬 타임존 기반 "오늘" 판정 — 단일 기기 사용 시 사용자 의도와 일치. Supabase UTC 환산은 sync 진입점 (`sqlite_pr_repository.dart:27` 등) 에서 처리됨. 멀티 디바이스 + 타임존 변경 동시 발생 케이스는 드물고 명확한 버그가 아니므로 헬퍼 도입은 사용처 명확하지 않은 추상화 — close.

---

## 잡다한 정리

- `weight_form.dart` 의 날짜 변경 강조 색상 — `Colors.amber.shade700` (hardcoded) → `AppTheme.warnFg(context)` 헬퍼화. C2 의 spirit (위젯에서 직접 색상 참조 격리) 반영.

---

## 향후 (v13+)

- C1 의 다른 폼 (DietForm / DirectRoutineInputDialog / ExerciseTemplateCard 추가 탭 / FoodTemplate) 동일 패턴 적용.
- C4 의 `inline_set_input` / `weight_form` / `activity_permission_card` / `exercise_template_card` 등 점진 마이그레이션.
- B6 의 `exercise_picker_field` 위젯 통합 테스트 (pumpWidget + search) + `base_supabase_sync` mocktail 부분 실패 회복력 테스트.
- v12-1 §향후 항목 그대로 — `RoutineItem` / `ExerciseTemplate` 의 `exerciseKey` 정식 슬롯 + 모든 화면 `exerciseDisplayNameProvider` 일관 적용 + 매핑 누락 정정 마법사.
