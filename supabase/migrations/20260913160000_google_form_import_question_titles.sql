-- Preserve the Form's question labels with each immutable import so review
-- never depends on opaque Google question IDs or a later Form edit.
ALTER TABLE public.google_form_imports
    ADD COLUMN IF NOT EXISTS question_snapshot JSONB NOT NULL DEFAULT '[]'::JSONB;

ALTER TABLE public.google_form_imports
    DROP CONSTRAINT IF EXISTS google_form_imports_question_snapshot_array;
ALTER TABLE public.google_form_imports
    ADD CONSTRAINT google_form_imports_question_snapshot_array
    CHECK (jsonb_typeof(question_snapshot) = 'array');

CREATE OR REPLACE FUNCTION public.google_form_question_snapshot(input_connection_id UUID)
RETURNS JSONB
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public
AS $$
    WITH form_questions AS (
        SELECT
            question.value ->> 'id' AS question_id,
            COALESCE(NULLIF(btrim(question.value ->> 'title'), ''), mapping.question_title, 'Question') AS question_title,
            mapping.field_key,
            question.ordinality::INTEGER AS position
        FROM public.google_form_connections connection
        CROSS JOIN LATERAL jsonb_array_elements(
            COALESCE(connection.form_snapshot -> 'questions', '[]'::JSONB)
        ) WITH ORDINALITY AS question(value, ordinality)
        LEFT JOIN public.google_form_question_mappings mapping
          ON mapping.connection_id = connection.id
         AND mapping.question_id = question.value ->> 'id'
         AND mapping.active = TRUE
        WHERE connection.id = input_connection_id
          AND NULLIF(question.value ->> 'id', '') IS NOT NULL
    ), mapped_questions AS (
        SELECT mapping.question_id, mapping.question_title, mapping.field_key,
               100000 + row_number() OVER (ORDER BY mapping.created_at, mapping.question_id) AS position
        FROM public.google_form_question_mappings mapping
        WHERE mapping.connection_id = input_connection_id
          AND mapping.active = TRUE
          AND NOT EXISTS (
              SELECT 1 FROM form_questions question WHERE question.question_id = mapping.question_id
          )
    ), questions AS (
        SELECT * FROM form_questions
        UNION ALL
        SELECT * FROM mapped_questions
    )
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'id', question_id,
        'title', question_title,
        'field_key', field_key
    ) ORDER BY position), '[]'::JSONB)
    FROM questions;
$$;

CREATE OR REPLACE FUNCTION public.snapshot_google_form_import_questions()
RETURNS TRIGGER
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF jsonb_array_length(COALESCE(NEW.question_snapshot, '[]'::JSONB)) = 0 THEN
        NEW.question_snapshot := public.google_form_question_snapshot(NEW.connection_id);
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS snapshot_google_form_import_questions ON public.google_form_imports;
CREATE TRIGGER snapshot_google_form_import_questions
BEFORE INSERT ON public.google_form_imports
FOR EACH ROW EXECUTE FUNCTION public.snapshot_google_form_import_questions();

UPDATE public.google_form_imports form_import
SET question_snapshot = public.google_form_question_snapshot(form_import.connection_id),
    updated_at = NOW()
WHERE jsonb_array_length(form_import.question_snapshot) = 0;

REVOKE ALL ON FUNCTION public.google_form_question_snapshot(UUID) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.snapshot_google_form_import_questions() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.google_form_question_snapshot(UUID) TO service_role;

CREATE OR REPLACE FUNCTION public.get_firefly_schema_version()
RETURNS BIGINT LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$ SELECT 20260913160000::BIGINT; $$;
