# v5.1 변경 로그 (기존 데이터 정리 & 설정 UI 개선)

## 개요
v5에서 추가된 `exerciseType` 필드를 기반으로 기존 데이터를 정리하고, 설정 화면의 템플릿 리스트를 유형별로 그룹화하여 UI 가독성 개선.

---

## 데이터베이스 (v5 → v6)

### 마이그레이션
- `version: 5` → `version: 6`
- `_upgradeDB`에 추가:
  ```dart
  if (oldVersion < 6) {
    await db.execute("DELETE FROM exercise_templates WHERE exercise_type = ''");
  }
  ```

### 효과
- v5 마이그레이션 당시 기본값 `exercise_type = ''`로 설정된 기존 데이터 모두 삭제
- v6부터는 `exerciseType` 반드시 지정 (빈 문자열 불가)

### 파일
- `lib/core/database/database_helper.dart`: version 6, `_upgradeDB` 마이그레이션 추가

---

## 설정 화면 UI 개선

### 변경 사항
**파일**: `lib/features/settings/presentation/widgets/exercise_template_card.dart`

#### 이전 (v5)
```
[벤치프레스 [가슴]] [딥스 [가슴]] [데드리프트 [등]] [스쿼트 [하체]] ...
```
- 모든 템플릿이 Wrap으로 일렬 나열
- 유형 정보를 Chip 레이블에 포함

#### 신규 (v5.1)
```
가슴 ──────────────────────────
  [벤치프레스] [딥스]

등 ────────────────────────────
  [데드리프트] [풀업]

하체 ──────────────────────────
  [스쿼트]
```
- `_exerciseTypes` 순서를 기준으로 섹션 생성
- 각 섹션: `Row(Divider + 유형명 + Divider)` 헤더 + `Wrap(Chip)` 목록
- 동일 유형 템플릿이 한 섹션에 묶임
- 템플릿 이름만 표시 (유형 배지 제거)

#### 구현 세부
1. **그룹화 로직** (`_buildGroupedTemplates`)
   ```dart
   final grouped = <String, List<ExerciseTemplate>>{};
   for (final type in _exerciseTypes) {
     final list = templates.where((t) => t.exerciseType == type).toList();
     if (list.isNotEmpty) grouped[type] = list;
   }
   ```
   - 유형순 그룹화로 일관된 배치 보장
   - 빈 섹션 제거

2. **섹션 렌더링**
   - Divider 좌우 배치로 시각적 계층 표현
   - 각 섹션의 템플릿 Chip은 간결한 이름만 표시

3. **마이그레이션 데이터 처리**
   - `exerciseType = ''` 데이터 → "기타" 섹션 표시
   - v6 마이그레이션 후 자동 삭제됨

---

## 검증 체크리스트

- [x] Flutter analyze 통과 (경고 없음)
- [x] DB 마이그레이션 (v5 → v6)
- [x] 기존 `exerciseType = ''` 데이터 삭제 로직
- [x] 설정 화면 유형별 그룹 렌더링
- [x] 섹션 헤더 (Divider + 유형명) 표시
- [x] 동일 유형 템플릿 한 섹션에 묶임

---

## 관련 문서 업데이트

| 문서 | 변경 |
|------|------|
| `docs/db-schema.md` | v6 스키마 정보 추가 |
| `docs/ui-architecture.md` | ExerciseTemplateCard 유형별 그룹화 설명 추가 |
| `CLAUDE.md` | DB version 6 업데이트 |

---

## 브레이킹 체인지 ⚠️

없음. v5에서 v6으로 자동 마이그레이션 시 기존 데이터 자동 삭제.

---

## 다음 단계 (선택)

- [ ] 템플릿 검색 기능 추가 (유형별 필터 포함)
- [ ] 템플릿 수정 기능 추가 (현재는 생성·삭제만)
- [ ] 템플릿 즐겨찾기/순서 조정 기능
