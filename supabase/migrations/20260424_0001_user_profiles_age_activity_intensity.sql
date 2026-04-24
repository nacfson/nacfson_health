-- user_profiles 테이블에 만 나이(age) / 활동 수준(activity_level) / 운동 강도(training_intensity) 컬럼 추가.
--
-- SQLite 클라이언트 DB v10 마이그레이션과 1:1 대응. Supabase 측에서도 동일한 스키마를 유지해야
-- sync 업로드 시 컬럼 누락으로 insert/update 가 실패하지 않는다.
--
-- 이 파일은 idempotent — 재실행해도 안전.

ALTER TABLE public.user_profiles
  ADD COLUMN IF NOT EXISTS age INTEGER NOT NULL DEFAULT 30;

ALTER TABLE public.user_profiles
  ADD COLUMN IF NOT EXISTS activity_level TEXT NOT NULL DEFAULT 'moderate';

ALTER TABLE public.user_profiles
  ADD COLUMN IF NOT EXISTS training_intensity TEXT NOT NULL DEFAULT 'moderate';

-- age_group 컬럼이 존재하는 경우에만 백필/NULL 허용 전환을 수행 (신규 Supabase 프로젝트에서는 컬럼이 아예 없을 수 있음).
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'user_profiles'
      AND column_name = 'age_group'
  ) THEN
    UPDATE public.user_profiles SET age = 25 WHERE age_group = '20s'  AND age = 30;
    UPDATE public.user_profiles SET age = 35 WHERE age_group = '30s'  AND age = 30;
    UPDATE public.user_profiles SET age = 45 WHERE age_group = '40s'  AND age = 30;
    UPDATE public.user_profiles SET age = 55 WHERE age_group = '50s+' AND age = 30;
    -- age_group 컬럼은 곧바로 drop 하지 않고 한 릴리스간 호환을 위해 nullable 로 유지.
    ALTER TABLE public.user_profiles ALTER COLUMN age_group DROP NOT NULL;
  END IF;
END $$;

-- 레거시 goal 문자열 정리: 'lean_mass' → 'lean_gain' (하위 모드 2개로 분리된 이후 규칙).
UPDATE public.user_profiles SET goal = 'lean_gain' WHERE goal = 'lean_mass';
