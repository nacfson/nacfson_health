# CLAUDE.md

이 문서는 AI 어시스턴트가 본 레포지토리의 코드를 작성하고 수정할 때 반드시 준수해야 하는 핵심 컨텍스트와 규칙입니다.

## 프로젝트 요약

- **목표**: 구글 폼/시트 대체 개인 맞춤형 피트니스 & 식단 통합 대시보드
- **스택**: Flutter, Dart, Riverpod (StateNotifier+Provider), go_router (ShellRoute), sqflite, googleapis
- **DB 버전**: v7 (테이블 6개: exercise_records · diet_records · exercise_templates · food_templates · weight_records · user_profiles)
- **탭 구조**: 운동 | 식단 | 체중 | 요약 | 설정
- **UX 원칙**: 폼보다 빠른 입력, 시트보다 직관적인 결과 시각화
- **데이터 흐름**: UI → Provider(StateNotifier) → Repository(Interface) → SQLite(구현체) ↔ SyncService ↔ Google Sheets API

## Task Routing (반드시 준수할 것)

작업의 종류에 따라 코드를 수정하기 전 아래의 연관 문서를 반드시 먼저 읽고 지시사항을 따르세요.

- **아키텍처, 데이터 흐름, 동기화 로직 수정 시**: `docs/architecture.md`
- **DB 테이블/컬럼 변경, 마이그레이션 작성 시**: `docs/db-schema.md`
- **UI 위젯/레이아웃/네비게이션 수정 시**: `docs/ui-architecture.md`
- **도메인 모듈(exercise/diet/weight/sync/settings) 수정 시**: `docs/domains.md`
- **에러 처리, try/catch 패턴 작성 시**: `docs/error-handling.md`
- **기능 완료/백로그 업데이트 시**: `docs/features.md`
- **새 도메인/테이블 추가 시**: `docs/implementation-guide.md`
- **코딩 컨벤션, 네이밍 규칙 확인 시**: `docs/conventions.md`
- **빌드 오류, 런타임 크래시, 프리뷰 실행 문제 발생 시**: `docs/build-debug.md`
- **StateNotifier 초기화, GoRouter redirect, dispose() ref 사용 시**: `docs/build-debug.md`

## 문서 업데이트 의무

- 기능 추가/변경 시 관련 문서를 즉시 동기화할 것.
- DB 테이블 변경 → `docs/db-schema.md` 업데이트 필수.
- 기능 완료 → `docs/features.md` 체크박스 반영 필수.
- 실수 발생 시 → 관련 docs 가이드라인에 하네스 프롬프트 추가.

## 참조 문서 목록

| 문서 | 설명 |
|------|------|
| `docs/architecture.md` | 동기화 프로토콜, 도메인 분리 구조, 데이터 흐름 |
| `docs/db-schema.md` | DB 버전 이력, 전체 테이블 스키마, 마이그레이션 SQL |
| `docs/ui-architecture.md` | 위젯 계층도, 네비게이션 구조, 애니메이션 |
| `docs/domains.md` | 도메인 모듈별 책임과 Provider 매핑 |
| `docs/error-handling.md` | 심각도별 예외 처리 전략, 금지사항 |
| `docs/features.md` | 구현 완료 기능 체크리스트, 백로그 |
| `docs/implementation-guide.md` | 새 도메인 추가 10단계, UUID/SyncStatus 규칙 |
| `docs/conventions.md` | 코딩 컨벤션, 네이밍, 테마, UI 규칙 |
| `docs/changelog-v5.md` | v5 변경 로그 (운동 템플릿 & UI 개선) |
| `docs/changelog-v5-1.md` | v5.1 변경 로그 (기존 데이터 정리 & 설정 UI 개선) |
| `docs/changelog-v6.md` | v6 변경 로그 (DB v7, AI 인사이트, 온보딩, 다크 모드, Pretendard) |
| `docs/build-debug.md` | 빌드 타겟, Riverpod 초기화, GoRouter, dispose, macOS 포커스, Gemini 디버깅 |