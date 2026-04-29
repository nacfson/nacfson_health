-- ============================================================================
-- v12: 다국어 지원 master 운동 데이터 + 1RM 공식 테이블
-- ============================================================================
-- 1) exercise_categories            : 카테고리 마스터 (admin-curated)
-- 2) exercise_category_translations : 카테고리 ko/en 표시명
-- 3) exercise_definitions           : 운동 정의 (admin-curated, exercise_key PK)
-- 4) exercise_translations          : 운동 ko/en 표시명 + 별칭
-- 5) one_rm_formulas                : 종목별 1RM 공식 (admin-curated)
--
-- RLS: 인증 사용자 read-only. write 정책 미부여 (Supabase Studio 직접 수정).
-- ============================================================================

-- ============================================================================
-- 1) 테이블 정의
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.exercise_categories (
  category_key TEXT PRIMARY KEY,
  display_order INT NOT NULL DEFAULT 0,
  updated_at TIMESTAMPTZ DEFAULT now(),
  is_deleted BOOLEAN DEFAULT FALSE
);

CREATE TABLE IF NOT EXISTS public.exercise_category_translations (
  category_key TEXT NOT NULL REFERENCES public.exercise_categories(category_key) ON DELETE CASCADE,
  locale TEXT NOT NULL,
  display_name TEXT NOT NULL,
  updated_at TIMESTAMPTZ DEFAULT now(),
  PRIMARY KEY (category_key, locale)
);

CREATE TABLE IF NOT EXISTS public.exercise_definitions (
  exercise_key TEXT PRIMARY KEY,
  category_key TEXT NOT NULL REFERENCES public.exercise_categories(category_key),
  is_compound BOOLEAN DEFAULT FALSE,
  default_name TEXT NOT NULL,
  updated_at TIMESTAMPTZ DEFAULT now(),
  is_deleted BOOLEAN DEFAULT FALSE
);

CREATE TABLE IF NOT EXISTS public.exercise_translations (
  exercise_key TEXT NOT NULL REFERENCES public.exercise_definitions(exercise_key) ON DELETE CASCADE,
  locale TEXT NOT NULL,
  display_name TEXT NOT NULL,
  aliases TEXT[],
  updated_at TIMESTAMPTZ DEFAULT now(),
  PRIMARY KEY (exercise_key, locale)
);

CREATE TABLE IF NOT EXISTS public.one_rm_formulas (
  exercise_key TEXT PRIMARY KEY REFERENCES public.exercise_definitions(exercise_key) ON DELETE CASCADE,
  formula_type TEXT NOT NULL CHECK (formula_type IN ('epley','linear','exponential','polynomial')),
  coefficients JSONB NOT NULL,
  source TEXT,
  optimal_rep_max INT,
  notice_translations JSONB,
  updated_at TIMESTAMPTZ DEFAULT now(),
  is_deleted BOOLEAN DEFAULT FALSE
);

CREATE INDEX IF NOT EXISTS idx_exercise_definitions_category ON public.exercise_definitions(category_key);
CREATE INDEX IF NOT EXISTS idx_exercise_translations_locale ON public.exercise_translations(locale);

-- ============================================================================
-- 2) updated_at 자동 갱신 트리거
-- ============================================================================

DROP TRIGGER IF EXISTS set_updated_at_exercise_definitions ON public.exercise_definitions;
CREATE TRIGGER set_updated_at_exercise_definitions
  BEFORE UPDATE ON public.exercise_definitions
  FOR EACH ROW EXECUTE FUNCTION extensions.moddatetime(updated_at);

DROP TRIGGER IF EXISTS set_updated_at_exercise_translations ON public.exercise_translations;
CREATE TRIGGER set_updated_at_exercise_translations
  BEFORE UPDATE ON public.exercise_translations
  FOR EACH ROW EXECUTE FUNCTION extensions.moddatetime(updated_at);

DROP TRIGGER IF EXISTS set_updated_at_exercise_categories ON public.exercise_categories;
CREATE TRIGGER set_updated_at_exercise_categories
  BEFORE UPDATE ON public.exercise_categories
  FOR EACH ROW EXECUTE FUNCTION extensions.moddatetime(updated_at);

DROP TRIGGER IF EXISTS set_updated_at_exercise_category_translations ON public.exercise_category_translations;
CREATE TRIGGER set_updated_at_exercise_category_translations
  BEFORE UPDATE ON public.exercise_category_translations
  FOR EACH ROW EXECUTE FUNCTION extensions.moddatetime(updated_at);

DROP TRIGGER IF EXISTS set_updated_at_one_rm_formulas ON public.one_rm_formulas;
CREATE TRIGGER set_updated_at_one_rm_formulas
  BEFORE UPDATE ON public.one_rm_formulas
  FOR EACH ROW EXECUTE FUNCTION extensions.moddatetime(updated_at);

-- ============================================================================
-- 3) RLS — read-all (authenticated), write 정책 미부여
-- ============================================================================

ALTER TABLE public.exercise_categories ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.exercise_category_translations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.exercise_definitions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.exercise_translations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.one_rm_formulas ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "read all" ON public.exercise_categories;
CREATE POLICY "read all" ON public.exercise_categories FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS "read all" ON public.exercise_category_translations;
CREATE POLICY "read all" ON public.exercise_category_translations FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS "read all" ON public.exercise_definitions;
CREATE POLICY "read all" ON public.exercise_definitions FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS "read all" ON public.exercise_translations;
CREATE POLICY "read all" ON public.exercise_translations FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS "read all" ON public.one_rm_formulas;
CREATE POLICY "read all" ON public.one_rm_formulas FOR SELECT TO authenticated USING (true);

-- ============================================================================
-- 4) Seed: exercise_categories (11)
-- ============================================================================

INSERT INTO public.exercise_categories (category_key, display_order) VALUES
  ('chest',     1),
  ('back',      2),
  ('legs',      3),
  ('glutes',    4),
  ('calves',    5),
  ('shoulders', 6),
  ('biceps',    7),
  ('triceps',   8),
  ('forearms',  9),
  ('core',     10),
  ('olympic',  11)
ON CONFLICT (category_key) DO NOTHING;

-- ============================================================================
-- 5) Seed: exercise_category_translations (ko + en)
-- ============================================================================

INSERT INTO public.exercise_category_translations (category_key, locale, display_name) VALUES
  ('chest',     'ko', '가슴'),       ('chest',     'en', 'Chest'),
  ('back',      'ko', '등'),         ('back',      'en', 'Back'),
  ('legs',      'ko', '하체'),       ('legs',      'en', 'Legs'),
  ('glutes',    'ko', '둔근'),       ('glutes',    'en', 'Glutes'),
  ('calves',    'ko', '종아리'),     ('calves',    'en', 'Calves'),
  ('shoulders', 'ko', '어깨'),       ('shoulders', 'en', 'Shoulders'),
  ('biceps',    'ko', '이두'),       ('biceps',    'en', 'Biceps'),
  ('triceps',   'ko', '삼두'),       ('triceps',   'en', 'Triceps'),
  ('forearms',  'ko', '전완'),       ('forearms',  'en', 'Forearms'),
  ('core',      'ko', '코어'),       ('core',      'en', 'Core'),
  ('olympic',   'ko', '올림픽 리프팅'), ('olympic',   'en', 'Olympic Lifting')
