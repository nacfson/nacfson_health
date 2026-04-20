# 기능 구현 현황

> **마지막 업데이트**: 2026-04  
> 새 기능 완료 시 체크박스를 채우고, 백로그에 새 항목을 추가할 것.

---

## 완료된 기능 ✅

### 핵심 데이터 입력
- [x] 운동 기록 CRUD (`ExerciseRecord` — 부위/종목/세트/중량/횟수/RPE)
- [x] 식단 기록 CRUD (`DietRecord` — 식사유형/음식명/칼로리/탄단지/만족도/메모)
- [x] 체중 기록 CRUD (`WeightRecord` — 체중)
- [x] 운동 기록 날짜·부위별 그룹핑 뷰 (`todayExerciseGroupedProvider`)
- [x] 식단 기록 식사유형별 그룹핑 뷰 (`todayDietGroupedProvider`)

### 요약/시각화
- [x] 일일 요약 화면 (`SummaryScreen` — fl_chart 기반)
- [x] 영양 목표 대비 진행률 표시 (`dailySummaryProvider`)
- [x] 운동 볼륨·RPE 계산 (`todayTotalVolumeProvider`)
- [x] 체중 차트 시각화 (`WeightChartCard` — fl_chart)

### 설정 화면
- [x] 영양 목표값 설정 (`DietTargetCard` — 칼로리/탄단지 목표)
- [x] 운동 템플릿 관리 (`ExerciseTemplateCard` — 종목 프리셋, 생성·삭제)
- [x] 음식 템플릿 관리 (`FoodTemplateCard` — 음식 프리셋, 생성·삭제, v4)
- [x] Google 로그인/로그아웃 (`GoogleSignInCard`)
- [x] 스프레드시트 상태 + 수동 동기화 (`SpreadsheetStatusCard`)
- [x] 테마 전환 — 시스템/라이트/다크 (`ThemeModeCard` + `themeModeProvider`, shared_preferences 영구 저장)
- [x] 기본 휴식 시간 설정 (`RestTimerSettingsCard` — 60/90/120/180초, `defaultRestSecondsProvider`)

### 운동 루틴 플래너 + 인라인 세트 입력 (v8)
- [x] DB v8 — `workout_routines` (Supabase 동기화) + `daily_routine` (로컬 전용) 테이블
- [x] `RoutinePlannerNotifier` — 오늘 루틴(`daily_routine`) 항목 추가/제거/교체/병합
- [x] `WorkoutRoutineNotifier` — 프리셋(저장된 루틴) CRUD + Supabase 양방향 동기화
- [x] `todayExerciseCardsProvider` — 계획(루틴)과 기록(세트)을 union 한 카드 데이터
- [x] `InlineSetInput` — 카드 하단 1행 입력기, 직전 세트 값 프리필 + 연속 입력
- [x] `addSetAutoNumber` — 같은 운동의 다음 세트 번호 자동 부여
- [x] `deleteSetAndRenumber` — 세트 삭제 후 동일 운동의 currentSet 재부여
- [x] `RoutinePresetSheet` — AppBar 아이콘으로 호출, 탭=불러오기(교체/추가) · 메뉴=이름변경/삭제
- [x] "루틴으로 저장" — 현재 오늘 루틴을 이름 붙여 프리셋으로 보관
- [x] FAB 동작 변경 — 모달 폼 대신 템플릿 피커로 직접 루틴에 운동 추가
- [x] 볼륨 공식 정정 — `weight × reps × currentSet` → `weight × reps`
- [x] 레거시 `ExerciseForm` 바텀시트 제거 (인라인 입력으로 대체)

### 휴식 타이머 (v7.1)
- [x] **인앱 sticky 미니바** (`RestTimerBar` — BottomNavShell 오버레이, 모든 탭에서 가시성 유지)
- [x] 운동 세트 신규 저장 시 자동 시작 (`InlineSetInput._submit` → `restTimerProvider.start`)
- [x] ±15초 빠른 조정 / 일시정지·재개 / 수동 종료
- [x] 백그라운드 복귀 정확성 (`endAt` 기반 계산, Timer.periodic은 UI 갱신 전용)
- [x] 5초 전 햅틱 1회 + 0초 도달 시 강한 햅틱 (`HapticFeedback`)
- [x] iOS Live Activity (Dynamic Island + Lock Screen) — `RestNotificationServiceIOS` + `live_activities` 패키지 + `RestActivityWidget.swift` (App Group `group.com.nacfson.nacfsonHealth` 통일, Xcode 수동 단계는 `docs/build-debug.md` §14)
- [x] Android persistent notification (chronometer + `[+15초]`·`[정지]` 액션) — `RestNotificationServiceAndroid` + `flutter_local_notifications` + `permission_handler`
- [ ] iOS Live Activity App Intents 액션 (현재는 인앱/Android만 액션 처리) — 백로그
- [ ] Android Foreground Service (앱 강제 종료 시에도 알림 유지) — 백로그

