-- 000002_sync_cursors.down.sql

DROP INDEX IF EXISTS workout_routines_user_updated_at_idx;
DROP INDEX IF EXISTS food_templates_user_updated_at_idx;
DROP INDEX IF EXISTS exercise_templates_user_updated_at_idx;
DROP INDEX IF EXISTS weight_records_user_updated_at_idx;
DROP INDEX IF EXISTS diet_records_user_updated_at_idx;
DROP INDEX IF EXISTS exercise_records_user_updated_at_idx;

CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$;