ON CONFLICT (category_key, locale) DO NOTHING;

-- ============================================================================
-- 6) Seed: exercise_definitions + exercise_translations (~158 종목)
-- ============================================================================
-- 형식: (exercise_key, category_key, is_compound, default_name)
-- + 각 종목당 ko/en translation 행 2개

-- ─── CHEST (18) ───────────────────────────────────────────────────────────
INSERT INTO public.exercise_definitions (exercise_key, category_key, is_compound, default_name) VALUES
  ('bench_press',              'chest', TRUE,  'Bench Press'),
  ('incline_bench_press',      'chest', TRUE,  'Incline Bench Press'),
  ('decline_bench_press',      'chest', TRUE,  'Decline Bench Press'),
  ('dumbbell_bench_press',     'chest', TRUE,  'Dumbbell Bench Press'),
  ('incline_dumbbell_press',   'chest', TRUE,  'Incline Dumbbell Press'),
  ('decline_dumbbell_press',   'chest', TRUE,  'Decline Dumbbell Press'),
  ('machine_chest_press',      'chest', TRUE,  'Machine Chest Press'),
  ('smith_bench_press',        'chest', TRUE,  'Smith Machine Bench Press'),
  ('chest_dip',                'chest', TRUE,  'Chest Dip'),
  ('push_up',                  'chest', TRUE,  'Push-Up'),
  ('incline_push_up',          'chest', TRUE,  'Incline Push-Up'),
  ('decline_push_up',          'chest', TRUE,  'Decline Push-Up'),
  ('dumbbell_fly',             'chest', FALSE, 'Dumbbell Fly'),
  ('incline_dumbbell_fly',     'chest', FALSE, 'Incline Dumbbell Fly'),
  ('cable_crossover',          'chest', FALSE, 'Cable Crossover'),
  ('cable_fly',                'chest', FALSE, 'Cable Fly'),
  ('pec_deck_fly',             'chest', FALSE, 'Pec Deck Fly'),
  ('machine_fly',              'chest', FALSE, 'Machine Fly')
ON CONFLICT (exercise_key) DO NOTHING;

INSERT INTO public.exercise_translations (exercise_key, locale, display_name, aliases) VALUES
  ('bench_press',              'ko', '벤치프레스',                   ARRAY['벤프']),
  ('bench_press',              'en', 'Bench Press',                  ARRAY['BP','Flat Bench']),
  ('incline_bench_press',      'ko', '인클라인 벤치프레스',           ARRAY['인벤']),
  ('incline_bench_press',      'en', 'Incline Bench Press',          ARRAY['Incline BP']),
  ('decline_bench_press',      'ko', '디클라인 벤치프레스',           NULL),
  ('decline_bench_press',      'en', 'Decline Bench Press',          NULL),
  ('dumbbell_bench_press',     'ko', '덤벨 벤치프레스',               ARRAY['덤벤']),
  ('dumbbell_bench_press',     'en', 'Dumbbell Bench Press',         ARRAY['DB Bench']),
  ('incline_dumbbell_press',   'ko', '인클라인 덤벨 프레스',          NULL),
  ('incline_dumbbell_press',   'en', 'Incline Dumbbell Press',       NULL),
  ('decline_dumbbell_press',   'ko', '디클라인 덤벨 프레스',          NULL),
  ('decline_dumbbell_press',   'en', 'Decline Dumbbell Press',       NULL),
  ('machine_chest_press',      'ko', '체스트 프레스',                 ARRAY['머신 체스트']),
  ('machine_chest_press',      'en', 'Machine Chest Press',          NULL),
  ('smith_bench_press',        'ko', '스미스 벤치프레스',             NULL),
  ('smith_bench_press',        'en', 'Smith Machine Bench Press',    NULL),
  ('chest_dip',                'ko', '체스트 딥스',                   NULL),
  ('chest_dip',                'en', 'Chest Dip',                    NULL),
  ('push_up',                  'ko', '푸쉬업',                       ARRAY['팔굽혀펴기']),
  ('push_up',                  'en', 'Push-Up',                      ARRAY['Pushup']),
  ('incline_push_up',          'ko', '인클라인 푸쉬업',               NULL),
  ('incline_push_up',          'en', 'Incline Push-Up',              NULL),
  ('decline_push_up',          'ko', '디클라인 푸쉬업',               NULL),
  ('decline_push_up',          'en', 'Decline Push-Up',              NULL),
  ('dumbbell_fly',             'ko', '덤벨 플라이',                   NULL),
  ('dumbbell_fly',             'en', 'Dumbbell Fly',                 NULL),
  ('incline_dumbbell_fly',     'ko', '인클라인 덤벨 플라이',          NULL),
  ('incline_dumbbell_fly',     'en', 'Incline Dumbbell Fly',         NULL),
  ('cable_crossover',          'ko', '케이블 크로스오버',             NULL),
  ('cable_crossover',          'en', 'Cable Crossover',              NULL),
  ('cable_fly',                'ko', '케이블 플라이',                 NULL),
  ('cable_fly',                'en', 'Cable Fly',                    NULL),
  ('pec_deck_fly',             'ko', '펙덱 플라이',                   ARRAY['머신 플라이']),
  ('pec_deck_fly',             'en', 'Pec Deck Fly',                 NULL),
  ('machine_fly',              'ko', '머신 플라이',                   NULL),
  ('machine_fly',              'en', 'Machine Fly',                  NULL)
ON CONFLICT (exercise_key, locale) DO NOTHING;

-- ─── BACK (26) ────────────────────────────────────────────────────────────
INSERT INTO public.exercise_definitions (exercise_key, category_key, is_compound, default_name) VALUES
  ('pull_up',              'back', TRUE,  'Pull-Up'),
  ('chin_up',              'back', TRUE,  'Chin-Up'),
  ('wide_grip_pull_up',    'back', TRUE,  'Wide Grip Pull-Up'),
  ('lat_pulldown',         'back', TRUE,  'Lat Pulldown'),
  ('close_grip_lat_pulldown','back',TRUE, 'Close Grip Lat Pulldown'),
  ('reverse_grip_lat_pulldown','back',TRUE,'Reverse Grip Lat Pulldown'),
  ('barbell_row',          'back', TRUE,  'Barbell Row'),
  ('pendlay_row',          'back', TRUE,  'Pendlay Row'),
  ('t_bar_row',            'back', TRUE,  'T-Bar Row'),
  ('dumbbell_row',         'back', TRUE,  'Dumbbell Row'),
  ('seated_row',           'back', TRUE,  'Seated Row'),
  ('cable_row',            'back', TRUE,  'Cable Row'),
  ('machine_row',          'back', TRUE,  'Machine Row'),
  ('inverted_row',         'back', TRUE,  'Inverted Row'),
  ('deadlift',             'back', TRUE,  'Deadlift'),
  ('sumo_deadlift',        'back', TRUE,  'Sumo Deadlift'),
  ('romanian_deadlift',    'back', TRUE,  'Romanian Deadlift'),
  ('stiff_leg_deadlift',   'back', TRUE,  'Stiff-Leg Deadlift'),
  ('trap_bar_deadlift',    'back', TRUE,  'Trap Bar Deadlift'),
  ('rack_pull',            'back', TRUE,  'Rack Pull'),
  ('snatch_grip_deadlift', 'back', TRUE,  'Snatch Grip Deadlift'),
  ('good_morning',         'back', TRUE,  'Good Morning'),
  ('back_extension',       'back', FALSE, 'Back Extension'),
  ('hyperextension',       'back', FALSE, 'Hyperextension'),
  ('reverse_hyperextension','back',FALSE, 'Reverse Hyperextension'),
  ('face_pull',            'back', FALSE, 'Face Pull'),
  ('shrug',                'back', FALSE, 'Shrug'),
  ('dumbbell_shrug',       'back', FALSE, 'Dumbbell Shrug')
