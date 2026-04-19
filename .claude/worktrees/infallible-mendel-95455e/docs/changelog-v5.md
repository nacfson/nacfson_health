# v5 변경 로그 (운동 템플릿 & UI 개선)

## 개요
운동 템플릿에 운동 유형 정보 추가, 입력 폼 UX 개선, 기록 화면 레이아웃 정렬.

---

## 데이터베이스 (v4 → v5)

### 마이그레이션
- `exercise_templates` 테이블에 `exercise_type TEXT NOT NULL DEFAULT ''` 컬럼 추가
- 기존 데이터: `exercise_type = ''` (빈 문자열)
- 이후 신규 템플릿: `exercise_type` 필수 입력

### 파일
- `lib/core/database/database_helper.dart`: version 5, `_upgradeDB` 마이그레이션 추가

---

## 엔티티 & 데이터 계층

### ExerciseTemplate
**파일**: `lib/features/settings/domain/entities/exercise_template.dart`

변경 사항:
```dart
class ExerciseTemplate {
  // ... 기존 필드들 ...
  final String exerciseType; // ✨ 신규: 운동 유형 (기본값 '')
  
  ExerciseTemplate({
    // ...
    this.exerciseType = '',
    // ...
  });
}
```

### Repository
**파일**: `lib/features/settings/data/repositories/sqlite_exercise_template_repository.dart`

```dart
// _toMap에 추가
'exercise_type': t.exerciseType,

// _fromMap에 추가
exerciseType: map['exercise_type'] as String? ?? '',
```

### Provider
**파일**: `lib/features/settings/presentation/providers/exercise_template_provider.dart`

```dart
// 시그니처 변경
Future<void> addTemplate(String name, String exerciseType) async {
  await _repository.add(ExerciseTemplate(
    uuid: '',
    name: name,
    exerciseType: exerciseType,  // ✨ 추가
    updatedAt: DateTime.now(),
  ));
  state = await _repository.getAll();
}
```

---

## 설정 화면 UI

### ExerciseTemplateCard
**파일**: `lib/features/settings/presentation/widgets/exercise_template_card.dart`

#### 변경 사항
1. **유형 선택 드롭다운 추가**
   - 상태 변수: `_selectedType` (String?)
   - 드롭다운: 8가지 운동 유형

2. **템플릿 Chip 업데이트**
   ```dart
   // 이전
   label: Text(template.name)
   
   // 신규 (v5)
   label: Text(
     template.exerciseType.isNotEmpty
         ? '${template.name} [${template.exerciseType}]'
         : template.name,
   )
   ```

3. **추가 검증**
   - 운동 이름 필수
   - 운동 유형 필수

---

## 운동 입력 폼 UX 재설계

### ExerciseForm
**파일**: `lib/features/exercise/presentation/widgets/exercise_form.dart`

#### 핵심 변경: 이름 먼저, 유형 나중

##### 직접 입력 모드 (기본)
```
[직접 입력 | 템플릿 선택] 토글

직접 입력:
  1️⃣ 운동 이름 (TextFormField)
  2️⃣ 운동 유형 (DropdownButtonFormField)
  3️⃣ 세트/중량/반복/RPE
```

##### 템플릿 선택 모드
```
템플릿 선택:
  1️⃣ 운동 유형 필터 ('전체' 포함)
  2️⃣ 해당 유형의 템플릿 목록
      └─ 선택 시 유형 자동 채움 ✨
  3️⃣ [선택된 유형] 배지 표시
  4️⃣ 세트/중량/반복/RPE
```

#### 상태 변수 변경
- `_isDirectInput` bool → `_useTemplate` bool (의미 역전)
- `_filterType` String? 추가 (유형 필터)
- `_selectedTemplate` ExerciseTemplate? 추가 (템플릿 선택 상태)

#### 폼 검증
```dart
String get _resolvedExerciseName {
  if (_useTemplate) return _selectedTemplate?.name ?? '';
  return _exerciseNameController.text.trim();
}

String get _resolvedExerciseType {
  if (_useTemplate) return _selectedTemplate?.exerciseType ?? '';
  return _directExerciseType ?? '';
}
```

---

## 운동 기록 화면 레이아웃

### Provider — 2레벨 그룹핑

**파일**: `lib/features/exercise/presentation/providers/exercise_provider.dart`

#### 변경
```dart
// 이전 (v4)
final todayExerciseGroupedProvider =
    Provider<Map<String, List<ExerciseRecord>>>((ref) {
  // exerciseType → [ExerciseRecord, ...]
});

// 신규 (v5)
final todayExerciseGroupedProvider =
    Provider<Map<String, Map<String, List<ExerciseRecord>>>>((ref) {
  // exerciseType → exerciseName → [ExerciseRecord, ...]
});
```

