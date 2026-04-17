# 도메인 모듈 구조

> **문서 버전**: 2026-04  
> **범위**: 각 도메인의 핵심 기능과 관련 Provider 매핑

| 도메인 | 핵심 기능 | 관련 Provider |
|--------|----------|---------------|
| **exercise** | 운동 기록 (가슴/등... 순서 고정), 볼륨 계산 | `todayExerciseGroupedProvider`, `todayTotalVolumeProvider` |
| **diet** | 식단 기록, 매크로(탄/단/지) 관리 | `todayDietGroupedProvider`, `todayDietSummaryProvider` |
| **weight** | 체중 기록, 추세 시각화 (주/월/년 필터) | `latestWeightProvider`, `weightChartDataProvider`, `todayWeightProvider`, `chartViewTypeProvider` |
| **summary** | 일일 요약 (fl_chart 시각화) | `dailySummaryProvider` (목표치 참조) |
| **sync** | 구글 시트 동기화, Auth, 목표값 관리 | `syncStateProvider`, `nutritionTargetsProvider` |
| **settings** | 운동·음식 템플릿 관리 (SQLite + 시트 동기화) | `exerciseTemplatesProvider`, `foodTemplatesProvider` |