ON CONFLICT (exercise_key) DO NOTHING;

INSERT INTO public.exercise_translations (exercise_key, locale, display_name, aliases) VALUES
  ('pull_up',              'ko', '풀업',                  ARRAY['턱걸이']),
  ('pull_up',              'en', 'Pull-Up',               NULL),
  ('chin_up',              'ko', '친업',                  NULL),
  ('chin_up',              'en', 'Chin-Up',               NULL),
  ('wide_grip_pull_up',    'ko', '와이드 그립 풀업',      NULL),
  ('wide_grip_pull_up',    'en', 'Wide Grip Pull-Up',     NULL),
  ('lat_pulldown',         'ko', '랫 풀다운',             ARRAY['랫풀']),
  ('lat_pulldown',         'en', 'Lat Pulldown',          NULL),
  ('close_grip_lat_pulldown','ko','클로즈 그립 랫 풀다운', NULL),
  ('close_grip_lat_pulldown','en','Close Grip Lat Pulldown',NULL),
  ('reverse_grip_lat_pulldown','ko','리버스 그립 랫 풀다운',NULL),
  ('reverse_grip_lat_pulldown','en','Reverse Grip Lat Pulldown',NULL),
  ('barbell_row',          'ko', '바벨 로우',             NULL),
  ('barbell_row',          'en', 'Barbell Row',           ARRAY['Bent Over Row']),
  ('pendlay_row',          'ko', '펜들레이 로우',         NULL),
  ('pendlay_row',          'en', 'Pendlay Row',           NULL),
  ('t_bar_row',            'ko', '티바 로우',             NULL),
  ('t_bar_row',            'en', 'T-Bar Row',             NULL),
  ('dumbbell_row',         'ko', '덤벨 로우',             ARRAY['원암 덤벨 로우']),
  ('dumbbell_row',         'en', 'Dumbbell Row',          ARRAY['DB Row']),
  ('seated_row',           'ko', '시티드 로우',           NULL),
  ('seated_row',           'en', 'Seated Row',            NULL),
  ('cable_row',            'ko', '케이블 로우',           NULL),
  ('cable_row',            'en', 'Cable Row',             NULL),
  ('machine_row',          'ko', '머신 로우',             NULL),
  ('machine_row',          'en', 'Machine Row',           NULL),
  ('inverted_row',         'ko', '인버티드 로우',         ARRAY['오스트레일리안 풀업']),
  ('inverted_row',         'en', 'Inverted Row',          ARRAY['Australian Pull-Up']),
  ('deadlift',             'ko', '데드리프트',             ARRAY['데드']),
  ('deadlift',             'en', 'Deadlift',              ARRAY['DL','Conventional Deadlift']),
  ('sumo_deadlift',        'ko', '스모 데드리프트',       NULL),
  ('sumo_deadlift',        'en', 'Sumo Deadlift',         NULL),
  ('romanian_deadlift',    'ko', '루마니안 데드리프트',   ARRAY['RDL']),
  ('romanian_deadlift',    'en', 'Romanian Deadlift',     ARRAY['RDL']),
  ('stiff_leg_deadlift',   'ko', '스티프 레그 데드리프트',NULL),
  ('stiff_leg_deadlift',   'en', 'Stiff-Leg Deadlift',    NULL),
  ('trap_bar_deadlift',    'ko', '트랩바 데드리프트',     ARRAY['헥스바 데드']),
  ('trap_bar_deadlift',    'en', 'Trap Bar Deadlift',     ARRAY['Hex Bar Deadlift']),
  ('rack_pull',            'ko', '랙 풀',                 NULL),
  ('rack_pull',            'en', 'Rack Pull',             NULL),
  ('snatch_grip_deadlift', 'ko', '스내치 그립 데드리프트',NULL),
  ('snatch_grip_deadlift', 'en', 'Snatch Grip Deadlift',  NULL),
  ('good_morning',         'ko', '굿모닝',                NULL),
  ('good_morning',         'en', 'Good Morning',          NULL),
  ('back_extension',       'ko', '백 익스텐션',           NULL),
  ('back_extension',       'en', 'Back Extension',        NULL),
  ('hyperextension',       'ko', '하이퍼익스텐션',        NULL),
  ('hyperextension',       'en', 'Hyperextension',        NULL),
  ('reverse_hyperextension','ko','리버스 하이퍼익스텐션', NULL),
  ('reverse_hyperextension','en','Reverse Hyperextension',NULL),
  ('face_pull',            'ko', '페이스 풀',             NULL),
  ('face_pull',            'en', 'Face Pull',             NULL),
  ('shrug',                'ko', '슈러그',                NULL),
  ('shrug',                'en', 'Shrug',                 NULL),
  ('dumbbell_shrug',       'ko', '덤벨 슈러그',           NULL),
  ('dumbbell_shrug',       'en', 'Dumbbell Shrug',        NULL)
ON CONFLICT (exercise_key, locale) DO NOTHING;

-- ─── LEGS (22) ────────────────────────────────────────────────────────────
INSERT INTO public.exercise_definitions (exercise_key, category_key, is_compound, default_name) VALUES
  ('squat',                   'legs', TRUE,  'Back Squat'),
  ('front_squat',             'legs', TRUE,  'Front Squat'),
  ('high_bar_squat',          'legs', TRUE,  'High Bar Squat'),
  ('low_bar_squat',           'legs', TRUE,  'Low Bar Squat'),
  ('box_squat',               'legs', TRUE,  'Box Squat'),
  ('pause_squat',             'legs', TRUE,  'Pause Squat'),
  ('goblet_squat',            'legs', TRUE,  'Goblet Squat'),
  ('dumbbell_squat',          'legs', TRUE,  'Dumbbell Squat'),
  ('smith_squat',             'legs', TRUE,  'Smith Machine Squat'),
  ('hack_squat',              'legs', TRUE,  'Hack Squat'),
  ('zercher_squat',           'legs', TRUE,  'Zercher Squat'),
  ('leg_press',               'legs', TRUE,  'Leg Press'),
  ('belt_squat',              'legs', TRUE,  'Belt Squat'),
  ('lunge',                   'legs', TRUE,  'Lunge'),
  ('walking_lunge',           'legs', TRUE,  'Walking Lunge'),
  ('reverse_lunge',           'legs', TRUE,  'Reverse Lunge'),
  ('split_squat',             'legs', TRUE,  'Split Squat'),
  ('bulgarian_split_squat',   'legs', TRUE,  'Bulgarian Split Squat'),
  ('step_up',                 'legs', TRUE,  'Step-Up'),
  ('leg_extension',           'legs', FALSE, 'Leg Extension'),
  ('leg_curl',                'legs', FALSE, 'Leg Curl'),
  ('seated_leg_curl',         'legs', FALSE, 'Seated Leg Curl'),
  ('nordic_curl',             'legs', FALSE, 'Nordic Curl')
