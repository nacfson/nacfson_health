# 기능 구현 현황

> **마지막 업데이트**: 2026-10-25 (health-web GHCR publish)
> 새 기능 완료 시 체크박스를 채우고, 백로그에 새 항목을 추가할 것.

---

## 완료된 기능 ✅

### health-web MVP (2026-09) — ProcessManager Option B SPA
- [x] `apps/health-web/` 신규 — Go API + vanilla SPA (Flutter `web/` 미사용). 네이티브 `lib/`/`ios/`/`android/` 미변경
- [x] ProcessManager SSO — cookie `nacfson_session` → Auth `GET /api/internal/cookie-session`; 로컬 users 테이블 없음; CSRF `health_csrf`
- [x] Postgres user-owned 스키마 + master 시드 (`./migrate up` + `./migrate seed`)
- [x] 5탭 CRUD — 운동|식단|체중|요약|설정; Atwater 서버 계산; summary DTO; daily_routine self-heal
- [x] K8s manifests — `ProcessManager/k8s/health/` (`health.nacfson.cloud`)
- [x] GHCR 이미지 자동 배포 — `.github/workflows/publish-ghcr-images.yml` (main push, amd64+arm64, sha7/latest, PR build-only, 게시 후 index 검증)
- [ ] 클러스터 배포 완료 — ~~registry push~~ (GHCR CI 로 대체) + shared-app-db provision + migrate Job + Ingress smoke (API 192.168.219.120:6443 unreachable at implement time)
- [ ] Native↔web sync bridge (P4, out of MVP)

### v12-5 (2026-05) — 칼로리 자동 계산 (Atwater)
- [x] `lib/core/nutrition/atwater_calculator.dart` 신규 — `kcalFromMacros(carbs, protein, fat)` 순수 함수 (Atwater 4/4/9). 단위 테스트 6건
- [x] `DietForm` 칼로리 `TextFormField` 제거 → 매크로(탄·단·지) 입력 아래 라이브 미리보기 (`자동 계산: NNN kcal`). 저장 시 `kcalFromMacros()` 로 산출하여 `diet_records.total_calories` 컬럼에 기록
- [x] `FoodTemplateCard` 추가 탭 칼로리 `TextFormField` 제거 → 매크로 한 줄 + kcal 미리보기 한 줄로 재구성. `_addTemplate()` 에서 자동 산출하여 `food_templates.calories` 컬럼에 기록
- [x] AI 사진 분석 / 음식 템플릿 picker / 최근 식사 칩 — 매크로만 컨트롤러에 채우고 kcal 은 항상 매크로에서 Atwater 로 재계산 (출처별 kcal 무시, 일관 규칙 우선)
- [x] DB 스키마 변경 없음 — 컬럼은 유지하여 과거 데이터·sync 호환 보존

