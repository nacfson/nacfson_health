# 아키텍처 문서

> **문서 버전**: 2026-04-12  
> **범위**: 비즈니스 로직, 데이터 흐름, 데이터베이스 스키마

---

## 데이터 파이프라인 (3-Tier Architecture)

- **Input (입력 계층)**: 운동 기록(중량/횟수/RPE), 식단 기록(탄단지/만족도) 입력 UI
- **Process (비즈니스 로직 계층)**: 일일 목표 대비 초과/미달 계산, 부위별 볼륨 계산, 전역 상태 관리
- **Output (출력 계층)**: 진행률, 달성도, 점진적 과부하 추세선 등 시각화

---

## 도메인 분리 (3 Domains)

| 도메인 | 책임 | 엔티티 |
|--------|------|--------|
| **운동** | 날짜별 부위, 종목, 세트, 중량, RPE 누적 기록 및 추적 | `ExerciseRecord` |
| **식단** | 날짜별 식사 종류(아침, 점심, 저녁, 간식), 음식명, 매크로(탄/단/지), 만족도 기록 | `DietRecord` |
| **요약** | 두 데이터 병합 → 하루 목표 대비 현재 섭취량/운동 소비량 통합 표시 | `DailySummary` |

---

## 아키텍처 원칙

- **낮은 결합도**: UI는 데이터 소스(로컬 DB, 외부 API)를 모름
- **인터페이스 기반**: Repository 인터페이스로 데이터 접근을 추상화
- **상태 무결성**: 탭 전환 시 모든 다이얼로그/바텀시트를 닫는 `popAll` 정책으로 네비게이션 스택 유지
- **반응형 제약**: 데스크톱/웹 환경을 위해 바텀 시트 최대 너비 600px
- **방어적 개발**: 기존 코드 재사용 우선, 중복 구현 금지

---

## DB 스키마 (SQLite v2)

### 운동 레코드 (`exercise_records`)
| 필드 | 타입 | 설명 |
|------|------|------|
| `timestamp` | DateTime | 기록 생성/수정 시간 |
| `exercise_type` | String | 운동 종류 (예: 가슴, 등, 팔, 하체, 어깨, 코어) |
| `exercise_name` | String | 운동 이름 (예: 벤치프레스, 스쿼트) |
| `current_set` | int | 현재 세트 수 |
| `weight` | double | 사용중량 (kg) |
| `reps` | int | 반복 횟수 |
| `rpe` | double | 자각강도 (RPE, 1~10) |

> **CRUD**: Create(세트 추가), Read(세트 목록 조회), Update(중량/RPE 수정), Delete(세트 삭제)

### 식단 레코드 (`diet_records`)
| 필드 | 타입 | 설명 |
|------|------|------|
| `timestamp` | DateTime | 기록 생성/수정 시간 |
| `meal_type` | String | 식사 종류 (아침, 점심, 저녁, 간식) |
| `food_name` | String | 음식 종류/음식명 |
| `total_calories` | int | 총 칼로리 (kcal) |
| `carbs` | double | 탄수화물 (g) |
| `protein` | double | 단백질 (g) |
| `fat` | double | 지방 (g) |
| `satisfaction` | int | 만족도 (1~5) |
| `memo` | String? | 메모 (선택) |

> **CRUD**: Create(식사 기록 추가), Read(일일/주간 목록 조회), Update(매크로/만족도 수정), Delete(식사 기록 삭제)

### 요약 레코드 (`summary`)
날짜별 식단/영양 요약과 운동 퍼포먼스를 통합 표시

#### 1. 식단 및 영양 요약 (`diet_nutrition`)
| 필드 | 타입 | 설명 |
|------|------|------|
| `date` | DateTime | 요약 기준 날짜 |
| `consumedCalories` | int | 총 섭취 칼로리 (kcal) - 그날 모든 식사의 칼로리 합 |
| `targetCalories` | int | 목표 칼로리 (kcal) - 사용자 설정값 (예: 1800) |
| `macroStatus` | Map<String, MacroInfo> | 탄/단/지 각각의 섭취량 및 달성률 |

```dart
class MacroInfo {
  final double consumed;    // 현재 섭취량 (g)
  final double target;      // 목표량 (g)
  final double percentage;  // 달성률 (%)
}
```

| `calorieResult` | enum | 최종 상태 (달성\|초과\|미달) - UI 색상 처리용 |

> **UI 활용**: 프로그레스 바/원형 차트 그리기관용 `percentage`, 상태별 색상 (초과=빨강, 달성=초록, 미달=노랑)

#### 2. 운동 퍼포먼스 요약 (`workout_performance`)
| 필드 | 타입 | 설명 |
|------|------|------|
| `isWorkoutDay` | bool | 오늘 운동 여부 |
| `targetedMuscles` | List<String> | 오늘 자극한 부위 리스트 (예: `['등', '가슴']`) - 캘린더 Dot 표시용 |
| `totalVolume` | double | 총 운동 볼륨 (중량×횟수×세트의 총합, kg) |
| `averageRPE` | double | 오늘 수행한 모든 세트의 평균 자각강도 (1~10) |

> **UI 활용**: `targetedMuscles`로 캘린더에 점(Dot) 표기, `totalVolume`으로 "오늘 총 X kg 들어올림" 피드백, `averageRPE`로 훈련 강도 수치화