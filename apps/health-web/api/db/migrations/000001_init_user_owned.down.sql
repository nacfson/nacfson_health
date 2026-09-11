-- 000001_init_user_owned.down.sql
-- Reverses 000001: drops every object created by the up migration, in reverse
-- dependency order. Indexes and triggers are dropped implicitly with their tables.

-- User-owned tables (no interdependencies), newest first.
DROP TABLE IF EXISTS exercise_records;
DROP TABLE IF EXISTS diet_records;
DROP TABLE IF EXISTS weight_records;
DROP TABLE IF EXISTS exercise_templates;
DROP TABLE IF EXISTS food_templates;
DROP TABLE IF EXISTS workout_routines;
DROP TABLE IF EXISTS daily_routine;
DROP TABLE IF EXISTS user_profiles;

-- Master reference tables, children before parents.
DROP TABLE IF EXISTS one_rm_formulas;
DROP TABLE IF EXISTS exercise_translations;
DROP TABLE IF EXISTS exercise_definitions;
DROP TABLE IF EXISTS exercise_category_translations;
DROP TABLE IF EXISTS exercise_categories;

-- Trigger function last: every trigger that used it is gone with its table.
DROP FUNCTION IF EXISTS public.set_updated_at();