### v12-3 (2026-05) — UI/UX HIGH 7건 (다크 모드/입력 흐름/실수 복구)
- [x] 다크 모드 색상 하드코딩 정리 — `app_theme.dart` 매크로 토큰 (`macroCarbsFg`/`macroProteinFg`/`macroFatFg`) 신설 + 7개 위젯의 `Colors.white/orange/blue/yellow/amber` → `AppTheme` 헬퍼 (`weight_chart_card` 툴팁, `calorie_trend_chart` 아이콘, `analysis_result_sheet` 신뢰도 배너, `spreadsheet_status_card` 라이트 분기 비대칭 해소, `diet_target_card` 매크로 라벨, `weight_form` 날짜 강조)
- [x] 입력 검증 메시지 — 현재 입력값 + 권장 범위 명시 (`diet_form` 칼로리/탄단지, `inline_set_input` 중량/반복/RPE, `onboarding_screen` 키/체중 톤 통일)
- [x] 터치 타겟 44x44 — `diet_record_card` 템플릿 등록 IconButton constraints 32→44, `summary_screen` 정보·새로고침 GestureDetector→IconButton(tooltip), `weight_screen` "오늘 기록 추가" InkWell + minHeight 44
- [x] 시트 swipe-down 손실 경고 — `DietForm.isDirty` getter + `DietFormState` public 화 + `diet_screen` 호출처 `_confirmDiscardIfDirty` (WeightForm 은 v12-2 에서 적용 완료)
- [x] 로딩 상태 표시 — `xxxRecordsInitialLoadingProvider` (운동/식단/체중) + `dailySummaryInitialLoadingProvider` (derived) 신설. 4개 화면에서 spinner 분기 (콜드 스타트 시 빈 리스트 깜빡임 제거)
- [x] `NumericStepperField` 신규 위젯 — long-press 100ms 가속, `min`/`max` 클램프, `inline_set_input` kg(0.5)/회(1)/RPE(0.5) 적용. `weight_form` 큰 폰트 유지 + 자체 `_LargeStepperButton` ±0.1kg
- [x] 식단 삭제 후 SnackBar Undo (5초) — `DietNotifier.softDelete`/`restoreSoftDelete`/`commitAllPending` + Timer 캐시. `performSync()` 진입점에서 `commitAllPending` 강제 호출로 sync 누락 방지. `diet_screen` swipe delete 적용
- [~] 운동 도메인 Undo — `deleteSetAndRenumber` 가 set 번호 일괄 재정렬을 동반해 reverse 복잡. 다음 라운드 분리 (현재 confirmDialog 유지)

### v12-2 (2026-05) — B/C 그룹 audit (품질 보강)
- [x] 빈 `catch (_)` 무주석 0건 — `main.dart` / `food_vision_provider` / `one_rm_formula` / `weight_provider` / `activity_summary_card` / `health_data_source` 7건 정리 (`docs/error-handling.md` §의도적 빈 catch 가이드 준수)
- [x] Master data fetch 5분 attempt throttle (`SqliteMasterDataRepository._lastAttemptKey`) — 첫 설치 + 오프라인 시 무한 네트워크 호출 차단
- [x] 휴식 타이머 stale Live Activity race 가드 — `RestTimerNotifier.start()/stop()` 의 `_notifications.end()` try-catch + 진행 보장
- [x] `RecordFormSheet` 미저장 경고 API — `onConfirmClose` 콜백 + `PopScope` (system back/swipe-down 도 가드)
- [x] `WeightForm.isDirty` getter + `WeightFormState` public 화 — `weight_input_card` / `weight_screen` 두 호출처에서 dirty 시 AlertDialog
- [x] `showAppSnackBar` 헬퍼 (`lib/shared/util/snackbar.dart`) — `clearSnackBars` + floating 통일. `diet_screen` / `photo_analysis_card` / `exercise_screen` 6곳 교체
- [x] `exercise_chips` GestureDetector `Semantics(button, selected, label)` — 1RM 코치 종목 칩 VoiceOver/TalkBack 인식
- [x] `legacy_korean_mapping_test.dart` — 한글명 → exercise_key 매핑 회귀 테스트 12건 (null/공백/대표 종목/스네이크케이스/카테고리/SQL 헬퍼)
- [x] `weight_form` 날짜 강조 색 — `Colors.amber.shade700` → `AppTheme.warnFg(context)` 헬퍼화
- [~] C1 다른 폼 (DietForm / DirectRoutineInputDialog / ExerciseTemplateCard 추가 탭 / FoodTemplate) — 같은 패턴 점진 마이그레이션
- [~] C4 나머지 호출처 (validation 단발성) — `inline_set_input` / `weight_form` / `activity_permission_card` 등 점진 마이그레이션

