-- Repair hosted schema drift where the response ingester remained installed
-- but its immutable snapshot lookup helper was missing.
CREATE OR REPLACE FUNCTION public.google_form_snapshot_answer(
    input_payload JSONB,
    input_snapshot JSONB,
    input_field_key TEXT
)
RETURNS TEXT
LANGUAGE sql IMMUTABLE
SET search_path = public
AS $$
    SELECT public.google_form_scalar_answer(input_payload, mapping ->> 'question_id')
    FROM jsonb_array_elements(COALESCE(input_snapshot -> 'mappings', '[]'::JSONB)) mapping
    WHERE mapping ->> 'field_key' = input_field_key
      AND COALESCE((mapping ->> 'active')::BOOLEAN, TRUE)
    LIMIT 1;
$$;
