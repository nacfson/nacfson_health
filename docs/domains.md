# 도메인 모듈 구조

> **문서 버전**: 2026-04  
> **범위**: 각 도메인의 핵심 기능과 관련 Provider 매핑

| 도메인 | 핵심 기능 | 관련 Provider |
|--------|----------|---------------|
| **exercise** | 운동 기록 (가슴/등... 순서 고정), 볼륨 계산(weight × reps), 루틴 플래너(오늘+프리셋), 인라인 세트 입력, 휴식 타이머 (인앱 + iOS Live Activity + Android 알림) | `todayExerciseGroupedProvider`, `todayExerciseCardsProvider`, `todayTotalVolumeProvider`, `routinePlannerProvider`, `workoutRoutinesProvider`, `latestSetOfTodayProvider`, `restTimerProvider`, `defaultRestSecondsProvider`, `restNotificationServiceProvider` |
| **diet** | 식단 기록, 매크로(탄/단/지) 관리 | `todayDietGroupedProvider`, `todayDietSummaryProvider` |
| **weight** | 체중 기록, 추세 시각화 (주/월/년 필터) | `latestWeightProvider`, `weightChartDataProvider`, `todayWeightProvider`, `chartViewTypeProvider` |
| **summary** | 일일 요약 (fl_chart 시각화) | `dailySummaryProvider` (목표치 참조) |
| **sync** | 구글 시트 동기화, Auth, 목표값 관리 | `syncStateProvider`, `nutritionTargetsProvider` |
| **settings** | 운동·음식 템플릿 관리 (SQLite + 시트 동기화), 기록 폼에서는 `shared/widgets/template_picker_sheet.dart`로 공통 피커 호출 | `exerciseTemplatesProvider`, `foodTemplatesProvider` |
| **theme** | 다크/라이트/시스템 모드 전환 (shared_preferences 영구 저장) | `themeModeProvider` (`ThemeModeNotifier`) |
| **onboarding** | 첫 실행 키/체중 입력 + 라우팅 게이트 (`refreshListenable`) | `onboardingDoneProvider`, `heightMProvider` |
| **ai** | Gemini 기반 건강 인사이트 + 코치 챗봇 (데이터 해시 캐시 + 60초 디바운스 + 세션 휘발 챗) | `healthInsightProvider`, `insightCacheProvider`, `insightLastRefreshAtProvider`, `insightCanRefreshProvider`, `suggestedPromptsProvider`, `coachChatProvider`, `coachChatCallCountProvider`, `foodVisionAnalysisProvider` |