### v12 (2026-04-29) — 다국어 + 종목별 권위 1RM 공식
- [x] 운동 마스터 데이터 다국어 지원 (`exercise_definitions` + `exercise_translations` ko/en, 161개 표준 웨이트 종목 + 322개 번역)
- [x] 카테고리 다국어 지원 (`exercise_categories` + `exercise_category_translations`, 11개 카테고리)
- [x] 종목별 1RM 공식 테이블 (`one_rm_formulas`, NSCA LeSuer 1997 검증 기반 — 벤치=Mayhew, 스쿼트/데드=Wathen, 등=Brzycki, 24개 종목 시드)
- [x] `OneRMFormulaSpec` 4 type evaluator (epley/linear/exponential/polynomial) + 22 회귀 테스트
- [x] TTL 24h pull-only 캐시 (1RM 코치 진입 시 Supabase 5 테이블 병렬 fetch + SQLite replace, 일반 sync 사이클과 분리)
- [x] 기존 사용자 데이터 마이그레이션 — `exercise_records`/`exercise_templates`/`workout_routines.items_json`/`daily_routine.items_json` 의 한글명 → `exercise_key` 자동 매핑 (M1 Eager, 52개 default 종목)
- [x] 1RM 코치가 종목별 권위 공식으로 e1RM 계산 (등록 종목 한정, 미등록은 Epley fallback)
- [x] 1RM 코치 종목 칩 — 공식 등록 종목만 노출 (`topExerciseNamesProvider` + `oneRMFormulaSpecMapProvider` 필터)
- [x] 사용자 커스텀 종목 입력 차단 — `ExercisePickerField` 공용 위젯으로 운동 추가 다이얼로그 + 운동 템플릿 추가 탭 통합. `exercise_definitions` 등록 종목만 선택 가능, 부위는 자동 분류
- [x] 1RM 코치 빠른 추정 카드 제거 — `currentE1RM` (5주 max) 와 중복이라 정리. `coachInputWeight/Reps/latestWorkSet/selectedExerciseFormula` Provider 도 함께 삭제
- [~] 모든 화면의 운동명 locale별 표시 (구조 완료, 전 화면 적용은 v13)


### 핵심 데이터 입력
- [x] 운동 기록 CRUD (`ExerciseRecord` — 부위/종목/세트/중량/횟수/RPE)
- [x] 식단 기록 CRUD (`DietRecord` — 식사유형/음식명/칼로리/탄단지/만족도/메모)
- [x] 체중 기록 CRUD (`WeightRecord` — 체중)
- [x] 운동 기록 날짜·부위별 그룹핑 뷰 (`todayExerciseGroupedProvider`)
- [x] 식단 기록 식사유형별 그룹핑 뷰 (`todayDietGroupedProvider`)
- [x] 식단 탭 헤더 목표 대비 진행률 표시 — 칼로리 `소비/목표·%`, 탄·단·지 막대를 `소비/목표` 비율로 변경 + 100% 초과 시 coral 색 강조 (`_DietSummaryCard`, `_MacroBarsRow`)

### 요약/시각화
- [x] 일일 요약 화면 (`SummaryScreen` — fl_chart 기반)
- [x] 영양 목표 대비 진행률 표시 (`dailySummaryProvider`)
- [x] 운동 볼륨·RPE 계산 (`todayTotalVolumeProvider`)
- [x] 체중 차트 시각화 (`WeightChartCard` — fl_chart)

