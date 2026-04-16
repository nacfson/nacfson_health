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

### Google Sheets 동기화
- [x] Google 계정 로그인 · 세션 복원 (`GoogleAuthService`)
- [x] 스프레드시트 자동 생성 + 필수 시트 보장 (`ensureAllRequiredSheets`)
- [x] 운동 기록 Push/Pull/HardDelete
- [x] 식단 기록 Push/Pull/HardDelete
- [x] 운동 템플릿 양방향 동기화 (Push/Pull/HardDelete)
- [x] 음식 템플릿 양방향 동기화 (Push/Pull/HardDelete, v4)
- [x] 체중 기록 양방향 동기화 (Push/Pull/HardDelete, v5)
- [x] 스프레드시트 교체 시 전체 재동기화 (`resetAllSyncStatus`)
- [x] 앱 포그라운드 전환 시 자동 동기화 (`AppLifecycleState.resumed`)

### UI/UX
- [x] `ErrorOverlay` — 자동 닫힘 오류 표시 (낮은 심각도)
- [x] Bottom Sheet 슬라이드/페이드 애니메이션 (`RecordFormSheet`)
- [x] 탭 전환 시 모든 오버레이 자동 닫기 (`popAll`)
- [x] `DietForm` — 음식 템플릿 드롭다운 + 자동 채움 (칼로리/탄단지 전체)
- [x] `ExerciseForm` — 운동 템플릿 드롭다운 + 종목명 자동 채움
- [x] `WeightScreen` — 체중 탭 (입력/차트 시각화)

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
10. docs 업데이트    db-schema.md + features.md + architecture.md
```

> 템플릿 계열 (`exercise_templates`, `food_templates`)은 `modified(2)` 없이 생성·삭제만,  
> Pull 병합은 insert-or-skip (LWW 불필요).  
> 레코드 계열 (`exercise_records`, `diet_records`, `weight_records`)은 전체 CRUD + LWW Pull.

---

## 백로그 📋

> 우선순위 없음 — 추가할 때 항목 작성

- [ ] 주간/월간 운동 볼륨 추세선 차트
- [ ] 날짜별 식단 칼로리 히스토리 차트
- [ ] 운동 기록 캘린더 뷰 (부위별 Dot 표시)
- [ ] 오프라인 모드 명시적 안내 (동기화 실패 시 배너)
- [ ] 다크 모드 지원