ON CONFLICT (exercise_key) DO NOTHING;

INSERT INTO public.exercise_translations (exercise_key, locale, display_name, aliases) VALUES
  ('squat',                'ko', '스쿼트',               ARRAY['백스쿼트']),
  ('squat',                'en', 'Back Squat',           ARRAY['Squat']),
  ('front_squat',          'ko', '프론트 스쿼트',        NULL),
  ('front_squat',          'en', 'Front Squat',          NULL),
  ('high_bar_squat',       'ko', '하이바 스쿼트',        NULL),
  ('high_bar_squat',       'en', 'High Bar Squat',       NULL),
  ('low_bar_squat',        'ko', '로우바 스쿼트',        NULL),
  ('low_bar_squat',        'en', 'Low Bar Squat',        NULL),
  ('box_squat',            'ko', '박스 스쿼트',          NULL),
  ('box_squat',            'en', 'Box Squat',            NULL),
  ('pause_squat',          'ko', '폴즈 스쿼트',          NULL),
  ('pause_squat',          'en', 'Pause Squat',          NULL),
  ('goblet_squat',         'ko', '고블릿 스쿼트',        NULL),
  ('goblet_squat',         'en', 'Goblet Squat',         NULL),
  ('dumbbell_squat',       'ko', '덤벨 스쿼트',          NULL),
  ('dumbbell_squat',       'en', 'Dumbbell Squat',       NULL),
  ('smith_squat',          'ko', '스미스 스쿼트',        NULL),
  ('smith_squat',          'en', 'Smith Machine Squat',  NULL),
  ('hack_squat',           'ko', '핵 스쿼트',            ARRAY['핵스쿼트']),
  ('hack_squat',           'en', 'Hack Squat',           NULL),
  ('zercher_squat',        'ko', '저처 스쿼트',          NULL),
  ('zercher_squat',        'en', 'Zercher Squat',        NULL),
  ('leg_press',            'ko', '레그 프레스',          NULL),
  ('leg_press',            'en', 'Leg Press',            NULL),
  ('belt_squat',           'ko', '벨트 스쿼트',          NULL),
  ('belt_squat',           'en', 'Belt Squat',           NULL),
  ('lunge',                'ko', '런지',                 NULL),
  ('lunge',                'en', 'Lunge',                NULL),
  ('walking_lunge',        'ko', '워킹 런지',            NULL),
  ('walking_lunge',        'en', 'Walking Lunge',        NULL),
  ('reverse_lunge',        'ko', '리버스 런지',          NULL),
  ('reverse_lunge',        'en', 'Reverse Lunge',        NULL),
  ('split_squat',          'ko', '스플릿 스쿼트',        NULL),
  ('split_squat',          'en', 'Split Squat',          NULL),
  ('bulgarian_split_squat','ko', '불가리안 스플릿 스쿼트',ARRAY['불스플']),
  ('bulgarian_split_squat','en', 'Bulgarian Split Squat',ARRAY['BSS']),
  ('step_up',              'ko', '스텝 업',              NULL),
  ('step_up',              'en', 'Step-Up',              NULL),
  ('leg_extension',        'ko', '레그 익스텐션',        NULL),
  ('leg_extension',        'en', 'Leg Extension',        NULL),
  ('leg_curl',             'ko', '레그 컬',              ARRAY['라잉 레그 컬']),
  ('leg_curl',             'en', 'Leg Curl',             ARRAY['Lying Leg Curl']),
  ('seated_leg_curl',      'ko', '시티드 레그 컬',       NULL),
  ('seated_leg_curl',      'en', 'Seated Leg Curl',      NULL),
  ('nordic_curl',          'ko', '노르딕 컬',            NULL),
  ('nordic_curl',          'en', 'Nordic Curl',          NULL)
ON CONFLICT (exercise_key, locale) DO NOTHING;

-- ─── GLUTES (7) ───────────────────────────────────────────────────────────
INSERT INTO public.exercise_definitions (exercise_key, category_key, is_compound, default_name) VALUES
  ('hip_thrust',          'glutes', TRUE,  'Hip Thrust'),
  ('barbell_hip_thrust',  'glutes', TRUE,  'Barbell Hip Thrust'),
  ('glute_bridge',        'glutes', TRUE,  'Glute Bridge'),
  ('cable_kickback',      'glutes', FALSE, 'Cable Kickback'),
  ('donkey_kick',         'glutes', FALSE, 'Donkey Kick'),
  ('glute_ham_raise',     'glutes', TRUE,  'Glute Ham Raise'),
  ('cable_pull_through',  'glutes', TRUE,  'Cable Pull-Through')
ON CONFLICT (exercise_key) DO NOTHING;

INSERT INTO public.exercise_translations (exercise_key, locale, display_name, aliases) VALUES
  ('hip_thrust',         'ko', '힙 쓰러스트',         NULL),
  ('hip_thrust',         'en', 'Hip Thrust',          NULL),
  ('barbell_hip_thrust', 'ko', '바벨 힙 쓰러스트',     NULL),
  ('barbell_hip_thrust', 'en', 'Barbell Hip Thrust',  NULL),
  ('glute_bridge',       'ko', '글루트 브릿지',        NULL),
  ('glute_bridge',       'en', 'Glute Bridge',        NULL),
  ('cable_kickback',     'ko', '케이블 킥백',          NULL),
  ('cable_kickback',     'en', 'Cable Kickback',      NULL),
  ('donkey_kick',        'ko', '덩키 킥',              NULL),
  ('donkey_kick',        'en', 'Donkey Kick',         NULL),
  ('glute_ham_raise',    'ko', '글루트 햄 레이즈',     ARRAY['GHR']),
  ('glute_ham_raise',    'en', 'Glute Ham Raise',     ARRAY['GHR']),
  ('cable_pull_through', 'ko', '케이블 풀 스루',       NULL),
  ('cable_pull_through', 'en', 'Cable Pull-Through',  NULL)
ON CONFLICT (exercise_key, locale) DO NOTHING;

-- ─── CALVES (5) ───────────────────────────────────────────────────────────
INSERT INTO public.exercise_definitions (exercise_key, category_key, is_compound, default_name) VALUES
  ('standing_calf_raise',     'calves', FALSE, 'Standing Calf Raise'),
  ('seated_calf_raise',       'calves', FALSE, 'Seated Calf Raise'),
  ('donkey_calf_raise',       'calves', FALSE, 'Donkey Calf Raise'),
  ('leg_press_calf_raise',    'calves', FALSE, 'Leg Press Calf Raise'),
  ('smith_calf_raise',        'calves', FALSE, 'Smith Machine Calf Raise')