### 설정 화면
- [x] 영양 목표값 설정 (`DietTargetCard` — 칼로리/탄단지 목표)
- [x] 운동 템플릿 관리 (`ExerciseTemplateCard` — 종목 프리셋, 생성·삭제, 종목별 휴식 시간 오버라이드 v11)<br/>   &nbsp;&nbsp;&nbsp;&nbsp;v11.1 UX 개편 — `ExpansionTile` 제거(설정 진입 즉시 노출), **검색/추가 SegmentedButton 탭 분리**(검색 탭: 입력 시에만 매칭 칩 노출, 매칭 0 → "추가 탭으로 이동" 링크 / 추가 탭: 이름+부위 ChoiceChip, 이미 보유한 이름이면 인라인 헬퍼 + 추가 버튼 disabled), 휴식 편집 시트 BottomNav 겹침·세자리 수 표시 잘림 버그 수정, 기본 템플릿 16 → 56종 확장(시드 플래그 v2)
- [x] 음식 템플릿 관리 (`FoodTemplateCard` — 음식 프리셋, 생성·삭제, v4)<br/>   &nbsp;&nbsp;&nbsp;&nbsp;v11.1 — `ExpansionTile` 제거 + **검색/추가 SegmentedButton 탭 분리**(검색 탭: 입력 시에만 매칭 ListTile, 매칭 0 → "추가 탭으로 이동" 링크 / 추가 탭: 이름+매크로(칼로리/탄·단·지) 입력, 중복 시 추가 버튼 disabled)
- [x] Google 로그인/로그아웃 (`GoogleSignInCard`)
- [x] 스프레드시트 상태 + 수동 동기화 (`SpreadsheetStatusCard`)
- [x] 테마 전환 — 시스템/라이트/다크 (`ThemeModeCard` + `themeModeProvider`, shared_preferences 영구 저장)
- [x] 부위별 기본 휴식 시간 (v11 — 근비대 기준 코드 상수, 사용자 수정 불가)<br/>   &nbsp;&nbsp;&nbsp;&nbsp;가슴 120s · 등 150s · 하체 180s · 어깨 90s · 팔 60s · 코어 60s · 기타 90s · 유산소 휴식 없음<br/>   &nbsp;&nbsp;&nbsp;&nbsp;종목별 오버라이드 → `ExerciseTemplateCard` 칩 탭(설정 탭)에서만 편집. 세션 중 ±15초 조정은 해당 세션에만 일시 적용
- [x] ~~기본 휴식 시간 설정 (`RestTimerSettingsCard` — 60/90/120/180초)~~ v11 에서 제거 — 부위별 기본값 + 종목 오버라이드 체계로 전환

### 운동 루틴 플래너 + 인라인 세트 입력 (v8)
- [x] DB v8 — `workout_routines` (Supabase 동기화) + `daily_routine` (로컬 전용) 테이블
- [x] `RoutinePlannerNotifier` — 오늘 루틴(`daily_routine`) 항목 추가/제거/교체/병합
- [x] `WorkoutRoutineNotifier` — 프리셋(저장된 루틴) CRUD + Supabase 양방향 동기화
- [x] `todayExerciseCardsProvider` — 루틴(`daily_routine`)을 기준으로 오늘 기록을 join 한 카드 데이터 (v9+: extras 경로 제거, 루틴=카드 1:1)
- [x] 세트 저장 시 루틴 자동 편입 (`InlineSetInput._submit` → `routinePlannerProvider.addItem`)
- [x] `RoutinePlannerNotifier._load` 자기치유 — 루틴에 없는 기존 기록을 자동 편입
- [x] "운동 제거" 메뉴 — 루틴 항목 + 선택 날짜 기록을 함께 soft delete, 기록 있을 시 확인 다이얼로그
- [x] `ExerciseRepository.deleteByExerciseNameOnDate` — 운동명+일자 기준 일괄 soft delete
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
- [x] 운동 세트 신규 저장 시 자동 시작 (`InlineSetInput._submit` → `restTimerProvider.start`, 부위 기본값/종목 override 해석)
- [x] ±15초 빠른 조정 (`RestTimerBar` 인라인 버튼 + 알림 액션) / 일시정지·재개 / 수동 종료
- [x] 백그라운드 복귀 정확성 (`endAt` 기반 계산, Timer.periodic은 UI 갱신 전용)
- [x] 5초 전 햅틱 1회 + 0초 도달 시 강한 햅틱 (`HapticFeedback`)
- [x] iOS Live Activity (Dynamic Island + Lock Screen) — `RestNotificationServiceIOS` + 자체 `RestActivityBridge` (Swift, MethodChannel `nacfson/rest_activity`) + `RestActivityWidget.swift`. ContentState (`RestActivityAttributes.ContentState`) 에 `endAtMs / isPaused / exerciseName / totalSeconds` 직접 적재 → ±15초 / 일시정지 변경 시 ActivityKit 이 위젯 rebuild 즉시 trigger (UserDefaults 우회 폐기). App Group `group.com.nacfson.nacfsonHealth` 유지, Xcode 수동 단계는 `docs/build-debug.md` §14
- [x] Android persistent notification (chronometer + `[+15초]`·`[정지]` 액션) — `RestNotificationServiceAndroid` + `flutter_local_notifications` + `permission_handler`
- [ ] iOS Live Activity App Intents 액션 — 자체 `RestActivityAttributes` 도입으로 ContentState 수정 자유도 확보. App Intents 추가 시 widget 코드만 변경하면 됨. (현재는 인앱/Android만 액션 처리) — 백로그
- [ ] Android Foreground Service (앱 강제 종료 시에도 알림 유지) — 백로그

