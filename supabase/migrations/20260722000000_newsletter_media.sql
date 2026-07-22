-- Store a small, ordered media manifest with each newsletter. The underlying
-- files remain in the private school bucket and are delivered through signed
-- URLs, just like other school-scoped media.

ALTER TABLE public.newsletters
    ADD COLUMN IF NOT EXISTS media JSONB NOT NULL DEFAULT '[]'::JSONB;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conrelid = 'public.newsletters'::REGCLASS
          AND conname = 'newsletters_media_is_array'
    ) THEN
        ALTER TABLE public.newsletters
            ADD CONSTRAINT newsletters_media_is_array
            CHECK (jsonb_typeof(media) = 'array');
    END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.can_access_newsletter_private_file(object_name TEXT, user_uuid UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    parts TEXT[];
    school_uuid UUID;
    newsletter_uuid UUID;
BEGIN
    IF object_name IS NULL OR user_uuid IS NULL THEN
        RETURN FALSE;
    END IF;

    parts := string_to_array(object_name, '/');
    IF array_length(parts, 1) < 5
       OR parts[1] <> 'schools'
       OR parts[3] <> 'newsletters' THEN
        RETURN FALSE;
    END IF;

    school_uuid := parts[2]::UUID;
    newsletter_uuid := parts[4]::UUID;

    RETURN public.is_school_member(school_uuid, user_uuid)
       AND EXISTS (
            SELECT 1
            FROM public.newsletters newsletters
            WHERE newsletters.id = newsletter_uuid
              AND newsletters.school_id = school_uuid
              AND EXISTS (
                    SELECT 1
                    FROM jsonb_array_elements(newsletters.media) item
                    WHERE item->>'file_path' = object_name
              )
       );
EXCEPTION WHEN invalid_text_representation THEN
    RETURN FALSE;
END;
$$;

CREATE OR REPLACE FUNCTION public.can_write_newsletter_private_file(object_name TEXT, user_uuid UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    parts TEXT[];
    school_uuid UUID;
    newsletter_uuid UUID;
BEGIN
    IF object_name IS NULL OR user_uuid IS NULL THEN
        RETURN FALSE;
    END IF;

    parts := string_to_array(object_name, '/');
    IF array_length(parts, 1) < 5
       OR parts[1] <> 'schools'
       OR parts[3] <> 'newsletters' THEN
        RETURN FALSE;
    END IF;

    school_uuid := parts[2]::UUID;
    newsletter_uuid := parts[4]::UUID;

    RETURN newsletter_uuid IS NOT NULL
       AND public.has_school_role(
            school_uuid,
            user_uuid,
            ARRAY['school_director', 'hq_director']
       );
EXCEPTION WHEN invalid_text_representation THEN
    RETURN FALSE;
END;
$$;

REVOKE ALL ON FUNCTION public.can_access_newsletter_private_file(TEXT, UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.can_write_newsletter_private_file(TEXT, UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.can_access_newsletter_private_file(TEXT, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.can_write_newsletter_private_file(TEXT, UUID) TO authenticated;

DROP POLICY IF EXISTS "School private files are restricted" ON storage.objects;
CREATE POLICY "School private files are restricted"
    ON storage.objects FOR SELECT
    USING (
        bucket_id = 'school_private_files'
        AND (
            public.can_access_school_private_file(name, auth.uid())
            OR public.can_access_newsletter_private_file(name, auth.uid())
        )
    );

DROP POLICY IF EXISTS "School members can upload private files" ON storage.objects;
CREATE POLICY "School members can upload private files"
    ON storage.objects FOR INSERT
    WITH CHECK (
        bucket_id = 'school_private_files'
        AND (
            public.can_write_school_private_file(name, auth.uid())
            OR public.can_write_newsletter_private_file(name, auth.uid())
        )
    );

DROP POLICY IF EXISTS "School members can update private files" ON storage.objects;
CREATE POLICY "School members can update private files"
    ON storage.objects FOR UPDATE
    USING (
        bucket_id = 'school_private_files'
        AND (
            public.can_write_school_private_file(name, auth.uid())
            OR public.can_write_newsletter_private_file(name, auth.uid())
        )
    )
    WITH CHECK (
        bucket_id = 'school_private_files'
        AND (
            public.can_write_school_private_file(name, auth.uid())
            OR public.can_write_newsletter_private_file(name, auth.uid())
        )
    );

DROP POLICY IF EXISTS "School members can delete own private uploads" ON storage.objects;
CREATE POLICY "School members can delete own private uploads"
    ON storage.objects FOR DELETE
    USING (
        bucket_id = 'school_private_files'
        AND (
            public.can_delete_school_private_file(name, auth.uid())
            OR public.can_write_newsletter_private_file(name, auth.uid())
        )
    );

CREATE OR REPLACE FUNCTION public.get_firefly_schema_version()
RETURNS BIGINT
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$ SELECT 20260722000000::BIGINT; $$;

NOTIFY pgrst, 'reload schema';
