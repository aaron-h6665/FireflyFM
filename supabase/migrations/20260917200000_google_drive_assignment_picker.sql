-- Direct, per-file Google Drive imports for assignment materials and submissions.
-- OAuth secrets and selected-file manifests are service-role only.

CREATE TABLE public.google_drive_assignment_operations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    school_id UUID NOT NULL REFERENCES public.schools(id) ON DELETE CASCADE,
    assignment_id UUID REFERENCES public.assignments(id) ON DELETE CASCADE,
    context_kind TEXT NOT NULL
        CHECK (context_kind IN ('material_create', 'material_manage', 'submission')),
    allows_multiple BOOLEAN NOT NULL DEFAULT TRUE,
    state_hash TEXT NOT NULL UNIQUE,
    pkce_verifier_ciphertext TEXT,
    pkce_verifier_iv TEXT,
    access_token_ciphertext TEXT,
    access_token_iv TEXT,
    selected_files JSONB NOT NULL DEFAULT '[]'::JSONB
        CHECK (jsonb_typeof(selected_files) = 'array'),
    oauth_completed_at TIMESTAMPTZ,
    expires_at TIMESTAMPTZ NOT NULL,
    consumed_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CHECK (
        (context_kind = 'material_create' AND assignment_id IS NULL)
        OR (context_kind IN ('material_manage', 'submission') AND assignment_id IS NOT NULL)
    ),
    CHECK (
        (pkce_verifier_ciphertext IS NULL AND pkce_verifier_iv IS NULL)
        OR (pkce_verifier_ciphertext IS NOT NULL AND pkce_verifier_iv IS NOT NULL)
    ),
    CHECK (
        (access_token_ciphertext IS NULL AND access_token_iv IS NULL)
        OR (access_token_ciphertext IS NOT NULL AND access_token_iv IS NOT NULL)
    )
);

CREATE INDEX idx_google_drive_assignment_operations_expiry
    ON public.google_drive_assignment_operations(expires_at)
    WHERE consumed_at IS NULL;

ALTER TABLE public.google_drive_assignment_operations ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.google_drive_assignment_operations FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.cleanup_expired_google_drive_assignment_operations()
RETURNS BIGINT
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
    WITH deleted AS (
        DELETE FROM public.google_drive_assignment_operations
        WHERE expires_at <= NOW()
        RETURNING 1
    )
    SELECT COUNT(*)::BIGINT FROM deleted;
$$;

REVOKE ALL ON FUNCTION public.cleanup_expired_google_drive_assignment_operations() FROM PUBLIC, anon, authenticated;

CREATE EXTENSION IF NOT EXISTS pg_cron WITH SCHEMA pg_catalog;

SELECT cron.schedule(
    'firefly-google-drive-assignment-picker-cleanup',
    '* * * * *',
    $$SELECT public.cleanup_expired_google_drive_assignment_operations();$$
);

CREATE OR REPLACE FUNCTION public.authorize_google_drive_assignment_import(
    input_context_kind TEXT,
    input_school_id UUID,
    input_assignment_id UUID DEFAULT NULL
)
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    actor UUID := auth.uid();
    assignment_school_id UUID;
BEGIN
    IF actor IS NULL THEN
        RETURN FALSE;
    END IF;

    IF input_context_kind = 'material_create' THEN
        RETURN input_assignment_id IS NULL
           AND public.has_school_role(input_school_id, actor, ARRAY['school_director', 'hq_director']);
    END IF;

    SELECT school_id INTO assignment_school_id
    FROM public.assignments
    WHERE id = input_assignment_id;

    IF assignment_school_id IS NULL OR assignment_school_id <> input_school_id THEN
        RETURN FALSE;
    END IF;

    IF input_context_kind = 'material_manage' THEN
        RETURN public.can_manage_assignment(input_assignment_id, actor);
    END IF;

    IF input_context_kind = 'submission' THEN
        RETURN public.can_submit_assignment(input_assignment_id, actor);
    END IF;

    RETURN FALSE;
END;
$$;

REVOKE ALL ON FUNCTION public.authorize_google_drive_assignment_import(TEXT, UUID, UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.authorize_google_drive_assignment_import(TEXT, UUID, UUID) TO authenticated;

CREATE OR REPLACE FUNCTION public.get_firefly_schema_version()
RETURNS BIGINT
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$ SELECT 20260917200000::BIGINT; $$;

NOTIFY pgrst, 'reload schema';
