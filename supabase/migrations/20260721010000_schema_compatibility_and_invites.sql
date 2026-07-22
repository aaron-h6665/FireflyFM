-- Compatibility contract and onboarding/invitation release blockers.

CREATE OR REPLACE FUNCTION public.get_firefly_schema_version()
RETURNS BIGINT
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$ SELECT 20260721010000::BIGINT; $$;

REVOKE ALL ON FUNCTION public.get_firefly_schema_version() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_firefly_schema_version() TO authenticated;

CREATE OR REPLACE FUNCTION public.create_child_for_current_parent(
    school_id UUID,
    first_name TEXT,
    last_name TEXT,
    birthdate DATE DEFAULT NULL
)
RETURNS SETOF public.children
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    actor UUID;
    created_child public.children%ROWTYPE;
    classroom_uuid UUID;
BEGIN
    actor := auth.uid();
    IF actor IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;

    -- A new parent needs this narrowly scoped action before full access.
    IF NOT EXISTS (
        SELECT 1 FROM public.school_memberships memberships
        WHERE memberships.school_id = $1
          AND memberships.user_id = actor
          AND memberships.active = TRUE
          AND memberships.role = 'parent'
    ) THEN
        RAISE EXCEPTION 'Only parents can add children to their active school';
    END IF;

    IF NULLIF(TRIM($2), '') IS NULL OR NULLIF(TRIM($3), '') IS NULL THEN
        RAISE EXCEPTION 'Child first and last name are required';
    END IF;

    INSERT INTO public.children (school_id, first_name, last_name, birthdate, active)
    VALUES ($1, TRIM($2), TRIM($3), $4, TRUE)
    RETURNING * INTO created_child;

    INSERT INTO public.child_guardians (child_id, guardian_id, relationship)
    VALUES (created_child.id, actor, 'Parent')
    ON CONFLICT (child_id, guardian_id) DO NOTHING;

    classroom_uuid := public.default_classroom_for_school($1);
    INSERT INTO public.classroom_children (classroom_id, child_id)
    VALUES (classroom_uuid, created_child.id)
    ON CONFLICT DO NOTHING;

    RETURN QUERY SELECT * FROM public.children WHERE id = created_child.id;
END;
$$;

CREATE OR REPLACE FUNCTION public.preview_role_invite(invite_token TEXT)
RETURNS TABLE (
    invite_id UUID,
    school_id UUID,
    school_name TEXT,
    role TEXT,
    expires_at TIMESTAMPTZ
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    joining_email TEXT;
BEGIN
    IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
    joining_email := lower(COALESCE(auth.jwt()->>'email', ''));
    IF joining_email = '' THEN RAISE EXCEPTION 'Your account email could not be verified'; END IF;

    RETURN QUERY
    SELECT invites.id, schools.id, schools.name, invites.role, invites.expires_at
    FROM public.role_invites invites
    JOIN public.schools schools ON schools.id = invites.school_id
    WHERE (
            invites.token_hash = encode(extensions.digest(NULLIF(TRIM(invite_token), ''), 'sha256'), 'hex')
            OR invites.token = NULLIF(TRIM(invite_token), '')
          )
      AND invites.status = 'pending'
      AND (invites.expires_at IS NULL OR invites.expires_at > NOW())
      AND lower(invites.email) = joining_email
    LIMIT 1;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'This invitation is invalid, expired, or belongs to another account';
    END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.preview_role_invite(TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.preview_role_invite(TEXT) TO authenticated;
