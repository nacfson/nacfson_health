-- exercise_templates 테이블에 rest_seconds_override 컬럼 추가.
--
-- SQLite 클라이언트 DB v11 마이그레이션과 1:1 대응. 종목별 휴식 시간 오버라이드(초)로,
-- NULL 이면 클라이언트에서 부위 기본값을 적용한다. 유효 범위는 60 ~ 300.
--
-- 이 파일은 idempotent — 재실행해도 안전.

ALTER TABLE public.exercise_templates
  ADD COLUMN IF NOT EXISTS rest_seconds_override INTEGER;
