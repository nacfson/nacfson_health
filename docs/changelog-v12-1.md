# v12-1 변경 로그 — 보안 하드닝 + iOS 휴식 알림 안정화 + 운동 추가 UX 통일

> 작성: 2026-05
> DB 버전: v12 (변경 없음 — 코드/빌드/UX 레벨 패치)

## 배경

v12 본 릴리즈 직후 외부 분석에서 발견된 **블로커 6건 중 실제 보완 4건** 을 정리하고, 1RM 코치 빠른 추정 카드의 중복 정보 + 운동 추가 다이얼로그의 자유 텍스트 입력 (마스터 매핑 우회) 등 v12 마스터 데이터 체계와 정합성이 어긋나는 UX 잔재를 함께 정리. iOS 휴식 타이머의 백그라운드/잠금화면 pre-alert 누락 사례도 함께 안정화.

DB 스키마 변경은 없으므로 v12 → v12-1 패치 릴리즈로 처리.

---

## 1. 보안: 환경 변수 주입 방식 전환 (블로커)

### 문제

`.env` 가 `.gitignore` 에는 등록돼 있어 저장소 노출은 차단됐지만, `pubspec.yaml` 의 `assets:` 에 `- .env` 가 포함되어 있어 **IPA/APK 빌드 산출물에 평문으로 번들** 되고 있었다. 디컴파일 시 Supabase URL · anon key · Gemini API 키 추출 가능.

### 변경

- `flutter_dotenv` 의존성 제거.
- 모든 환경 변수는 빌드 시점 `--dart-define-from-file=.env` 로 주입.
- 단일 진입점 `lib/core/config/app_env.dart` 추가 — `AppEnv.supabaseUrl` / `AppEnv.supabaseAnonKey` / `AppEnv.geminiApiKey`.
- `Makefile` 에 `DEFINES = --dart-define-from-file=.env` 변수 일괄 적용 (install-ios / run-ios-dev / build-ipa / build-ios).
- 코드 내 `dotenv.env[...]` 직접 호출 전부 `AppEnv.*` 로 교체 (`gemini_service.dart` 5건, `ai_analysis_strategy.dart` 1건, `main.dart` 2건).

### 검증

```bash
flutter build apk --release --dart-define-from-file=.env
unzip -l build/app/outputs/flutter-apk/app-release.apk | grep -i env
# → .env 파일이 결과에 없어야 함
```

---

## 2. iOS Google OAuth reversed client ID 교체 (블로커)

`ios/Runner/Info.plist` 의 `CFBundleURLSchemes` 에 placeholder `YOUR_REVERSED_CLIENT_ID` 가 그대로 남아있어 Google 로그인 후 앱 redirect 가 실패. iOS 클라이언트 ID 의 reversed 값으로 교체 (`com.googleusercontent.apps.<client-id>`).

---

## 3. 빈 catch 블록 정리 (의도/비의도 분리)

### DB v10 마이그레이션 (의도적 — 주석만 추가)

`lib/core/database/database_helper.dart` 의 v10 ALTER TABLE 블록 2건 (`activity_level`, `training_intensity`) 의 빈 catch 에 `// 이미 존재` 주석 추가. 같은 파일 313/324/361/379 의 기존 패턴과 통일.

### UI dispose/finally 정리 (의도 명시)

`diet_screen.dart:39`, `exercise_screen.dart:44/73/177` 의 catch 블록에 사유 주석 추가:
- dispose 시점 ref 무효 → 무시 안전
- finally 의 시트 상태 정리 실패 → 다음 진입 시 자연 복구

---

## 4. iOS 휴식 타이머 pre-alert 알림 안정화

### 4-1. UNUserNotificationCenter delegate 등록 (foreground 진입 케이스)

`AppDelegate.swift` 에 `UNUserNotificationCenter.current().delegate = self` + `willPresent` override 로 `[.banner, .sound, .list]` 반환. delegate 누락 시 foreground 에서 알림 미표시 사례 차단.

### 4-2. 권한 캐시 안티패턴 제거

`rest_notification_service_ios.dart` 의 `_permissionRequested` flag 제거. 매 호출마다 `IOSFlutterLocalNotificationsPlugin.checkPermissions()` 로 실제 시스템 상태 조회 — 사용자가 시스템 설정에서 권한을 토글한 경우에도 정확히 반영.

### 4-3. preAt race 가드 fallback

`endAt - 5s` 가 이미 지났거나 0.5s 이내인 경우 (매우 짧은 휴식, MethodChannel 지연) `zonedSchedule` 가 silently skip 되던 문제. `_notifications.show()` 즉시 발송 fallback 으로 5초 안내 누락 차단.