ON CONFLICT (exercise_key) DO NOTHING;

INSERT INTO public.exercise_translations (exercise_key, locale, display_name, aliases) VALUES
  ('standing_calf_raise',  'ko', '스탠딩 카프 레이즈',  ARRAY['카프 레이즈']),
  ('standing_calf_raise',  'en', 'Standing Calf Raise', ARRAY['Calf Raise']),
  ('seated_calf_raise',    'ko', '시티드 카프 레이즈',  NULL),
  ('seated_calf_raise',    'en', 'Seated Calf Raise',   NULL),
  ('donkey_calf_raise',    'ko', '덩키 카프 레이즈',    NULL),
  ('donkey_calf_raise',    'en', 'Donkey Calf Raise',   NULL),
  ('leg_press_calf_raise', 'ko', '레그 프레스 카프 레이즈',NULL),
  ('leg_press_calf_raise', 'en', 'Leg Press Calf Raise',NULL),
  ('smith_calf_raise',     'ko', '스미스 카프 레이즈',  NULL),
  ('smith_calf_raise',     'en', 'Smith Machine Calf Raise',NULL)
ON CONFLICT (exercise_key, locale) DO NOTHING;

-- ─── SHOULDERS (22) ───────────────────────────────────────────────────────
INSERT INTO public.exercise_definitions (exercise_key, category_key, is_compound, default_name) VALUES
  ('overhead_press',           'shoulders', TRUE,  'Overhead Press'),
  ('seated_overhead_press',    'shoulders', TRUE,  'Seated Overhead Press'),
  ('military_press',           'shoulders', TRUE,  'Military Press'),
  ('push_press',               'shoulders', TRUE,  'Push Press'),
  ('behind_neck_press',        'shoulders', TRUE,  'Behind The Neck Press'),
  ('dumbbell_shoulder_press',  'shoulders', TRUE,  'Dumbbell Shoulder Press'),
  ('seated_dumbbell_shoulder_press','shoulders',TRUE,'Seated Dumbbell Shoulder Press'),
  ('arnold_press',             'shoulders', TRUE,  'Arnold Press'),
  ('machine_shoulder_press',   'shoulders', TRUE,  'Machine Shoulder Press'),
  ('smith_shoulder_press',     'shoulders', TRUE,  'Smith Machine Shoulder Press'),
  ('lateral_raise',            'shoulders', FALSE, 'Lateral Raise'),
  ('cable_lateral_raise',      'shoulders', FALSE, 'Cable Lateral Raise'),
  ('machine_lateral_raise',    'shoulders', FALSE, 'Machine Lateral Raise'),
  ('lying_lateral_raise',      'shoulders', FALSE, 'Lying Lateral Raise'),
  ('front_raise',              'shoulders', FALSE, 'Front Raise'),
  ('cable_front_raise',        'shoulders', FALSE, 'Cable Front Raise'),
  ('plate_front_raise',        'shoulders', FALSE, 'Plate Front Raise'),
  ('rear_delt_fly',            'shoulders', FALSE, 'Rear Delt Fly'),
  ('reverse_pec_deck',         'shoulders', FALSE, 'Reverse Pec Deck'),
  ('bent_over_lateral_raise',  'shoulders', FALSE, 'Bent Over Lateral Raise'),
  ('upright_row',              'shoulders', TRUE,  'Upright Row'),
  ('cable_upright_row',        'shoulders', TRUE,  'Cable Upright Row')
ON CONFLICT (exercise_key) DO NOTHING;

INSERT INTO public.exercise_translations (exercise_key, locale, display_name, aliases) VALUES
  ('overhead_press',          'ko', '오버헤드 프레스',       ARRAY['숄더 프레스','OHP']),
  ('overhead_press',          'en', 'Overhead Press',        ARRAY['OHP','Standing Press']),
  ('seated_overhead_press',   'ko', '시티드 오버헤드 프레스', NULL),
  ('seated_overhead_press',   'en', 'Seated Overhead Press', NULL),
  ('military_press',          'ko', '밀리터리 프레스',        NULL),
  ('military_press',          'en', 'Military Press',        NULL),
  ('push_press',              'ko', '푸시 프레스',           NULL),
  ('push_press',              'en', 'Push Press',            NULL),
  ('behind_neck_press',       'ko', '비하인드 넥 프레스',     NULL),
  ('behind_neck_press',       'en', 'Behind The Neck Press', NULL),
  ('dumbbell_shoulder_press', 'ko', '덤벨 숄더 프레스',       NULL),
  ('dumbbell_shoulder_press', 'en', 'Dumbbell Shoulder Press',NULL),
  ('seated_dumbbell_shoulder_press','ko','시티드 덤벨 숄더 프레스',NULL),
  ('seated_dumbbell_shoulder_press','en','Seated Dumbbell Shoulder Press',NULL),
  ('arnold_press',            'ko', '아놀드 프레스',          NULL),
  ('arnold_press',            'en', 'Arnold Press',          NULL),
  ('machine_shoulder_press',  'ko', '머신 숄더 프레스',       NULL),
  ('machine_shoulder_press',  'en', 'Machine Shoulder Press',NULL),
  ('smith_shoulder_press',    'ko', '스미스 숄더 프레스',     NULL),
  ('smith_shoulder_press',    'en', 'Smith Machine Shoulder Press',NULL),
  ('lateral_raise',           'ko', '사이드 레터럴 레이즈',   ARRAY['레터럴']),
  ('lateral_raise',           'en', 'Lateral Raise',         ARRAY['Side Lateral Raise']),
  ('cable_lateral_raise',     'ko', '케이블 레터럴 레이즈',   NULL),
  ('cable_lateral_raise',     'en', 'Cable Lateral Raise',   NULL),
  ('machine_lateral_raise',   'ko', '머신 레터럴 레이즈',     NULL),
  ('machine_lateral_raise',   'en', 'Machine Lateral Raise', NULL),
  ('lying_lateral_raise',     'ko', '라잉 레터럴 레이즈',     NULL),
  ('lying_lateral_raise',     'en', 'Lying Lateral Raise',   NULL),
  ('front_raise',             'ko', '프론트 레이즈',          NULL),
  ('front_raise',             'en', 'Front Raise',           NULL),
  ('cable_front_raise',       'ko', '케이블 프론트 레이즈',   NULL),
  ('cable_front_raise',       'en', 'Cable Front Raise',     NULL),
  ('plate_front_raise',       'ko', '플레이트 프론트 레이즈', NULL),
  ('plate_front_raise',       'en', 'Plate Front Raise',     NULL),
  ('rear_delt_fly',           'ko', '리어 델트 플라이',       NULL),
  ('rear_delt_fly',           'en', 'Rear Delt Fly',         NULL),
  ('reverse_pec_deck',        'ko', '리버스 펙덱',            NULL),
  ('reverse_pec_deck',        'en', 'Reverse Pec Deck',      NULL),
  ('bent_over_lateral_raise', 'ko', '벤트오버 레터럴 레이즈', NULL),
  ('bent_over_lateral_raise', 'en', 'Bent Over Lateral Raise',NULL),
  ('upright_row',             'ko', '업라이트 로우',          NULL),
  ('upright_row',             'en', 'Upright Row',           NULL),
  ('cable_upright_row',       'ko', '케이블 업라이트 로우',   NULL),
  ('cable_upright_row',       'en', 'Cable Upright Row',     NULL)
