# v7 변경 로그 — Google Sheets → Supabase 전환

> 작성: 2026-04  
> 관련 브랜치: `claude/fitness-app-analysis-Bjivj`

## 배경

v6까지의 동기화 백엔드는 Google Sheets API였다. 스프레드시트는 직관적이었지만 다음의 한계가 누적됨:

1. **스키마 경직** — 컬럼 추가 시 각 사용자 시트를 일괄 마이그레이션할 수단이 없음.
2. **Row 파싱 오버헤드** — A:Z 문자열 셀을 타입별 파싱하는 비용이 기록 수에 비례 증가.
3. **권한 모델 복잡성** — 스프레드시트 생성/공유/재발급 흐름이 사용자 혼동을 유발.
4. **LWW 충돌 해결** — updated_at 기반 LWW를 시트에서 견고하게 구현하기 어려움.

## 변경 요약

- **`googleapis`, `google_sign_in`, `extension_google_sign_in_as_googleapis_auth` 패키지 전면 제거.**
- **Supabase 전면 도입** (`supabase_flutter`, PostgreSQL 테이블):
  - `exercise_records`, `diet_records`, `weight_records`, `exercise_templates`, `food_templates`, `workout_routines`
  - `is_deleted` 컬럼으로 soft-delete 표현
  - `user_id`로 사용자별 격리 (RLS 정책)
- **`GoogleAuthService`는 이름 유지**하되 Supabase OAuth 래퍼로 내부 전환. 향후 `SupabaseAuthService`로 리네임 고려.
- **`SpreadsheetStatusCard`** 위젯 이름 유지(설정 카드) — 향후 `SupabaseStatusCard`로 리네임 고려.
- **`SupabaseService.ensureAllRequiredSheets()` 는 no-op** — Supabase 테이블은 서버 측에서 관리. 호출 경로는 legacy 호환 유지.

## 현재 아키텍처 (v7 이후)

```
UI ↔ Riverpod Provider ↔ Repository(인터페이스)
                              ↓
                         Sqlite<X>Repository (로컬 캐시)
                              ↕
                         SupabaseService (batchPush* / read*Delta)
                              ↕
                         Supabase PostgreSQL
```

- **Push**: `syncStatus != synced` 인 로컬 레코드를 upsert (`onConflict: 'uuid'`).
- **Pull**: 마지막 동기화 이후의 delta를 `updated_at >= lastSyncAt` 로 조회.
- **LWW**: 로컬·리모트 모두 있는 uuid는 `updated_at` 비교로 최신 승리.
- **HardDelete**: `syncStatus == deleted` 이고 push 성공한 레코드는 로컬 DB에서 실제 삭제.

## v9 Supabase 운영 체크리스트 (set_type 컬럼 추가)

DB v9에서 로컬 `exercise_records.set_type` 컬럼이 신설되었으므로, **Supabase 대시보드에서 원격 테이블도 동일 컬럼을 수동 ALTER**해야 한다:

```sql
ALTER TABLE public.exercise_records
ADD COLUMN IF NOT EXISTS set_type text NOT NULL DEFAULT 'work';
```

- 대시보드 → Database → Tables → `exercise_records` → Add column (`text`, NOT NULL, default `'work'`).
- ALTER 이전에 배포된 앱 버전이 push하면 RPC 측에서 에러가 날 수 있으므로, **컬럼 ALTER를 배포보다 먼저** 수행한다.
- 기존 row는 DEFAULT로 전부 `'work'` 가 되며 이는 의도된 동작(과거 데이터는 본세트로 간주).
- `SupabaseService.batchPushExerciseRecords` 의 row 맵에 `'set_type': r.setType.value` 가 추가됨.
- `SupabaseService._rowToExerciseRecord` 는 `SetType.fromString(row['set_type'] as String?)` 로 legacy row(컬럼 없음)도 안전히 `work` 로 fallback.

## 문서 정리 노트

v6 시절 작성된 다음 서술은 본 changelog 작성 시점까지 갱신이 누락되어 있었으며, v9 브랜치에서 함께 정정됨:

- `CLAUDE.md` L8 스택 표기 (`googleapis` → `supabase_flutter`)
- `CLAUDE.md` L12 데이터 흐름 ("Google Sheets API" → "Supabase API")
- `docs/features.md` L57-67 "Google Sheets 동기화" 섹션 (→ "Supabase 동기화")
- `docs/db-schema.md` 버전 이력에 v7 설명 추가

## 잔여 작업 (백로그)

- [ ] `GoogleAuthService` → `SupabaseAuthService` 리네임 (호출자 다수, 신중히)
- [ ] `SpreadsheetStatusCard` → `SupabaseStatusCard` 리네임 (UX 혼동 방지)
- [ ] `SupabaseService.ensureAllRequiredSheets()` no-op 함수 제거 (호출자 정리 후)
- [ ] 오프라인 모드 명시 배너 (features.md 백로그)

---

## 7.x — Contextual Coach Chatbot 도입 (2026-04)