### 4-4. interruptionLevel: timeSensitive → active

entitlement 의존도를 낮추기 위해 `active` 로 하향. timeSensitive 사용 가이드 (entitlement + Personal team 호환성) 는 [docs/build-debug.md §15-1](build-debug.md) 별도 정리.

---

## 5. 운동 추가 UX 통일 — `ExercisePickerField` 도입

### 문제

v12 의 `exercise_definitions` 마스터 체계는 admin-curated 종목만 선택받도록 설계됐는데, 두 화면이 **자유 텍스트 입력** 을 허용해 마스터 매핑 우회 경로로 작동:
- 운동 화면의 `direct_routine_input_dialog`
- 설정 탭의 `exercise_template_card` (추가 탭)

### 변경

- `lib/features/exercise/presentation/widgets/exercise_picker_field.dart` 신규 추가 (303줄). 공용 picker — `exercise_definitions` 등록 종목만 선택 + alias 검색 + 부위(`legacyExerciseType`) 자동 분류.
- `direct_routine_input_dialog`: 자유 텍스트 + 부위 dropdown → picker 단일 입력으로 전환.
- `exercise_template_card` 추가 탭: 자유 텍스트 + 부위 ChoiceChip → picker. 검색 결과 0 일 때 추가 탭으로 prefill.

`docs/features.md` 의 "사용자 커스텀 종목 입력 차단" 항목이 `[~]` (이월) → `[x]` (완료) 로 갱신됨.

---

## 6. 1RM 코치 빠른 추정 카드 제거

### 이유

`currentE1RM` (5주 max 기반) 과 `quick_estimate_stepper` 의 live e1RM 이 **개념적으로 중복**. 5주 max 가 본질적으로 더 안정적인 지표인데, 사용자가 stepper 로 즉석 수치를 만져 메인 카드의 신뢰도를 흔드는 상호작용이 가치 대비 노이즈가 컸다.

### 제거

- `quick_estimate_stepper.dart` 삭제 (231줄).
- 관련 Provider 4종 삭제: `coachInputWeightProvider`, `coachInputRepsProvider`, `latestWorkSetProvider`, `selectedExerciseFormulaProvider`.
- `CoachNoteRequest` 의 `lastSetWeight`/`lastSetReps` 파라미터 제거. Gemini 프롬프트에서도 "최근 세트" 라인 삭제.
- `CurrentE1RMCard` 의 `inputWeight/inputReps` 파라미터 제거 — 표시 라벨이 "X kg × Y회 기준" → "최근 5주 최고 추정" 으로 단순화.
- `PercentOfOneRMTable` 의 `currentReps` 파라미터 제거 — 입력 reps 행 강조 로직 폐기, 전 행 동일 표시.
- `e1RM == null` 케이스에 환산표 자리에 안내 문구 표시 ("운동 기록을 추가하면 환산표가 표시됩니다").

---

## 7. 잡다한 정리

- `activity_summary_card.dart`, `exercise_progression_sheet.dart`: 미사용 람다 파라미터 `(_, __)` → `(_, _)` wildcard 패턴 (Dart 3.6+).
- `user_profile_provider.dart`: `HeightNotifier`/`OnboardingNotifier` 의 initial 파라미터 super-parameter 단축.
- `summary_screen.dart` `_AiInsightCard`: `!canRefresh && lastRefresh != null` 의 중복 null guard 제거 (`!canRefresh` 분기에선 `lastRefresh` 가 항상 non-null 임이 위쪽 분기에서 보장됨).

---

## 커밋 매핑

| 커밋 | 항목 |
|------|------|
| `e9bcc34` | 1, 2, 3 — A 그룹 (블로커/보안) |
| `5235132` | 4 — iOS 휴식 알림 안정화 |
| `f53678e` | 5, 6 — picker 통합 + 1RM 빠른 추정 카드 제거 |
| `424eef0` | 7 — 잡다한 정리 |

---

## 향후 (v13+)

- `RoutineItem` / `ExerciseTemplate` 에 `exerciseKey` 필드 정식 도입 (현재는 displayName 만 저장 — `ExercisePickerField` 가 `exerciseKey` 를 함께 반환하지만 스키마에 슬롯이 없어 미사용).
- 모든 화면의 운동명 표시를 `exerciseDisplayNameProvider` 로 일관 적용 (locale 별 표시).
- 기존 사용자 데이터 매핑 누락 정정 UX (`exercise_key=NULL` → 표준 종목 매핑 마법사).