ON CONFLICT (exercise_key, locale) DO NOTHING;

-- ─── BICEPS (13) ──────────────────────────────────────────────────────────
INSERT INTO public.exercise_definitions (exercise_key, category_key, is_compound, default_name) VALUES
  ('barbell_curl',           'biceps', FALSE, 'Barbell Curl'),
  ('ez_bar_curl',            'biceps', FALSE, 'EZ Bar Curl'),
  ('dumbbell_curl',          'biceps', FALSE, 'Dumbbell Curl'),
  ('alternate_dumbbell_curl','biceps', FALSE, 'Alternate Dumbbell Curl'),
  ('hammer_curl',            'biceps', FALSE, 'Hammer Curl'),
  ('cable_hammer_curl',      'biceps', FALSE, 'Cable Hammer Curl'),
  ('preacher_curl',          'biceps', FALSE, 'Preacher Curl'),
  ('spider_curl',            'biceps', FALSE, 'Spider Curl'),
  ('concentration_curl',     'biceps', FALSE, 'Concentration Curl'),
  ('cable_curl',             'biceps', FALSE, 'Cable Curl'),
  ('incline_dumbbell_curl',  'biceps', FALSE, 'Incline Dumbbell Curl'),
  ('reverse_curl',           'biceps', FALSE, 'Reverse Curl'),
  ('zottman_curl',           'biceps', FALSE, 'Zottman Curl')
ON CONFLICT (exercise_key) DO NOTHING;

INSERT INTO public.exercise_translations (exercise_key, locale, display_name, aliases) VALUES
  ('barbell_curl',           'ko', '바벨 컬',                NULL),
  ('barbell_curl',           'en', 'Barbell Curl',           NULL),
  ('ez_bar_curl',            'ko', 'EZ바 컬',                NULL),
  ('ez_bar_curl',            'en', 'EZ Bar Curl',            NULL),
  ('dumbbell_curl',          'ko', '덤벨 컬',                NULL),
  ('dumbbell_curl',          'en', 'Dumbbell Curl',          NULL),
  ('alternate_dumbbell_curl','ko', '얼터네이트 덤벨 컬',     NULL),
  ('alternate_dumbbell_curl','en', 'Alternate Dumbbell Curl',NULL),
  ('hammer_curl',            'ko', '해머 컬',                NULL),
  ('hammer_curl',            'en', 'Hammer Curl',            NULL),
  ('cable_hammer_curl',      'ko', '케이블 해머 컬',         NULL),
  ('cable_hammer_curl',      'en', 'Cable Hammer Curl',      NULL),
  ('preacher_curl',          'ko', '프리처 컬',              NULL),
  ('preacher_curl',          'en', 'Preacher Curl',          NULL),
  ('spider_curl',            'ko', '스파이더 컬',            NULL),
  ('spider_curl',            'en', 'Spider Curl',            NULL),
  ('concentration_curl',     'ko', '컨센트레이션 컬',        NULL),
  ('concentration_curl',     'en', 'Concentration Curl',     NULL),
  ('cable_curl',             'ko', '케이블 컬',              NULL),
  ('cable_curl',             'en', 'Cable Curl',             NULL),
  ('incline_dumbbell_curl',  'ko', '인클라인 덤벨 컬',       NULL),
  ('incline_dumbbell_curl',  'en', 'Incline Dumbbell Curl',  NULL),
  ('reverse_curl',           'ko', '리버스 컬',              NULL),
  ('reverse_curl',           'en', 'Reverse Curl',           NULL),
  ('zottman_curl',           'ko', '졸트만 컬',              NULL),
  ('zottman_curl',           'en', 'Zottman Curl',           NULL)
ON CONFLICT (exercise_key, locale) DO NOTHING;

-- ─── TRICEPS (14) ─────────────────────────────────────────────────────────
INSERT INTO public.exercise_definitions (exercise_key, category_key, is_compound, default_name) VALUES
  ('triceps_pushdown',         'triceps', FALSE, 'Triceps Pushdown'),
  ('rope_pushdown',            'triceps', FALSE, 'Rope Pushdown'),
  ('reverse_grip_pushdown',    'triceps', FALSE, 'Reverse Grip Pushdown'),
  ('skull_crusher',            'triceps', FALSE, 'Skull Crusher'),
  ('lying_triceps_extension',  'triceps', FALSE, 'Lying Triceps Extension'),
  ('overhead_cable_extension', 'triceps', FALSE, 'Overhead Cable Extension'),
  ('overhead_dumbbell_extension','triceps',FALSE,'Overhead Dumbbell Extension'),
  ('close_grip_bench_press',   'triceps', TRUE,  'Close Grip Bench Press'),
  ('triceps_dip',              'triceps', TRUE,  'Triceps Dip'),
  ('bench_dip',                'triceps', FALSE, 'Bench Dip'),
  ('triceps_kickback',         'triceps', FALSE, 'Triceps Kickback'),
  ('diamond_push_up',          'triceps', TRUE,  'Diamond Push-Up'),
  ('machine_triceps_extension','triceps', FALSE, 'Machine Triceps Extension'),
  ('jm_press',                 'triceps', TRUE,  'JM Press')
ON CONFLICT (exercise_key) DO NOTHING;

INSERT INTO public.exercise_translations (exercise_key, locale, display_name, aliases) VALUES
  ('triceps_pushdown',          'ko', '트라이셉 푸쉬다운',     NULL),
  ('triceps_pushdown',          'en', 'Triceps Pushdown',      NULL),
  ('rope_pushdown',             'ko', '로프 푸쉬다운',         NULL),
  ('rope_pushdown',             'en', 'Rope Pushdown',         NULL),
  ('reverse_grip_pushdown',     'ko', '리버스 그립 푸쉬다운',  NULL),
  ('reverse_grip_pushdown',     'en', 'Reverse Grip Pushdown', NULL),
  ('skull_crusher',             'ko', '스컬 크러셔',           NULL),
  ('skull_crusher',             'en', 'Skull Crusher',         NULL),
  ('lying_triceps_extension',   'ko', '라잉 트라이셉 익스텐션',NULL),
  ('lying_triceps_extension',   'en', 'Lying Triceps Extension',NULL),
  ('overhead_cable_extension',  'ko', '케이블 오버헤드 익스텐션',NULL),
  ('overhead_cable_extension',  'en', 'Overhead Cable Extension',NULL),
  ('overhead_dumbbell_extension','ko','덤벨 오버헤드 익스텐션',NULL),
  ('overhead_dumbbell_extension','en','Overhead Dumbbell Extension',NULL),
  ('close_grip_bench_press',    'ko', '클로즈 그립 벤치프레스', NULL),
  ('close_grip_bench_press',    'en', 'Close Grip Bench Press',NULL),
  ('triceps_dip',               'ko', '딥스',                  ARRAY['트라이셉 딥스']),
  ('triceps_dip',               'en', 'Triceps Dip',           ARRAY['Dips']),
  ('bench_dip',                 'ko', '벤치 딥스',             NULL),
  ('bench_dip',                 'en', 'Bench Dip',             NULL),
  ('triceps_kickback',          'ko', '트라이셉 킥백',          NULL),
  ('triceps_kickback',          'en', 'Triceps Kickback',      NULL),
  ('diamond_push_up',           'ko', '다이아몬드 푸쉬업',      NULL),
  ('diamond_push_up',           'en', 'Diamond Push-Up',       NULL),
  ('machine_triceps_extension', 'ko', '머신 트라이셉 익스텐션', NULL),
  ('machine_triceps_extension', 'en', 'Machine Triceps Extension',NULL),
  ('jm_press',                  'ko', 'JM 프레스',             NULL),
  ('jm_press',                  'en', 'JM Press',              NULL)