### Google Sheets 동기화
- [x] Google 계정 로그인 · 세션 복원 (`GoogleAuthService`)
- [x] 스프레드시트 자동 생성 + 필수 시트 보장 (`ensureAllRequiredSheets`)
- [x] 운동 기록 Push/Pull/HardDelete
- [x] 식단 기록 Push/Pull/HardDelete
- [x] 운동 템플릿 양방향 동기화 (Push/Pull/HardDelete)
- [x] 음식 템플릿 양방향 동기화 (Push/Pull/HardDelete, v4)
- [x] 체중 기록 양방향 동기화 (Push/Pull/HardDelete, v5) ✅ 완성
- [x] 운동 루틴 프리셋 양방향 동기화 (Push/Pull/HardDelete, v8) — `daily_routine`은 로컬 전용
- [x] 스프레드시트 교체 시 전체 재동기화 (`resetAllSyncStatus`)
- [x] 앱 포그라운드 전환 시 자동 동기화 (`AppLifecycleState.resumed`)

### UI/UX
- [x] `ErrorOverlay` — 자동 닫힘 오류 표시 (낮은 심각도)
- [x] Bottom Sheet 슬라이드/페이드 애니메이션 (`RecordFormSheet`)
- [x] 탭 전환 시 모든 오버레이 자동 닫기 (`popAll`)
- [x] `DietForm` — 음식 템플릿 드롭다운 + 자동 채움 (칼로리/탄단지 전체)
- [x] `ExerciseForm` — 운동 템플릿 드롭다운 + 종목명 자동 채움
- [x] `TemplatePickerSheet` 도입 — 운동·식단 이름 필드 suffixIcon 명시적 트리거 BottomSheet, 기본 상태 템플릿 노출 제거(넛지 최소화), 검색 + 운동 부위 필터 + 빈 상태 설정 화면 이동
- [x] `WeightScreen` — 체중 탭 (입력/차트 시각화)
- [x] `WeightForm` — 날짜 선택 기능 (`showDatePicker`, 과거 날짜 소급 입력 지원)
- [x] `DateNavigationBar` — 운동/식단/요약 탭 날짜 탐색 (좌우 이동 + DatePicker)
- [x] `VolumeTrendChart` — 운동 볼륨 주간/월간 추세 꺾은선 차트 (fl_chart)
- [x] `CalorieTrendChart` — 식단 칼로리 주간/월간 추세 막대 차트 + 목표선 (fl_chart)
- [x] 과거 날짜 데이터 열람 (selectedDateProvider 기반 전역 날짜 상태)
- [x] 설정 화면 하단 스크롤 버그 수정 (`SizedBox(height: 96)` — glassmorphic nav bar 오버레이 대응)
- [x] 요약 탭 네비게이션 버그 수정 (FAB 표시 중 요약 탭 버튼 숨김 조건 제거)
- [x] Google 로그인 직후 자동 동기화 (`AuthCallbackScreen` → `performSync()`)
- [x] 로그인 콜백 흐름 안정화 — `ConsumerStatefulWidget` + `ref.listenManual` 한 번만 구독, `/settings`로 복귀, 동기화는 `unawaited` + try/catch로 분리 (`docs/build-debug.md` §11)
- [x] `ChipTheme.labelStyle` 색상 명시 — 라이트 테마 템플릿 칩 흰색 텍스트 버그 수정 (`chipFg` 토큰 추가)
- [x] Bottom Sheet 상태 race 제거 — `sheet_state_provider`의 `Future.microtask` 제거로 FAB 복귀 지연 해소 (`docs/build-debug.md` §10)
- [x] `EmptyState` 중복 "운동 추가"/"식사 추가" 버튼 제거 — 하단 FAB로 통일, 탭 하단 여백 96→120
- [x] FAB 상태 관리 — 바텀시트 열림 시 자동 숨김 (`activeSheetProvider` 연결, `openSheet()` 헬퍼 일괄 적용)
- [x] `RecordFormSheet` DraggableScrollableSheet 전환 — 드래그로 시트 높이 조절 (45%~95%), 내부 폼 스크롤과 자연 연동
- [x] 다크모드 잔여 흰색 UI 전수 정비 — glassmorphic nav bar, TriRing/AI 인사이트 카드, BMI 바, 날짜 네비게이션 바, 온보딩, Autocomplete 드롭다운, 차트 목표선
- [x] 다크모드 2차 전수 감사 — 운동 세트 칩(`_StatItem` kg/횟수/RPE), 매크로 게이지 단/지, 섹션 헤더(운동/식단), 칼로리 추세 차트 막대, 체중 차트 그리드 라인, 설정 경고 카드(Google 미로그인), SnackBar 오류 배경, FAB 아이콘 → 모두 `ColorScheme` 기반 동적 색상으로 전환 (brightness-aware 헬퍼 추가: `AppTheme.catDiet/catSleep/lunchTint/snackTint/warnBg/warnFg`)