> 관련 브랜치: `claude/chatbot-conversion-planning-al8WD`  
> 관련 리서치: Exerbot 2025 (88% DAU), JMIR 2024 하이브리드 챗봇 권고

### 변경 요약

- **단발 인사이트 카드 → 컨텍스트 챗봇 하이브리드** 전환.
- 기존 `_AiInsightCard` 는 그대로 유지(자동 생성 한줄 인사이트)하되, 카드 하단에 "💬 코치에게 더 물어보기" CTA 추가.
- CTA 탭 시 **하단 모달 시트(90% 높이)** 에서 자유 질의 응답 + 컨텍스트 추천 칩 노출.

### 모델/예산 정책

| 호출 종류 | 모델 | 일일 한도 | 캐시/방어 |
|---|---|---|---|
| 자동 인사이트 카드 | `gemini-2.5-flash-lite` | **무제한** | 데이터 해시 캐시 + UI 60초 디바운스 |
| 코치 챗봇 | `gemini-2.5-flash` | **30회/일** (메시지 기준) | follow_ups 같은 JSON에 포함 (추가 호출 0) |
| 음식 Vision | `gemini-2.5-flash` | 5회/일 (변경 없음) | sha256 해시 캐시 |

### 신규 / 수정 파일

- `lib/core/ai/coach_chat_models.dart` — `ChatRole`, `ChatMessage`, `CoachReply`, `HealthContext`, `SuggestedPrompt`, `PromptCategory`, `SuggestedPromptKind`
- `lib/core/ai/gemini_service.dart` — `_chatModel` (`gemini-2.5-flash`, JSON 모드) + `coachChat()` 메서드
- `lib/core/ai/health_insight_provider.dart` — 일일 제한 제거, 데이터 해시 기반 캐시 키, 60초 디바운스 providers 추가
- `lib/core/ai/suggested_prompts_provider.dart` — **신규**, 20+ 규칙 플러그인 구조 (`_PromptRule`), `evaluateSuggestedPrompts` pure function
- `lib/core/ai/coach_chat_notifier.dart` — **신규**, `CoachChatNotifier` (autoDispose), `CoachChatCallCountNotifier` (일일 30회 한도, 자정 자동 리셋)
- `lib/features/summary/presentation/widgets/chat_message_bubble.dart` — **신규**, user/assistant 버블
- `lib/features/summary/presentation/widgets/suggested_prompt_chip.dart` — **신규**, `ActionChip` + `FollowUpChip` (카테고리 아이콘)
- `lib/features/summary/presentation/widgets/coach_chat_sheet.dart` — **신규**, 모달 시트 + 빈 상태 + 대화 리스트 + 입력창
- `lib/features/summary/presentation/screens/summary_screen.dart` — `_AiInsightCard` 에 디바운스 카운트다운 라벨 + CTA 추가
- `lib/main.dart` — `InsightCallCountNotifier` pre-load/override 제거
- `test/core/ai/suggested_prompts_test.dart` — **신규**, 규칙 평가 & 랭킹 단위 테스트

### 규칙 카테고리 (총 23개 규칙)

| 카테고리 | 대표 규칙 |
|---|---|
| 🍱 식단 | `diet.missing_today`(navigation), `diet.cal_over`, `diet.cal_under`(저녁), `diet.repetitive` |
| 🥗 매크로 | `macro.protein_low`, `macro.protein_high`, `macro.carb_low`(운동일), `macro.fat_high` |
| 💪 운동 | `workout.volume_drop`, `workout.same_muscle_3d`, `workout.rpe_high/low`, `workout.rest_day_long`, `workout.today_missing` |
| ⚖️ 체중 | `weight.weekly_gain/loss`, `weight.plateau`, `weight.high_variance`, `weight.no_record_3d` |
| 🔥 동기부여 | `motivation.streak_7d`, `motivation.weekly_review` (일요일 저녁) |
| ⏰ 시간대 | `time.morning_plan` (06~09시 & 식단 0), `time.late_night_craving` (22시+ & 칼로리 초과) |

### 랭킹 알고리즘

1. priority 내림차순 정렬
2. 카테고리 다양성: 같은 카테고리가 3개 연속 나오지 않도록 round-robin 끼워넣기
3. 최대 5개 선별
4. 어떤 규칙도 매칭 안 되면 fallback 3개 (`오늘 내 하루 건강 총평` / `이번 주 운동 개선 포인트` / `지금 먹으면 좋은 간식 추천`)

### UX 원칙

- **첫 진입 시 자동 인사 없음** — 추천 칩만 노출 → API 비용 절약
- **Follow-up = 같은 응답 JSON** — 대화 이어가기도 API 비용 0 추가
- **autoDispose 로 세션 휘발** — 히스토리는 메모리에만, 시트 닫으면 초기화
- **네비게이션 타입 칩** (`diet.missing_today`) 은 Gemini 호출 없이 `context.go('/diet')` 로 이동