### 홈스크린 위젯 (iOS)
- [x] `NutritionWidget` — 오늘 칼로리·탄단지 진행률 (small / medium) — `ios/NacfsonHealthWidget/NutritionWidget.swift`, 데이터: `HomeWidgetService.update()`
- [x] `WorkoutHeatmapWidget` — 최근 13주 운동 볼륨 잔디밭 (medium / large) — `ios/NacfsonHealthWidget/WorkoutHeatmapWidget.swift`, 데이터: `HomeWidgetService.updateHeatmap()` (요약 탭 `WorkoutHeatmapCard` 와 동일한 4분위 색상 로직)
- [x] App Group `group.com.nacfson.nacfsonHealth` 공유 (Live Activity 와 통일) + `_registerHomeWidgetSync` 자동 갱신 (식단 합계 / 영양 목표 / 본세트 볼륨 변경 시)
- [x] 위젯 탭 → 앱 진입 딥링크 — `nacfsonhealth://` 자체 URL 스킴 + 각 위젯 `.widgetURL(...)` (영양 → `/diet`, 잔디 → `/summary`). cold/warm launch 모두 `lib/main.dart`의 `_registerWidgetTapListener` → `appRouterProvider.go(...)` 로 라우팅. medium/large 위젯은 `widgetURL` 없이는 탭 무반응이므로 필수.
- [ ] Android App Widget — 백로그

### Supabase 동기화
- [x] Supabase OAuth 로그인 · 세션 복원 (`GoogleAuthService` — Supabase OAuth 래퍼)
- [x] 운동 기록 Push/Pull/HardDelete — `SupabaseService.batchPushExerciseRecords` / `readExerciseRecordsDelta`
- [x] 식단 기록 Push/Pull/HardDelete
- [x] 운동 템플릿 양방향 동기화 (Push/Pull/HardDelete)
- [x] 음식 템플릿 양방향 동기화 (Push/Pull/HardDelete, v4)
- [x] 체중 기록 양방향 동기화 (Push/Pull/HardDelete, v5) ✅ 완성
- [x] 운동 루틴 프리셋 양방향 동기화 (Push/Pull/HardDelete, v8) — `daily_routine`은 로컬 전용
- [x] LWW (Last-Write-Wins) 머지 — `updated_at` 기준, Soft-delete(`is_deleted=true`)
- [x] 전체 재동기화 (`resetAllSyncStatus`)
- [x] 앱 포그라운드 전환 시 자동 동기화 (`AppLifecycleState.resumed`)
- [x] **Google Sheets 동기화는 v7에서 제거됨** (자세한 경위는 `docs/changelog-v7.md`)