### 온보딩 & 사용자 프로필
- [x] 첫 실행 온보딩 화면 (`OnboardingScreen` — 키/체중 입력, SharedPreferences 플래그)
- [x] `HeightNotifier` — SharedPreferences 기반 키(m) 영구 저장 (`user_height_m`)
- [x] `OnboardingNotifier` — 온보딩 완료 플래그 (`onboarding_done`)
- [x] GoRouter 온보딩 리다이렉트 (`RouterNotifier` + `refreshListenable` 패턴)
- [x] 온보딩 체중 입력 → `WeightRecord` 오늘 날짜로 자동 저장

### AI 건강 인사이트
- [x] `GeminiService` — `gemini-2.5-flash-lite` 기반 한국어 건강 조언 생성 (`.env` API 키)
- [x] `healthInsightProvider` — `FutureProvider.autoDispose`, 체중·식단·운동 종합 분석
- [x] `_AiInsightCard` — 요약 화면 AI 인사이트 카드 (로딩/에러/데이터 상태, 새로고침)
- [x] `InsightCallCountNotifier` — 날짜별 호출 횟수 SharedPreferences 영속 (하루 3회 상한)
- [x] BMI 동적 계산 (`_BmiBar` → ConsumerWidget, `heightMProvider` 연동)

---

## 구현 패턴 요약

새 도메인(테이블) 추가 시 아래 순서로 구현:

```
1. Entity           lib/features/{domain}/domain/entities/{entity}.dart
2. DB 마이그레이션   lib/core/database/database_helper.dart (version++, onCreate, onUpgrade)
3. Repository 인터페이스  lib/features/{domain}/data/repositories/{entity}_repository.dart
4. SQLite 구현체     lib/features/{domain}/data/repositories/sqlite_{entity}_repository.dart
5. Provider         lib/features/{domain}/presentation/providers/{entity}_provider.dart
6. GoogleSheetsService  ensureAllRequiredSheets + push + pull 메서드 추가
7. GoogleAuthService    createSpreadsheet 시트 목록에 추가
8. sync_state.dart  SyncStateNotifier 주입 + _syncAll 단계 추가
9. UI 위젯          설정 카드 or 폼 드롭다운
10. docs 업데이트    db-schema.md + features.md + architecture.md + domains.md + ui-architecture.md
```

> 템플릿 계열 (`exercise_templates`, `food_templates`)은 `modified(2)` 없이 생성·삭제만,  
> Pull 병합은 insert-or-skip (LWW 불필요).  
> 레코드 계열 (`exercise_records`, `diet_records`, `weight_records`)은 전체 CRUD + LWW Pull.

---

## 백로그 📋

> 우선순위 없음 — 추가할 때 항목 작성

- [x] 주간/월간 운동 볼륨 추세선 차트
- [x] 날짜별 식단 칼로리 히스토리 차트
- [ ] 운동 기록 캘린더 뷰 (부위별 Dot 표시)
- [ ] 오프라인 모드 명시적 안내 (동기화 실패 시 배너)
- [x] 다크 모드 지원 (전수 정비 완료)
- [ ] 스트릭 시스템 (연속 기록 동기부여)
- [ ] 설정 화면에서 키 수정 기능 (온보딩 이후 변경)
- [ ] AI 인사이트 캐싱 (같은 날 데이터 변경 없으면 재호출 생략)