ON CONFLICT (exercise_key, locale) DO NOTHING;

-- ─── FOREARMS (5) ─────────────────────────────────────────────────────────
INSERT INTO public.exercise_definitions (exercise_key, category_key, is_compound, default_name) VALUES
  ('wrist_curl',          'forearms', FALSE, 'Wrist Curl'),
  ('reverse_wrist_curl',  'forearms', FALSE, 'Reverse Wrist Curl'),
  ('farmers_walk',        'forearms', TRUE,  'Farmer''s Walk'),
  ('plate_pinch',         'forearms', FALSE, 'Plate Pinch'),
  ('gripper',             'forearms', FALSE, 'Hand Gripper')
ON CONFLICT (exercise_key) DO NOTHING;

INSERT INTO public.exercise_translations (exercise_key, locale, display_name, aliases) VALUES
  ('wrist_curl',         'ko', '리스트 컬',           NULL),
  ('wrist_curl',         'en', 'Wrist Curl',          NULL),
  ('reverse_wrist_curl', 'ko', '리버스 리스트 컬',    NULL),
  ('reverse_wrist_curl', 'en', 'Reverse Wrist Curl',  NULL),
  ('farmers_walk',       'ko', '파머스 워크',         NULL),
  ('farmers_walk',       'en', 'Farmer''s Walk',      NULL),
  ('plate_pinch',        'ko', '플레이트 핀치',       NULL),
  ('plate_pinch',        'en', 'Plate Pinch',         NULL),
  ('gripper',            'ko', '그립퍼',              NULL),
  ('gripper',            'en', 'Hand Gripper',        NULL)
ON CONFLICT (exercise_key, locale) DO NOTHING;

-- ─── CORE (18) ────────────────────────────────────────────────────────────
INSERT INTO public.exercise_definitions (exercise_key, category_key, is_compound, default_name) VALUES
  ('plank',                'core', FALSE, 'Plank'),
  ('side_plank',           'core', FALSE, 'Side Plank'),
  ('weighted_plank',       'core', FALSE, 'Weighted Plank'),
  ('crunch',               'core', FALSE, 'Crunch'),
  ('decline_crunch',       'core', FALSE, 'Decline Crunch'),
  ('cable_crunch',         'core', FALSE, 'Cable Crunch'),
  ('hanging_leg_raise',    'core', FALSE, 'Hanging Leg Raise'),
  ('hanging_knee_raise',   'core', FALSE, 'Hanging Knee Raise'),
  ('lying_leg_raise',      'core', FALSE, 'Lying Leg Raise'),
  ('toes_to_bar',          'core', FALSE, 'Toes To Bar'),
  ('russian_twist',        'core', FALSE, 'Russian Twist'),
  ('cable_woodchopper',    'core', FALSE, 'Cable Woodchopper'),
  ('ab_rollout',           'core', FALSE, 'Ab Rollout'),
  ('dumbbell_side_bend',   'core', FALSE, 'Dumbbell Side Bend'),
  ('cable_side_bend',      'core', FALSE, 'Cable Side Bend'),
  ('dragon_flag',          'core', FALSE, 'Dragon Flag'),
  ('dead_bug',             'core', FALSE, 'Dead Bug'),
  ('bird_dog',             'core', FALSE, 'Bird Dog')
ON CONFLICT (exercise_key) DO NOTHING;

INSERT INTO public.exercise_translations (exercise_key, locale, display_name, aliases) VALUES
  ('plank',              'ko', '플랭크',               NULL),
  ('plank',              'en', 'Plank',                NULL),
  ('side_plank',         'ko', '사이드 플랭크',        NULL),
  ('side_plank',         'en', 'Side Plank',           NULL),
  ('weighted_plank',     'ko', '가중 플랭크',          NULL),
  ('weighted_plank',     'en', 'Weighted Plank',       NULL),
  ('crunch',             'ko', '크런치',               NULL),
  ('crunch',             'en', 'Crunch',               NULL),
  ('decline_crunch',     'ko', '디클라인 크런치',      NULL),
  ('decline_crunch',     'en', 'Decline Crunch',       NULL),
  ('cable_crunch',       'ko', '케이블 크런치',        NULL),
  ('cable_crunch',       'en', 'Cable Crunch',         NULL),
  ('hanging_leg_raise',  'ko', '행잉 레그 레이즈',     NULL),
  ('hanging_leg_raise',  'en', 'Hanging Leg Raise',    NULL),
  ('hanging_knee_raise', 'ko', '행잉 니 레이즈',       NULL),
  ('hanging_knee_raise', 'en', 'Hanging Knee Raise',   NULL),
  ('lying_leg_raise',    'ko', '라잉 레그 레이즈',     NULL),
  ('lying_leg_raise',    'en', 'Lying Leg Raise',      NULL),
  ('toes_to_bar',        'ko', '토즈 투 바',           ARRAY['T2B']),
  ('toes_to_bar',        'en', 'Toes To Bar',          ARRAY['T2B']),
  ('russian_twist',      'ko', '러시안 트위스트',      NULL),
  ('russian_twist',      'en', 'Russian Twist',        NULL),
  ('cable_woodchopper',  'ko', '케이블 우드차퍼',      NULL),
  ('cable_woodchopper',  'en', 'Cable Woodchopper',    NULL),
  ('ab_rollout',         'ko', '앱 롤아웃',            NULL),
  ('ab_rollout',         'en', 'Ab Rollout',           NULL),
  ('dumbbell_side_bend', 'ko', '덤벨 사이드 벤드',     NULL),
  ('dumbbell_side_bend', 'en', 'Dumbbell Side Bend',   NULL),
  ('cable_side_bend',    'ko', '케이블 사이드 벤드',   NULL),
  ('cable_side_bend',    'en', 'Cable Side Bend',      NULL),
  ('dragon_flag',        'ko', '드래곤 플래그',        NULL),
  ('dragon_flag',        'en', 'Dragon Flag',          NULL),
  ('dead_bug',           'ko', '데드 버그',            NULL),
  ('dead_bug',           'en', 'Dead Bug',             NULL),
  ('bird_dog',           'ko', '버드독',               NULL),
  ('bird_dog',           'en', 'Bird Dog',             NULL)