### UI/UX
- [x] `ErrorOverlay` — 자동 닫힘 오류 표시 (낮은 심각도)
- [x] Bottom Sheet 슬라이드/페이드 애니메이션 (`RecordFormSheet`)
- [x] 탭 전환 시 모든 오버레이 자동 닫기 (`popAll`)
- [x] `DietForm` — 음식 템플릿 드롭다운 + 자동 채움 (칼로리/탄단지 전체)
- [x] `ExerciseForm` — 운동 템플릿 드롭다운 + 종목명 자동 채움
- [x] `TemplatePickerSheet` 도입 — 운동·식단 이름 필드 suffixIcon 명시적 트리거 BottomSheet, 기본 상태 템플릿 노출 제거(넛지 최소화), 검색 + 운동 부위 필터 + 빈 상태 설정 화면 이동
- [x] `DietForm` 상단 "최근 식사에서 다시 추가" 가로 칩 (`recentUniqueDietRecordsProvider` — 최근 7일 고유 foodName, 최대 10개) — 칩 탭 시 폼 필드 자동 채움 + timestamp 현재 시각 갱신
- [x] `DietRecordCard` 북마크 버튼 — 식단 카드에서 원탭으로 `FoodTemplate` 등록 (중복 이름 방어, 이미 등록된 음식은 filled bookmark로 시각화)
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
- [x] 첫 실행 온보딩 화면 (`OnboardingScreen` — 키/체중/만 나이/성별/활동 수준/운동 강도/목표 입력, SharedPreferences 플래그)
- [x] `HeightNotifier` — SharedPreferences 기반 키(m) 영구 저장 (`user_height_m`)
- [x] `OnboardingNotifier` — 온보딩 완료 플래그 (`onboarding_done`)
- [x] GoRouter 온보딩 리다이렉트 (`RouterNotifier` + `refreshListenable` 패턴)
- [x] 온보딩 체중 입력 → `WeightRecord` 오늘 날짜로 자동 저장
- [x] **영양 목표 공식 v2 (2026-04)** — 목표 4분할 (다이어트 / 린매스(감량) / 린매스(증량) / 벌크업), TDEE 조정 −500 / −200 / +200 / +500, 활동 수준 5단계 (1.2/1.375/1.55/1.725/1.9), 운동 강도 4단계로 단백질 1.8~2.4 g/kg, 만 나이 직접 입력 (`lib/core/nutrition/nutrition_calculator.dart`)
- [x] `SyncPreferences` 사용자 프로필 저장 — `user_gender` / `user_age` / `activity_level` / `training_intensity` / `fitness_goal`. 레거시 `user_age_group` · `fitness_goal=lean_mass` 는 `migrateLegacyProfile()` 로 1회 재작성
- [x] 설정 화면 '영양 목표' 카드 — 목표 · 활동 수준 · 운동 강도 bottom sheet picker + '프로필 기반 재계산' 버튼

### AI 건강 인사이트 & 코치 챗봇
- [x] `GeminiService` — `gemini-2.5-flash-lite` 기반 한국어 건강 조언 생성 (`.env` API 키)
- [x] `healthInsightProvider` — `FutureProvider.autoDispose`, 체중·식단·운동 종합 분석
- [x] `_AiInsightCard` — 요약 화면 AI 인사이트 카드 (로딩/에러/데이터 상태, 새로고침)
- [x] **일일 호출 제한 해제** — `insightCacheProvider` 데이터 해시 기반 캐싱 + UI 60초 디바운스로 방어
- [x] `insightLastRefreshAtProvider` / `insightCanRefreshProvider` — 수동 새로고침 디바운스 타이머 + 카운트다운 라벨
- [x] BMI 동적 계산 (`_BmiBar` → ConsumerWidget, `heightMProvider` 연동)
- [x] **코치 챗봇** (`coachChatProvider`, autoDispose) — `gemini-2.5-flash`, JSON 모드 (answer + follow_ups), 최근 6턴 히스토리
- [x] **일일 호출 한도 30회** (`coachChatCallCountProvider`, 자정 자동 리셋, increment-before 정책)
- [x] **추천 칩 Provider** (`suggestedPromptsProvider`) — 20+ 규칙 기반 (식단/매크로/운동/체중/루틴/동기부여/시간대), 카테고리 다양성 랭킹, 최대 5개, fallback 3개
- [x] **`showCoachChatSheet`** — 90% 높이 하단 모달, 빈 상태 추천 칩 + 대화 + follow-up 칩 이어가기
- [x] **요약 카드 "더 물어보기" CTA** (`_AiInsightCard` 하단 TextButton)
- [x] `evaluateSuggestedPrompts` pure function — 테스트 용이성을 위해 Provider와 분리

