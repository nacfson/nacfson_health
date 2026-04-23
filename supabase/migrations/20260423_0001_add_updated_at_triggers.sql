-- Supabase 서버측 updated_at 자동 갱신 트리거.
--
-- Delta sync(`updated_at > lastSync`)가 외부 SQL 경로로 일어난 UPDATE 도 확실히
-- 포착하도록, sync 대상 테이블 전부에 BEFORE UPDATE 트리거를 설치한다.
-- 트리거가 없으면 Supabase Studio 또는 관리 스크립트에서 값만 수정하고
-- `updated_at` 을 건드리지 않은 변경이 다른 기기로 전파되지 않는 silent drift 가 발생한다.
--
-- 이 파일은 idempotent — 재실행해도 안전.

CREATE EXTENSION IF NOT EXISTS moddatetime SCHEMA extensions;

DO $$
DECLARE
  t text;
  tables text[] := ARRAY[
    'exercise_records',
    'diet_records',
    'weight_records',
    'exercise_templates',
    'food_templates',
    'workout_routines'
  ];
BEGIN
  FOREACH t IN ARRAY tables LOOP
    EXECUTE format($f$
      DROP TRIGGER IF EXISTS set_updated_at ON public.%I;
      CREATE TRIGGER set_updated_at
        BEFORE UPDATE ON public.%I
        FOR EACH ROW EXECUTE FUNCTION extensions.moddatetime(updated_at);
    $f$, t, t);
  END LOOP;
END $$;