ON CONFLICT (exercise_key, locale) DO NOTHING;

-- ─── OLYMPIC (8) ──────────────────────────────────────────────────────────
INSERT INTO public.exercise_definitions (exercise_key, category_key, is_compound, default_name) VALUES
  ('clean',              'olympic', TRUE, 'Clean'),
  ('power_clean',        'olympic', TRUE, 'Power Clean'),
  ('hang_clean',         'olympic', TRUE, 'Hang Clean'),
  ('snatch',             'olympic', TRUE, 'Snatch'),
  ('power_snatch',       'olympic', TRUE, 'Power Snatch'),
  ('push_jerk',          'olympic', TRUE, 'Push Jerk'),
  ('clean_and_jerk',     'olympic', TRUE, 'Clean and Jerk'),
  ('kettlebell_swing',   'olympic', TRUE, 'Kettlebell Swing')
ON CONFLICT (exercise_key) DO NOTHING;

INSERT INTO public.exercise_translations (exercise_key, locale, display_name, aliases) VALUES
  ('clean',            'ko', '클린',              NULL),
  ('clean',            'en', 'Clean',             NULL),
  ('power_clean',      'ko', '파워 클린',         NULL),
  ('power_clean',      'en', 'Power Clean',       NULL),
  ('hang_clean',       'ko', '행 클린',           NULL),
  ('hang_clean',       'en', 'Hang Clean',        NULL),
  ('snatch',           'ko', '스내치',            NULL),
  ('snatch',           'en', 'Snatch',            NULL),
  ('power_snatch',     'ko', '파워 스내치',       NULL),
  ('power_snatch',     'en', 'Power Snatch',      NULL),
  ('push_jerk',        'ko', '푸시 저크',         NULL),
  ('push_jerk',        'en', 'Push Jerk',         NULL),
  ('clean_and_jerk',   'ko', '클린 앤 저크',      ARRAY['C&J']),
  ('clean_and_jerk',   'en', 'Clean and Jerk',    ARRAY['C&J']),
  ('kettlebell_swing', 'ko', '케틀벨 스윙',       NULL),
  ('kettlebell_swing', 'en', 'Kettlebell Swing',  NULL)
ON CONFLICT (exercise_key, locale) DO NOTHING;

-- ============================================================================
-- 7) Seed: one_rm_formulas (NSCA LeSuer 1997 검증 기반)
-- ============================================================================

INSERT INTO public.one_rm_formulas (exercise_key, formula_type, coefficients, source, optimal_rep_max, notice_translations) VALUES
  -- Mayhew (상체 push, NSCA validated)
  ('bench_press',           'exponential', '{"a":100,"b":52.2,"c":41.9,"k":-0.055}', 'Mayhew et al. 1992', 10, '{"ko":"NSCA 검증 — 상체 push 최적","en":"NSCA validated — best for upper body push"}'::jsonb),
  ('incline_bench_press',   'exponential', '{"a":100,"b":52.2,"c":41.9,"k":-0.055}', 'Mayhew et al. 1992', 10, NULL),
  ('decline_bench_press',   'exponential', '{"a":100,"b":52.2,"c":41.9,"k":-0.055}', 'Mayhew et al. 1992', 10, NULL),
  ('close_grip_bench_press','exponential', '{"a":100,"b":52.2,"c":41.9,"k":-0.055}', 'Mayhew et al. 1992', 10, NULL),
  ('dumbbell_bench_press',  'exponential', '{"a":100,"b":52.2,"c":41.9,"k":-0.055}', 'Mayhew et al. 1992', 10, NULL),
  ('overhead_press',        'exponential', '{"a":100,"b":52.2,"c":41.9,"k":-0.055}', 'Mayhew et al. 1992', 10, NULL),
  ('military_press',        'exponential', '{"a":100,"b":52.2,"c":41.9,"k":-0.055}', 'Mayhew et al. 1992', 10, NULL),
  ('push_press',            'exponential', '{"a":100,"b":52.2,"c":41.9,"k":-0.055}', 'Mayhew et al. 1992',  8, NULL),

  -- Wathen (하체, NSCA validated)
  ('squat',                 'exponential', '{"a":100,"b":48.8,"c":53.8,"k":-0.075}', 'Wathen 1994',        10, '{"ko":"NSCA 검증 — 하체 최적","en":"NSCA validated — best for lower body"}'::jsonb),
  ('high_bar_squat',        'exponential', '{"a":100,"b":48.8,"c":53.8,"k":-0.075}', 'Wathen 1994',        10, NULL),
  ('low_bar_squat',         'exponential', '{"a":100,"b":48.8,"c":53.8,"k":-0.075}', 'Wathen 1994',        10, NULL),
  ('front_squat',           'exponential', '{"a":100,"b":48.8,"c":53.8,"k":-0.075}', 'Wathen 1994',        10, NULL),
  ('hack_squat',            'exponential', '{"a":100,"b":48.8,"c":53.8,"k":-0.075}', 'Wathen 1994',        10, NULL),
  ('leg_press',             'exponential', '{"a":100,"b":48.8,"c":53.8,"k":-0.075}', 'Wathen 1994',        10, NULL),
  ('deadlift',              'exponential', '{"a":100,"b":48.8,"c":53.8,"k":-0.075}', 'Wathen 1994',         8, '{"ko":"데드리프트는 추정이 다소 보수적입니다","en":"Deadlift estimates trend conservative"}'::jsonb),
  ('sumo_deadlift',         'exponential', '{"a":100,"b":48.8,"c":53.8,"k":-0.075}', 'Wathen 1994',         8, NULL),
  ('romanian_deadlift',     'exponential', '{"a":100,"b":48.8,"c":53.8,"k":-0.075}', 'Wathen 1994',        10, NULL),
  ('trap_bar_deadlift',     'exponential', '{"a":100,"b":48.8,"c":53.8,"k":-0.075}', 'Wathen 1994',         8, NULL),
  ('rack_pull',             'exponential', '{"a":100,"b":48.8,"c":53.8,"k":-0.075}', 'Wathen 1994',         8, NULL),

  -- Brzycki (등 운동 — NSCA에서 squat/bench와 비슷한 정확도)
  ('barbell_row',           'linear',      '{"a":1.0278,"b":0.0278}',                'Brzycki 1993',       10, NULL),
  ('pendlay_row',           'linear',      '{"a":1.0278,"b":0.0278}',                'Brzycki 1993',       10, NULL),
  ('t_bar_row',             'linear',      '{"a":1.0278,"b":0.0278}',                'Brzycki 1993',       10, NULL),
  ('pull_up',               'linear',      '{"a":1.0278,"b":0.0278}',                'Brzycki 1993',       10, NULL),
  ('chin_up',               'linear',      '{"a":1.0278,"b":0.0278}',                'Brzycki 1993',       10, NULL),
  ('lat_pulldown',           'linear',     '{"a":1.0278,"b":0.0278}',                'Brzycki 1993',       10, NULL)
ON CONFLICT (exercise_key) DO NOTHING;