### Apple Health & Android Health Connect 연동 (Phase 1, 2026-04)
- [x] `health: ^13.3.1` 패키지 통합 (iOS HealthKit + Android Health Connect 단일 API)
- [x] iOS: `NSHealthShareUsageDescription` Info.plist + `com.apple.developer.healthkit` entitlement (Personal Team 환경에서는 시트 미동작 가능 — 유료 가입 필요할 수 있음)
- [x] Android: Health Connect 5종 권한 (STEPS / ACTIVE_CALORIES_BURNED / BASAL_METABOLIC_RATE / HEART_RATE / RESTING_HEART_RATE), `<queries>` Health Connect 패키지 가시성, `PrivacyPolicyActivity` (Google Play 정책 강제), minSdk 26 상향
- [x] `lib/features/activity/` 신규 도메인 — `DailyActivity` 엔티티, `HealthDataSource` 추상 + `HealthDataSourceImpl`, `HealthActivityRepository`
- [x] Riverpod 인메모리 캐시 (Supabase 미동기화) + `AppLifecycleState.resumed` 시 자동 invalidate
- [x] `ActivityPermissionCard` (notDetermined/denied/needsHealthConnectInstall) + `ActivitySummaryCard` (걸음/소모/심박)
- [x] iOS read 권한 불투명성 양가적 안내 ("권한이 꺼져 있거나 데이터가 없거나")
- [x] `HealthContext` + `GeminiService.getHealthInsight` + Gemini 프롬프트에 활동 라인 추가 — 1만보 걸은 날 vs 좌식 날 추천 차별화
- [x] 단위 테스트 10개 (`test/features/activity/`) — 엔티티 invariants + 프롬프트 라인 + contentHash 안정성

### 운동 볼륨 기반 칼로리 추정 (2026-04)
- [x] `lib/features/exercise/domain/body_part_calorie_coefficients.dart` — 부위별 계수 (하체 1.0 / 등·가슴 0.85 / 어깨·팔 0.6 / 코어 0.5 / 유산소 0.0 / 기타 0.7) + `kKcalPerKgVolume = 0.01`
- [x] `lib/features/exercise/domain/exercise_calorie_estimator.dart` — `kcal = Σ(volume × 0.01 × 부위계수)`, warmup/failure 제외 (Scott 2011 단순 모델)
- [x] `WorkoutPerformance.estimatedCalories` 필드 + `dailySummaryProvider` 통합
- [x] 요약 탭 운동 카드에 "운동 칼로리 ~XX kcal *추정치*" 행 + ⓘ 탭 시 ±40% 오차 안내 스낵바
- [x] HealthKit / Health Connect 의 활동 칼로리와 **분리 표시** — 합산하지 않음 (이중 카운팅 방지)
- [x] 단위 테스트 11개 (`test/features/exercise/exercise_calorie_estimator_test.dart`) — 빈 입력 / 부위계수 / set_type 필터 / 폴백 / 합산

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

### 헬스 사용자 UX 강화 (v9)
- [x] **세트 타입 구분** — 웜업/본세트/드롭/실패 4종 (C1, DB v9 `exercise_records.set_type`)
  - 볼륨 집계는 `work` + `drop` 만 포함 (`countsTowardVolume` getter)
  - `InlineSetInput` 좌측 드롭다운 (웜/본/드/실)
  - `ExerciseGroupCard` 세트 행에 타입 뱃지 (웜업=회색 아웃라인 / 드롭=코럴 채움 / 실패=코럴 필)
  - 헤더 볼륨 옆 "본세트 기준" 보조 라벨 (웜업/실패 있을 때만)
