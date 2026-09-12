-- 000002_sync_cursors.up.sql
-- Sync bridge: preserve client updated_at on explicit upserts, and index
-- delta pulls by (user_id, updated_at).

CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    -- CRUD paths leave updated_at unchanged → stamp now().
    -- Sync upserts set a client updated_at distinct from OLD → keep it (LWW).
    IF TG_OP = 'UPDATE' THEN
        IF NEW.updated_at IS NOT DISTINCT FROM OLD.updated_at THEN
            NEW.updated_at = now();
        END IF;
        RETURN NEW;
    END IF;
    -- INSERT: keep the provided updated_at (DEFAULT now() when omitted).
    RETURN NEW;
END;
$$;

CREATE INDEX IF NOT EXISTS exercise_records_user_updated_at_idx
    ON exercise_records (user_id, updated_at);
CREATE INDEX IF NOT EXISTS diet_records_user_updated_at_idx
    ON diet_records (user_id, updated_at);
CREATE INDEX IF NOT EXISTS weight_records_user_updated_at_idx
    ON weight_records (user_id, updated_at);
CREATE INDEX IF NOT EXISTS exercise_templates_user_updated_at_idx
    ON exercise_templates (user_id, updated_at);
CREATE INDEX IF NOT EXISTS food_templates_user_updated_at_idx
    ON food_templates (user_id, updated_at);
CREATE INDEX IF NOT EXISTS workout_routines_user_updated_at_idx
    ON workout_routines (user_id, updated_at);