### ExerciseGroupCard (신규 위젯)

**파일**: `lib/features/exercise/presentation/widgets/exercise_record_card.dart`

#### 구조
```
┌─────────────────────────────────────┐
│ 💪 종목명              Vol 1,575kg  │ ← 헤더 (이름 + 총볼륨)
├─────────────────────────────────────┤
│ 1세트  100kg  5회  RPE 7.0  ▶      │ ← 탭 시 편집
│ 2세트  105kg  5회  RPE 8.0  ▶      │
│ 3세트  110kg  3회  RPE 9.0  ▶      │
└─────────────────────────────────────┘
```

#### 하위 컴포넌트
- `_SetRow`: 각 세트 행 (InkWell + 탭 이벤트)
- `_SetBadge`: 세트 번호 배지
- `_StatText`: 통계 텍스트 (중량, 반복 등)
- `_TypeIcon`: 유형 아이콘 (기존 색상/아이콘 매핑 유지)

---

### ExerciseScreen (레이아웃 업데이트)

**파일**: `lib/features/exercise/presentation/screens/exercise_screen.dart`

#### 변경 사항
1. **종목별 카드 그룹핑**
   - 같은 `exerciseName`의 세트들이 하나의 카드로 표시

2. **섹션 헤더 유지**
   ```
   ── 등 ─────────────────── (3세트)
   [데드리프트 카드]
   [풀업 카드]
   
   ── 하체 ───────────────── (2세트)
   [스쿼트 카드]
   ```

3. **세트 행 탭 → 편집**
   - 각 세트 행 탭 시 `ExerciseForm(initialRecord: record)` 바텀시트 오픈
   - 기존 개별 카드 삭제 UX → 행 탭으로 통합

---

## Google Sheets 동기화

### 시트 헤더 업데이트

**파일**: `lib/core/sync/google_sheets_service.dart`

#### exercise_templates 시트

**이전 (v4)**
```
A1:C1 헤더
uuid | name | updatedAt
```

**신규 (v5)**
```
A1:D1 헤더
uuid | name | exerciseType | updatedAt
```

#### 코드 변경
```dart
// headers 배열
['uuid', 'name', 'exerciseType', 'updatedAt']

// Range
'exercise_templates!A1:D1'
'exercise_templates!A2:D'

// batchPushTemplates
appendValues.add([
  t.uuid,
  t.name,
  t.exerciseType,  // ✨ 추가
  t.updatedAt.millisecondsSinceEpoch,
]);
```

#### 하위호환성
```dart
// _rowToTemplate: 구(3컬럼) 및 신(4컬럼) 포맷 모두 지원
final hasExerciseType = row.length >= 4;
exerciseType: hasExerciseType ? row[2].toString() : '',
updatedAt: DateTime.fromMillisecondsSinceEpoch(
    int.parse(row[hasExerciseType ? 3 : 2].toString())),
```

---

## 문서 업데이트

| 문서 | 변경 내용 |
|------|---------|
| `docs/db-schema.md` | v5 버전 추가, `exercise_templates` 스키마 업데이트, Sheets 헤더 범위 수정 |
| `docs/ui-architecture.md` | ExerciseForm v5 UX 추가, ExerciseGroupCard 설명, Provider 2레벨 그룹핑 |
| `docs/features.md` | 완료된 기능 목록 v5 항목 추가 |
| `CLAUDE.md` | v5 스키마 참조 |

---

## 검증 체크리스트

- [x] Flutter analyze 통과 (경고 없음)
- [x] DB 마이그레이션 (v4 → v5)
- [x] 템플릿 추가 시 유형 필수 선택
- [x] 템플릿 Chip에 유형 배지 표시
- [x] ExerciseForm 직접입력/템플릿 토글
- [x] 템플릿 선택 시 유형 필터 + 자동 채움
- [x] 기록 화면에서 같은 종목이 카드로 묶임
- [x] 세트 행 탭 → 편집 시트 오픈
- [x] Google Sheets 템플릿 헤더 4컬럼 (역호환성 포함)

---

## 브레이킹 체인지 ⚠️

없음. 기존 데이터는 자동 마이그레이션 (exerciseType = '').

---

## 다음 단계 (선택)

- [ ] 운동 템플릿 수정 기능 추가 (현재는 생성·삭제만)
- [ ] 템플릿 자동 정렬 (유형별 그룹핑)
- [ ] 운동 기록 필터링 UI (유형별/날짜별)
- [ ] Sheets 기존 데이터 마이그레이션 스크립트