- [x] **종목별 진행 차트** (A2, `ExerciseProgressionSheet`)
  - 메트릭 3종 토글: 최고 무게 / e1RM (Epley, reps≤10) / 세션 볼륨
  - 기간 토글: 1개월 / 3개월 / 6개월
  - 요약 카드 (최고 기록·세션 수·평균 RPE) + 최근 10세션 리스트
  - 진입: `ExerciseGroupCard` 헤더 탭
- [x] **운동 달력 히트맵** (D1, `WorkoutHeatmapCard`)
  - 최근 13주 × 7일 GitHub 스타일
  - 본세트 볼륨 분위수(Q1/Q2/Q3+) 기반 4단계 색상
  - 셀 탭 → `selectedDateProvider` + `/exercise` 라우팅
  - 요약 탭 최상단 배치
- [x] **1RM 코치** 풀스크린 (`/exercise/coach/one-rm`, `OneRMCoachScreen`)
  - 종목 칩(최근 90일 볼륨 상위 8) + 메인 카드(권위 공식/Epley e1RM + 5주 추세 스파크라인 + 4주 전 대비 변화량)
  - ~~빠른 추정 스테퍼(중량 ±2.5kg / 횟수 ±1) + 입력 신뢰도 배지~~ — v12 정리에서 제거 (5주 max e1RM 과 중복)
  - **1RM 도전 가이드 카드** — 신호등(녹/황/적/회). "현재 능력으로 봤을 때 도전이 적절한 시점인지" 진단(트레이너 처방 X)<br/>   &nbsp;&nbsp;&nbsp;&nbsp;판단 입력: 5주 e1RM 추세 + 최근 7일 work 세트 수 + 최근 7일 RPE 평균 + 최근 14일 failure 세트 수
  - % of 1RM 환산표 (100~65%, 8행). e1RM 데이터가 없으면 안내 문구로 대체
  - **AI 코치 노트** (Gemini, 100자 이내, 처방·진단 금지) — `oneRmNote_{exercise}_{level}_{yyyymmdd}` SharedPreferences 캐시
  - 진입점 3곳: 운동 탭 AppBar `bolt` IconButton / `ExerciseGroupCard ⋯` 메뉴 / `ExerciseProgressionSheet` 하단 `1RM 코치 보기` 버튼 / 요약 탭 `RecentPrCard`
  - 데이터 부족(currentE1RM null) 케이스 처리 — 변화량 배지 숨김, 회색 신호등, "데이터 부족" 안내
  - DB 마이그레이션 불필요 (`exercise_records.weight, reps, set_type, timestamp, rpe` 만 사용)
- [x] **요약 탭 최근 PR 카드** (`RecentPrCard`) — 상위 3종목 e1RM + Δ, 행 탭 시 1RM 코치(해당 종목 선택) 진입

## 백로그 📋

> 우선순위 없음 — 추가할 때 항목 작성

- [x] 주간/월간 운동 볼륨 추세선 차트
- [x] 날짜별 식단 칼로리 히스토리 차트
- [x] 운동 기록 캘린더 뷰 (히트맵 형태로 구현, v9)
- [ ] 오프라인 모드 명시적 안내 (동기화 실패 시 배너)
- [x] 다크 모드 지원 (전수 정비 완료)
- [ ] 스트릭 시스템 (연속 기록 동기부여)
- [ ] 설정 화면에서 키 수정 기능 (온보딩 이후 변경)
- [ ] AI 인사이트 캐싱 (같은 날 데이터 변경 없으면 재호출 생략)
- [x] 개인 기록(PR) 카드 (요약 탭) — `RecentPrCard` 로 구현. 3대 운동 합산은 별도 항목으로 후속
- [ ] 원판 계산기 (플레이트 브레이크다운)
- [ ] 기본 운동 라이브러리 (30~50종 시드)

